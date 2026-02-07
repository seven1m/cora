const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "If expression" {
    var result = try evalCode(
        \\if true
        \\  42
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode(
        \\if false
        \\  42
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);

    result = try evalCode(
        \\if true
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode(
        \\if false
        \\  42
        \\end
    );
    try std.testing.expect(result.data == .nil);
}
