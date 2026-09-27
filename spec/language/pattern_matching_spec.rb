require_relative '../spec_helper'

describe "Pattern matching" do
  before :each do
    ScratchPad.record []
  end

  describe "Rightward assignment (`=>`) that can be standalone assoc operator that" do
    it "deconstructs value" do
      suppress_warning do
        [0, 1] => [a, b]
        [a, b].should == [0, 1]
      end
    end

    it "deconstructs value and properly scopes variables" do
      suppress_warning do
        a = nil
        1.times {
          [0, 1] => [a, b]
        }
        [a, defined?(b)].should == [0, nil]
      end
    end

    it "can work with keywords" do
      { a: 0, b: 1 } => { a:, b: }
      [a, b].should == [0, 1]
    end
  end

  # Adapted from upstream case/in examples for Nokogiri's rightward patterns.
  describe "find pattern" do
    it "captures both preceding and following elements to the pattern" do
      [0, 1, 2, 3, 4] => [*pre, 2, *post]
      [pre, post].should == [[0, 1], [3, 4]]
    end

    it "can nest hash and array patterns" do
      [0, {a: 42, b: [0, 1]}, {a: 42, b: [1, 2]}] => [*, {a: 42, b: [1, c]}, *]
      c.should == 2
    end
  end

  describe "variable pattern" do
    it "supports existing variables in a pattern specified with ^ operator" do
      a = 0
      [0] => [^a]
      a.should == 0
    end
  end

  describe "pinned expression" do
    it "supports pinning expressions in hash patterns" do
      expected = "value"
      matched = ({ key: "value" } => { key: ^(expected.upcase.downcase) })
      matched.should == { key: "value" }
    end
  end
end
