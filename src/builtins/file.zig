const std = @import("std");
const builtin = @import("builtin");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const Encoding = enc.Encoding;

fn passwdDir(passwd: *const std.c.passwd) ?[]const u8 {
    const dir_z = passwd.dir orelse return null;
    return std.mem.span(dir_z);
}

fn homeFromPasswdByUid(vm: *VM) VMError!?[]const u8 {
    const passwd = std.c.getpwuid(std.c.getuid()) orelse return null;
    const dir = passwdDir(passwd) orelse return null;
    if (!std.fs.path.isAbsolute(dir)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return dir;
}

fn homeFromPasswdByName(vm: *VM, username: []const u8) VMError!?[]const u8 {
    const username_z = try vm.allocCStringZ(username);
    defer vm.allocator.free(username_z);

    const passwd = std.c.getpwnam(username_z.ptr) orelse return null;
    const dir = passwdDir(passwd) orelse return null;
    if (!std.fs.path.isAbsolute(dir)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return dir;
}

const FileMode = struct {
    read: bool,
    write: bool,
    append: bool,
    create: bool,
    truncate: bool,
};

pub fn register(vm: *VM) !void {
    const file_class_val = Value.fromObject(vm.file_class);
    const file_singleton = try vm.getOrCreateSingletonClass(file_class_val);

    const separator_sym = try vm.intern("SEPARATOR");
    try vm.file_class.module.constants.put(separator_sym, .{ .value = try vm.newString("/", false) });

    const alt_separator_sym = try vm.intern("ALT_SEPARATOR");
    try vm.file_class.module.constants.put(alt_separator_sym, .{ .value = Value.nil() });

    const path_separator_sym = try vm.intern("PATH_SEPARATOR");
    try vm.file_class.module.constants.put(path_separator_sym, .{ .value = try vm.newString(":", false) });

    const fnm_dotmatch_sym = try vm.intern("FNM_DOTMATCH");
    try vm.file_class.module.constants.put(fnm_dotmatch_sym, .{ .value = Value.integer(0x04) });

    const fnm_noescape_sym = try vm.intern("FNM_NOESCAPE");
    try vm.file_class.module.constants.put(fnm_noescape_sym, .{ .value = Value.integer(0x01) });

    const fnm_extglob_sym = try vm.intern("FNM_EXTGLOB");
    try vm.file_class.module.constants.put(fnm_extglob_sym, .{ .value = Value.integer(0x10) });

    const new_sym = try vm.intern("new");
    try file_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinFileNew, .{ .variadic = 0 }));

    const open_sym = try vm.intern("open");
    try file_singleton.module.methods.put(open_sym, value.MethodEntry.builtin(&builtinFileOpen, .{ .variadic = 0 }));

    const read_sym = try vm.intern("read");
    try file_singleton.module.methods.put(read_sym, value.MethodEntry.builtin(&builtinFileRead, .{ .variadic = 0 }));

    const write_sym = try vm.intern("write");
    try file_singleton.module.methods.put(write_sym, value.MethodEntry.builtin(&builtinFileWrite, .{ .variadic = 0 }));

    const expand_path_sym = try vm.intern("expand_path");
    try file_singleton.module.methods.put(expand_path_sym, value.MethodEntry.builtin(&builtinFileExpandPath, .{ .variadic = 0 }));

    const realpath_sym = try vm.intern("realpath");
    try file_singleton.module.methods.put(realpath_sym, value.MethodEntry.builtin(&builtinFileRealpath, .{ .variadic = 0 }));

    const join_sym = try vm.intern("join");
    try file_singleton.module.methods.put(join_sym, value.MethodEntry.builtin(&builtinFileJoin, .{ .variadic = 0 }));

    const dirname_sym = try vm.intern("dirname");
    try file_singleton.module.methods.put(dirname_sym, value.MethodEntry.builtin(&builtinFileDirname, .{ .variadic = 0 }));

    const directory_sym = try vm.intern("directory?");
    try file_singleton.module.methods.put(directory_sym, value.MethodEntry.builtin(&builtinFileDirectory, .{ .exact = 1 }));

    const file_sym = try vm.intern("file?");
    try file_singleton.module.methods.put(file_sym, value.MethodEntry.builtin(&builtinFileFile, .{ .exact = 1 }));

    const exist_sym = try vm.intern("exist?");
    try file_singleton.module.methods.put(exist_sym, value.MethodEntry.builtin(&builtinFileExist, .{ .exact = 1 }));

    const delete_sym = try vm.intern("delete");
    try file_singleton.module.methods.put(delete_sym, value.MethodEntry.builtin(&builtinFileDelete, .{ .variadic = 0 }));

    const unlink_sym = try vm.intern("unlink");
    try file_singleton.module.methods.put(unlink_sym, value.MethodEntry.builtin(&builtinFileDelete, .{ .variadic = 0 }));

    const path_sym = try vm.intern("path");
    try file_singleton.module.methods.put(path_sym, value.MethodEntry.builtin(&builtinFilePath, .{ .variadic = 0 }));
}

fn parseMode(vm: *VM, mode_str: []const u8) VMError!FileMode {
    if (mode_str.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode", .{});
    }

    const plus = std.mem.indexOfScalar(u8, mode_str, '+') != null;
    return switch (mode_str[0]) {
        'r' => .{ .read = true, .write = plus, .append = false, .create = false, .truncate = false },
        'w' => .{ .read = plus, .write = true, .append = false, .create = true, .truncate = true },
        'a' => .{ .read = plus, .write = true, .append = true, .create = true, .truncate = false },
        else => vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode {s}", .{mode_str}),
    };
}

fn openFileWithMode(vm: *VM, path: []const u8, mode: FileMode) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "File is not implemented on Windows", .{});
    }

    const flags: std.c.O = .{
        .ACCMODE = if (mode.read and mode.write) .RDWR else if (mode.write) .WRONLY else .RDONLY,
        .CLOEXEC = true,
        .CREAT = mode.create,
        .TRUNC = mode.truncate,
        .APPEND = mode.append,
    };

    const path_z = try vm.allocCStringZ(path);
    defer vm.allocator.free(path_z);
    const fd = std.c.open(path_z.ptr, flags, @as(std.c.mode_t, 0o666));
    if (fd < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(fd), "failed to open file: {s}", .{path});
    }

    const path_copy = vm.gc_allocator.dupe(u8, path) catch return error.Fatal;
    return vm.newIo(vm.file_class, @intCast(fd), true, mode.read, mode.write, mode.append, path_copy);
}

fn pathAndMode(vm: *VM, args: []Value) VMError!struct { path: []const u8, mode: FileMode } {
    try vm.requireArgCountRange(args, 1, 2);
    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");

    const mode_str: []const u8 = if (args.len == 2) blk: {
        if (args[1].isNil()) break :blk "r";
        break :blk try args[1].coerceToStr(vm, "no implicit conversion into String");
    } else "r";
    const mode = try parseMode(vm, mode_str);
    return .{ .path = path, .mode = mode };
}

fn currentHome(vm: *VM) VMError![]const u8 {
    const home_z = std.c.getenv("HOME") orelse {
        return (try homeFromPasswdByUid(vm)) orelse vm.raiseExceptionFmt(
            vm.argument_error_class,
            "couldn't find HOME environment -- expanding `~'",
            .{},
        );
    };
    const home = std.mem.span(home_z);
    if (home.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "couldn't find HOME environment -- expanding `~'", .{});
    }
    if (!std.fs.path.isAbsolute(home)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return home;
}

fn currentWorkingDir(vm: *VM) VMError![]u8 {
    const cwd_z = std.process.currentPathAlloc(vm.io, vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(cwd_z);
    return vm.dupeCStringZAsSlice(cwd_z);
}

fn joinPathPartsAlloc(allocator: std.mem.Allocator, base: []const u8, tail: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    if (base.len == 0) {
        out.appendSlice(allocator, tail) catch return error.OutOfMemory;
    } else if (tail.len == 0) {
        out.appendSlice(allocator, base) catch return error.OutOfMemory;
    } else {
        out.appendSlice(allocator, base) catch return error.OutOfMemory;
        if (out.items[out.items.len - 1] != '/') {
            out.append(allocator, '/') catch return error.OutOfMemory;
        }
        var start: usize = 0;
        while (start < tail.len and tail[start] == '/') : (start += 1) {}
        out.appendSlice(allocator, tail[start..]) catch return error.OutOfMemory;
    }

    return allocator.dupe(u8, out.items);
}

fn normalizeAbsolutePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var leading_slashes: usize = 0;
    while (leading_slashes < path.len and path[leading_slashes] == '/') : (leading_slashes += 1) {}
    if (leading_slashes == 0) return error.InvalidArgument;

    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(allocator);

    var i: usize = leading_slashes;
    while (i <= path.len) {
        const start = i;
        while (i < path.len and path[i] != '/') : (i += 1) {}
        const segment = path[start..i];
        if (segment.len > 0 and !std.mem.eql(u8, segment, ".")) {
            if (std.mem.eql(u8, segment, "..")) {
                if (segments.items.len > 0) _ = segments.pop();
            } else {
                segments.append(allocator, segment) catch return error.OutOfMemory;
            }
        }
        i += 1;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (0..leading_slashes) |_| {
        out.append(allocator, '/') catch return error.OutOfMemory;
    }

    for (segments.items, 0..) |segment, idx| {
        if (idx > 0) out.append(allocator, '/') catch return error.OutOfMemory;
        out.appendSlice(allocator, segment) catch return error.OutOfMemory;
    }

    return allocator.dupe(u8, out.items);
}

fn expandUserPathAlloc(vm: *VM, path: []const u8) VMError![]u8 {
    std.debug.assert(path.len > 0 and path[0] == '~');
    var split: usize = 1;
    while (split < path.len and path[split] != '/') : (split += 1) {}
    const username = path[1..split];
    const rest = path[split..];

    const home = if (username.len == 0)
        try currentHome(vm)
    else
        (try homeFromPasswdByName(vm, username)) orelse {
            return vm.raiseExceptionFmt(vm.argument_error_class, "user {s} doesn't exist", .{username});
        };
    if (rest.len == 0 or (rest.len == 1 and rest[0] == '/')) {
        return vm.allocator.dupe(u8, home) catch return error.Fatal;
    }

    return joinPathPartsAlloc(vm.allocator, home, rest[1..]) catch return error.Fatal;
}

fn expandBaseDirAlloc(vm: *VM, base_opt: ?[]const u8) VMError![]u8 {
    const base = base_opt orelse {
        return currentWorkingDir(vm);
    };

    if (base.len > 0 and base[0] == '~') {
        const expanded = try expandUserPathAlloc(vm, base);
        defer vm.allocator.free(expanded);
        return normalizeAbsolutePathAlloc(vm.allocator, expanded) catch return error.Fatal;
    }

    if (base.len > 0 and base[0] == '/') {
        return normalizeAbsolutePathAlloc(vm.allocator, base) catch return error.Fatal;
    }

    const cwd = try currentWorkingDir(vm);
    defer vm.allocator.free(cwd);
    const joined = joinPathPartsAlloc(vm.allocator, cwd, base) catch return error.Fatal;
    defer vm.allocator.free(joined);
    return normalizeAbsolutePathAlloc(vm.allocator, joined) catch return error.Fatal;
}

fn expandPathAlloc(vm: *VM, path: []const u8, base_opt: ?[]const u8) VMError![]u8 {
    if (path.len > 0 and path[0] == '~') {
        const expanded = try expandUserPathAlloc(vm, path);
        defer vm.allocator.free(expanded);
        return normalizeAbsolutePathAlloc(vm.allocator, expanded) catch return error.Fatal;
    }

    if (path.len > 0 and path[0] == '/') {
        return normalizeAbsolutePathAlloc(vm.allocator, path) catch return error.Fatal;
    }

    const base = try expandBaseDirAlloc(vm, base_opt);
    defer vm.allocator.free(base);

    const joined = joinPathPartsAlloc(vm.allocator, base, path) catch return error.Fatal;
    defer vm.allocator.free(joined);
    return normalizeAbsolutePathAlloc(vm.allocator, joined) catch return error.Fatal;
}

fn dirnameBytesAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, ".");

    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];

    if (std.mem.eql(u8, trimmed, "/")) return allocator.dupe(u8, "/");

    const last_slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return allocator.dupe(u8, ".");
    if (last_slash == 0) return allocator.dupe(u8, "/");
    return allocator.dupe(u8, trimmed[0..last_slash]);
}

pub fn builtinFileNew(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const parsed = try pathAndMode(vm, args);
    return openFileWithMode(vm, parsed.path, parsed.mode);
}

pub fn builtinFileOpen(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    const parsed = try pathAndMode(vm, args);
    const file_val = try openFileWithMode(vm, parsed.path, parsed.mode);

    if (block) |blk| {
        var yield_args: [1]Value = .{file_val};
        const yielded = vm.yieldToBlock(blk, &yield_args) catch |err| {
            _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
            return err;
        };
        _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
        return yielded.value;
    }

    return file_val;
}

pub fn builtinFileRead(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const file_val = try openFileWithMode(vm, path, .{ .read = true, .write = false, .append = false, .create = false, .truncate = false });
    defer _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
    return vm.callMethodByName(file_val, "read", &[_]Value{}, null);
}

pub fn builtinFileWrite(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const file_val = try openFileWithMode(vm, path, .{ .read = false, .write = true, .append = false, .create = true, .truncate = true });
    defer _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
    return vm.callMethodByName(file_val, "write", args[1..2], null);
}

pub fn builtinFileExpandPath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.expand_path is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();

    const base: ?[]const u8 = if (args.len == 2 and !args[1].isNil()) blk: {
        const base_value = try vm.coerceToPathValue(args[1], "no implicit conversion into String");
        break :blk base_value.toStringObject().str;
    } else null;

    const expanded = try expandPathAlloc(vm, path_obj.str, base);
    defer vm.allocator.free(expanded);
    return try vm.newStringWithEncoding(expanded, false, path_obj.encoding);
}

pub fn builtinFileRealpath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.realpath is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();

    const base: ?[]const u8 = if (args.len == 2 and !args[1].isNil()) blk: {
        const base_value = try vm.coerceToPathValue(args[1], "no implicit conversion into String");
        break :blk base_value.toStringObject().str;
    } else null;

    const expanded = try expandPathAlloc(vm, path_obj.str, base);
    defer vm.allocator.free(expanded);

    const resolved = std.Io.Dir.cwd().realPathFileAlloc(vm.io, expanded, vm.allocator) catch {
        return vm.raiseExceptionFmt(vm.io_error_class, "No such file or directory @ rb_check_realpath_internal - {s}", .{path_obj.str});
    };
    defer vm.allocator.free(resolved);

    return try vm.newStringWithEncoding(resolved, false, path_obj.encoding);
}

pub fn builtinFileJoin(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.join is not implemented on Windows", .{});
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(vm.allocator);

    var output_encoding: Encoding = .{ .utf8 = .{} };
    var have_encoding = false;

    var effective_args = args;
    if (args.len == 1 and args[0].isArray()) {
        effective_args = args[0].toArrayObject().elements.items;
    }

    for (effective_args, 0..) |arg, idx| {
        const part_value = try vm.coerceToPathValue(arg, "no implicit conversion into String");
        const part_obj = part_value.toStringObject();
        if (!have_encoding) {
            output_encoding = part_obj.encoding;
            have_encoding = true;
        }

        if (idx == 0) {
            result.appendSlice(vm.allocator, part_obj.str) catch return error.Fatal;
            continue;
        }

        if (part_obj.str.len > 0 and part_obj.str[0] == '/') {
            result.clearRetainingCapacity();
            result.appendSlice(vm.allocator, part_obj.str) catch return error.Fatal;
            continue;
        }

        if (result.items.len > 0 and result.items[result.items.len - 1] != '/') {
            result.append(vm.allocator, '/') catch return error.Fatal;
        }

        var start: usize = 0;
        while (start < part_obj.str.len and part_obj.str[start] == '/') : (start += 1) {}
        result.appendSlice(vm.allocator, part_obj.str[start..]) catch return error.Fatal;
    }

    return try vm.newStringWithEncoding(result.items, false, output_encoding);
}

pub fn builtinFileDirname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.dirname is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const dir = dirnameBytesAlloc(vm.allocator, path_obj.str) catch return error.Fatal;
    defer vm.allocator.free(dir);
    return try vm.newStringWithEncoding(dir, false, path_obj.encoding);
}

pub fn builtinFileDirectory(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.directory? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    var dir = std.Io.Dir.cwd().openDir(vm.io, path, .{}) catch return Value.boolean(false);
    defer dir.close(vm.io);
    return Value.boolean(true);
}

pub fn builtinFileFile(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.file? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const st = std.Io.Dir.cwd().statFile(vm.io, path, .{}) catch return Value.boolean(false);
    return Value.boolean(st.kind == .file);
}

pub fn builtinFileExist(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.exist? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    std.Io.Dir.cwd().access(vm.io, path, .{}) catch return Value.boolean(false);
    return Value.boolean(true);
}

pub fn builtinFileDelete(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.delete is not implemented on Windows", .{});
    }

    var deleted: usize = 0;
    for (args) |arg| {
        const path = try vm.coerceToPath(arg, "no implicit conversion into String");
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);
        const result = std.c.unlink(path_z.ptr);
        if (result < 0) {
            return vm.raiseErrnoFmt(std.posix.errno(result), "No such file or directory @ unlink_internal - {s}", .{path});
        }
        deleted += 1;
    }
    return Value.integer(@intCast(deleted));
}

pub fn builtinFilePath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const arg = args[0];
    if (arg.isIo()) {
        const io = arg.toIoObject();
        if (io.path) |p| {
            return vm.newString(p, false);
        }
        return Value.nil();
    }
    const path = try vm.coerceToPath(arg, "no implicit conversion into String");
    return vm.newString(path, false);
}
