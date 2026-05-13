require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#%" do
  it "formats multiple expressions" do
    ("%b %x %d %s" % [10, 10, 10, 10]).should == "1010 a 10 10"
  end

  it "formats expressions mid string" do
    ("hello %s!" % "world").should == "hello world!"
  end

  it "formats %% into %" do
    ("%d%% %s" % [10, "of chickens!"]).should == "10% of chickens!"
  end

  it "always interprets an array argument as a list of argument parameters" do
    -> { "%p" % [] }.should raise_error(ArgumentError)
    ("%p" % [1]).should == "1"
    ("%p %p" % [1, 2]).should == "1 2"
  end

  it "always interprets an array subclass argument as a list of argument parameters" do
    -> { "%p" % StringSpecs::MyArray[] }.should raise_error(ArgumentError)
    ("%p" % StringSpecs::MyArray[1]).should == "1"
    ("%p %p" % StringSpecs::MyArray[1, 2]).should == "1 2"
  end

  it "supports binary formats using %b for positive numbers" do
    ("%b" % 10).should == "1010"
    ("%05b" % 10).should == "01010"
    ("%.4b" % 2).should == "0010"
  end

  it "supports character formats using %c" do
    ("%c" % 10).should == "\n"
    ("%-4c" % 10).should == "\n   "
    ("%c" % 42).should == "*"
    ("%c" % "AA").should == "A"
  end

  it "supports integer formats using %d and %i" do
    ("%d" % 10).should == "10"
    ("% i" % 10).should == " 10"
    ("%+d" % 10).should == "+10"
    ("%-7i" % 10).should == "10     "
    ("%04d" % 10).should == "0010"
    ("%6.4d" % 123).should == "  0123"
  end

  it "supports octal formats using %o for positive numbers" do
    ("%o" % 10).should == "12"
    ("%05o" % 10).should == "00012"
  end

  it "supports string formats using %s and inspect formats using %p" do
    ("%s" % "hello").should == "hello"
    ("%-5s" % 10).should == "10   "
    ("%p" % {capture: 1}).should == {capture: 1}.inspect
    ("%p" % "str").should == "\"str\""
  end

  it "supports lowercase and uppercase hexadecimal formats" do
    ("%x" % 10).should == "a"
    ("%X" % 10).should == "A"
    ("%02X" % 15).should == "0F"
  end

  it "supports URI percent-encoding style format strings" do
    ("%%%02X" % 15).should == "%0F"
    ("%%%X%X" % [10, 11]).should == "%AB"
  end
end
