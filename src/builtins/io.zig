const std = @import("std");
const builtin = @import("builtin");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const IoObject = value.IoObject;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;

const null_device_path = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

fn monotonicMilliseconds() i64 {
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(std.posix.CLOCK.MONOTONIC, &timespec) != 0) return 0;

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);
    return seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000);
}

fn openFlagValue(flags: std.posix.O) i64 {
    return @intCast(@as(c_int, @bitCast(flags)));
}

pub fn register(vm: *VM) !void {
    const io_class_val = Value.fromObject(&vm.io_class.module.object);
    const io_singleton = try vm.getOrCreateSingletonClass(io_class_val);

    const select_sym = try vm.intern("select");
    try io_singleton.module.methods.put(select_sym, value.MethodEntry.builtin(&builtinIoSelect, .{ .variadic = 1 }));

    const pipe_sym = try vm.intern("pipe");
    try io_singleton.module.methods.put(pipe_sym, value.MethodEntry.builtin(&builtinIoPipe, .{ .exact = 0 }));

    const popen_sym = try vm.intern("popen");
    try io_singleton.module.methods.put(popen_sym, value.MethodEntry.builtin(&builtinIoPopen, .{ .variadic = 0 }));

    const copy_stream_sym = try vm.intern("copy_stream");
    try io_singleton.module.methods.put(copy_stream_sym, value.MethodEntry.builtin(&builtinIoCopyStream, .{ .variadic = 2 }));

    const binread_sym = try vm.intern("binread");
    try io_singleton.module.methods.put(binread_sym, value.MethodEntry.builtin(&builtinIoBinread, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.io_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinIoInitialize, .{ .variadic = 1 }, .private));

    const to_io_sym = try vm.intern("to_io");
    try vm.io_class.module.methods.put(to_io_sym, value.MethodEntry.builtin(&builtinIoToIo, .{ .exact = 0 }));

    const pid_sym = try vm.intern("pid");
    try vm.io_class.module.methods.put(pid_sym, value.MethodEntry.builtin(&builtinIoPid, .{ .exact = 0 }));

    const external_encoding_sym = try vm.intern("external_encoding");
    try vm.io_class.module.methods.put(external_encoding_sym, value.MethodEntry.builtin(&builtinIoExternalEncoding, .{ .exact = 0 }));

    const internal_encoding_sym = try vm.intern("internal_encoding");
    try vm.io_class.module.methods.put(internal_encoding_sym, value.MethodEntry.builtin(&builtinIoInternalEncoding, .{ .exact = 0 }));

    const rdonly_sym = try vm.intern("RDONLY");
    try vm.io_class.module.constants.put(rdonly_sym, .{ .value = Value.integer(0) });
    const wronly_sym = try vm.intern("WRONLY");
    try vm.io_class.module.constants.put(wronly_sym, .{ .value = Value.integer(1) });
    const rdwr_sym = try vm.intern("RDWR");
    try vm.io_class.module.constants.put(rdwr_sym, .{ .value = Value.integer(2) });
    const append_sym_const = try vm.intern("APPEND");
    try vm.io_class.module.constants.put(append_sym_const, .{ .value = Value.integer(openFlagValue(.{ .APPEND = true })) });
    const trunc_sym = try vm.intern("TRUNC");
    try vm.io_class.module.constants.put(trunc_sym, .{ .value = Value.integer(openFlagValue(.{ .TRUNC = true })) });
    const creat_sym = try vm.intern("CREAT");
    try vm.io_class.module.constants.put(creat_sym, .{ .value = Value.integer(openFlagValue(.{ .CREAT = true })) });
    const excl_sym = try vm.intern("EXCL");
    try vm.io_class.module.constants.put(excl_sym, .{ .value = Value.integer(openFlagValue(.{ .EXCL = true })) });
    const binary_sym = try vm.intern("BINARY");
    try vm.io_class.module.constants.put(binary_sym, .{ .value = Value.integer(0) });
    const null_sym = try vm.intern("NULL");
    try vm.io_class.module.constants.put(null_sym, .{ .value = try vm.newString(null_device_path, false) });
    const seek_set_sym = try vm.intern("SEEK_SET");
    try vm.io_class.module.constants.put(seek_set_sym, .{ .value = Value.integer(0) });
    const seek_cur_sym = try vm.intern("SEEK_CUR");
    try vm.io_class.module.constants.put(seek_cur_sym, .{ .value = Value.integer(1) });
    const seek_end_sym = try vm.intern("SEEK_END");
    try vm.io_class.module.constants.put(seek_end_sym, .{ .value = Value.integer(2) });

    const nonblock_q_sym = try vm.intern("nonblock?");
    try vm.io_class.module.methods.put(nonblock_q_sym, value.MethodEntry.builtin(&builtinIoNonblockQ, .{ .exact = 0 }));

    const nonblock_set_sym = try vm.intern("nonblock=");
    try vm.io_class.module.methods.put(nonblock_set_sym, value.MethodEntry.builtin(&builtinIoNonblockSet, .{ .exact = 1 }));

    const nonblock_sym = try vm.intern("nonblock");
    try vm.io_class.module.methods.put(nonblock_sym, value.MethodEntry.builtin(&builtinIoNonblock, .{ .variadic = 0 }));

    const read_sym = try vm.intern("read");
    try vm.io_class.module.methods.put(read_sym, value.MethodEntry.builtin(&builtinIoRead, .{ .variadic = 0 }));

    const seek_sym = try vm.intern("seek");
    try vm.io_class.module.methods.put(seek_sym, value.MethodEntry.builtin(&builtinIoSeek, .{ .variadic = 0 }));

    const read_nonblock_sym = try vm.intern("read_nonblock");
    try vm.io_class.module.methods.put(read_nonblock_sym, value.MethodEntry.builtin(&builtinIoReadNonblock, .{ .variadic = 1 }));

    const readpartial_sym = try vm.intern("readpartial");
    try vm.io_class.module.methods.put(readpartial_sym, value.MethodEntry.builtin(&builtinIoReadpartial, .{ .variadic = 1 }));

    const chmod_sym = try vm.intern("chmod");
    try vm.io_class.module.methods.put(chmod_sym, value.MethodEntry.builtin(&builtinIoChmod, .{ .exact = 1 }));

    const write_sym = try vm.intern("write");
    try vm.io_class.module.methods.put(write_sym, value.MethodEntry.builtin(&builtinIoWrite, .{ .variadic = 0 }));

    const syswrite_sym = try vm.intern("syswrite");
    try vm.io_class.module.methods.put(syswrite_sym, value.MethodEntry.builtin(&builtinIoWrite, .{ .exact = 1 }));

    const append_sym = try vm.intern("<<");
    try vm.io_class.module.methods.put(append_sym, value.MethodEntry.builtin(&builtinIoAppend, .{ .exact = 1 }));

    const write_nonblock_sym = try vm.intern("write_nonblock");
    try vm.io_class.module.methods.put(write_nonblock_sym, value.MethodEntry.builtin(&builtinIoWriteNonblock, .{ .variadic = 1 }));

    const print_sym = try vm.intern("print");
    try vm.io_class.module.methods.put(print_sym, value.MethodEntry.builtin(&builtinIoPrint, .{ .variadic = 0 }));

    const puts_sym = try vm.intern("puts");
    try vm.io_class.module.methods.put(puts_sym, value.MethodEntry.builtin(&builtinIoPuts, .{ .variadic = 0 }));

    const flush_sym = try vm.intern("flush");
    try vm.io_class.module.methods.put(flush_sym, value.MethodEntry.builtin(&builtinIoFlush, .{ .exact = 0 }));

    const close_sym = try vm.intern("close");
    try vm.io_class.module.methods.put(close_sym, value.MethodEntry.builtin(&builtinIoClose, .{ .exact = 0 }));

    const closed_sym = try vm.intern("closed?");
    try vm.io_class.module.methods.put(closed_sym, value.MethodEntry.builtin(&builtinIoClosed, .{ .exact = 0 }));

    const eof_sym = try vm.intern("eof");
    try vm.io_class.module.methods.put(eof_sym, value.MethodEntry.builtin(&builtinIoEof, .{ .exact = 0 }));

    const eof_q_sym = try vm.intern("eof?");
    try vm.io_class.module.methods.put(eof_q_sym, value.MethodEntry.builtin(&builtinIoEof, .{ .exact = 0 }));

    const fileno_sym = try vm.intern("fileno");
    try vm.io_class.module.methods.put(fileno_sym, value.MethodEntry.builtin(&builtinIoFileno, .{ .exact = 0 }));

    const flock_sym = try vm.intern("flock");
    try vm.io_class.module.methods.put(flock_sym, value.MethodEntry.builtin(&builtinIoFlock, .{ .exact = 1 }));

    const path_sym = try vm.intern("path");
    try vm.io_class.module.methods.put(path_sym, value.MethodEntry.builtin(&builtinIoPath, .{ .exact = 0 }));

    const to_path_sym = try vm.intern("to_path");
    try vm.io_class.module.methods.put(to_path_sym, value.MethodEntry.builtin(&builtinIoPath, .{ .exact = 0 }));

    const pos_sym = try vm.intern("pos");
    try vm.io_class.module.methods.put(pos_sym, value.MethodEntry.builtin(&builtinIoPos, .{ .exact = 0 }));

    const tell_sym = try vm.intern("tell");
    try vm.io_class.module.methods.put(tell_sym, value.MethodEntry.builtin(&builtinIoPos, .{ .exact = 0 }));

    const pos_set_sym = try vm.intern("pos=");
    try vm.io_class.module.methods.put(pos_set_sym, value.MethodEntry.builtin(&builtinIoPosSet, .{ .exact = 1 }));

    const tty_q_sym = try vm.intern("tty?");
    try vm.io_class.module.methods.put(tty_q_sym, value.MethodEntry.builtin(&builtinIoTtyQ, .{ .exact = 0 }));

    const gets_sym = try vm.intern("gets");
    try vm.io_class.module.methods.put(gets_sym, value.MethodEntry.builtin(&builtinIoGets, .{ .variadic = 0 }));

    const readline_sym = try vm.intern("readline");
    try vm.io_class.module.methods.put(readline_sym, value.MethodEntry.builtin(&builtinIoReadline, .{ .variadic = 0 }));

    const rewind_sym = try vm.intern("rewind");
    try vm.io_class.module.methods.put(rewind_sym, value.MethodEntry.builtin(&builtinIoRewind, .{ .exact = 0 }));

    const lineno_sym = try vm.intern("lineno");
    try vm.io_class.module.methods.put(lineno_sym, value.MethodEntry.builtin(&builtinIoLineno, .{ .exact = 0 }));

    const lineno_set_sym = try vm.intern("lineno=");
    try vm.io_class.module.methods.put(lineno_set_sym, value.MethodEntry.builtin(&builtinIoLinenoSet, .{ .exact = 1 }));

    const each_sym = try vm.intern("each");
    try vm.io_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinIoEach, .{ .exact = 0 }));

    const each_line_sym = try vm.intern("each_line");
    try vm.io_class.module.methods.put(each_line_sym, value.MethodEntry.builtin(&builtinIoEach, .{ .exact = 0 }));

    const nread_sym = try vm.intern("nread");
    try vm.io_class.module.methods.put(nread_sym, value.MethodEntry.builtin(&builtinIoNread, .{ .exact = 0 }));

    const ready_q_sym = try vm.intern("ready?");
    try vm.io_class.module.methods.put(ready_q_sym, value.MethodEntry.builtin(&builtinIoReady, .{ .exact = 0 }));

    const wait_readable_sym = try vm.intern("wait_readable");
    try vm.io_class.module.methods.put(wait_readable_sym, value.MethodEntry.builtin(&builtinIoWaitReadable, .{ .variadic = 0 }));

    const wait_writable_sym = try vm.intern("wait_writable");
    try vm.io_class.module.methods.put(wait_writable_sym, value.MethodEntry.builtin(&builtinIoWaitWritable, .{ .variadic = 0 }));

    const binmode_sym = try vm.intern("binmode");
    try vm.io_class.module.methods.put(binmode_sym, value.MethodEntry.builtin(&builtinIoBinmode, .{ .exact = 0 }));

    const binmode_q_sym = try vm.intern("binmode?");
    try vm.io_class.module.methods.put(binmode_q_sym, value.MethodEntry.builtin(&builtinIoBinmodeQ, .{ .exact = 0 }));

    const sync_sym = try vm.intern("sync");
    try vm.io_class.module.methods.put(sync_sym, value.MethodEntry.builtin(&builtinIoSync, .{ .exact = 0 }));

    const sync_eq_sym = try vm.intern("sync=");
    try vm.io_class.module.methods.put(sync_eq_sym, value.MethodEntry.builtin(&builtinIoSyncEq, .{ .exact = 1 }));

    const autoclose_q_sym = try vm.intern("autoclose?");
    try vm.io_class.module.methods.put(autoclose_q_sym, value.MethodEntry.builtin(&builtinIoAutocloseQ, .{ .exact = 0 }));

    const autoclose_eq_sym = try vm.intern("autoclose=");
    try vm.io_class.module.methods.put(autoclose_eq_sym, value.MethodEntry.builtin(&builtinIoAutocloseEq, .{ .exact = 1 }));

    const reopen_sym = try vm.intern("reopen");
    try vm.io_class.module.methods.put(reopen_sym, value.MethodEntry.builtin(&builtinIoReopen, .{ .variadic = 1 }));
}

const PopenEnvEntry = struct {
    key: []const u8,
    value: []const u8,
};

const IoSelectKind = enum {
    read,
    write,
    except,
};

const IoSelectWatch = struct {
    original: Value,
    fd: i32,
    events: i16,
    kind: IoSelectKind,
    pollfd_index: usize = 0,
    fd_is_socket: bool = false,
};

fn selectFdIsSocket(fd: i32) bool {
    var optval: c_int = undefined;
    var optlen: std.c.socklen_t = @sizeOf(c_int);
    const rc = std.c.getsockopt(@intCast(fd), std.c.SOL.SOCKET, std.c.SO.TYPE, @ptrCast(&optval), &optlen);
    return rc == 0;
}

const PopenConfig = struct {
    env: std.ArrayList(PopenEnvEntry),
    argv: std.ArrayList([]const u8),
    exec_path: ?[]const u8 = null,
    shell_command: ?[]const u8 = null,
    chdir_path: ?[]const u8 = null,
    readable: bool = true,
    writable: bool = false,
    merge_stderr: bool = false,
    external_encoding: ?Value = null,
    internal_encoding: ?Value = null,

    fn init(_: std.mem.Allocator) PopenConfig {
        return .{
            .env = .empty,
            .argv = .empty,
        };
    }

    fn deinit(self: *PopenConfig, allocator: std.mem.Allocator) void {
        self.env.deinit(allocator);
        self.argv.deinit(allocator);
    }
};

fn hashKeyName(key: Value) ?[]const u8 {
    if (key.isSymbol()) return key.toSymbolObject().name;
    if (key.isString()) return key.toStringObject().str;
    return null;
}

fn parsePopenEnvHash(vm: *VM, env_hash: *value.HashObject, out: *std.ArrayList(PopenEnvEntry)) VMError!void {
    for (env_hash.entries.items) |entry| {
        const key = try entry.key.coerceToStr(vm, "no implicit conversion into String");
        const value_bytes = try entry.value.coerceToStr(vm, "no implicit conversion into String");
        out.append(vm.allocator, .{ .key = key, .value = value_bytes }) catch return error.Fatal;
    }
}

fn parsePopenExecOptions(_: *VM, options_hash: *value.HashObject, config: *PopenConfig) VMError!void {
    for (options_hash.entries.items) |entry| {
        const key_name = hashKeyName(entry.key) orelse continue;
        if (std.mem.eql(u8, key_name, "err")) {
            if (entry.value.isSymbol()) {
                const name = entry.value.toSymbolObject().name;
                if (std.mem.eql(u8, name, "out")) {
                    config.merge_stderr = true;
                }
            } else if (entry.value.isArray()) {
                const array = entry.value.toArrayObject().elements.items;
                if (array.len == 2 and array[0].isSymbol() and array[1].isSymbol()) {
                    const left = array[0].toSymbolObject().name;
                    const right = array[1].toSymbolObject().name;
                    if (std.mem.eql(u8, left, "child") and std.mem.eql(u8, right, "out")) {
                        config.merge_stderr = true;
                    }
                }
            }
        }
    }
}

fn parsePopenMode(vm: *VM, mode_value: Value, config: *PopenConfig) VMError!void {
    const mode = try mode_value.coerceToStr(vm, "no implicit conversion into String");
    if (std.mem.indexOfScalar(u8, mode, '+') != null) {
        config.readable = true;
        config.writable = true;
        return;
    }
    if (mode.len == 0 or mode[0] == 'r') {
        config.readable = true;
        config.writable = false;
        return;
    }
    if (mode[0] == 'w') {
        config.readable = false;
        config.writable = true;
        return;
    }
}

fn parsePopenArrayCommand(vm: *VM, array_value: Value, config: *PopenConfig) VMError!void {
    const items = array_value.toArrayObject().elements.items;
    var start: usize = 0;
    var end = items.len;

    if (start < end and items[start].isHash()) {
        try parsePopenEnvHash(vm, items[start].toHashObject(), &config.env);
        start += 1;
    }
    if (start < end and items[end - 1].isHash()) {
        try parsePopenExecOptions(vm, items[end - 1].toHashObject(), config);
        end -= 1;
    }
    if (start >= end) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given 0, expected 1+)", .{});
    }

    const first = items[start];
    if (first.isArray()) {
        const pair = first.toArrayObject().elements.items;
        if (pair.len >= 2) {
            config.exec_path = try pair[0].coerceToStr(vm, "no implicit conversion into String");
            config.argv.append(vm.allocator, try pair[1].coerceToStr(vm, "no implicit conversion into String")) catch return error.Fatal;
        }
    } else {
        const first_str = try first.coerceToStr(vm, "no implicit conversion into String");
        config.exec_path = first_str;
        config.argv.append(vm.allocator, first_str) catch return error.Fatal;
    }

    var i = start + 1;
    while (i < end) : (i += 1) {
        config.argv.append(vm.allocator, try items[i].coerceToStr(vm, "no implicit conversion into String")) catch return error.Fatal;
    }
}

fn parsePopenArgs(vm: *VM, args: []Value) VMError!PopenConfig {
    var config = PopenConfig.init(vm.allocator);
    errdefer config.deinit(vm.allocator);

    var external_encoding: ?Value = null;
    var internal_encoding: ?Value = null;
    var chdir_value: ?Value = null;
    var err_value: ?Value = null;
    try vm.consumeKeywordArgs(.{ "external_encoding", "internal_encoding", "chdir", "err" }, .{ &external_encoding, &internal_encoding, &chdir_value, &err_value });
    try vm.validateKeywordArgsConsumed();

    if (external_encoding) |val| config.external_encoding = val;
    if (internal_encoding) |val| config.internal_encoding = val;
    if (config.external_encoding != null and config.internal_encoding != null and config.external_encoding.?.raw == config.internal_encoding.?.raw) {
        config.internal_encoding = null;
    }
    if (chdir_value) |val| {
        config.chdir_path = try vm.coerceToPath(val, "no implicit conversion into String");
    }
    if (err_value) |val| {
        const hash = try vm.createHash();
        try vm.hashSetEntry(hash, Value.fromObject(&(try vm.intern("err")).object), val);
        try parsePopenExecOptions(vm, hash, &config);
    }

    var index: usize = 0;
    if (args.len > 0 and args[0].isHash()) {
        try parsePopenEnvHash(vm, args[0].toHashObject(), &config.env);
        index += 1;
    }
    if (index >= args.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given 0, expected 1+)", .{});
    }

    const command = args[index];
    index += 1;
    if (command.isArray()) {
        try parsePopenArrayCommand(vm, command, &config);
    } else {
        config.shell_command = try command.coerceToStr(vm, "no implicit conversion into String");
    }

    if (index < args.len) {
        try parsePopenMode(vm, args[index], &config);
        index += 1;
    }
    if (index != args.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments", .{});
    }

    return config;
}

fn closeFdIfOpen(fd: i32) void {
    if (fd >= 0) _ = std.c.close(@intCast(fd));
}

fn makeSocketPair(vm: *VM) VMError![2]i32 {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds) != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "socketpair failed", .{});
    }
    return .{ @intCast(fds[0]), @intCast(fds[1]) };
}

fn applyChildDup(fd: i32, target: i32) void {
    if (fd == target) return;
    _ = std.c.dup2(@intCast(fd), @intCast(target));
}

fn buildPopenEnvp(vm: *VM, config: *PopenConfig) VMError!struct {
    env_map: std.process.Environ.Map,
    env_strings: std.ArrayList([:0]u8),
    envp: std.ArrayList(?[*:0]const u8),
} {
    var env_map = try vm.currentEnvMap();
    errdefer env_map.deinit();
    for (config.env.items) |entry| {
        env_map.put(entry.key, entry.value) catch return error.Fatal;
    }

    var env_strings: std.ArrayList([:0]u8) = .empty;
    errdefer {
        for (env_strings.items) |item| vm.allocator.free(item);
        env_strings.deinit(vm.allocator);
    }
    var envp: std.ArrayList(?[*:0]const u8) = .empty;
    errdefer envp.deinit(vm.allocator);

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const combined = std.fmt.allocPrint(vm.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch return error.Fatal;
        defer vm.allocator.free(combined);
        const combined_z = try vm.allocCStringZ(combined);
        env_strings.append(vm.allocator, combined_z) catch return error.Fatal;
        envp.append(vm.allocator, combined_z.ptr) catch return error.Fatal;
    }
    envp.append(vm.allocator, null) catch return error.Fatal;

    return .{
        .env_map = env_map,
        .env_strings = env_strings,
        .envp = envp,
    };
}

fn buildPopenArgv(vm: *VM, config: *PopenConfig, env_map: *const std.process.Environ.Map) VMError!struct {
    path_z: [:0]u8,
    arg_strings: std.ArrayList([:0]u8),
    argv: std.ArrayList(?[*:0]const u8),
} {
    const exec_path = config.exec_path orelse if (config.shell_command != null) "/bin/sh" else unreachable;
    const path_z = try vm.resolveExecPathFromEnvMap(env_map, exec_path);
    errdefer vm.allocator.free(path_z);

    var arg_strings: std.ArrayList([:0]u8) = .empty;
    errdefer {
        for (arg_strings.items) |item| vm.allocator.free(item);
        arg_strings.deinit(vm.allocator);
    }
    var argv: std.ArrayList(?[*:0]const u8) = .empty;
    errdefer argv.deinit(vm.allocator);

    if (config.shell_command) |shell_command| {
        const sh0 = try vm.allocCStringZ("sh");
        const shc = try vm.allocCStringZ("-c");
        const cmd = try vm.allocCStringZ(shell_command);
        arg_strings.append(vm.allocator, sh0) catch return error.Fatal;
        arg_strings.append(vm.allocator, shc) catch return error.Fatal;
        arg_strings.append(vm.allocator, cmd) catch return error.Fatal;
        argv.append(vm.allocator, sh0.ptr) catch return error.Fatal;
        argv.append(vm.allocator, shc.ptr) catch return error.Fatal;
        argv.append(vm.allocator, cmd.ptr) catch return error.Fatal;
    } else {
        for (config.argv.items) |arg| {
            const arg_z = try vm.allocCStringZ(arg);
            arg_strings.append(vm.allocator, arg_z) catch return error.Fatal;
            argv.append(vm.allocator, arg_z.ptr) catch return error.Fatal;
        }
    }
    argv.append(vm.allocator, null) catch return error.Fatal;

    return .{
        .path_z = path_z,
        .arg_strings = arg_strings,
        .argv = argv,
    };
}

fn popenSpawn(vm: *VM, receiver: Value, config: *PopenConfig) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "IO.popen is not implemented on Windows", .{});
    }

    const io_class = if (receiver.isClass()) receiver.toClassObject() else vm.io_class;

    var envp_data = try buildPopenEnvp(vm, config);
    defer {
        envp_data.env_map.deinit();
        for (envp_data.env_strings.items) |item| vm.allocator.free(item);
        envp_data.env_strings.deinit(vm.allocator);
        envp_data.envp.deinit(vm.allocator);
    }

    var argv_data = try buildPopenArgv(vm, config, &envp_data.env_map);
    defer {
        vm.allocator.free(argv_data.path_z);
        for (argv_data.arg_strings.items) |item| vm.allocator.free(item);
        argv_data.arg_strings.deinit(vm.allocator);
        argv_data.argv.deinit(vm.allocator);
    }

    var parent_fd: i32 = -1;
    var child_stdin_fd: i32 = -1;
    var child_stdout_fd: i32 = -1;
    var extra_child_fd: i32 = -1;

    if (config.readable and config.writable) {
        const fds = try makeSocketPair(vm);
        parent_fd = fds[0];
        child_stdin_fd = fds[1];
        child_stdout_fd = fds[1];
        extra_child_fd = fds[1];
    } else if (config.readable) {
        var fds: [2]std.c.fd_t = undefined;
        if (std.c.pipe(&fds) != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "pipe failed", .{});
        }
        parent_fd = @intCast(fds[0]);
        child_stdout_fd = @intCast(fds[1]);
    } else if (config.writable) {
        var fds: [2]std.c.fd_t = undefined;
        if (std.c.pipe(&fds) != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "pipe failed", .{});
        }
        child_stdin_fd = @intCast(fds[0]);
        parent_fd = @intCast(fds[1]);
    }
    errdefer closeFdIfOpen(parent_fd);
    errdefer closeFdIfOpen(child_stdin_fd);
    errdefer closeFdIfOpen(child_stdout_fd);

    const pid = std.c.fork();
    if (pid < 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "fork failed", .{});
    }

    if (pid == 0) {
        if (config.readable and config.writable) {
            closeFdIfOpen(parent_fd);
            applyChildDup(child_stdin_fd, 0);
            applyChildDup(child_stdout_fd, 1);
            if (config.merge_stderr) applyChildDup(child_stdout_fd, 2);
            if (extra_child_fd >= 0) closeFdIfOpen(extra_child_fd);
        } else {
            if (config.readable) {
                closeFdIfOpen(parent_fd);
                applyChildDup(child_stdout_fd, 1);
                if (config.merge_stderr) applyChildDup(child_stdout_fd, 2);
                closeFdIfOpen(child_stdout_fd);
            }
            if (config.writable) {
                closeFdIfOpen(parent_fd);
                applyChildDup(child_stdin_fd, 0);
                closeFdIfOpen(child_stdin_fd);
            }
        }

        if (config.chdir_path) |path| {
            const path_z = vm.allocCStringZ(path) catch std.c._exit(127);
            defer vm.allocator.free(path_z);
            if (std.c.chdir(path_z.ptr) != 0) std.c._exit(127);
        }

        _ = execve(argv_data.path_z.ptr, @ptrCast(argv_data.argv.items.ptr), @ptrCast(envp_data.envp.items.ptr));
        std.c._exit(127);
    }

    if (config.readable and config.writable) {
        closeFdIfOpen(child_stdin_fd);
    } else {
        closeFdIfOpen(child_stdin_fd);
        closeFdIfOpen(child_stdout_fd);
    }

    const io_value = try vm.newIo(io_class, parent_fd, .{
        .owns_fd = true,
        .readable = config.readable,
        .writable = config.writable,
    });
    try vm.setInstanceVariable(io_value, "@pid", Value.integer(pid));
    try vm.setInstanceVariable(io_value, "@child_process", Value.boolean(true));
    if (config.external_encoding) |encoding| {
        try vm.setInstanceVariable(io_value, "@external_encoding", encoding);
    }
    if (config.internal_encoding) |encoding| {
        try vm.setInstanceVariable(io_value, "@internal_encoding", encoding);
    }
    return io_value;
}

pub fn builtinIoPopen(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    var config = try parsePopenArgs(vm, args);
    defer config.deinit(vm.allocator);

    const io_value = try popenSpawn(vm, receiver, &config);
    if (block) |blk| {
        const yielded = vm.yieldToBlock(blk, &[_]Value{io_value}) catch |err| {
            _ = builtinIoClose(vm, io_value, &[_]Value{}, null) catch {};
            return err;
        };
        _ = builtinIoClose(vm, io_value, &[_]Value{}, null) catch {};
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }
    return io_value;
}

pub fn builtinIoPipe(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const io_class = if (receiver.isClass()) receiver.toClassObject() else vm.io_class;

    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "pipe failed", .{});
    }
    errdefer {
        _ = std.c.close(fds[0]);
        _ = std.c.close(fds[1]);
    }

    const read_io = try vm.newIo(io_class, @intCast(fds[0]), .{ .owns_fd = true, .readable = true, .writable = false });
    const write_io = try vm.newIo(io_class, @intCast(fds[1]), .{ .owns_fd = true, .readable = false, .writable = true });
    try ensureIoNonblocking(vm, read_io.toIoObject());
    try ensureIoNonblocking(vm, write_io.toIoObject());

    const pair = try vm.createArray();
    pair.elements.append(vm.gc_allocator, read_io) catch return error.Fatal;
    pair.elements.append(vm.gc_allocator, write_io) catch return error.Fatal;
    return Value.fromObject(&pair.object);
}

pub fn builtinIoCopyStream(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 4);
    const src_arg = args[0];
    const dst_arg = args[1];
    // Optional length limit (3rd arg) — nil means unlimited
    const max_len: ?i64 = if (args.len >= 3 and !args[2].isNil()) blk: {
        if (!args[2].isInteger()) return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        break :blk args[2].toInteger();
    } else null;

    var total: i64 = 0;
    var buf: [8192]u8 = undefined;

    // Resolve destination: raw IO, string path, or IO-like (write method)
    const dst_is_raw_io = dst_arg.isIo();
    var dst_fd: i32 = -1;
    var dst_opened = false;
    if (dst_is_raw_io) {
        const dst = try requireIoReceiver(vm, dst_arg);
        try ensureIoWritable(vm, dst);
        dst_fd = dst.fd;
    } else if (dst_arg.isString()) {
        const path = dst_arg.toStringObject().str;
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);
        const flags: std.c.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true };
        const fd = std.c.open(path_z.ptr, flags, @as(std.c.mode_t, 0o666));
        if (fd < 0) return vm.raiseErrnoFmt(std.posix.errno(fd), "failed to open: {s}", .{path});
        dst_fd = fd;
        dst_opened = true;
    }
    defer if (dst_opened) {
        _ = std.c.close(dst_fd);
    };

    const writeChunkToDst = struct {
        fn call(vm2: *VM, dst_arg2: Value, dst_fd2: i32, dst_is_fd: bool, bytes: []const u8) VMError!void {
            if (dst_is_fd) {
                _ = std.c.write(dst_fd2, bytes.ptr, bytes.len);
            } else {
                const chunk = try vm2.newString(bytes, false);
                var write_args = [1]Value{chunk};
                _ = try vm2.callMethodByName(dst_arg2, "write", &write_args, null);
            }
        }
    }.call;

    const dst_is_fd = dst_is_raw_io or dst_opened;

    // Read from source: raw IO, string path, or IO-like (read method)
    if (src_arg.isIo()) {
        const src = try requireIoReceiver(vm, src_arg);
        try ensureIoReadable(vm, src);
        while (true) {
            if (max_len) |limit| if (total >= limit) break;
            const to_read = if (max_len) |limit| @min(buf.len, @as(usize, @intCast(limit - total))) else buf.len;
            const n = std.posix.read(@intCast(src.fd), buf[0..to_read]) catch break;
            if (n == 0) break;
            try writeChunkToDst(vm, dst_arg, dst_fd, dst_is_fd, buf[0..n]);
            total += @intCast(n);
        }
    } else if (src_arg.isString()) {
        const path = src_arg.toStringObject().str;
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);
        const flags: std.c.O = .{ .ACCMODE = .RDONLY };
        const fd = std.c.open(path_z.ptr, flags, @as(std.c.mode_t, 0o666));
        if (fd < 0) return vm.raiseErrnoFmt(std.posix.errno(fd), "failed to open: {s}", .{path});
        defer _ = std.c.close(fd);
        while (true) {
            if (max_len) |limit| if (total >= limit) break;
            const to_read = if (max_len) |limit| @min(buf.len, @as(usize, @intCast(limit - total))) else buf.len;
            const n = std.posix.read(fd, buf[0..to_read]) catch break;
            if (n == 0) break;
            try writeChunkToDst(vm, dst_arg, dst_fd, dst_is_fd, buf[0..n]);
            total += @intCast(n);
        }
    } else {
        // IO-like source: call read in a loop until nil/empty/EOFError
        while (true) {
            if (max_len) |limit| if (total >= limit) break;
            const chunk_size = if (max_len) |limit| @min(@as(i64, 8192), limit - total) else @as(i64, 8192);
            var len_arg = Value.integer(chunk_size);
            const chunk = vm.callMethodByName(src_arg, "read", @as([]Value, (&len_arg)[0..1]), null) catch |err| {
                if (err == error.Unwind) {
                    vm.setPendingException(null);
                    break;
                }
                return err;
            };
            if (chunk.isNil()) break;
            if (!chunk.isString()) break;
            const s = chunk.toStringObject().str;
            if (s.len == 0) break;
            try writeChunkToDst(vm, dst_arg, dst_fd, dst_is_fd, s);
            total += @intCast(s.len);
        }
    }

    return Value.integer(total);
}

pub fn builtinIoBinread(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);
    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");

    const path_z = try vm.allocCStringZ(path);
    defer vm.allocator.free(path_z);
    const flags: std.c.O = .{
        .ACCMODE = .RDONLY,
    };
    const fd = std.c.open(path_z.ptr, flags, @as(std.c.mode_t, 0o666));
    if (fd < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(fd), "could not open file: {s}", .{path});
    }
    errdefer _ = std.c.close(fd);

    if (args.len >= 3) {
        const offset_val = args[2];
        if (!offset_val.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        const offset = offset_val.toInteger();
        if (offset < 0) {
            _ = std.c.lseek(fd, offset, 0);
            const errno_val = std.c._errno().*;
            return vm.raiseErrnoFmt(@enumFromInt(errno_val), "invalid argument", .{});
        }
        const result = std.c.lseek(fd, offset, 0);
        if (result < 0) {
            const errno_val = std.c._errno().*;
            return vm.raiseErrnoFmt(@enumFromInt(errno_val), "seek failed", .{});
        }
    }

    if (args.len == 1) {
        var buf: [4096]u8 = undefined;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(vm.allocator);
        while (true) {
            const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
            if (n == 0) break;
            out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        }
        return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    const len_val = args[1];
    if (!len_val.isInteger() and !len_val.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const len: ?i64 = if (len_val.isNil()) null else len_val.toInteger();
    if (len != null and len.? < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len.?});
    }

    if (len == null) {
        var buf: [4096]u8 = undefined;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(vm.allocator);
        while (true) {
            const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
            if (n == 0) break;
            out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        }
        return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    const len_usize: usize = @intCast(len.?);
    if (len_usize == 0) {
        return vm.newStringWithEncoding(&[_]u8{}, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    out.ensureTotalCapacity(vm.allocator, len_usize) catch return error.Fatal;

    var remaining = len_usize;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const n = std.posix.read(fd, buf[0..to_read]) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        remaining -= n;
    }

    return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
}

pub fn builtinIoToIo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    return receiver;
}

pub fn builtinIoPid(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    if (io.closed and (try vm.getInstanceVariable(receiver, "@child_process")).isTruthy()) {
        return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});
    }
    return vm.getInstanceVariable(receiver, "@pid");
}

pub fn builtinIoExternalEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    const explicit = try vm.getInstanceVariable(receiver, "@external_encoding");
    if (!explicit.isNil()) return explicit;
    return Value.fromObject(&vm.default_external_encoding.object);
}

pub fn builtinIoInternalEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    const explicit = try vm.getInstanceVariable(receiver, "@internal_encoding");
    if (!explicit.isNil()) return explicit;
    return if (vm.default_internal_encoding) |encoding| Value.fromObject(&encoding.object) else Value.nil();
}

pub fn builtinIoBinmode(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, receiver.toIoObject());
    const binary_encoding = Value.fromObject(&vm.encoding_ascii_8bit.object);
    try vm.setInstanceVariable(receiver, "@external_encoding", binary_encoding);
    try vm.setInstanceVariable(receiver, "@internal_encoding", Value.nil());
    return receiver;
}

pub fn builtinIoBinmodeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, receiver.toIoObject());
    const ext = try vm.getInstanceVariable(receiver, "@external_encoding");
    if (ext.isEncoding()) {
        const encoding_obj = ext.toEncodingObject();
        return Value.boolean(encoding_obj.encoding == .ascii_8bit);
    }
    return Value.boolean(false);
}

pub fn builtinIoSync(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    return Value.boolean(io.sync);
}

pub fn builtinIoSyncEq(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    io.sync = args[0].isTruthy();
    return args[0];
}

pub fn builtinIoNonblockQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    return Value.boolean(try ioIsNonblocking(vm, io));
}

pub fn builtinIoNonblockSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    try setIoNonblocking(vm, io, args[0].isTruthy());
    return receiver;
}

pub fn builtinIoNonblock(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    const blk = try vm.requireBlock(block);
    const desired = if (args.len == 0) true else args[0].isTruthy();
    const original = try ioIsNonblocking(vm, io);

    if (original == desired) {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{receiver});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }

    try setIoNonblocking(vm, io, desired);
    const yielded = vm.yieldToBlock(blk, &[_]Value{receiver}) catch |err| {
        try setIoNonblocking(vm, io, original);
        return err;
    };
    try setIoNonblocking(vm, io, original);
    if (yielded.controlFlowValue()) |return_value| return return_value;
    return yielded.value;
}

fn findLineEnd(data: []const u8, separator: ?[]const u8, limit: ?usize) ?usize {
    if (limit) |max_len| {
        if (data.len >= max_len) return max_len;
    }
    if (separator) |sep| {
        if (sep.len == 0) {
            if (std.mem.indexOf(u8, data, "\n\n")) |pos| return pos + 2;
        } else {
            if (std.mem.indexOf(u8, data, sep)) |pos| return pos + sep.len;
        }
    }
    return null;
}

fn ensureIoReadBuf(vm: *VM, io: *IoObject) VMError!void {
    if (io.read_buf == null) {
        io.read_buf = vm.allocator.alloc(u8, 8192) catch return error.Fatal;
        io.read_buf_offset = 0;
        io.read_buf_avail = 0;
    }
}

pub fn builtinIoGets(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    var separator: ?[]const u8 = "\n";
    var limit: ?usize = null;

    if (args.len >= 1) {
        if (args[0].isNil()) {
            separator = null;
        } else if (args[0].isInteger()) {
            const parsed_limit = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer too big to convert into `long`");
            if (parsed_limit < 0) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "negative limit {d} given", .{parsed_limit});
            }
            limit = @intCast(parsed_limit);
        } else {
            separator = (try args[0].coerceToStringValue(vm, "no implicit conversion into String")).toStringObject().str;
        }
    }

    if (args.len == 2 and !args[1].isNil()) {
        const parsed_limit = try args[1].integerArgToI64(vm, "no implicit conversion into Integer", "integer too big to convert into `long`");
        if (parsed_limit < 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "negative limit {d} given", .{parsed_limit});
        }
        limit = @intCast(parsed_limit);
    }

    if (limit != null and limit.? == 0) {
        io.lineno += 1;
        return vm.newString("", false);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    // Phase 1: consume buffered data from previous gets call
    if (io.read_buf) |buf| {
        const avail = io.read_buf_avail - io.read_buf_offset;
        if (avail > 0) {
            out.appendSlice(vm.allocator, buf[io.read_buf_offset..io.read_buf_avail]) catch return error.Fatal;
            io.read_buf_offset = io.read_buf_avail;
        }
        if (findLineEnd(out.items, separator, limit)) |end| {
            if (end < out.items.len) {
                const excess = out.items[end..];
                try ensureIoReadBuf(vm, io);
                @memcpy(io.read_buf.?[0..excess.len], excess);
                io.read_buf_avail = excess.len;
                io.read_buf_offset = 0;
                out.shrinkRetainingCapacity(end);
            }
            io.lineno += 1;
            return vm.newString(out.items, false);
        }
        io.read_buf_offset = 0;
        io.read_buf_avail = 0;
    }

    // Phase 2: read chunks from fd, scanning byte-by-byte for separator/limit
    var chunk: [8192]u8 = undefined;
    while (true) {
        const n = try blockingIoRead(vm, io, chunk[0..]);
        if (n == 0) {
            if (out.items.len == 0) return Value.nil();
            break;
        }

        var i: usize = 0;
        var done = false;
        while (i < n and !done) {
            out.append(vm.allocator, chunk[i]) catch return error.Fatal;
            i += 1;

            if (limit) |max_len| {
                if (out.items.len >= max_len) done = true;
            }
            if (!done) {
                if (separator) |sep| {
                    if (sep.len == 0) {
                        if (out.items.len >= 2 and out.items[out.items.len - 1] == '\n' and out.items[out.items.len - 2] == '\n')
                            done = true;
                    } else if (out.items.len >= sep.len) {
                        if (std.mem.eql(u8, out.items[out.items.len - sep.len ..], sep))
                            done = true;
                    }
                }
            }
        }

        if (done) {
            if (i < n) {
                try ensureIoReadBuf(vm, io);
                const remaining = n - i;
                @memcpy(io.read_buf.?[0..remaining], chunk[i..n]);
                io.read_buf_avail = remaining;
                io.read_buf_offset = 0;
            }
            io.lineno += 1;
            return vm.newString(out.items, false);
        }
    }

    io.lineno += 1;
    return vm.newString(out.items, false);
}

pub fn builtinIoTtyQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    return Value.boolean(std.c.isatty(@intCast(io.fd)) == 1);
}

pub fn builtinIoEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };

    var empty_args = [_]Value{};
    while (true) {
        const line = try builtinIoGets(vm, receiver, empty_args[0..], null);
        if (line.isNil()) break;
        const yield_args = [_]Value{line};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

fn requireIoReceiver(vm: *VM, receiver: Value) VMError!*IoObject {
    if (receiver.isIo()) return receiver.toIoObject();
    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});
}

const IoOpenMode = struct {
    readable: bool,
    writable: bool,
    append: bool,
    create: bool,
    truncate: bool,
};

fn parseIoModeValue(vm: *VM, mode_value: Value) VMError!IoOpenMode {
    if (mode_value.isInteger()) {
        return switch (@as(i64, @intCast(@mod(mode_value.toInteger(), 4)))) {
            0 => .{ .readable = true, .writable = false, .append = false, .create = false, .truncate = false },
            1 => .{ .readable = false, .writable = true, .append = false, .create = false, .truncate = false },
            2 => .{ .readable = true, .writable = true, .append = false, .create = false, .truncate = false },
            else => .{ .readable = true, .writable = false, .append = false, .create = false, .truncate = false },
        };
    }

    const mode = try mode_value.coerceToStr(vm, "no implicit conversion into String");
    const plus = std.mem.indexOfScalar(u8, mode, '+') != null;
    if (mode.len == 0 or mode[0] == 'r') {
        return .{ .readable = true, .writable = plus, .append = false, .create = false, .truncate = false };
    }
    if (mode[0] == 'w') {
        return .{ .readable = plus, .writable = true, .append = false, .create = true, .truncate = true };
    }
    if (mode[0] == 'a') {
        return .{ .readable = plus, .writable = true, .append = true, .create = true, .truncate = false };
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode", .{});
}

pub fn builtinIoInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    var path_value: ?Value = null;
    var autoclose_value: ?Value = null;
    var mode_keyword: ?Value = null;
    try vm.consumeKeywordArgs(.{ "path", "autoclose", "mode" }, .{ &path_value, &autoclose_value, &mode_keyword });
    try vm.validateKeywordArgsConsumed();

    const io = try requireIoReceiver(vm, receiver);
    const fd_value = try args[0].coerceToIntegerValue(vm, "no implicit conversion to Integer", "can't convert to Integer");
    if (!fd_value.isInteger()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "bignum too big to convert into `long'", .{});
    }

    const mode_value = if (mode_keyword != null and !mode_keyword.?.isNil()) mode_keyword.? else if (args.len == 2 and !args[1].isNil()) args[1] else null;
    const mode: IoOpenMode = if (mode_value) |val|
        try parseIoModeValue(vm, val)
    else
        .{ .readable = true, .writable = false, .append = false, .create = false, .truncate = false };

    io.fd = @intCast(fd_value.toInteger());
    io.owns_fd = if (autoclose_value) |val| val.isTruthy() else true;
    io.closed = false;
    io.readable = mode.readable;
    io.writable = mode.writable;
    io.append = mode.append;
    io.path = null;
    io.path_encoding = null;

    if (path_value) |val| {
        const path = try vm.coerceToPathValue(val, "no implicit conversion into String");
        io.path = vm.gc_allocator.dupe(u8, path.toStringObject().str) catch return error.Fatal;
        io.path_encoding = path.toStringObject().encoding;
    }

    return Value.nil();
}

fn builtinIoAutocloseQ(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    return Value.boolean(io.owns_fd);
}

fn builtinIoAutocloseEq(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    io.owns_fd = args[0].isTruthy();
    return args[0];
}

fn builtinIoReopen(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const io = try requireIoReceiver(vm, receiver);

    if (args[0].isIo()) {
        const other = try requireIoReceiver(vm, args[0]);
        try ensureIoOpen(vm, other);
        if (std.c.dup2(@intCast(other.fd), @intCast(io.fd)) < 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "dup2 failed", .{});
        }
        io.closed = false;
        io.readable = other.readable;
        io.writable = other.writable;
        io.append = other.append;
        io.path = other.path;
        io.path_encoding = other.path_encoding;
        return receiver;
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const mode: IoOpenMode = if (args.len == 2 and !args[1].isNil())
        try parseIoModeValue(vm, args[1])
    else
        .{
            .readable = io.readable,
            .writable = io.writable,
            .append = io.append,
            .create = io.writable or io.append,
            .truncate = io.writable and !io.readable and !io.append,
        };

    const flags: std.c.O = .{
        .ACCMODE = if (mode.readable and mode.writable) .RDWR else if (mode.writable) .WRONLY else .RDONLY,
        .APPEND = mode.append,
        .CREAT = mode.create,
        .TRUNC = mode.truncate,
    };
    const path = path_value.toStringObject().str;
    const path_z = try vm.allocCStringZ(path);
    defer vm.allocator.free(path_z);
    const fd = std.c.open(path_z.ptr, flags, @as(std.c.mode_t, 0o666));
    if (fd < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "failed to open: {s}", .{path});
    }
    defer _ = std.c.close(fd);

    if (std.c.dup2(@intCast(fd), @intCast(io.fd)) < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "dup2 failed", .{});
    }

    io.closed = false;
    io.readable = mode.readable;
    io.writable = mode.writable;
    io.append = mode.append;
    io.path = vm.gc_allocator.dupe(u8, path) catch return error.Fatal;
    io.path_encoding = path_value.toStringObject().encoding;
    return receiver;
}

fn ensureIoOpen(vm: *VM, io: *IoObject) VMError!void {
    if (io.closed) {
        return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});
    }
}

fn ensureIoReadable(vm: *VM, io: *IoObject) VMError!void {
    try ensureIoOpen(vm, io);
    if (!io.readable) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for reading", .{});
    }
}

fn ensureIoWritable(vm: *VM, io: *IoObject) VMError!void {
    try ensureIoOpen(vm, io);
    if (!io.writable) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for writing", .{});
    }
}

fn timeoutArgToSeconds(vm: *VM, timeout: Value) VMError!?f64 {
    if (timeout.isNil()) return null;
    if (timeout.isInteger()) return timeout.integerToF64();
    if (timeout.isFloat()) {
        const seconds = timeout.toFloatObject().val;
        if (std.math.isNan(seconds)) {
            return vm.raiseExceptionFmt(vm.range_error_class, "NaN out of Time range", .{});
        }
        if (std.math.isInf(seconds)) {
            if (seconds < 0) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must not be negative", .{});
            }
            return null;
        }
        return seconds;
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into time interval", .{vm.className(timeout)});
}

fn timeoutArgToPollMilliseconds(vm: *VM, timeout: Value) VMError!i32 {
    const seconds = (try timeoutArgToSeconds(vm, timeout)) orelse return -1;
    if (seconds < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must not be negative", .{});
    }

    const max_ms = @as(f64, @floatFromInt(std.math.maxInt(i32)));
    const ms = seconds * 1000.0;
    if (ms >= max_ms) return std.math.maxInt(i32);
    return @intFromFloat(@floor(ms));
}

fn waitForIo(vm: *VM, io: *IoObject, events: i16, timeout_ms: i32, include_hup: bool) VMError!bool {
    var fds = [_]std.posix.pollfd{.{
        .fd = @intCast(io.fd),
        .events = events,
        .revents = 0,
    }};
    const ready_mask = blk: {
        var mask = events | std.posix.POLL.ERR;
        if (include_hup) mask |= std.posix.POLL.HUP;
        break :blk mask;
    };

    const current_thread = vm.current_thread;
    const is_worker_thread = current_thread != null and vm.main_thread != null and current_thread.? != vm.main_thread.?;
    if (!is_worker_thread) {
        const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;

        while (true) {
            try vm.checkAsyncEvents();

            const step_timeout_ms: i32 = if (deadline_ms) |deadline| blk: {
                const remaining = deadline - monotonicMilliseconds();
                if (remaining <= 0) break :blk 0;
                break :blk @intCast(@min(remaining, 100));
            } else 100;

            const ready_count = std.c.poll(fds[0..].ptr, @intCast(fds[0..].len), step_timeout_ms);
            if (ready_count < 0) {
                const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
                if (errno_code == .INTR) {
                    try vm.checkAsyncEvents();
                    continue;
                }
                return vm.raiseErrnoFmt(errno_code, "poll failed", .{});
            }
            try vm.checkAsyncEvents();
            if (ready_count == 0) {
                if (deadline_ms != null and step_timeout_ms == 0) return false;
                try yieldSleepingMainThread(vm);
                continue;
            }
            return (fds[0].revents & ready_mask) != 0;
        }
    }

    const thread = current_thread.?;
    const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;
    defer {
        thread.io_wait = null;
        if (thread.state == .sleeping) thread.state = .running;
    }

    while (true) {
        try vm.checkAsyncEvents();
        const ready_count = std.c.poll(fds[0..].ptr, @intCast(fds[0..].len), 0);
        if (ready_count < 0) {
            const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
            if (errno_code == .INTR) {
                try vm.checkAsyncEvents();
                continue;
            }
            return vm.raiseErrnoFmt(errno_code, "poll failed", .{});
        }
        if (ready_count != 0) {
            return (fds[0].revents & ready_mask) != 0;
        }

        if (deadline_ms) |deadline| {
            if (monotonicMilliseconds() >= deadline) return false;
        }

        thread.io_wait = .{
            .fd = io.fd,
            .events = events,
            .include_hup = include_hup,
            .deadline_ms = deadline_ms,
        };
        thread.state = .sleeping;
        try vm.threadYield();
    }
}

fn waitReadable(vm: *VM, io: *IoObject, timeout_ms: i32) VMError!bool {
    return waitForIo(vm, io, std.posix.POLL.IN, timeout_ms, true);
}

fn waitWritable(vm: *VM, io: *IoObject, timeout_ms: i32) VMError!bool {
    return waitForIo(vm, io, std.posix.POLL.OUT, timeout_ms, false);
}

fn requireSelectArrayArg(vm: *VM, arg: Value) VMError!?*value.ArrayObject {
    if (arg.isNil()) return null;
    if (arg.isArray()) return arg.toArrayObject();
    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into Array", .{vm.className(arg)});
}

fn selectWatchEvent(kind: IoSelectKind) i16 {
    return switch (kind) {
        .read => std.posix.POLL.IN,
        .write => std.posix.POLL.OUT,
        .except => std.posix.POLL.PRI,
    };
}

fn selectReadyMask(kind: IoSelectKind) i16 {
    return switch (kind) {
        .read => std.posix.POLL.IN | std.posix.POLL.ERR | std.posix.POLL.HUP,
        .write => std.posix.POLL.OUT | std.posix.POLL.ERR,
        .except => std.posix.POLL.PRI,
    };
}

fn selectWatchIo(vm: *VM, object: Value) VMError!*IoObject {
    if (object.isIo()) return object.toIoObject();

    const maybe_io = try vm.checkCallMethodByName(object, "to_io", false, &[_]Value{}, null);
    const io_value = maybe_io orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into IO", .{vm.className(object)});
    };
    if (!io_value.isIo()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into IO", .{vm.className(object)});
    }
    return io_value.toIoObject();
}

fn appendSelectWatches(vm: *VM, watches: *std.ArrayList(IoSelectWatch), array: ?*value.ArrayObject, kind: IoSelectKind) VMError!void {
    const source = array orelse return;
    for (source.elements.items) |object| {
        const io = try selectWatchIo(vm, object);
        watches.append(vm.allocator, .{
            .original = object,
            .fd = io.fd,
            .events = selectWatchEvent(kind),
            .kind = kind,
            .fd_is_socket = selectFdIsSocket(io.fd),
        }) catch return error.Fatal;
    }
}

fn selectPollfds(vm: *VM, watches: []IoSelectWatch) VMError!std.ArrayList(std.posix.pollfd) {
    var pollfds: std.ArrayList(std.posix.pollfd) = .empty;
    errdefer pollfds.deinit(vm.allocator);
    var fd_to_index = std.AutoHashMap(i32, usize).init(vm.allocator);
    defer fd_to_index.deinit();

    pollfds.ensureTotalCapacity(vm.allocator, watches.len) catch return error.Fatal;
    for (watches) |*watch| {
        if (fd_to_index.get(watch.fd)) |index| {
            watch.pollfd_index = index;
            pollfds.items[index].events |= watch.events;
            continue;
        }

        const index = pollfds.items.len;
        pollfds.appendAssumeCapacity(.{
            .fd = @intCast(watch.fd),
            .events = watch.events,
            .revents = 0,
        });
        fd_to_index.put(watch.fd, index) catch return error.Fatal;
        watch.pollfd_index = index;
    }
    return pollfds;
}

fn selectResetPollfds(pollfds: []std.posix.pollfd) void {
    for (pollfds) |*pollfd| pollfd.revents = 0;
}

fn selectRaiseIfInvalid(vm: *VM, pollfds: []const std.posix.pollfd) VMError!void {
    for (pollfds) |pollfd| {
        if ((pollfd.revents & std.posix.POLL.NVAL) != 0) {
            return vm.raiseErrnoFmt(.BADF, "poll failed", .{});
        }
    }
}

fn selectResult(vm: *VM, watches: []const IoSelectWatch, pollfds: []const std.posix.pollfd) VMError!Value {
    const read_array = try vm.createArray();
    const write_array = try vm.createArray();
    const error_array = try vm.createArray();

    var any_ready = false;
    for (watches) |watch| {
        const pollfd = pollfds[watch.pollfd_index];
        const ready_mask = if (watch.kind == .except and !watch.fd_is_socket)
            @as(i16, 0)
        else
            selectReadyMask(watch.kind);
        if ((pollfd.revents & ready_mask) == 0) continue;
        any_ready = true;
        const target = switch (watch.kind) {
            .read => read_array,
            .write => write_array,
            .except => error_array,
        };
        target.elements.append(vm.gc_allocator, watch.original) catch return error.Fatal;
    }

    if (!any_ready) return Value.nil();

    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, Value.fromObject(&read_array.object)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.fromObject(&write_array.object)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.fromObject(&error_array.object)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

fn yieldSleepingMainThread(vm: *VM) VMError!void {
    const thread = vm.current_thread orelse return;
    const main_thread = vm.main_thread orelse return;
    if (thread != main_thread) return;

    thread.state = .sleeping;
    defer {
        if (thread.state == .sleeping) thread.state = .running;
    }
    try vm.schedulerYield();
}

fn ioSelectWaitNoDescriptors(vm: *VM, timeout_ms: i32) VMError!Value {
    const current_thread = vm.current_thread;
    const is_worker_thread = current_thread != null and vm.main_thread != null and current_thread.? != vm.main_thread.?;
    var dummy_pollfd = [_]std.posix.pollfd{undefined};

    if (is_worker_thread and timeout_ms < 0) {
        const thread = current_thread.?;
        defer {
            if (thread.state == .sleeping) thread.state = .running;
        }

        while (true) {
            thread.state = .sleeping;
            try vm.threadYield();
        }
    }

    const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;
    while (true) {
        try vm.checkAsyncEvents();
        const step_timeout_ms: i32 = if (deadline_ms) |deadline| blk: {
            const remaining = deadline - monotonicMilliseconds();
            if (remaining <= 0) break :blk 0;
            break :blk @intCast(@min(remaining, 100));
        } else 100;

        const ready_count = std.c.poll(dummy_pollfd[0..].ptr, 0, step_timeout_ms);
        if (ready_count < 0) {
            const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
            if (errno_code == .INTR) {
                try vm.checkAsyncEvents();
                continue;
            }
            return vm.raiseErrnoFmt(errno_code, "poll failed", .{});
        }
        if (deadline_ms != null and step_timeout_ms == 0) return Value.nil();
        try yieldSleepingMainThread(vm);
    }
}

pub fn builtinIoSelect(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 4);

    const read_arg = args[0];
    const write_arg = if (args.len >= 2) args[1] else Value.nil();
    const error_arg = if (args.len >= 3) args[2] else Value.nil();
    const timeout_arg = if (args.len >= 4) args[3] else Value.nil();

    const read_array = try requireSelectArrayArg(vm, read_arg);
    const write_array = try requireSelectArrayArg(vm, write_arg);
    const error_array = try requireSelectArrayArg(vm, error_arg);
    const timeout_ms = try timeoutArgToPollMilliseconds(vm, timeout_arg);

    var watches: std.ArrayList(IoSelectWatch) = .empty;
    defer watches.deinit(vm.allocator);

    try appendSelectWatches(vm, &watches, read_array, .read);
    try appendSelectWatches(vm, &watches, write_array, .write);
    try appendSelectWatches(vm, &watches, error_array, .except);

    if (watches.items.len == 0) return ioSelectWaitNoDescriptors(vm, timeout_ms);

    var pollfds = try selectPollfds(vm, watches.items);
    defer pollfds.deinit(vm.allocator);

    const current_thread = vm.current_thread;
    const is_worker_thread = current_thread != null and vm.main_thread != null and current_thread.? != vm.main_thread.?;
    if (!is_worker_thread) {
        const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;

        while (true) {
            try vm.checkAsyncEvents();
            selectResetPollfds(pollfds.items);

            const step_timeout_ms: i32 = if (deadline_ms) |deadline| blk: {
                const remaining = deadline - monotonicMilliseconds();
                if (remaining <= 0) break :blk 0;
                break :blk @intCast(@min(remaining, 100));
            } else 100;

            const ready_count = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), step_timeout_ms);
            if (ready_count < 0) {
                const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
            if (errno_code == .INTR) {
                try vm.checkAsyncEvents();
                continue;
            }
                return vm.raiseErrnoFmt(errno_code, "poll failed", .{});
            }
            try selectRaiseIfInvalid(vm, pollfds.items);
            if (ready_count == 0) {
                if (deadline_ms != null and step_timeout_ms == 0) return Value.nil();
                try yieldSleepingMainThread(vm);
                continue;
            }

            const result = try selectResult(vm, watches.items, pollfds.items);
            if (!result.isNil()) return result;
            if (deadline_ms != null and monotonicMilliseconds() >= deadline_ms.?) return Value.nil();
            try yieldSleepingMainThread(vm);
        }
    }

    const deadline_ms = if (timeout_ms < 0) null else monotonicMilliseconds() + timeout_ms;
    while (true) {
        try vm.checkAsyncEvents();
        selectResetPollfds(pollfds.items);
        const ready_count = std.c.poll(pollfds.items.ptr, @intCast(pollfds.items.len), 0);
        if (ready_count < 0) {
            const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
            if (errno_code == .INTR) {
                try vm.checkAsyncEvents();
                continue;
            }
            return vm.raiseErrnoFmt(errno_code, "poll failed", .{});
        }
        try selectRaiseIfInvalid(vm, pollfds.items);
        if (ready_count != 0) {
            const result = try selectResult(vm, watches.items, pollfds.items);
            if (!result.isNil()) return result;
        }
        if (deadline_ms) |deadline| {
            if (monotonicMilliseconds() >= deadline) return Value.nil();
        }
        try vm.threadYield();
    }
}

fn maybeRemainingSeekableBytes(io: *IoObject) ?usize {
    const fd: std.posix.fd_t = @intCast(io.fd);
    const cur = std.c.lseek(fd, 0, std.posix.SEEK.CUR);
    if (cur < 0) return null;

    const end = std.c.lseek(fd, 0, std.posix.SEEK.END);
    if (end < 0) {
        _ = std.c.lseek(fd, cur, std.posix.SEEK.SET);
        return null;
    }

    _ = std.c.lseek(fd, cur, std.posix.SEEK.SET);
    if (end <= cur) return 0;
    return @intCast(end - cur);
}

/// BSD/macOS ioctl _IOR(group, nr, T): encodes a read-direction ioctl request number.
/// Mirrors the kernel macro: IOC_OUT | (sizeof(T) << 16) | (group << 8) | nr
/// IOC_OUT = 0x40000000 on BSD (bit 30 = "kernel reads from userspace ptr").
fn bsd_IOR(group: u8, nr: u8, comptime T: type) u32 {
    return 0x40000000 | (@as(u32, @sizeOf(T)) << 16) | (@as(u32, group) << 8) | nr;
}

fn pendingIoBytes(io: *IoObject) usize {
    if (maybeRemainingSeekableBytes(io)) |remaining| return remaining;

    var bytes_available: c_int = 0;
    const fd: std.posix.fd_t = @intCast(io.fd);
    // Linux exposes FIONREAD via std.os.linux.T; on macOS/BSD the T struct only
    // has IOCGWINSZ, so we derive it with the same _IOR encoding the kernel uses.
    const FIONREAD: u32 = switch (builtin.os.tag) {
        .linux => std.os.linux.T.FIONREAD,
        else => comptime bsd_IOR('f', 127, c_int), // FIONREAD = _IOR('f', 127, int)
    };
    if (std.c.ioctl(fd, FIONREAD, &bytes_available) == 0 and bytes_available > 0) {
        return @intCast(bytes_available);
    }
    return 0;
}

fn ioOutBufferValue(vm: *VM, maybe_outbuf: ?Value, bytes: []const u8) VMError!Value {
    if (maybe_outbuf) |outbuf| {
        const string_obj = outbuf.toStringObject();
        const copy = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
        string_obj.str = copy;
        string_obj.validity = .unknown;
        return outbuf;
    }

    return vm.newStringWithEncoding(bytes, false, enc.Encoding{ .ascii_8bit = .{} });
}

fn exceptionKeywordEnabled(vm: *VM) VMError!bool {
    var exception_value: ?Value = null;
    try vm.consumeKeywordArgs(.{"exception"}, .{&exception_value});
    try vm.validateKeywordArgsConsumed();

    const raw = exception_value orelse return true;
    if (raw.isTrue()) return true;
    if (raw.isFalse()) return false;
    return vm.raiseExceptionFmt(vm.type_error_class, "expected true or false as exception", .{});
}

fn ioStatusFlags(vm: *VM, io: *IoObject) VMError!c_int {
    const fd: std.posix.fd_t = @intCast(io.fd);
    const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
    if (flags < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
    return flags;
}

fn errnoWouldBlock(errno_code: std.posix.E) bool {
    if (errno_code == .AGAIN) return true;
    if (@hasField(std.posix.E, "WOULDBLOCK")) {
        return errno_code == .WOULDBLOCK;
    }
    return false;
}

fn setIoNonblocking(vm: *VM, io: *IoObject, enabled: bool) VMError!void {
    const flags = try ioStatusFlags(vm, io);
    const nonblock_flag: c_int = @bitCast(std.posix.O{ .NONBLOCK = true });
    const already_enabled = (flags & nonblock_flag) != 0;
    if (already_enabled == enabled) return;

    const next_flags = if (enabled) flags | nonblock_flag else flags & ~nonblock_flag;
    const fd: std.posix.fd_t = @intCast(io.fd);
    if (std.c.fcntl(fd, std.c.F.SETFL, next_flags) < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
}

fn ensureIoNonblocking(vm: *VM, io: *IoObject) VMError!void {
    return setIoNonblocking(vm, io, true);
}

fn ioIsNonblocking(vm: *VM, io: *IoObject) VMError!bool {
    const flags = try ioStatusFlags(vm, io);
    const nonblock_flag: c_int = @bitCast(std.posix.O{ .NONBLOCK = true });
    return (flags & nonblock_flag) != 0;
}

fn ioWriteBytes(vm: *VM, io: *IoObject, bytes: []const u8) VMError!usize {
    try ensureIoWritable(vm, io);

    if (io.fd == 1 and io.path == null) {
        vm.setupOutput();
        vm.stdout.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        _ = vm.stdout.?.flush() catch {};
        return bytes.len;
    }
    if (io.fd == 2 and io.path == null) {
        vm.setupOutput();
        vm.stderr.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        _ = vm.stderr.?.flush() catch {};
        return bytes.len;
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = std.c.write(fd, bytes[total..].ptr, bytes[total..].len);
        if (n < 0) return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        if (n == 0) break;
        total += @intCast(n);
    }
    return total;
}

fn blockingIoRead(vm: *VM, io: *IoObject, buf: []u8) VMError!usize {
    const fd: std.posix.fd_t = @intCast(io.fd);
    while (true) {
        try vm.checkAsyncEvents();
        _ = try waitReadable(vm, io, -1);

        const n = std.c.read(fd, buf.ptr, buf.len);
        if (n >= 0) return @intCast(n);

        const errno_code: std.posix.E = @enumFromInt(std.c._errno().*);
        switch (errno_code) {
            .INTR => {
                try vm.checkAsyncEvents();
                continue;
            },
            .AGAIN => continue,
            else => return vm.raiseErrnoFmt(errno_code, "read failed", .{}),
        }
    }
}

fn ioReadAll(vm: *VM, io: *IoObject) VMError!Value {
    try ensureIoReadable(vm, io);
    var buf: [4096]u8 = undefined;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    while (true) {
        const n = try blockingIoRead(vm, io, buf[0..]);
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
    }

    return vm.newString(out.items, false);
}

fn ioReadN(vm: *VM, io: *IoObject, len: usize) VMError!Value {
    try ensureIoReadable(vm, io);
    if (len == 0) return vm.newString("", false);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    out.ensureTotalCapacity(vm.allocator, len) catch return error.Fatal;

    var remaining = len;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const n = try blockingIoRead(vm, io, buf[0..to_read]);
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        remaining -= n;
    }

    if (out.items.len == 0) return Value.nil();
    return vm.newString(out.items, false);
}

pub fn builtinIoRead(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);

    if (args.len == 0 or args[0].isNil()) {
        return ioReadAll(vm, io);
    }

    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    if (args[0].toInteger() < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{args[0].toInteger()});
    }

    return ioReadN(vm, io, @intCast(args[0].toInteger()));
}

pub fn builtinIoReadNonblock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const exception_enabled = try exceptionKeywordEnabled(vm);
    const len = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer too big to convert into `long`");
    if (len < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len});
    }

    const outbuf = if (args.len == 2)
        try args[1].coerceToStringValue(vm, "no implicit conversion into String")
    else
        null;

    if (len == 0) return ioOutBufferValue(vm, outbuf, "");
    try ensureIoNonblocking(vm, io);

    if (!try waitReadable(vm, io, 0)) {
        if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_readable")).object);
        return vm.raiseExceptionFmt(vm.io_eagain_wait_readable_class, "read would block", .{});
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    const buf = vm.allocator.alloc(u8, @intCast(len)) catch return error.Fatal;
    defer vm.allocator.free(buf);

    const read_len = std.c.read(fd, buf.ptr, buf.len);
    if (read_len < 0) {
        const errno_code = std.posix.errno(read_len);
        if (errno_code == .AGAIN) {
            if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_readable")).object);
            return vm.raiseExceptionFmt(vm.io_eagain_wait_readable_class, "read would block", .{});
        }
        return vm.raiseErrnoFmt(errno_code, "read failed", .{});
    }

    if (read_len == 0) {
        if (!exception_enabled) return Value.nil();
        if (outbuf) |buffer| {
            _ = try ioOutBufferValue(vm, buffer, "");
        }
        return vm.raiseExceptionFmt(vm.eof_error_class, "end of file reached", .{});
    }

    return ioOutBufferValue(vm, outbuf, buf[0..@intCast(read_len)]);
}

// readpartial(maxlen[, outbuf]) — reads at most maxlen bytes in one syscall.
// Unlike read(), raises EOFError instead of returning nil at end-of-file.
pub fn builtinIoReadpartial(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const len = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer too big to convert into `long`");
    if (len < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len});
    }

    const outbuf = if (args.len == 2 and !args[1].isNil())
        try args[1].coerceToStringValue(vm, "no implicit conversion into String")
    else
        null;

    if (len == 0) return ioOutBufferValue(vm, outbuf, "");

    const fd: std.posix.fd_t = @intCast(io.fd);
    const buf = vm.allocator.alloc(u8, @intCast(len)) catch return error.Fatal;
    defer vm.allocator.free(buf);

    const read_len = std.c.read(fd, buf.ptr, buf.len);
    if (read_len < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(read_len), "read failed", .{});
    }
    if (read_len == 0) {
        if (outbuf) |buffer| _ = try ioOutBufferValue(vm, buffer, "");
        return vm.raiseExceptionFmt(vm.eof_error_class, "end of file reached", .{});
    }

    return ioOutBufferValue(vm, outbuf, buf[0..@intCast(read_len)]);
}

// File#chmod(mode) — set permissions on the open file via fchmod
pub fn builtinIoChmod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const mode: std.c.mode_t = @intCast(args[0].toInteger() & 0o7777);
    const result = std.c.fchmod(@intCast(io.fd), mode);
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "fchmod failed", .{});
    }
    return Value.integer(0);
}

pub fn builtinIoWrite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    const str = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const written = try ioWriteBytes(vm, io, str);
    return Value.integer(@intCast(written));
}

pub fn builtinIoAppend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    const str = try args[0].coerceToStr(vm, "no implicit conversion into String");
    _ = try ioWriteBytes(vm, io, str);
    return receiver;
}

pub fn builtinIoWriteNonblock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoWritable(vm, io);

    const exception_enabled = try exceptionKeywordEnabled(vm);
    const str_val = try vm.callMethodByName(args[0], "to_s", &[_]Value{}, null);
    if (!str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const str = str_val.toStringObject().str;
    if (str.len == 0) return Value.integer(0);
    try ensureIoNonblocking(vm, io);

    // Write directly — the fd is non-blocking so write() returns EAGAIN if full,
    // EPIPE if the read end is closed, without blocking.
    const fd: std.posix.fd_t = @intCast(io.fd);
    const written = std.c.write(fd, str.ptr, str.len);
    if (written < 0) {
        const errno_code = std.posix.errno(written);
        if (errno_code == .AGAIN) {
            if (!exception_enabled) return Value.fromObject(&(try vm.intern("wait_writable")).object);
            return vm.raiseExceptionFmt(vm.io_eagain_wait_writable_class, "write would block", .{});
        }
        if (errno_code == .PIPE) {
            return vm.raiseErrnoFmt(errno_code, "Broken pipe", .{});
        }
        return vm.raiseErrnoFmt(errno_code, "write failed", .{});
    }

    return Value.integer(@intCast(written));
}

pub fn builtinIoPrint(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    for (args) |arg| {
        const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
        if (!str_val.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
        }
        _ = try ioWriteBytes(vm, io, str_val.toStringObject().str);
    }
    return Value.nil();
}

pub fn builtinIoPuts(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    if (args.len == 0) {
        _ = try ioWriteBytes(vm, io, "\n");
        _ = try builtinIoFlush(vm, receiver, &[_]Value{}, null);
        return Value.nil();
    }

    for (args) |arg| {
        try ioPutsValue(vm, io, arg);
    }
    _ = try builtinIoFlush(vm, receiver, &[_]Value{}, null);
    return Value.nil();
}

fn ioPutsValue(vm: *VM, io: *IoObject, arg: Value) VMError!void {
    if (arg.isArray()) {
        for (arg.toArrayObject().elements.items) |elem| {
            try ioPutsValue(vm, io, elem);
        }
        return;
    }

    const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
    if (!str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const str = str_val.toStringObject().str;
    _ = try ioWriteBytes(vm, io, str);
    if (!std.mem.endsWith(u8, str, "\n")) {
        _ = try ioWriteBytes(vm, io, "\n");
    }
}

pub fn builtinIoFlush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    if (io.fd == 1) {
        vm.setupOutput();
        _ = vm.stdout.?.flush() catch {};
    } else if (io.fd == 2) {
        vm.setupOutput();
        _ = vm.stderr.?.flush() catch {};
    }
    return receiver;
}

pub fn builtinIoClose(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    if (io.closed) return Value.nil();

    if (io.read_buf) |buf| {
        vm.allocator.free(buf);
        io.read_buf = null;
    }
    io.read_buf_offset = 0;
    io.read_buf_avail = 0;

    if (io.owns_fd and io.fd >= 0) {
        _ = std.c.close(@intCast(io.fd));
    }

    const pid_value = try vm.getInstanceVariable(receiver, "@pid");
    if (pid_value.isInteger()) {
        const child_pid = pid_value.toInteger();

        var status: c_int = 0;
        const waited = std.c.waitpid(@intCast(child_pid), &status, 0);

        if (waited > 0) {
            try vm.setLastProcessStatusFromWaitStatus(status, waited);
        }
        try vm.setInstanceVariable(receiver, "@pid", Value.nil());
    }
    io.closed = true;
    return Value.nil();
}

pub fn builtinIoEof(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    // Seekable streams (files): compare position against end-of-file.
    if (maybeRemainingSeekableBytes(io)) |remaining| {
        return Value.boolean(remaining == 0);
    }

    // Non-seekable streams (pipes, sockets): use poll(0) to probe state, then
    // FIONREAD to count bytes when the write end is known to be closed.
    //
    // Platform behaviour (both macOS and Linux):
    //   write end open, no data  → revents = 0              → not eof (would block)
    //   write end open, data     → revents = POLLIN          → not eof
    //   write end closed, data   → revents = POLLIN|POLLHUP  → not eof
    //   write end closed, no data→ revents = POLLIN|POLLHUP  → eof
    //
    // So POLLHUP distinguishes "write end closed" from "write end open".
    // When POLLHUP is set, use FIONREAD to settle whether bytes remain.
    var fds = [_]std.posix.pollfd{.{
        .fd = @intCast(io.fd),
        .events = std.posix.POLL.IN | std.posix.POLL.HUP,
        .revents = 0,
    }};
    _ = std.posix.poll(fds[0..], 0) catch
        return vm.raiseExceptionFmt(vm.io_error_class, "poll failed", .{});
    if ((fds[0].revents & std.posix.POLL.HUP) == 0) {
        // Write end is still open — EOF is impossible regardless of data.
        return Value.boolean(false);
    }
    // Write end is closed. EOF iff no bytes remain in the pipe buffer.
    return Value.boolean(pendingIoBytes(io) == 0);
}

pub fn builtinIoClosed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    return Value.boolean(io.closed);
}

pub fn builtinIoFileno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    return Value.integer(io.fd);
}

pub fn builtinIoFlock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    if (@TypeOf(std.posix.system.flock) == void) {
        return vm.raiseErrnoFmt(.NOSYS, "flock failed", .{});
    }

    const operation_value = try args[0].coerceToIntegerValue(vm, "no implicit conversion to Integer", "can't convert to Integer");
    if (!operation_value.isInteger()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "bignum too big to convert into `int'", .{});
    }

    const operation = std.math.cast(i32, operation_value.toInteger()) orelse
        return vm.raiseExceptionFmt(vm.range_error_class, "bignum too big to convert into `int'", .{});
    const fd: std.posix.fd_t = @intCast(io.fd);

    while (true) {
        switch (std.posix.errno(std.posix.system.flock(fd, operation))) {
            .SUCCESS => return Value.integer(0),
            .INTR => {
                try vm.checkAsyncEvents();
                continue;
            },
            else => |errno_code| {
                if ((operation & std.posix.LOCK.NB) != 0 and errnoWouldBlock(errno_code)) {
                    return Value.FALSE;
                }
                return vm.raiseErrnoFmt(errno_code, "flock failed", .{});
            },
        }
    }
}

pub fn builtinIoPath(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    if (io.path) |path| {
        return vm.newStringWithEncoding(path, false, io.path_encoding orelse .{ .utf8 = .{} });
    }
    return Value.nil();
}

pub fn builtinIoPos(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    const result = std.c.lseek(@intCast(io.fd), 0, std.c.SEEK.CUR);
    if (result < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "seek failed", .{});
    }
    return Value.integer(result);
}

pub fn builtinIoPosSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    const class_name = vm.className(args[0]);
    const missing_message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{class_name}) catch return error.Fatal;
    defer vm.allocator.free(missing_message);
    const offset = try args[0].coerceToI64ViaToInt(
        vm,
        missing_message,
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );

    const result = std.c.lseek(@intCast(io.fd), offset, std.c.SEEK.SET);
    if (result < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "seek failed", .{});
    }
    return Value.integer(result);
}

pub fn builtinIoNread(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);
    return Value.integer(@intCast(pendingIoBytes(io)));
}

pub fn builtinIoReady(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    if (pendingIoBytes(io) > 0) return Value.boolean(true);
    return Value.boolean(try waitReadable(vm, io, 0));
}

pub fn builtinIoWaitReadable(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoReadable(vm, io);

    const timeout_ms = if (args.len == 1) try timeoutArgToPollMilliseconds(vm, args[0]) else -1;
    if (pendingIoBytes(io) > 0) return receiver;
    return if (try waitReadable(vm, io, timeout_ms)) receiver else Value.nil();
}

pub fn builtinIoWaitWritable(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoWritable(vm, io);

    const timeout_ms = if (args.len == 1) try timeoutArgToPollMilliseconds(vm, args[0]) else -1;
    return if (try waitWritable(vm, io, timeout_ms)) receiver else Value.nil();
}

pub fn builtinIoSeek(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    const offset_val = args[0];
    if (!offset_val.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const offset = offset_val.toInteger();

    const whence: i32 = if (args.len >= 2) blk: {
        const w_val = args[1];
        if (!w_val.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        break :blk @as(i32, @intCast(w_val.toInteger()));
    } else 0;

    const fd: std.c.fd_t = @intCast(io.fd);
    const result = std.c.lseek(fd, offset, @intCast(whence));
    if (result < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "seek failed", .{});
    }
    return Value.integer(result);
}

pub fn builtinIoReadline(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const line = try builtinIoGets(vm, receiver, args, block);
    if (line.isNil()) {
        return vm.raiseExceptionFmt(vm.eof_error_class, "end of file reached", .{});
    }
    return line;
}

pub fn builtinIoRewind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    if (io.read_buf) |buf| {
        vm.allocator.free(buf);
        io.read_buf = null;
    }
    io.read_buf_offset = 0;
    io.read_buf_avail = 0;

    const result = std.c.lseek(@intCast(io.fd), 0, std.c.SEEK.SET);
    if (result < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "rewind failed", .{});
    }
    io.lineno = 0;
    return Value.integer(0);
}

pub fn builtinIoLineno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);
    return Value.integer(io.lineno);
}

pub fn builtinIoLinenoSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    try ensureIoOpen(vm, io);

    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    io.lineno = args[0].toInteger();
    return args[0];
}
