const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Nil value" {
    const result = try evalCode("nil");
    try std.testing.expect(result.data == .nil);
}

test "NilClass#inspect" {
    const result = try evalCode("nil.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "nil", result.data.string.str);
}

test "NilClass#to_s" {
    const result = try evalCode("nil.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "", result.data.string.str);
}
