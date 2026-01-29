const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "String#inspect basic" {
    const result = try evalCode("\"hello\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\"", result.data.string.str);
}

test "String#inspect with quotes" {
    const result = try evalCode("\"say \\\"hi\\\"\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"say \\\"hi\\\"\"", result.data.string.str);
}

test "String#inspect with newline" {
    const result = try evalCode("\"hello\\nworld\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\\nworld\"", result.data.string.str);
}

test "String#inspect with tab" {
    const result = try evalCode("\"hello\\tworld\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\\tworld\"", result.data.string.str);
}

test "String#inspect with backslash" {
    const result = try evalCode("\"path\\\\to\\\\file\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"path\\\\to\\\\file\"", result.data.string.str);
}

test "String#inspect empty string" {
    const result = try evalCode("\"\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"\"", result.data.string.str);
}

test "String#to_s" {
    const result = try evalCode("'hello'.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}
