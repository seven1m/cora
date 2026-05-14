const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "safe navigation returns nil for nil receiver" {
    const result = try evalCode("nil&.downcase");
    try std.testing.expect(result.isNil());
}

test "safe navigation still dispatches for non-nil receiver" {
    var result = try evalCode("\"HTTP\"&.downcase");
    try std.testing.expectEqualStrings("http", result.toStringObject().stringBytes());

    result = try evalCode("false&.nil?");
    try std.testing.expect(result.isBool() and !result.toBool());
}

test "safe navigation does not evaluate arguments when receiver is nil" {
    const result = try evalCode(
        \\def recv(value)
        \\  value
        \\end
        \\
        \\x = 0
        \\nil&.recv(x = 1)
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}
