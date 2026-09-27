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
end
