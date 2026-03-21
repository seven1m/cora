const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Basic integer arithmetic" {
    const result = try evalCode("10 + 3");
    try std.testing.expectEqual(@as(i64, 13), result.toInteger());
}

test "Subtraction" {
    const result = try evalCode("10 - 3");
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Multiplication" {
    const result = try evalCode("6 * 7");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Division floors toward negative infinity" {
    var result = try evalCode("7 / 3");
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());

    result = try evalCode("-7 / 3");
    try std.testing.expectEqual(@as(i64, -3), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());

    result = try evalCode("-7 % 3");
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());

    result = try evalCode("7 % -3");
    try std.testing.expectEqual(@as(i64, -2), result.toInteger());
}

test "Exponentiation" {
    const result = try evalCode("2 ** 10");
    try std.testing.expectEqual(@as(i64, 1024), result.toInteger());
}

test "Integer#abs" {
    var result = try evalCode("(-42).abs");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());

    result = try evalCode("42.abs");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Integer#negative?" {
    var result = try evalCode("(-1).negative?");
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("0.negative?");
    try std.testing.expectEqual(false, result.toBool());
}

test "Integer#zero?" {
    var result = try evalCode("0.zero?");
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("1.zero?");
    try std.testing.expectEqual(false, result.toBool());
}

test "Integer#times yields indices and returns receiver" {
    const result = try evalCode(
        \\acc = []
        \\ret = 5.times { |i| acc << i }
        \\[acc.inspect, ret]
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expect(values[0].isString());
    try std.testing.expectEqualSlices(u8, "[0, 1, 2, 3, 4]", values[0].toStringObject().str);
    try std.testing.expect(values[1].isInteger());
    try std.testing.expectEqual(@as(i64, 5), values[1].toInteger());
}

test "Integer#times returns break value" {
    const result = try evalCode("5.times { |i| break :done if i == 2 }");
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "done", result.toSymbolObject().name);
}

test "Integer#times next skips the current iteration" {
    const result = try evalCode(
        \\a = []
        \\3.times do |i|
        \\  next if i == 1
        \\  a << i
        \\end
        \\a
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[1].toInteger());
}

test "Integer#times for non-positive receiver does not yield" {
    var result = try evalCode(
        \\count = 0
        \\ret = 0.times { count += 1 }
        \\[count, ret]
    );
    try std.testing.expect(result.isArray());
    var values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 0), values[1].toInteger());

    result = try evalCode(
        \\count = 0
        \\ret = (-2).times { count += 1 }
        \\[count, ret]
    );
    try std.testing.expect(result.isArray());
    values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, -2), values[1].toInteger());
}

test "Integer#times without a block returns Enumerator" {
    const result = try evalCode("3.times");
    try std.testing.expect(result.isEnumerator());
}

test "Equality comparison - true" {
    const result = try evalCode("5 == 5");
    try std.testing.expectEqual(true, result.toBool());
}

test "Equality comparison - false" {
    const result = try evalCode("6 == 7");
    try std.testing.expectEqual(false, result.toBool());
}

test "Integer#inspect" {
    const result = try evalCode("42.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "42", result.toStringObject().str);
}

test "Integer#to_s" {
    const result = try evalCode("42.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "42", result.toStringObject().str);
}

test "Integer#to_s(base)" {
    var result = try evalCode("12345.to_s(2)");
    try std.testing.expectEqualSlices(u8, "11000000111001", result.toStringObject().str);

    result = try evalCode("12345.to_s(16)");
    try std.testing.expectEqualSlices(u8, "3039", result.toStringObject().str);

    result = try evalCode("12345.to_s(36)");
    try std.testing.expectEqualSlices(u8, "9ix", result.toStringObject().str);

    result = try evalCode("(-95).to_s(16)");
    try std.testing.expectEqualSlices(u8, "-5f", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "A", result.toStringObject().str);
    try std.testing.expectEqualSlices(u8, "US-ASCII", result.toStringObject().encoding.name());

    result = try evalCode("255.chr.encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toStringObject().str);

    result = try evalCode("65.chr(Encoding::UTF_8).encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);

    result = try evalCode("128.chr(Encoding::UTF_8).bytesize");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());

    result = try evalCode("65.chr(\"utf-8\").encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);
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

test "large integer literals and overflow promote to big integer" {
    var result = try evalCode("18446744073709551616");
    try std.testing.expect(result.isBigInteger());

    result = try evalCode("9223372036854775807 + 1");
    try std.testing.expect(result.isBigInteger());

    result = try evalCode("(9223372036854775807 + 1).to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "9223372036854775808", result.toStringObject().str);
}

test "Integer division/modulo overflow promote" {
    var result = try evalCode("(-9223372036854775808) / -1");
    try std.testing.expect(result.isBigInteger());

    result = try evalCode("(-9223372036854775808) % -1");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "Integer math dispatches redefined +" {
    const result = try evalCode(
        \\1 + 2
        \\class Integer
        \\  def +(other)
        \\    99
        \\  end
        \\end
        \\1 + 2
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Integer math dispatches prepended +" {
    const result = try evalCode(
        \\module IntegerPlusOverride
        \\  def +(other)
        \\    123
        \\  end
        \\end
        \\1 + 2
        \\class Integer
        \\  prepend IntegerPlusOverride
        \\end
        \\1 + 2
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 123), result.toInteger());
}

test "Integer == dispatches redefined ==" {
    const result = try evalCode(
        \\1 == 1
        \\class Integer
        \\  def ==(other)
        \\    false
        \\  end
        \\end
        \\1 == 1
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Integer == dispatches prepended ==" {
    const result = try evalCode(
        \\module IntegerEqOverride
        \\  def ==(other)
        \\    :eq_override
        \\  end
        \\end
        \\1 == 1
        \\class Integer
        \\  prepend IntegerEqOverride
        \\end
        \\1 == 1
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "eq_override", result.toSymbolObject().name);
}
