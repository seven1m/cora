const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "while loop - basic execution" {
    const result = try evalCode(
        \\x = 3
        \\while x == 3
        \\  x = x + 1
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "while loop - condition false from start" {
    const result = try evalCode(
        \\x = 10
        \\while false
        \\  x = 999
        \\end
        \\x
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "while loop - empty body" {
    const result = try evalCode(
        \\while false
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "while loop - modifier form" {
    const result = try evalCode(
        \\x = 5
        \\x = x - 1 while x == 5
        \\x
    );
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}
