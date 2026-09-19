const std = @import("std");
const test_helper = @import("test_helper.zig");

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
