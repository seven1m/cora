const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Random constant exists and is a class" {
    const result = try evalCode("Random.is_a?(Class)");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
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

test "SecureRandom.bytes supplies random bytes to its formatter" {
    const result = try evalCode(
        \\require "securerandom"
        \\[SecureRandom.bytes(12).bytesize, SecureRandom.alphanumeric(8).length]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 12), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 8), items[1].toInteger());
}

test "Random copies retain independent native state without exposing seed storage" {
    const result = try evalCode(
        \\random = Random.new(2 ** 80 + 17)
        \\hidden = random.instance_variables.empty?
        \\random.bytes(7)
        \\random.instance_variable_set(:@seed, :user_value)
        \\copy = random.dup
        \\clone = random.clone
        \\same = random == copy && random == clone
        \\bytes = random.bytes(12)
        \\same && hidden && copy.bytes(12) == bytes && clone.bytes(12) == bytes &&
        \\  random.seed == 2 ** 80 + 17 && copy.instance_variable_get(:@seed) == :user_value &&
        \\  (random.bytes(1); random != copy)
    );
    try std.testing.expect(result.isTrue());
}

test "Random global byte and numeric draws share deterministic seeded state" {
    const result = try evalCode(
        \\Random.srand(33)
        \\random = Random.new(33)
        \\same = Random.bytes(3) == random.bytes(3) && Random.rand == random.rand && Kernel.rand(256) == random.rand(256)
        \\seed = Random.seed == 33
        \\Random.srand(2 ** 252)
        \\huge = Random.bytes(12) == Random.new(2 ** 252).bytes(12)
        \\negative = Random.new(-33)
        \\same && seed && huge && negative.seed == -33 && negative.bytes(12) == Random.new(33).bytes(12)
    );
    try std.testing.expect(result.isTrue());
}

test "Random formatter keeps floats below one and rejects malformed byte providers" {
    const result = try evalCode(
        \\require "random/formatter"
        \\source = Object.new.extend(Random::Formatter)
        \\def source.bytes(n); "\xff".b * n; end
        \\bounded = source.random_number < 1.0 && source.random_number(-1) < 1.0
        \\def source.bytes(n); "abc"; end
        \\short = begin; source.random_number; false; rescue RangeError; true; end
        \\def source.bytes(n); nil; end
        \\wrong_type = begin; source.random_number; false; rescue TypeError; true; end
        \\bounded && short && wrong_type
    );
    try std.testing.expect(result.isTrue());
}

test "Random class copies and subclasses preserve native allocation" {
    const result = try evalCode(
        \\classes = [Random.dup, Random.clone, Class.new(Random)]
        \\classes.all? do |klass|
        \\  random = klass.new(33)
        \\  random.class == klass && random.seed == 33 && random.bytes(12) == Random.new(33).bytes(12)
        \\end
    );
    try std.testing.expect(result.isTrue());
}
