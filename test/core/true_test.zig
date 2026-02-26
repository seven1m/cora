const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Boolean true" {
    const result = try evalCode("true");
    try std.testing.expectEqual(true, result.toBool());
}

test "TrueClass#inspect" {
    const result = try evalCode("true.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "true", result.toStringObject().str);
}

test "TrueClass#to_s" {
    const result = try evalCode("true.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "true", result.toStringObject().str);
}
