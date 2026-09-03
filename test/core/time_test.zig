const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Time.now returns a Time instance" {
    const result = try evalCode("Time.now.instance_of?(Time)");
    try std.testing.expectEqual(true, result.toBool());
}

test "Time.utc exposes UTC date parts" {
    const result = try evalCode(
        \\t = Time.utc(2024, 6, 15, 12, 34, 56)
        \\[t.year, t.month, t.day, t.utc?]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqual(@as(i64, 2024), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 6), items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 15), items[2].toInteger());
    try std.testing.expectEqual(true, items[3].toBool());
}

test "Time.at preserves integer and fractional epoch values" {
    var result = try evalCode("Time.at(1).to_i");
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());

    result = try evalCode("Time.at(1.25) - Time.at(1)");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), result.toFloatObject().val, 0.0000001);
}

test "Time supports dates outside the i64 nanosecond range" {
    const result = try evalCode(
        \\ancient = Time.local(1, 1, 1)
        \\far_future = Time.utc(292277026596, 1, 1)
        \\[ancient.year, ancient.month, ancient.day, far_future.year]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 292277026596), items[3].toInteger());
}

test "Time stores arbitrary-precision epoch values like MRI" {
    const result = try evalCode(
        \\year = 10**30
        \\huge_year = Time.utc(year, 1, 1)
        \\huge_epoch = Time.at(1e30)
        \\[
        \\  huge_year.year == year,
        \\  huge_epoch.year == 31688738506811431596650,
        \\  huge_epoch.to_i == 1000000000000000019884624838656,
        \\  (huge_epoch + 1).to_i - huge_epoch.to_i
        \\]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(true, items[0].toBool());
    try std.testing.expectEqual(true, items[1].toBool());
    try std.testing.expectEqual(true, items[2].toBool());
    try std.testing.expectEqual(@as(i64, 1), items[3].toInteger());
}

test "Time preserves exact rational arithmetic" {
    const result = try evalCode(
        \\third = Time.at(Rational(1, 3))
        \\[
        \\  (third + Rational(2, 3)) <=> Time.at(1),
        \\  Time.at(1.0).hash == Time.at(1).hash
        \\]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), items[0].toInteger());
    try std.testing.expectEqual(true, items[1].toBool());
}

test "Time rejects non-finite epoch values with FloatDomainError" {
    const result = try evalCode(
        \\[Float::INFINITY, -Float::INFINITY, Float::NAN].map do |value|
        \\  begin
        \\    Time.at(value)
        \\    nil
        \\  rescue => error
        \\    [error.class, error.message]
        \\  end
        \\end
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("FloatDomainError", items[0].toArrayObject().elements.items[0].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("Infinity", items[0].toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualStrings("-Infinity", items[1].toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualStrings("NaN", items[2].toArrayObject().elements.items[1].toStringObject().str);
}

test "Time arithmetic and comparison use epoch values" {
    const result = try evalCode(
        \\a = Time.at(10)
        \\b = a + 5
        \\[b.to_i, a < b, b - a]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 15), items[0].toInteger());
    try std.testing.expectEqual(true, items[1].toBool());
    try std.testing.expect(items[2].isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), items[2].toFloatObject().val, 0.0000001);
}

test "Time#to_a uses Ruby Time field ordering" {
    const result = try evalCode("Time.at(0).getgm.to_a");
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 10), items.len);
    try std.testing.expectEqual(@as(i64, 0), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 0), items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 0), items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 1), items[3].toInteger());
    try std.testing.expectEqual(@as(i64, 1), items[4].toInteger());
    try std.testing.expectEqual(@as(i64, 1970), items[5].toInteger());
    try std.testing.expect(items[9].isString());
    try std.testing.expectEqualStrings("UTC", items[9].toStringObject().str);
}

test "Time#strftime supports RubyGems formats" {
    const result = try evalCode(
        \\t = Time.new("2024-06-15 12:34:56.123456789 Z")
        \\[
        \\  t.strftime("%Y%m%d%H%M%S"),
        \\  t.strftime("%Y%m%dT%H%M%SZ"),
        \\  t.strftime("%Y-%m-%d"),
        \\  t.strftime("%Y-%m-%d %H:%M:%S.%9N Z"),
        \\  t.strftime("%F %T %Z")
        \\]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("20240615123456", items[0].toStringObject().str);
    try std.testing.expectEqualStrings("20240615T123456Z", items[1].toStringObject().str);
    try std.testing.expectEqualStrings("2024-06-15", items[2].toStringObject().str);
    try std.testing.expectEqualStrings("2024-06-15 12:34:56.123456789 Z", items[3].toStringObject().str);
    try std.testing.expectEqualStrings("2024-06-15 12:34:56 UTC", items[4].toStringObject().str);
}

test "Time.new parses RubyGems timestamp strings and rejects date-only strings" {
    var result = try evalCode("Time.new(\"2024-06-15 12:34:56\").strftime(\"%F %T %Z\")");
    try std.testing.expectEqualStrings("2024-06-15 12:34:56 UTC", result.toStringObject().str);

    result = try evalCode(
        \\begin
        \\  Time.new("2024-06-15")
        \\  :no_error
        \\rescue ArgumentError
        \\  :argument_error
        \\end
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("argument_error", result.toSymbolObject().name);
}

test "Time._load decodes MRI marshal payload" {
    const result = try evalCode(
        \\payload = [0xec, 0x15, 0x1f, 0xc0, 0x00, 0x00, 0x80, 0x8b].pack("C*")
        \\Time._load(payload).strftime("%F %T %Z")
    );
    try std.testing.expectEqualStrings("2024-06-15 12:34:56 UTC", result.toStringObject().str);
}

test "Marshal.load restores marshaled Time values" {
    const result = try evalCode(
        \\payload = [0x04, 0x08, 0x49, 0x75, 0x3a, 0x09, 0x54, 0x69, 0x6d, 0x65, 0x0d, 0xec, 0x15, 0x1f, 0xc0, 0x00, 0x00, 0x80, 0x8b, 0x06, 0x3a, 0x09, 0x7a, 0x6f, 0x6e, 0x65, 0x49, 0x22, 0x08, 0x55, 0x54, 0x43, 0x06, 0x3a, 0x06, 0x45, 0x46].pack("C*")
        \\time = Marshal.load(payload)
        \\[time.strftime("%F %T %Z"), time.utc?]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("2024-06-15 12:34:56 UTC", items[0].toStringObject().str);
    try std.testing.expectEqual(true, items[1].toBool());
}
