require_relative '../../spec_helper'
require_relative 'shared/to_i'
require_relative 'shared/integer_rounding'
require_relative 'shared/integer_ceil_precision'

describe "Integer#ceil" do
  it_behaves_like :integer_to_i, :ceil
  it_behaves_like :integer_rounding_positive_precision, :ceil

  context "with precision" do
    it_behaves_like :integer_ceil_precision, :Integer
  end

  it "handles big integers with negative precision" do
    (10**30).ceil(-1).should == 10**30
    (10**30).ceil(-40).should == 10**40
    (-(10**30)).ceil(-40).should == 0
  end
end
