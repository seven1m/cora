const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Boolean false" {
    const result = try evalCode("false");
    try std.testing.expectEqual(false, result.toBool());
}

test "FalseClass#inspect" {
    const result = try evalCode("false.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "false", result.toStringObject().str);
}

test "FalseClass#to_s" {
    const result = try evalCode("false.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "false", result.toStringObject().str);
}
