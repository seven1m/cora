const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const FileMode = struct {
    read: bool,
    write: bool,
    append: bool,
    create: bool,
    truncate: bool,
};

pub fn register(vm: *VM) !void {
    const file_class_val = Value{ .data = .{ .class = vm.file_class } };
    const file_singleton = try vm.getOrCreateSingletonClass(file_class_val);

    const new_sym = try vm.intern("new");
    try file_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinFileNew } });

    const open_sym = try vm.intern("open");
    try file_singleton.module.methods.put(open_sym, .{ .method = .{ .builtin = &builtinFileOpen } });

    const read_sym = try vm.intern("read");
    try file_singleton.module.methods.put(read_sym, .{ .method = .{ .builtin = &builtinFileRead } });

    const write_sym = try vm.intern("write");
    try file_singleton.module.methods.put(write_sym, .{ .method = .{ .builtin = &builtinFileWrite } });
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

    const flags: std.posix.O = .{
        .ACCMODE = if (mode.read and mode.write) .RDWR else if (mode.write) .WRONLY else .RDONLY,
        .CLOEXEC = true,
        .CREAT = mode.create,
        .TRUNC = mode.truncate,
        .APPEND = mode.append,
    };

    const fd = std.posix.open(path, flags, 0o666) catch {
        return vm.raiseExceptionFmt(vm.io_error_class, "failed to open file: {s}", .{path});
    };

    return vm.newIo(vm.file_class, @intCast(fd), true, mode.read, mode.write, mode.append);
}

fn pathAndMode(vm: *VM, args: []Value) VMError!struct { path: []const u8, mode: FileMode } {
    try vm.requireArgCountRange(args, 1, 2);
    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");

    const mode_str: []const u8 = if (args.len == 2) blk: {
        if (args[1].data == .nil) break :blk "r";
        break :blk try args[1].coerceToStr(vm, "no implicit conversion into String");
    } else "r";
    const mode = try parseMode(vm, mode_str);
    return .{ .path = path, .mode = mode };
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
