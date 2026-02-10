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

test "String#to_str" {
    const result = try evalCode("'hello'.to_str");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "String#+ concatenates two strings" {
    const result = try evalCode("\"Hello, \" + \"world!\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "Hello, world!", result.data.string.str);
}

test "String#+ concatenates multiple strings" {
    const result = try evalCode("\"a\" + \"b\" + \"c\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "abc", result.data.string.str);
}

test "String#+ TypeError for non-string receiver" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "1 + \"hello\"",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
}

test "String#+ TypeError for non-string argument" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "\"hello\" + 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
}

test "String#+ coerces argument via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.to_str
        \\  " world"
        \\end
        \\"hello" + obj
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello world", result.data.string.str);
}

test "String#+ raises TypeError when to_str returns non-string" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\obj = Object.new
        \\def obj.to_str
        \\  123
        \\end
        \\"hello" + obj
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
}
