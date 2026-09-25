const std = @import("std");
const test_helper = @import("test_helper.zig");

test "TCPSocket subclass connections retain their class" {
    const result = try test_helper.evalCode(
        \\require "socket"
        \\server = TCPServer.new("127.0.0.1", 0)
        \\subclass = Class.new(TCPSocket)
        \\client = subclass.new("127.0.0.1", server.addr[1])
        \\actual_class = client.class
        \\client.close
        \\server.close
        \\actual_class == subclass
    );
    try std.testing.expect(result.isTruthy());
}

test "TCPSocket setsockopt accepts boolean values" {
    const result = try test_helper.evalCode(
        \\require "socket"
        \\server = TCPServer.new("127.0.0.1", 0)
        \\client = TCPSocket.new("127.0.0.1", server.addr[1])
        \\values = [true, false].map { |value| client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, value) }
        \\client.close
        \\server.close
        \\values
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 0), values[1].toInteger());
}

test "Socket exposes system socket option constants" {
    const result = try test_helper.evalCode(
        \\require "socket"
        \\[Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, Socket::SO_RCVBUF, Socket::SO_SNDBUF, Socket::SO_RCVTIMEO, Socket::SO_SNDTIMEO]
    );
    const values = result.toArrayObject().elements.items;
    const expected = [_]i64{ std.c.SOL.SOCKET, std.c.SO.KEEPALIVE, std.c.SO.RCVBUF, std.c.SO.SNDBUF, std.c.SO.RCVTIMEO, std.c.SO.SNDTIMEO };
    for (values, expected) |actual, constant| {
        try std.testing.expectEqual(constant, actual.toInteger());
    }
}

test "UNIXServer and UNIXSocket exchange data" {
    const result = try test_helper.evalCode(
        \\require "socket"
        \\path = "/tmp/cora-unix-socket-#{$$}"
        \\server = UNIXServer.new(path)
        \\client = UNIXSocket.open(path)
        \\accepted = server.accept
        \\client.write("ping")
        \\value = [server.path, accepted.read(4), client.class, accepted.class]
        \\accepted.close
        \\client.close
        \\server.close
        \\File.unlink(path)
        \\value
    );

    const items = result.toArrayObject().elements.items;
    try std.testing.expect(std.mem.startsWith(u8, items[0].toStringObject().str, "/tmp/cora-unix-socket-"));
    try std.testing.expectEqualStrings("ping", items[1].toStringObject().str);
    try std.testing.expectEqualStrings("UNIXSocket", items[2].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("UNIXSocket", items[3].toClassObject().module.name.name);
}
