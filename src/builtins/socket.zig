const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    if (builtin.os.tag == .windows) return;

    const tcp_server_name = try vm.intern("TCPServer");
    const tcp_server_val = try vm.newClassWithType(tcp_server_name, vm.io_class, .io);
    const tcp_server_class = tcp_server_val.toClassObject();
    try vm.object_class.module.constants.put(tcp_server_name, tcp_server_val);

    const tcp_socket_name = try vm.intern("TCPSocket");
    const tcp_socket_val = try vm.newClassWithType(tcp_socket_name, vm.io_class, .io);
    try vm.object_class.module.constants.put(tcp_socket_name, tcp_socket_val);

    const tcp_server_singleton = try vm.getOrCreateSingletonClass(tcp_server_val);
    const new_sym = try vm.intern("new");
    try tcp_server_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinTCPServerNew } });

    const accept_sym = try vm.intern("accept");
    try tcp_server_class.module.methods.put(accept_sym, .{ .method = .{ .builtin = &builtinTCPServerAccept } });
}

fn socketError(vm: *VM, comptime fmt: []const u8, args: anytype) VMError {
    return vm.raiseExceptionFmt(vm.io_error_class, fmt, args);
}

pub fn builtinTCPServerNew(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const port: u16 = blk: {
        const n = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "port out of range");
        if (n < 0 or n > 65535) return vm.raiseExceptionFmt(vm.argument_error_class, "port out of range", .{});
        break :blk @intCast(n);
    };
    _ = if (args.len >= 2) args[1] else Value.nil();

    const fd = std.c.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
    if (fd < 0) return socketError(vm, "socket() failed", .{});

    const one: c_int = 1;
    _ = std.c.setsockopt(
        fd,
        std.posix.SOL.SOCKET,
        std.posix.SO.REUSEADDR,
        &one,
        @sizeOf(c_int),
    );

    var addr: std.posix.sockaddr.in = .{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = 0, // INADDR_ANY
        .zero = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    if (std.c.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)) != 0) {
        _ = std.c.close(fd);
        return socketError(vm, "bind() failed on port {d}", .{port});
    }

    if (std.c.listen(fd, 128) != 0) {
        _ = std.c.close(fd);
        return socketError(vm, "listen() failed", .{});
    }

    const tcp_server_name = try vm.intern("TCPServer");
    const tcp_server_val = vm.object_class.module.constants.get(tcp_server_name) orelse return error.Fatal;
    return vm.newIo(tcp_server_val.toClassObject(), @intCast(fd), true, true, false, false);
}

pub fn builtinTCPServerAccept(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!receiver.isIo()) return vm.raiseExceptionFmt(vm.type_error_class, "not a TCPServer", .{});
    const io = receiver.toIoObject();
    if (io.closed) return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});

    var client_addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    const client_fd = std.c.accept(io.fd, @ptrCast(&client_addr), &addr_len);
    if (client_fd < 0) return socketError(vm, "accept() failed", .{});

    const tcp_socket_name = try vm.intern("TCPSocket");
    const tcp_socket_val = vm.object_class.module.constants.get(tcp_socket_name) orelse return error.Fatal;
    return vm.newIo(tcp_socket_val.toClassObject(), @intCast(client_fd), true, true, true, false);
}
