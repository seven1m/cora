const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const available = build_options.tcc_jit;

const c = if (available) @cImport({
    @cInclude("libtcc.h");
    if (builtin.os.tag == .linux) {
        @cDefine("_GNU_SOURCE", "1");
        @cInclude("dlfcn.h");
        @cInclude("stdlib.h");
    }
}) else struct {};

pub const State = if (available) c.TCCState else opaque {};

pub const ExternalSymbol = struct {
    name: [:0]const u8,
    ptr: *const anyopaque,
};

pub const CompileError = error{
    Unavailable,
    CreateFailed,
    ConfigureFailed,
    AddSymbolFailed,
    CompileFailed,
    RelocateFailed,
    MissingSymbol,
};

pub const ErrorCollector = struct {
    buffer: [2048]u8 = undefined,
    len: usize = 0,

    fn append(self: *ErrorCollector, msg: []const u8) void {
        if (self.len >= self.buffer.len) return;
        const remaining = self.buffer.len - self.len;
        const copy_len = @min(msg.len, remaining);
        @memcpy(self.buffer[self.len .. self.len + copy_len], msg[0..copy_len]);
        self.len += copy_len;
        if (self.len < self.buffer.len) {
            self.buffer[self.len] = '\n';
            self.len += 1;
        }
    }

    pub fn slice(self: *const ErrorCollector) []const u8 {
        return self.buffer[0..self.len];
    }
};

pub const Compilation = struct {
    state: ?*State = null,

    pub fn deinit(self: *Compilation) void {
        if (!available) return;
        if (self.state) |state| {
            c.tcc_delete(state);
            self.state = null;
        }
    }
};

fn errorCallback(userdata: ?*anyopaque, msg: [*c]const u8) callconv(.c) void {
    const collector: *ErrorCollector = @ptrCast(@alignCast(@constCast(userdata.?)));
    collector.append(std.mem.span(msg));
}

fn addRuntimeLibcPath(state: *State) CompileError!void {
    if (!available) return;
    if (comptime builtin.os.tag != .linux) return;

    var info: c.Dl_info = undefined;
    if (c.dladdr(@ptrCast(&c.malloc), &info) == 0 or info.dli_fname == null) {
        return;
    }

    const libc_path = std.mem.span(info.dli_fname);
    const libc_dir = std.fs.path.dirname(libc_path) orelse return;
    if (libc_dir.len >= std.fs.max_path_bytes) return;

    var libc_dir_z: [std.fs.max_path_bytes:0]u8 = undefined;
    @memcpy(libc_dir_z[0..libc_dir.len], libc_dir);
    libc_dir_z[libc_dir.len] = 0;

    if (c.tcc_add_library_path(state, &libc_dir_z) < 0) {
        return error.ConfigureFailed;
    }
}

pub fn initErrorCollector() ErrorCollector {
    return .{};
}

pub fn compile(
    lib_path: [:0]const u8,
    source_code: [:0]const u8,
    symbol_name: [:0]const u8,
    symbols: []const ExternalSymbol,
    error_collector: *ErrorCollector,
) CompileError!Compilation {
    if (!available) return error.Unavailable;

    const state = c.tcc_new() orelse return error.CreateFailed;
    errdefer c.tcc_delete(state);

    c.tcc_set_error_func(state, error_collector, errorCallback);
    c.tcc_set_lib_path(state, lib_path.ptr);
    try addRuntimeLibcPath(state);
    _ = c.tcc_set_options(state, "-O2");

    if (c.tcc_set_output_type(state, c.TCC_OUTPUT_MEMORY) < 0) {
        return error.ConfigureFailed;
    }

    for (symbols) |symbol| {
        if (c.tcc_add_symbol(state, symbol.name.ptr, symbol.ptr) < 0) {
            return error.AddSymbolFailed;
        }
    }

    if (c.tcc_compile_string(state, source_code.ptr) < 0) {
        return error.CompileFailed;
    }

    if (c.tcc_relocate(state) < 0) {
        return error.RelocateFailed;
    }

    if (c.tcc_get_symbol(state, symbol_name.ptr) == null) {
        return error.MissingSymbol;
    }

    return .{ .state = state };
}

pub fn getSymbol(comptime T: type, compilation: *Compilation, symbol_name: [:0]const u8) ?T {
    if (!available) return null;
    const state = compilation.state orelse return null;
    const symbol = c.tcc_get_symbol(state, symbol_name.ptr) orelse return null;
    return @ptrCast(symbol);
}
