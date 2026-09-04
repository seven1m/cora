require_relative '../spec_helper'

describe "CORAFIXME" do
  it "hides a failing block with default exception" do
    CORAFIXME "generic failing behavior" do
      raise "expected failure"
    end
  end

  it "hides a failing block with exception and regex message" do
    CORAFIXME "specific failure", exception: NoMethodError, message: /undefined method/ do
      Object.new.not_a_real_method
    end
  end

  it "raises when the block passes" do
    -> {
      CORAFIXME "now passing behavior" do
        1.should == 1
      end
    }.should raise_error(CoraFixMeException, /Issue has been fixed/)
  end

  it "raises when the block raises the wrong exception class" do
    -> {
      CORAFIXME "wrong class", exception: ZeroDivisionError do
        raise NoMethodError, "wrong error"
      end
    }.should raise_error(CoraFixMeException, /marker class is incorrect/)
  end

  it "raises when the block raises the expected class but wrong message" do
    -> {
      CORAFIXME "wrong message", exception: RuntimeError, message: /expected text/ do
        raise "different text"
      end
    }.should raise_error(CoraFixMeException, /marker message is incorrect/)
  end

  it "runs the block normally when condition is false" do
    CORAFIXME "disabled marker", condition: false do
      2.should == 2
    end
  end

  it "requires a block" do
    -> {
      CORAFIXME "missing block"
    }.should raise_error(SpecExpectationNotMetError, /requires a block/)
  end
end
