const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const IoObject = value.IoObject;

pub fn register(vm: *VM) !void {
    const read_sym = try vm.intern("read");
    try vm.io_class.module.methods.put(read_sym, .{ .method = .{ .builtin = &builtinIoRead } });

    const write_sym = try vm.intern("write");
    try vm.io_class.module.methods.put(write_sym, .{ .method = .{ .builtin = &builtinIoWrite } });

    const print_sym = try vm.intern("print");
    try vm.io_class.module.methods.put(print_sym, .{ .method = .{ .builtin = &builtinIoPrint } });

    const puts_sym = try vm.intern("puts");
    try vm.io_class.module.methods.put(puts_sym, .{ .method = .{ .builtin = &builtinIoPuts } });

    const flush_sym = try vm.intern("flush");
    try vm.io_class.module.methods.put(flush_sym, .{ .method = .{ .builtin = &builtinIoFlush } });

    const close_sym = try vm.intern("close");
    try vm.io_class.module.methods.put(close_sym, .{ .method = .{ .builtin = &builtinIoClose } });

    const closed_sym = try vm.intern("closed?");
    try vm.io_class.module.methods.put(closed_sym, .{ .method = .{ .builtin = &builtinIoClosed } });

    const fileno_sym = try vm.intern("fileno");
    try vm.io_class.module.methods.put(fileno_sym, .{ .method = .{ .builtin = &builtinIoFileno } });
}

fn requireIoReceiver(vm: *VM, receiver: Value) VMError!*IoObject {
    return switch (receiver.data) {
        .io => |io| io,
        else => vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{}),
    };
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

fn ioWriteBytes(vm: *VM, io: *IoObject, bytes: []const u8) VMError!usize {
    try ensureIoWritable(vm, io);

    if (io.fd == 1) {
        vm.setupOutput();
        vm.stdout.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        return bytes.len;
    }
    if (io.fd == 2) {
        vm.setupOutput();
        vm.stderr.?.writeAll(bytes) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        return bytes.len;
    }

    const fd: std.posix.fd_t = @intCast(io.fd);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = std.posix.write(fd, bytes[total..]) catch return vm.raiseExceptionFmt(vm.io_error_class, "write failed", .{});
        if (n == 0) break;
        total += n;
    }
    return total;
}

fn ioReadAll(vm: *VM, io: *IoObject) VMError!Value {
    try ensureIoReadable(vm, io);
    const fd: std.posix.fd_t = @intCast(io.fd);
    var buf: [4096]u8 = undefined;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    while (true) {
        const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
    }

    return vm.newString(out.items, false);
}

fn ioReadN(vm: *VM, io: *IoObject, len: usize) VMError!Value {
    try ensureIoReadable(vm, io);
    if (len == 0) return vm.newString("", false);

    const fd: std.posix.fd_t = @intCast(io.fd);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    out.ensureTotalCapacity(vm.allocator, len) catch return error.Fatal;

    var remaining = len;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const n = std.posix.read(fd, buf[0..to_read]) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        remaining -= n;
    }

    if (out.items.len == 0) return Value.nil();
    return vm.newString(out.items, false);
}

pub fn builtinIoRead(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgRange(args, 0, 1);
    const io = try requireIoReceiver(vm, receiver);

    if (args.len == 0 or args[0].data == .nil) {
        return ioReadAll(vm, io);
    }

    if (args[0].data != .integer) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    if (args[0].data.integer < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{args[0].data.integer});
    }

    return ioReadN(vm, io, @intCast(args[0].data.integer));
}

pub fn builtinIoWrite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const io = try requireIoReceiver(vm, receiver);
    const str = try vm.coerceToStr(args[0], "no implicit conversion into String");
    const written = try ioWriteBytes(vm, io, str);
    return Value.integer(@intCast(written));
}

pub fn builtinIoPrint(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const io = try requireIoReceiver(vm, receiver);
    for (args) |arg| {
        const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
        if (str_val.data != .string) {
            return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
        }
        _ = try ioWriteBytes(vm, io, str_val.data.string.str);
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
    if (arg.data == .array) {
        for (arg.data.array.elements.items) |elem| {
            try ioPutsValue(vm, io, elem);
        }
        return;
    }

    const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
    if (str_val.data != .string) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const str = str_val.data.string.str;
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

    if (io.owns_fd and io.fd >= 0) {
        std.posix.close(@intCast(io.fd));
    }
    io.closed = true;
    return Value.nil();
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
