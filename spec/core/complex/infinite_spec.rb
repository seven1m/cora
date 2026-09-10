require_relative '../../spec_helper'

describe "Complex#infinite?" do
  it "returns nil if magnitude is finite" do
    # Upstream uses (1+1i); the `1i` imaginary literal (ImaginaryNode) is not
    # supported by the compiler yet, so use the equivalent Complex() form.
    Complex(1, 1).infinite?.should == nil
  end

  it "returns 1 for positive infinity" do
    value = Complex(Float::INFINITY, 42).infinite?
    value.should == 1
  end

  it "returns 1 for positive complex with infinite imaginary" do
    value = Complex(1, Float::INFINITY).infinite?
    value.should == 1
  end

  it "returns -1 for negative infinity" do
    value = -Complex(Float::INFINITY, 42).infinite?
    value.should == -1
  end

  it "returns -1 for negative complex with infinite imaginary" do
    value = -Complex(1, Float::INFINITY).infinite?
    value.should == -1
  end

  it "returns nil for NaN" do
    value = Complex(0, Float::NAN).infinite?
    value.should == nil
  end
end
