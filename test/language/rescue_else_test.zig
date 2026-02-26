const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Else clause runs on normal completion" {
    const result = try evalCode(
        \\begin
        \\  10
        \\rescue
        \\  20
        \\else
        \\  30
        \\end
    );
    try std.testing.expectEqual(@as(i64, 30), result.toInteger());
}

test "Else clause does not run when exception is rescued" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  40
        \\else
        \\  50
        \\end
    );
    try std.testing.expectEqual(@as(i64, 40), result.toInteger());
}
