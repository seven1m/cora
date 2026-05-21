const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Random constant exists and is a class" {
    const result = try evalCode("Random.is_a?(Class)");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
}

test "Random.urandom returns a String of the requested length" {
    const result = try evalCode("Random.urandom(8).bytesize");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Random.urandom returns ASCII-8BIT string with byte length semantics" {
    const result = try evalCode("[s = Random.urandom(16), s.encoding.name, s.bytesize, s.length]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 16), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 16), result.toArrayObject().elements.items[3].toInteger());
}

test "Random formatter adds random_number for SecureRandom-style receivers" {
    const result = try evalCode(
        \\require "random/formatter"
        \\module RandomFormatterTest
        \\  def self.bytes(n)
        \\    Random.bytes(n)
        \\  end
        \\  extend Random::Formatter
        \\end
        \\RandomFormatterTest.random_number(10)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() >= 0);
    try std.testing.expect(result.toInteger() < 10);
}
