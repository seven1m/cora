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

    const basic_socket_name = try vm.intern("BasicSocket");
    const basic_socket_val = try vm.newClassWithType(basic_socket_name, vm.io_class, .io);
    const basic_socket_class = basic_socket_val.toClassObject();
    try vm.object_class.module.constants.put(basic_socket_name, .{ .value = basic_socket_val });

    const ip_socket_name = try vm.intern("IPSocket");
    const ip_socket_val = try vm.newClassWithType(ip_socket_name, basic_socket_class, .io);
    const ip_socket_class = ip_socket_val.toClassObject();
    try vm.object_class.module.constants.put(ip_socket_name, .{ .value = ip_socket_val });

    const socket_name = try vm.intern("Socket");
    const socket_val = try vm.newClassWithType(socket_name, basic_socket_class, .io);
    const socket_class = socket_val.toClassObject();
    try vm.object_class.module.constants.put(socket_name, .{ .value = socket_val });

    const socket_error_name = try vm.intern("SocketError");
    const socket_error_val = try vm.newClass(socket_error_name, vm.standard_error_class);
    try vm.object_class.module.constants.put(socket_error_name, .{ .value = socket_error_val });

    const tcp_server_name = try vm.intern("TCPServer");
    const tcp_server_val = try vm.newClassWithType(tcp_server_name, ip_socket_class, .io);
    const tcp_server_class = tcp_server_val.toClassObject();
    try vm.object_class.module.constants.put(tcp_server_name, .{ .value = tcp_server_val });

    const tcp_socket_name = try vm.intern("TCPSocket");
    const tcp_socket_val = try vm.newClassWithType(tcp_socket_name, ip_socket_class, .io);
    const tcp_socket_class = tcp_socket_val.toClassObject();
    try vm.object_class.module.constants.put(tcp_socket_name, .{ .value = tcp_socket_val });

    const basic_socket_singleton = try vm.getOrCreateSingletonClass(basic_socket_val);
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

    const for_fd_sym = try vm.intern("for_fd");
    try tcp_server_singleton.module.methods.put(for_fd_sym, value.MethodEntry.builtin(&builtinTCPServerForFd, .{ .exact = 1 }));

    const tcp_sym = try vm.intern("tcp");
    try socket_singleton.module.methods.put(tcp_sym, value.MethodEntry.builtin(&builtinSocketTcp, .{ .variadic = 0 }));

    const tcp_server_sockets_sym = try vm.intern("tcp_server_sockets");
    try socket_singleton.module.methods.put(tcp_server_sockets_sym, value.MethodEntry.builtin(&builtinSocketTcpServerSockets, .{ .variadic = 1 }));

    const gethostname_sym = try vm.intern("gethostname");
    try socket_singleton.module.methods.put(gethostname_sym, value.MethodEntry.builtin(&builtinSocketGethostname, .{ .exact = 0 }));

    const getaddrinfo_sym = try vm.intern("getaddrinfo");
    try socket_singleton.module.methods.put(getaddrinfo_sym, value.MethodEntry.builtin(&builtinSocketGetaddrinfo, .{ .variadic = 2 }));

    const do_not_reverse_lookup_sym = try vm.intern("do_not_reverse_lookup");
    try basic_socket_singleton.module.methods.put(do_not_reverse_lookup_sym, value.MethodEntry.builtin(&builtinSocketDoNotReverseLookup, .{ .exact = 0 }));

    const do_not_reverse_lookup_set_sym = try vm.intern("do_not_reverse_lookup=");
    try basic_socket_singleton.module.methods.put(do_not_reverse_lookup_set_sym, value.MethodEntry.builtin(&builtinSocketSetDoNotReverseLookup, .{ .exact = 1 }));
    try basic_socket_class.module.methods.put(do_not_reverse_lookup_sym, value.MethodEntry.builtin(&builtinSocketDoNotReverseLookup, .{ .exact = 0 }));
    try basic_socket_class.module.methods.put(do_not_reverse_lookup_set_sym, value.MethodEntry.builtin(&builtinSocketSetDoNotReverseLookup, .{ .exact = 1 }));

    const shutdown_sym = try vm.intern("shutdown");
    try basic_socket_class.module.methods.put(shutdown_sym, value.MethodEntry.builtin(&builtinBasicSocketShutdown, .{ .variadic = 0 }));

    const addr_sym = try vm.intern("addr");
    try ip_socket_class.module.methods.put(addr_sym, value.MethodEntry.builtin(&builtinIPSocketAddr, .{ .variadic = 0 }));

    const peeraddr_sym = try vm.intern("peeraddr");
    try ip_socket_class.module.methods.put(peeraddr_sym, value.MethodEntry.builtin(&builtinIPSocketPeeraddr, .{ .variadic = 0 }));

    const setsockopt_sym = try vm.intern("setsockopt");
    try tcp_socket_class.module.methods.put(setsockopt_sym, value.MethodEntry.builtin(&builtinTCPSocketSetsockopt, .{ .exact = 3 }));

    try vm.setInstanceVariable(basic_socket_val, "@do_not_reverse_lookup", Value.boolean(true));

    const ipproto_tcp_sym = try vm.intern("IPPROTO_TCP");
    try socket_class.module.constants.put(ipproto_tcp_sym, .{ .value = Value.integer(std.posix.IPPROTO.TCP) });

    const tcp_nodelay_sym = try vm.intern("TCP_NODELAY");
    try socket_class.module.constants.put(tcp_nodelay_sym, .{ .value = Value.integer(std.c.TCP.NODELAY) });

    const af_inet_sym = try vm.intern("AF_INET");
    try socket_class.module.constants.put(af_inet_sym, .{ .value = Value.integer(std.posix.AF.INET) });

    const af_inet6_sym = try vm.intern("AF_INET6");
    try socket_class.module.constants.put(af_inet6_sym, .{ .value = Value.integer(std.posix.AF.INET6) });

    const shut_rd_sym = try vm.intern("SHUT_RD");
    try socket_class.module.constants.put(shut_rd_sym, .{ .value = Value.integer(std.posix.SHUT.RD) });
    const shut_wr_sym = try vm.intern("SHUT_WR");
    try socket_class.module.constants.put(shut_wr_sym, .{ .value = Value.integer(std.posix.SHUT.WR) });
    const shut_rdwr_sym = try vm.intern("SHUT_RDWR");
    try socket_class.module.constants.put(shut_rdwr_sym, .{ .value = Value.integer(std.posix.SHUT.RDWR) });
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

fn socketClass(vm: *VM) VMError!*ClassObject {
    const socket_name = try vm.intern("Socket");
    const socket_entry = vm.object_class.module.constants.get(socket_name) orelse return error.Fatal;
    return socket_entry.value.toClassObject();
}

fn tcpServerClass(vm: *VM) VMError!*ClassObject {
    const tcp_server_name = try vm.intern("TCPServer");
    const tcp_server_entry = vm.object_class.module.constants.get(tcp_server_name) orelse return error.Fatal;
    return tcp_server_entry.value.toClassObject();
}

fn basicSocketDefaultReverseLookup(vm: *VM) VMError!Value {
    const basic_socket_name = try vm.intern("BasicSocket");
    const basic_socket_entry = vm.object_class.module.constants.get(basic_socket_name) orelse return error.Fatal;
    return vm.getInstanceVariable(basic_socket_entry.value, "@do_not_reverse_lookup");
}

fn initializeSocketReverseLookup(vm: *VM, socket: Value) VMError!void {
    try vm.setInstanceVariable(socket, "@do_not_reverse_lookup", try basicSocketDefaultReverseLookup(vm));
}

fn shutdownHowFromName(vm: *VM, name: []const u8) VMError!c_int {
    if (std.mem.eql(u8, name, "RD") or std.mem.eql(u8, name, "SHUT_RD")) return std.posix.SHUT.RD;
    if (std.mem.eql(u8, name, "WR") or std.mem.eql(u8, name, "SHUT_WR")) return std.posix.SHUT.WR;
    if (std.mem.eql(u8, name, "RDWR") or std.mem.eql(u8, name, "SHUT_RDWR")) return std.posix.SHUT.RDWR;
    return raiseSocketErrorFmt(vm, "unknown shutdown argument: {s}", .{name});
}

fn shutdownHow(vm: *VM, arg: Value) VMError!c_int {
    if (arg.isInteger()) {
        const how = arg.toInteger();
        if (how == std.posix.SHUT.RD or how == std.posix.SHUT.WR or how == std.posix.SHUT.RDWR) return @intCast(how);
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid shutdown argument: {d}", .{how});
    }
    if (arg.isSymbol()) return shutdownHowFromName(vm, arg.toSymbolObject().name);
    return shutdownHowFromName(vm, try arg.coerceToStr(vm, "no implicit conversion into String"));
}

fn socketNumericAddressMode(vm: *VM, receiver: Value, args: []Value) VMError!bool {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 0) {
        return (try vm.getInstanceVariable(receiver, "@do_not_reverse_lookup")).is_truthy();
    }
    if (args[0].isFalse()) return true;
    if (args[0].isTrue()) return false;
    if (args[0].isSymbol() and std.mem.eql(u8, args[0].toSymbolObject().name, "hostname")) return false;
    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid reverse lookup flag: expected true, false, or :hostname", .{});
}

fn sockaddrFamilyName(addr: *const std.c.sockaddr) []const u8 {
    return switch (addr.family) {
        std.posix.AF.INET => "AF_INET",
        std.posix.AF.INET6 => "AF_INET6",
        else => "AF_UNSPEC",
    };
}

fn socketAddressInfo(
    vm: *VM,
    receiver: Value,
    args: []Value,
    comptime name_fn: anytype,
) VMError!Value {
    const numeric = try socketNumericAddressMode(vm, receiver, args);
    if (!receiver.isIo()) return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});

    const io = receiver.toIoObject();
    if (io.closed) return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});

    var storage: std.c.sockaddr.storage = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.c.sockaddr.storage);
    if (name_fn(io.fd, @ptrCast(&storage), &addr_len) != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "socket address lookup failed", .{});
    }

    const addr: *std.c.sockaddr = @ptrCast(&storage);
    var host_buffer: [std.posix.HOST_NAME_MAX + 1]u8 = undefined;
    var ip_buffer: [47]u8 = undefined;
    var service_buffer: [16]u8 = undefined;

    const numeric_flags = std.c.NI{ .NUMERICHOST = true, .NUMERICSERV = true };
    if (@intFromEnum(std.c.getnameinfo(addr, addr_len, ip_buffer[0..].ptr, @intCast(ip_buffer.len), service_buffer[0..].ptr, @intCast(service_buffer.len), numeric_flags)) != 0) {
        return raiseSocketErrorFmt(vm, "getnameinfo failed", .{});
    }

    const hostname_flags = std.c.NI{ .NUMERICSERV = true };
    if (numeric) {
        @memcpy(host_buffer[0..ip_buffer.len], ip_buffer[0..ip_buffer.len]);
    } else if (@intFromEnum(std.c.getnameinfo(addr, addr_len, host_buffer[0..].ptr, @intCast(host_buffer.len), null, 0, hostname_flags)) != 0) {
        @memcpy(host_buffer[0..ip_buffer.len], ip_buffer[0..ip_buffer.len]);
    }

    const port = std.fmt.parseInt(i64, std.mem.sliceTo(service_buffer[0..], 0), 10) catch return error.Fatal;
    const out = try vm.createArray();
    out.elements.append(vm.gc_allocator, try vm.newString(sockaddrFamilyName(addr), false)) catch return error.Fatal;
    out.elements.append(vm.gc_allocator, Value.integer(port)) catch return error.Fatal;
    out.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(host_buffer[0..], 0), false)) catch return error.Fatal;
    out.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(ip_buffer[0..], 0), false)) catch return error.Fatal;
    return Value.fromObject(&out.object);
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

const TcpListenerConfig = struct {
    host: ?[]const u8,
    port_arg: Value,
};

fn parseTcpListenerArgs(vm: *VM, args: []Value) VMError!TcpListenerConfig {
    try vm.requireArgCountRange(args, 1, 2);

    var host: ?[]const u8 = null;
    var port_arg = args[0];
    if (args.len == 2) {
        if (!args[0].isNil()) {
            host = try args[0].coerceToStr(vm, "no implicit conversion into String");
        }
        port_arg = args[1];
    }
    if (host) |host_bytes| {
        if (host_bytes.len == 0) host = null;
    }

    return .{ .host = host, .port_arg = port_arg };
}

fn createTcpListener(vm: *VM, class_obj: *ClassObject, fd: std.posix.fd_t, owns_fd: bool) VMError!Value {
    const socket = try vm.newIo(class_obj, @intCast(fd), .{ .owns_fd = owns_fd, .readable = true, .writable = false });
    try initializeSocketReverseLookup(vm, socket);
    return socket;
}

fn createTcpListeners(vm: *VM, args: []Value, class_obj: *ClassObject, all_matches: bool) VMError!Value {
    const config = try parseTcpListenerArgs(vm, args);

    const host_z = if (config.host) |host| try vm.allocCStringZ(host) else null;
    defer if (host_z) |host| vm.allocator.free(host);

    var service_buf: [32]u8 = undefined;
    const service = if (config.port_arg.isNil())
        ""
    else if (config.port_arg.isString())
        try config.port_arg.coerceToStr(vm, "no implicit conversion into String")
    else blk: {
        const port = try config.port_arg.integerArgToI64(vm, "no implicit conversion into String", "port out of range");
        if (port < 0 or port > 65535) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "port out of range", .{});
        }
        break :blk std.fmt.bufPrint(&service_buf, "{d}", .{port}) catch return error.Fatal;
    };

    const service_z = try vm.allocCStringZ(service);
    defer vm.allocator.free(service_z);

    var hints = std.mem.zeroes(std.c.addrinfo);
    hints.family = std.posix.AF.UNSPEC;
    hints.socktype = std.posix.SOCK.STREAM;
    hints.flags = .{ .PASSIVE = true };

    var addrinfo_result: ?*std.c.addrinfo = null;
    const gai = std.c.getaddrinfo(
        if (host_z) |host| host.ptr else null,
        service_z.ptr,
        &hints,
        &addrinfo_result,
    );
    if (@intFromEnum(gai) != 0) {
        return raiseSocketErrorFmt(vm, "getaddrinfo failed for {s}:{s}", .{ config.host orelse "", service });
    }
    defer if (addrinfo_result) |result| std.c.freeaddrinfo(result);

    const listeners = try vm.createArray();
    var current = addrinfo_result;
    while (current) |addrinfo| : (current = addrinfo.next) {
        const addr = addrinfo.addr orelse continue;
        if (addrinfo.socktype != std.posix.SOCK.STREAM) continue;

        const fd = std.c.socket(@intCast(addrinfo.family), @intCast(addrinfo.socktype), @intCast(addrinfo.protocol));
        if (fd < 0) continue;

        const one: c_int = 1;
        _ = std.c.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &one, @sizeOf(c_int));

        if (std.c.bind(fd, addr, addrinfo.addrlen) != 0) {
            _ = std.c.close(fd);
            continue;
        }

        if (std.c.listen(fd, 128) != 0) {
            _ = std.c.close(fd);
            continue;
        }

        const listener = try createTcpListener(vm, class_obj, @intCast(fd), true);
        listeners.elements.append(vm.gc_allocator, listener) catch return error.Fatal;
        if (!all_matches) break;
    }

    if (listeners.elements.items.len == 0) {
        return socketError(vm, "listen() failed", .{});
    }

    return Value.fromObject(&listeners.object);
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
            const socket = try vm.newIo(try tcpSocketClass(vm), @intCast(fd), .{ .owns_fd = true, .readable = true, .writable = true });
            try initializeSocketReverseLookup(vm, socket);
            return socket;
        }

        const connect_errno = std.posix.errno(-1);
        switch (connect_errno) {
            .INPROGRESS, .AGAIN, .ALREADY => {
                try waitForConnectWritable(vm, posix_fd);
                const so_error = socketConnectError(posix_fd);
                if (so_error == .SUCCESS) {
                    const socket = try vm.newIo(try tcpSocketClass(vm), @intCast(fd), .{ .owns_fd = true, .readable = true, .writable = true });
                    try initializeSocketReverseLookup(vm, socket);
                    return socket;
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
    const listeners = (try createTcpListeners(vm, args, try tcpServerClass(vm), false)).toArrayObject();
    return listeners.elements.items[0];
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
    const socket = try vm.newIo(tcp_socket_entry.value.toClassObject(), @intCast(client_fd), .{ .owns_fd = true, .readable = true, .writable = true });
    try initializeSocketReverseLookup(vm, socket);
    return socket;
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

pub fn builtinSocketGetaddrinfo(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 7);

    const host = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const reverse_lookup = args.len >= 7 and args[6].is_truthy();

    const service = if (args[1].isNil())
        ""
    else if (args[1].isString())
        try args[1].coerceToStr(vm, "no implicit conversion into String")
    else blk: {
        const port = try args[1].integerArgToI64(vm, "no implicit conversion into String", "port out of range");
        break :blk std.fmt.allocPrint(vm.gc_allocator, "{d}", .{port}) catch return error.Fatal;
    };
    defer if (!args[1].isNil() and !args[1].isString()) vm.gc_allocator.free(service);

    const host_z = try vm.allocCStringZ(host);
    defer vm.allocator.free(host_z);
    const service_z = try vm.allocCStringZ(service);
    defer vm.allocator.free(service_z);

    var hints = std.mem.zeroes(std.c.addrinfo);
    var family: c_int = std.posix.AF.UNSPEC;
    var socktype: c_int = 0;
    var protocol: c_int = 0;
    if (args.len >= 3 and !args[2].isNil()) family = @intCast(try args[2].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    if (args.len >= 4 and !args[3].isNil()) socktype = @intCast(try args[3].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    if (args.len >= 5 and !args[4].isNil()) protocol = @intCast(try args[4].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    hints.family = family;
    hints.socktype = socktype;
    hints.protocol = protocol;

    var addrinfo_result: ?*std.c.addrinfo = null;
    const gai = std.c.getaddrinfo(host_z.ptr, if (service.len == 0) null else service_z.ptr, &hints, &addrinfo_result);
    if (@intFromEnum(gai) != 0) {
        return raiseSocketErrorFmt(vm, "getaddrinfo failed for {s}:{s}", .{ host, service });
    }
    defer if (addrinfo_result) |result| std.c.freeaddrinfo(result);

    const out = try vm.createArray();
    var current = addrinfo_result;
    while (current) |addrinfo| : (current = addrinfo.next) {
        const addr = addrinfo.addr orelse continue;
        var host_buffer: [std.posix.HOST_NAME_MAX + 1]u8 = undefined;
        var ip_buffer: [47]u8 = undefined;
        var service_buffer: [16]u8 = undefined;

        const numeric_flags = std.c.NI{ .NUMERICHOST = true, .NUMERICSERV = true };
        if (@intFromEnum(std.c.getnameinfo(addr, addrinfo.addrlen, ip_buffer[0..].ptr, @intCast(ip_buffer.len), service_buffer[0..].ptr, @intCast(service_buffer.len), numeric_flags)) != 0) {
            continue;
        }

        if (reverse_lookup) {
            const hostname_flags = std.c.NI{ .NUMERICSERV = true };
            if (@intFromEnum(std.c.getnameinfo(addr, addrinfo.addrlen, host_buffer[0..].ptr, @intCast(host_buffer.len), null, 0, hostname_flags)) != 0) {
                @memcpy(host_buffer[0..ip_buffer.len], ip_buffer[0..ip_buffer.len]);
            }
        } else {
            const hostname_flags = std.c.NI{ .NUMERICSERV = true };
            if (@intFromEnum(std.c.getnameinfo(addr, addrinfo.addrlen, host_buffer[0..].ptr, @intCast(host_buffer.len), null, 0, hostname_flags)) != 0) {
                @memcpy(host_buffer[0..ip_buffer.len], ip_buffer[0..ip_buffer.len]);
            }
        }

        const entry = try vm.createArray();
        entry.elements.append(vm.gc_allocator, try vm.newString(sockaddrFamilyName(addr), false)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(service_buffer[0..], 0), false)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(host_buffer[0..], 0), false)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(ip_buffer[0..], 0), false)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, Value.integer(addrinfo.family)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, Value.integer(addrinfo.socktype)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, Value.integer(addrinfo.protocol)) catch return error.Fatal;
        out.elements.append(vm.gc_allocator, Value.fromObject(&entry.object)) catch return error.Fatal;
    }

    return Value.fromObject(&out.object);
}

pub fn builtinSocketTcpServerSockets(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    const sockets = try createTcpListeners(vm, args, try socketClass(vm), true);
    if (block) |blk| {
        const yielded = vm.yieldToBlock(blk, &[_]Value{sockets}) catch |err| {
            for (sockets.toArrayObject().elements.items) |socket| {
                _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
            }
            return err;
        };
        for (sockets.toArrayObject().elements.items) |socket| {
            _ = vm.callMethodByName(socket, "close", &[_]Value{}, null) catch {};
        }
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }
    return sockets;
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

pub fn builtinBasicSocketShutdown(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (!receiver.isIo()) return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});

    const io = receiver.toIoObject();
    if (io.closed) return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});

    const how = if (args.len == 0) std.posix.SHUT.RDWR else try shutdownHow(vm, args[0]);
    if (std.c.shutdown(@intCast(io.fd), how) != 0) {
        return socketError(vm, "shutdown() failed", .{});
    }

    return Value.integer(0);
}

pub fn builtinIPSocketAddr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return socketAddressInfo(vm, receiver, args, std.c.getsockname);
}

pub fn builtinIPSocketPeeraddr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return socketAddressInfo(vm, receiver, args, std.c.getpeername);
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

pub fn builtinTCPServerForFd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const fd: std.posix.fd_t = @intCast(try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range"));
    return createTcpListener(vm, try tcpServerClass(vm), fd, true);
}
