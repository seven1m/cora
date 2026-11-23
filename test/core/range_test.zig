const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Range reverse iteration and size cross immediate Integer boundaries exactly" {
    const result = try evalCode(
        \\limit = 2**62
        \\positive = ((limit - 2)..(limit + 1))
        \\negative = ((-limit - 2)..(-limit + 1))
        \\positive.reverse_each.to_a == [limit + 1, limit, limit - 1, limit - 2] &&
        \\  negative.reverse_each.to_a == [-limit + 1, -limit, -limit - 1, -limit - 2] &&
        \\  (..-limit).reverse_each.take(3) == [-limit, -limit - 1, -limit - 2] &&
        \\  positive.size == 4 && positive.reverse_each.size == 4 &&
        \\  ((-2**64)..(2**64)).size == 2**65 + 1 &&
        \\  ((-2**64)...(2**64)).reverse_each.size == 2**65
    );
    try std.testing.expect(result.toBool());
}

test "Range methods use native endpoints and clamp captures bounds before callbacks" {
    const result = try evalCode(
        \\subclass = Class.new(Range) do
        \\  def begin; raise "unexpected begin"; end
        \\  def end; raise "unexpected end"; end
        \\end
        \\range = subclass.new(1, 3)
        \\values = []
        \\range.reverse_each { |value| values << value }
        \\steps = []
        \\range.step { |value| steps << value }
        \\range = subclass.allocate
        \\bounds = Object.new
        \\bounds.define_singleton_method(:begin) { range.send(:initialize, 20, 30); 3 }
        \\def bounds.end; 7; end
        \\def bounds.exclude_end?; false; end
        \\clamped = range.clamp(bounds)
        \\values == [3, 2, 1] && steps == [1, 2, 3] && range == (20..30) && clamped == (3..7) &&
        \\  clamped.instance_of?(Range) && clamped.frozen?
    );
    try std.testing.expect(result.toBool());
}

test "Range minmax dispatches endpoint overrides only without a comparison block" {
    const result = try evalCode(
        \\subclass = Class.new(Range) do
        \\  def min; :low; end
        \\  def max; :high; end
        \\end
        \\range = subclass.new(1, 3)
        \\range.minmax == [:low, :high] &&
        \\  range.minmax { |a, b| b <=> a } == [3, 1] &&
        \\  range.minmax { break :stopped } == :stopped
    );
    try std.testing.expect(result.toBool());
}

test "Range reverse fallback enumerates each instead of overridden to_a" {
    const result = try evalCode(
        \\subclass = Class.new(Range) do
        \\  def to_a; raise "unexpected to_a"; end
        \\end
        \\values = []
        \\subclass.new("a", "c").reverse_each { |value| values << value }
        \\values == ["c", "b", "a"]
    );
    try std.testing.expect(result.toBool());
}

test "Range numeric step sizes and values support Rational and large Integer endpoints" {
    const result = try evalCode(
        \\rational = (1..Rational(7, 2)) % Rational(1, 2)
        \\big = 2**64 + 1
        \\integers = (big..big+4) % 2
        \\(1..Rational(7,2)).reverse_each.size == 3 &&
        \\  (1...Rational(7,2)).reverse_each.size == 3 &&
        \\  rational.size == 6 && rational.to_a.eql?([
        \\    1, Rational(3,2), Rational(2), Rational(5,2), Rational(3), Rational(7,2)
        \\  ]) && integers.size == 3 && integers.to_a == [big, big+2, big+4] &&
        \\  ((1..Rational(7,2)) % 0.5).to_a.eql?([1.0, 1.5, 2.0, 2.5, 3.0, 3.5])
    );
    try std.testing.expect(result.toBool());
}
