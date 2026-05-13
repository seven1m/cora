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
