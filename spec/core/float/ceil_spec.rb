require_relative '../../spec_helper'

describe "Float#ceil" do
  it "returns the smallest Integer greater than or equal to self" do
    -1.2.ceil.should eql(-1)
    -1.0.ceil.should eql(-1)
    0.0.ceil.should eql(0)
    1.3.ceil.should eql(2)
    3.0.ceil.should eql(3)
  end

  it "returns self if precision is positive" do
    2.1679.ceil(0).should eql(3)
    7.0.ceil(1).should eql(7.0)
    200.0.ceil(-2).should eql(200)
  end
end