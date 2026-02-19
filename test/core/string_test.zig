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

test "String#length and String#size" {
    var result = try evalCode("'hello'.length");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);

    result = try evalCode("'hello'.size");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "String#[] with integer index" {
    var result = try evalCode("'hello'[0]");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "h", result.data.string.str);

    result = try evalCode("'hello'[-1]");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "o", result.data.string.str);

    result = try evalCode("'hello'[99]");
    try std.testing.expect(result.data == .nil);
}

test "String#[] with range slice" {
    var result = try evalCode("'hello world'[0...5]");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);

    result = try evalCode("'hello world'[6..-1]");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "world", result.data.string.str);

    result = try evalCode("'hello'[20..25]");
    try std.testing.expect(result.data == .nil);
}

test "String#<< appends string and codepoint" {
    var result = try evalCode("s = 'ab'; s << 'cd'; s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "abcd", result.data.string.str);

    result = try evalCode("s = 'A'; s << 66; s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "AB", result.data.string.str);
}

test "String#start_with? and #end_with?" {
    var result = try evalCode("'|abc'.start_with?('|')");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("\"line\\n\".end_with?(\"\\n\")");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("'hello'.start_with?('x')");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "String#prepend" {
    var result = try evalCode("s = 'world'; s.prepend('hello '); s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello world", result.data.string.str);

    result = try evalCode("s = 'world'; s.prepend('he', '', 'llo '); s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello world", result.data.string.str);
}

test "String#upcase" {
    var result = try evalCode("'hello'.upcase");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "HELLO", result.data.string.str);

    result = try evalCode("'a1b!'.upcase");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "A1B!", result.data.string.str);
}

test "String#to_i" {
    var result = try evalCode("'123abc'.to_i");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 123), result.data.integer);

    result = try evalCode("'  -10x'.to_i");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, -10), result.data.integer);

    result = try evalCode("'ff'.to_i(16)");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 255), result.data.integer);
}

test "String#to_sym" {
    const result = try evalCode("'hello'.to_sym.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "String#chars propagates break value" {
    var result = try evalCode("'abc'.chars { |c| break :done if c == 'b' }");
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "done", result.data.symbol.name);

    result = try evalCode("'abc'.chars { break }");
    try std.testing.expect(result.data == .nil);
}

test "String#unpack integer and float directives" {
    var result = try evalCode("\"\\x01\\x02\".b.unpack('C2').inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, 2]", result.data.string.str);

    result = try evalCode("\"\".b.unpack('C2').inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[nil, nil]", result.data.string.str);

    result = try evalCode("[1.5].pack('d').unpack('d')[0]");
    try std.testing.expect(result.data == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.data.float, 0.0000001);
}

test "String#unpack string directives" {
    var result = try evalCode("\"A \\x00\".b.unpack('A3').inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[\"A\"]", result.data.string.str);

    result = try evalCode("\"abc\\x00xyz\".b.unpack('Z*').inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[\"abc\"]", result.data.string.str);
}
