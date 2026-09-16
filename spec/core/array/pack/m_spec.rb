# encoding: binary
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'

describe "Array#pack with format 'm'" do
  it_behaves_like :array_pack_basic, 'm'
  it_behaves_like :array_pack_basic_non_float, 'm'
  it_behaves_like :array_pack_arguments, 'm'

  it "encodes an empty string as an empty string" do
    [""].pack("m").should == ""
  end

  it "appends a newline to the end of the encoded string" do
    ["a"].pack("m").should == "YQ==\n"
  end

  it "encodes one element per directive" do
    ["abc", "DEF"].pack("mm").should == "YWJj\nREVG\n"
  end

  it "encodes 1, 2, or 3 characters in 4 output characters (Base64 encoding)" do
    [ [["a"],       "YQ==\n"],
      [["ab"],      "YWI=\n"],
      [["abc"],     "YWJj\n"],
      [["abcd"],    "YWJjZA==\n"],
      [["abcde"],   "YWJjZGU=\n"],
      [["abcdef"],  "YWJjZGVm\n"],
      [["abcdefg"], "YWJjZGVmZw==\n"],
    ].should be_computed_by(:pack, "m")
  end

  it "emits a newline after complete groups of count / 3 input characters when passed a count modifier" do
    ["abcdefg"].pack("m3").should == "YWJj\nZGVm\nZw==\n"
  end

  it "implicitly has a count of 45 when passed '*', 1, 2 or no count modifier" do
    s = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    r = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFh\nYWFhYWE=\n"
    [ [[s], "m", r],
      [[s], "m*", r],
      [[s], "m1", r],
      [[s], "m2", r],
    ].should be_computed_by(:pack)
  end

  it "calls #to_str to convert an object to a String" do
    obj = mock("pack m string")
    obj.should_receive(:to_str).and_return("abc")
    [obj].pack("m").should == "YWJj\n"
  end

  it "raises a TypeError if #to_str does not return a String" do
    obj = mock("pack m non-string")
    -> { [obj].pack("m") }.should.raise(TypeError)
  end

  it "raises a TypeError if passed nil" do
    -> { [nil].pack("m") }.should.raise(TypeError)
  end

  it "raises a TypeError if passed an Integer" do
    -> { [0].pack("m") }.should.raise(TypeError)
    -> { [bignum_value].pack("m") }.should.raise(TypeError)
  end

  it "does not emit a newline if passed zero as the count modifier" do
    s = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    r = "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE="
    [s].pack("m0").should == r
  end

  it "sets the output string to US-ASCII encoding" do
    ["abcd"].pack("m").encoding.should == Encoding::US_ASCII
  end
end
