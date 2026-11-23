const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Numeric step preserves large Integer and Rational values and exact sizes" {
    const result = try evalCode(
        \\start = 2**80
        \\sequence = start.step(start + 10, 3)
        \\expected = [start, start + 3, start + 6, start + 9]
        \\raise "integer values" unless sequence.to_a == expected && sequence.size == 4
        \\raise "metadata" unless [sequence.begin, sequence.end, sequence.step] == [start, start + 10, 3]
        \\raise "external iteration" unless sequence.next == start && sequence.to_a == expected && sequence.next == start + 3
        \\r = Rational(1, 3).step(Rational(1), Rational(1, 6))
        \\raise "rational values" unless r.to_a == [Rational(1, 3), Rational(1, 2), Rational(2, 3), Rational(5, 6), Rational(1)] && r.size == 5
        \\raise "negative values" unless (start + 10).step(start, -3).to_a == [start + 10, start + 7, start + 4, start + 1]
        \\raise "range size" unless (start..start + 10).step(3).size == 4
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "Numeric step metadata and block control flow preserve their Numeric receiver" {
    const result = try evalCode(
        \\sequence = 1.5.step(to: 5, by: 0.5)
        \\raise "sequence" unless [sequence.begin, sequence.end, sequence.step] == [1.5, 5, 0.5]
        \\range_sequence = (1..5).step(2)
        \\raise "range metadata" unless [range_sequence.begin, range_sequence.end, range_sequence.step] == [1, 5, 2]
        \\raise "break" unless 1.step(to: 10, by: 2) { |n| break [:stopped, n] if n == 5 } == [:stopped, 5]
        \\def from_step
        \\  Rational(1).step(Rational(2), Rational(1, 3)) { |n| return n if n > 1 }
        \\end
        \\raise "return" unless from_step == Rational(4, 3)
        \\value = Rational(2, 3)
        \\raise "receiver" unless value.step(value) {}.equal?(value)
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "Numeric rejected singleton methods are removed and overridden hooks remain effective" {
    const result = try evalCode(
        \\class Number < Numeric
        \\  def singleton_method_removed(name)
        \\    @removed = name
        \\  end
        \\  attr_reader :removed
        \\end
        \\n = Number.new
        \\begin
        \\  def n.rejected; 1; end
        \\  raise "singleton accepted"
        \\rescue TypeError
        \\end
        \\raise "method remains" if n.respond_to?(:rejected)
        \\raise "remove hook" unless n.removed == :rejected
        \\[1.5, 2**80].each do |number|
        \\  begin
        \\    def number.rejected; 1; end
        \\    raise "singleton accepted"
        \\  rescue TypeError
        \\  end
        \\  raise "method remains" if number.respond_to?(:rejected)
        \\end
        \\class AllowedNumber < Number
        \\  def singleton_method_added(name); end
        \\end
        \\allowed = AllowedNumber.new
        \\def allowed.accepted; 7; end
        \\allowed.accepted == 7
    );
    try std.testing.expect(result.isTruthy());
}
