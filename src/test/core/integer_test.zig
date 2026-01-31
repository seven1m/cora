const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Basic integer arithmetic" {
    const result = try evalCode("10 + 3");
    try std.testing.expectEqual(@as(i64, 13), result.data.integer);
}

test "Subtraction" {
    const result = try evalCode("10 - 3");
    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "Multiplication" {
    const result = try evalCode("6 * 7");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Equality comparison - true" {
    const result = try evalCode("5 == 5");
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Equality comparison - false" {
    const result = try evalCode("6 == 7");
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Integer#inspect" {
    const result = try evalCode("42.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "42", result.data.string.str);
}

test "Integer#to_s" {
    const result = try evalCode("42.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "42", result.data.string.str);
}
