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

    const socket_name = try vm.intern("Socket");
    const socket_val = try vm.newClass(socket_name, vm.object_class);
    const socket_class = socket_val.toClassObject();
    try vm.object_class.module.constants.put(socket_name, .{ .value = socket_val });

    const socket_error_name = try vm.intern("SocketError");
    const socket_error_val = try vm.newClass(socket_error_name, vm.standard_error_class);
    try vm.object_class.module.constants.put(socket_error_name, .{ .value = socket_error_val });

    const tcp_server_name = try vm.intern("TCPServer");
    const tcp_server_val = try vm.newClassWithType(tcp_server_name, vm.io_class, .io);
    const tcp_server_class = tcp_server_val.toClassObject();
    try vm.object_class.module.constants.put(tcp_server_name, .{ .value = tcp_server_val });

    const tcp_socket_name = try vm.intern("TCPSocket");
    const tcp_socket_val = try vm.newClassWithType(tcp_socket_name, vm.io_class, .io);
    const tcp_socket_class = tcp_socket_val.toClassObject();
    try vm.object_class.module.constants.put(tcp_socket_name, .{ .value = tcp_socket_val });

    const socket_singleton = try vm.getOrCreateSingletonClass(socket_val);
    const tcp_server_singleton = try vm.getOrCreateSingletonClass(tcp_server_val);
    const tcp_socket_singleton = try vm.getOrCreateSingletonClass(tcp_socket_val);
    const new_sym = try vm.intern("new");
    try tcp_server_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinTCPServerNew, .{ .variadic = 0 }));
    try tcp_socket_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinTCPSocketOpen, .{ .variadic = 0 }));

    const accept_sym = try vm.intern("accept");
    try tcp_server_class.module.methods.put(accept_sym, value.MethodEntry.builtin(&builtinTCPServerAccept, .{ .exact = 0 }));

    const open_sym = try vm.intern("open");
    try tcp_socket_singleton.module.methods.put(open_sym, value.MethodEntry.builtin(&builtinTCPSocketOpen, .{ .variadic = 0 }));

    const tcp_sym = try vm.intern("tcp");
    try socket_singleton.module.methods.put(tcp_sym, value.MethodEntry.builtin(&builtinSocketTcp, .{ .variadic = 0 }));

    const gethostname_sym = try vm.intern("gethostname");
    try socket_singleton.module.methods.put(gethostname_sym, value.MethodEntry.builtin(&builtinSocketGethostname, .{ .exact = 0 }));

    const do_not_reverse_lookup_sym = try vm.intern("do_not_reverse_lookup");
    try socket_singleton.module.methods.put(do_not_reverse_lookup_sym, value.MethodEntry.builtin(&builtinSocketDoNotReverseLookup, .{ .exact = 0 }));

    const do_not_reverse_lookup_set_sym = try vm.intern("do_not_reverse_lookup=");
    try socket_singleton.module.methods.put(do_not_reverse_lookup_set_sym, value.MethodEntry.builtin(&builtinSocketSetDoNotReverseLookup, .{ .exact = 1 }));

    const setsockopt_sym = try vm.intern("setsockopt");
    try tcp_socket_class.module.methods.put(setsockopt_sym, value.MethodEntry.builtin(&builtinTCPSocketSetsockopt, .{ .exact = 3 }));

    try vm.setInstanceVariable(socket_val, "@do_not_reverse_lookup", Value.boolean(false));

    const ipproto_tcp_sym = try vm.intern("IPPROTO_TCP");
    try socket_class.module.constants.put(ipproto_tcp_sym, .{ .value = Value.integer(std.posix.IPPROTO.TCP) });

    const tcp_nodelay_sym = try vm.intern("TCP_NODELAY");
    try socket_class.module.constants.put(tcp_nodelay_sym, .{ .value = Value.integer(std.c.TCP.NODELAY) });

    const af_inet_sym = try vm.intern("AF_INET");
    try socket_class.module.constants.put(af_inet_sym, .{ .value = Value.integer(std.posix.AF.INET) });

    const af_inet6_sym = try vm.intern("AF_INET6");
    try socket_class.module.constants.put(af_inet6_sym, .{ .value = Value.integer(std.posix.AF.INET6) });
}

fn socketError(vm: *VM, comptime fmt: []const u8, args: anytype) VMError {
    return vm.raiseLastErrnoFmt(fmt, args);
}

fn socketErrorClass(vm: *VM) VMError!*ClassObject {
    const socket_error_name = try vm.intern("SocketError");
    const socket_error_entry = vm.object_class.module.constants.get(socket_error_name) orelse return error.Fatal;
    return socket_error_entry.value.toClassObject();
}

fn raiseSocketErrorFmt(vm: *VM, comptime fmt: []const u8, args: anytype) VMError {
    return vm.raiseExceptionFmt(try socketErrorClass(vm), fmt, args);
}

fn tcpSocketClass(vm: *VM) VMError!*ClassObject {
    const tcp_socket_name = try vm.intern("TCPSocket");
    const tcp_socket_entry = vm.object_class.module.constants.get(tcp_socket_name) orelse return error.Fatal;
    return tcp_socket_entry.value.toClassObject();
}

fn socketStatusFlags(vm: *VM, fd: std.posix.fd_t) VMError!c_int {
    const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
    if (flags < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
    return flags;
}

fn setSocketNonblocking(vm: *VM, fd: std.posix.fd_t, enabled: bool) VMError!void {
    const flags = try socketStatusFlags(vm, fd);
    const nonblock_flag: c_int = @intCast(std.c.SOCK.NONBLOCK);
    const already_enabled = (flags & nonblock_flag) != 0;
    if (already_enabled == enabled) return;

    const next_flags = if (enabled) flags | nonblock_flag else flags & ~nonblock_flag;
    if (std.c.fcntl(fd, std.c.F.SETFL, next_flags) < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fcntl failed", .{});
    }
}

fn waitForConnectWritable(vm: *VM, fd: std.posix.fd_t) VMError!void {
    var fds = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.OUT,
        .revents = 0,
    }};
    const ready_mask = std.posix.POLL.OUT | std.posix.POLL.ERR | std.posix.POLL.HUP;

    const current_thread = vm.current_thread;
    const is_worker_thread = current_thread != null and vm.main_thread != null and current_thread.? != vm.main_thread.?;
    if (!is_worker_thread) {
        _ = std.posix.poll(fds[0..], -1) catch return vm.raiseExceptionFmt(vm.io_error_class, "poll failed", .{});
        return;
    }

    const thread = current_thread.?;
    defer {
        thread.io_wait = null;
        if (thread.state == .sleeping) thread.state = .running;
    }

    while (true) {
        const ready_count = std.posix.poll(fds[0..], 0) catch return vm.raiseExceptionFmt(vm.io_error_class, "poll failed", .{});
        if (ready_count != 0 and (fds[0].revents & ready_mask) != 0) return;

        thread.io_wait = .{
            .fd = @intCast(fd),
            .events = std.posix.POLL.OUT,
            .include_hup = true,
            .deadline_ms = null,
        };
        thread.state = .sleeping;
        try vm.threadYield();
    }
}

fn socketConnectError(fd: std.posix.fd_t) std.posix.E {
    var so_error: c_int = 0;
    var so_error_len: std.posix.socklen_t = @sizeOf(c_int);
    if (std.c.getsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.ERROR, &so_error, &so_error_len) != 0) {
        return std.posix.errno(-1);
    }
    if (so_error == 0) return .SUCCESS;
    return std.posix.errno(so_error);
}

fn connectTCPSocket(vm: *VM, host_value: Value, port_value: Value) VMError!Value {
    const host = try host_value.coerceToStr(vm, "no implicit conversion into String");
    var service_buf: [32]u8 = undefined;
    const service = if (port_value.isString())
        try port_value.coerceToStr(vm, "no implicit conversion into String")
    else blk: {
        const port = try port_value.integerArgToI64(vm, "no implicit conversion into Integer", "port out of range");
        if (port < 0 or port > 65535) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "port out of range", .{});
        }
        break :blk std.fmt.bufPrint(&service_buf, "{d}", .{port}) catch return error.Fatal;
    };

    const host_z = try vm.allocCStringZ(host);
    defer vm.allocator.free(host_z);
    const service_z = try vm.allocCStringZ(service);
    defer vm.allocator.free(service_z);

    var hints = std.mem.zeroes(std.c.addrinfo);
    hints.family = std.posix.AF.UNSPEC;
    hints.socktype = std.posix.SOCK.STREAM;

    var addrinfo_result: ?*std.c.addrinfo = null;
    const gai = std.c.getaddrinfo(host_z.ptr, service_z.ptr, &hints, &addrinfo_result);
    if (@intFromEnum(gai) != 0) {
        return raiseSocketErrorFmt(vm, "getaddrinfo failed for {s}:{s}", .{ host, service });
    }
    defer if (addrinfo_result) |result| std.c.freeaddrinfo(result);

    var last_errno: ?std.posix.E = null;
    var current = addrinfo_result;
    while (current) |addrinfo| : (current = addrinfo.next) {
        const addr = addrinfo.addr orelse continue;
        const fd = std.c.socket(@intCast(addrinfo.family), @intCast(addrinfo.socktype), @intCast(addrinfo.protocol));
        if (fd < 0) continue;
        errdefer _ = std.c.close(fd);

        const posix_fd: std.posix.fd_t = @intCast(fd);
        try setSocketNonblocking(vm, posix_fd, true);
        defer setSocketNonblocking(vm, posix_fd, false) catch {};

        if (std.c.connect(fd, addr, addrinfo.addrlen) == 0) {
            return vm.newIo(try tcpSocketClass(vm), @intCast(fd), .{ .owns_fd = true, .readable = true, .writable = true });
        }

        const connect_errno = std.posix.errno(-1);
        switch (connect_errno) {
            .INPROGRESS, .AGAIN, .ALREADY => {
                try waitForConnectWritable(vm, posix_fd);
                const so_error = socketConnectError(posix_fd);
                if (so_error == .SUCCESS) {
                    return vm.newIo(try tcpSocketClass(vm), @intCast(fd), .{ .owns_fd = true, .readable = true, .writable = true });
                }
                last_errno = so_error;
            },
            else => {
                last_errno = connect_errno;
            },
        }

        _ = std.c.close(fd);
    }

    if (last_errno) |err| {
        return vm.raiseErrnoFmt(err, "connect() failed for {s}:{s}", .{ host, service });
    }
    return socketError(vm, "connect() failed for {s}:{s}", .{ host, service });
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
    const tcp_server_entry = vm.object_class.module.constants.get(tcp_server_name) orelse return error.Fatal;
    return vm.newIo(tcp_server_entry.value.toClassObject(), @intCast(fd), .{ .owns_fd = true, .readable = true, .writable = false });
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
    const tcp_socket_entry = vm.object_class.module.constants.get(tcp_socket_name) orelse return error.Fatal;
    return vm.newIo(tcp_socket_entry.value.toClassObject(), @intCast(client_fd), .{ .owns_fd = true, .readable = true, .writable = true });
}

pub fn builtinTCPSocketOpen(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 4);
    const socket = try connectTCPSocket(vm, args[0], args[1]);
    if (block) |blk| {
        var yield_args: [1]Value = .{socket};
        const yielded = vm.yieldToBlock(blk, &yield_args) catch |err| {
            _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
            return err;
        };
        _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
        return yielded.value;
    }
    return socket;
}

pub fn builtinSocketTcp(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 4);
    const socket = try connectTCPSocket(vm, args[0], args[1]);
    if (block) |blk| {
        var yield_args: [1]Value = .{socket};
        const yielded = vm.yieldToBlock(blk, &yield_args) catch |err| {
            _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
            return err;
        };
        _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
        return yielded.value;
    }
    return socket;
}

pub fn builtinSocketGethostname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&hostname_buffer) catch {
        return socketError(vm, "gethostname() failed", .{});
    };
    return vm.newString(hostname, false);
}

pub fn builtinSocketDoNotReverseLookup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.getInstanceVariable(receiver, "@do_not_reverse_lookup");
}

pub fn builtinSocketSetDoNotReverseLookup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try vm.setInstanceVariable(receiver, "@do_not_reverse_lookup", Value.boolean(args[0].is_truthy()));
    return args[0];
}

pub fn builtinTCPSocketSetsockopt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    if (!receiver.isIo()) return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});

    const io = receiver.toIoObject();
    if (io.closed) return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});

    const level: c_int = @intCast(try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    const optname: u32 = @intCast(try args[1].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    const optval: c_int = @intCast(try args[2].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));

    if (std.c.setsockopt(io.fd, level, optname, &optval, @sizeOf(c_int)) != 0) {
        return socketError(vm, "setsockopt() failed", .{});
    }

    return Value.integer(0);
}
