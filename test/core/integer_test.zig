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

test "Division floors toward negative infinity" {
    var result = try evalCode("7 / 3");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("-7 / 3");
    try std.testing.expectEqual(@as(i64, -3), result.data.integer);
}

test "Division by zero raises ZeroDivisionError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("1 / 0", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ZeroDivisionError") != null);
}

test "Modulo follows Ruby sign behavior" {
    var result = try evalCode("7 % 3");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("-7 % 3");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("7 % -3");
    try std.testing.expectEqual(@as(i64, -2), result.data.integer);
}

test "Exponentiation" {
    const result = try evalCode("2 ** 10");
    try std.testing.expectEqual(@as(i64, 1024), result.data.integer);
}

test "Integer#abs" {
    var result = try evalCode("(-42).abs");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode("42.abs");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Integer#negative?" {
    var result = try evalCode("(-1).negative?");
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("0.negative?");
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Integer#zero?" {
    var result = try evalCode("0.zero?");
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("1.zero?");
    try std.testing.expectEqual(false, result.data.boolean);
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

test "Integer#to_s(base)" {
    var result = try evalCode("12345.to_s(2)");
    try std.testing.expectEqualSlices(u8, "11000000111001", result.data.string.str);

    result = try evalCode("12345.to_s(16)");
    try std.testing.expectEqualSlices(u8, "3039", result.data.string.str);

    result = try evalCode("12345.to_s(36)");
    try std.testing.expectEqualSlices(u8, "9ix", result.data.string.str);

    result = try evalCode("(-95).to_s(16)");
    try std.testing.expectEqualSlices(u8, "-5f", result.data.string.str);
}

test "Integer#to_s(base) invalid radix raises ArgumentError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    var result = evalCodeWithOutput("123.to_s(1)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);

    result = evalCodeWithOutput("123.to_s(37)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "Integer#chr default and with encoding" {
    var result = try evalCode("65.chr");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "A", result.data.string.str);
    try std.testing.expectEqualSlices(u8, "US-ASCII", result.data.string.encoding.name());

    result = try evalCode("255.chr.encoding.name");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.data.string.str);

    result = try evalCode("65.chr(Encoding::UTF_8).encoding.name");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "UTF-8", result.data.string.str);

    result = try evalCode("128.chr(Encoding::UTF_8).bytesize");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("65.chr(\"utf-8\").encoding.name");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "UTF-8", result.data.string.str);
}

test "Integer#chr range errors" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    var result = evalCodeWithOutput("-1.chr", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RangeError") != null);

    result = evalCodeWithOutput("256.chr", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RangeError") != null);

    result = evalCodeWithOutput("256.chr(Encoding::ASCII_8BIT)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RangeError") != null);
}
