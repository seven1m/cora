const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Complex imaginary literals preserve numeric types and bypass Ruby constructors" {
    const result = try evalCode(
        \\values = [1i, -2i, 0xffi, 1.25i, 2ri, 1.25ri, 123456789012345678901234567890i]
        \\raise "coefficients" unless values.map(&:imag) == [1, -2, 255, 1.25, Rational(2), Rational(5, 4), 123456789012345678901234567890]
        \\raise "types" unless values.map { |n| n.imag.class } == [Integer, Integer, Integer, Float, Rational, Rational, Integer]
        \\raise "real parts" unless values.all? { |n| n.real.eql?(0) && n.frozen? }
        \\expected = Rational(12345678901234567890123456789012345678901234567890, 10**20)
        \\raise "large rational imaginary" unless 123456789012345678901234567890.12345678901234567890ri.imag == expected
        \\raise "large rational" unless 123456789012345678901234567890.12345678901234567890r == expected
        \\original = Complex
        \\Object.send(:remove_const, :Complex)
        \\Complex = Class.new
        \\literal = eval('123456789012345678901234567890i')
        \\literal.class == original && literal.real == 0 && literal.imag == 123456789012345678901234567890 && defined?(1i) == "expression"
    );
    try std.testing.expect(result.isTruthy());
}

test "Complex integer powers retain exact components and handle large exponents and axes" {
    const result = try evalCode(
        \\value = Complex(Rational(2, 3), Rational(1, 4))
        \\raise "exact positive power" unless (value**5).eql?(value*value*value*value*value)
        \\raise "exact reciprocal" unless (value**-5 * value**5) == 1
        \\raise "rational integer exponent" unless (value**Rational(3, 1)).eql?(value**3)
        \\raise "complex integer exponent" unless (value**Complex(3, 0)).eql?(value**3)
        \\raise "large exponent" unless (1i**(2**80 + 3)) == -1i
        \\infinite = Complex(Float::INFINITY, 0.0)**2
        \\raise "axis infinity" unless infinite.real.infinite? == 1 && infinite.imag.eql?(0.0)
        \\negative_zero = Complex(2.0, -0.0)**3
        \\raise "signed zero" unless (1.0 / negative_zero.imag).infinite? == -1
        \\true
    );
    try std.testing.expect(result.isTruthy());
}

test "Complex polar construction preserves exact axes and validates Numeric conversions" {
    const result = try evalCode(
        \\radius = Rational(2, 3)
        \\raise "zero angle" unless Complex.polar(radius).real.eql?(radius)
        \\raise "quarter turn" unless Complex.polar(radius, Math::PI/2).imag.eql?(radius)
        \\raise "half turn" unless Complex.polar(radius, Math::PI).real.eql?(-radius)
        \\raise "three quarters" unless Complex.polar(radius, 3*Math::PI/2).imag.eql?(-radius)
        \\class BadReal < Numeric
        \\  def real?; true; end
        \\  def zero?; false; end
        \\  def to_f; "bad"; end
        \\end
        \\begin
        \\  Complex.polar(1, BadReal.new)
        \\  raise "invalid conversion accepted"
        \\rescue TypeError
        \\end
        \\true
    );
    try std.testing.expect(result.isTruthy());
}
