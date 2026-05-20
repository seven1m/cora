require_relative '../../spec_helper'

describe "Float#floor" do
  it "returns the largest Integer less than or equal to self" do
    -1.2.floor.should eql(-2)
    -1.0.floor.should eql(-1)
    0.0.floor.should eql(0)
    1.0.floor.should eql(1)
    5.9.floor.should eql(5)
  end

  it "returns self if precision is positive" do
    2.1679.floor(0).should eql(2)
    7.0.floor(1).should eql(7.0)
    200.0.floor(-2).should eql(200)
  end
end