# encoding: utf-8

require_relative '../../spec_helper'

describe "Time#strftime" do
  before :all do
    @new_time = -> *args { Time.gm(*args) }
    @new_time_in_zone = -> zone, offset, *args {
      with_timezone(zone, offset) do
        Time.new(*args)
      end
    }
    @new_time_with_offset = -> y, m, d, h, min, s, offset {
      Time.new(y,m,d,h,min,s,offset)
    }

    @time = @new_time[2001, 2, 3, 4, 5, 6]
  end

  # Differences with date
  it "requires an argument" do
    -> { @time.strftime }.should raise_error(ArgumentError)
  end

  describe "with %z" do
    it "formats a UTC time offset as '+0000'" do
      @new_time_in_zone["GMT", 0, 2005].strftime("%z").should == "+0000"
    end

    it "formats a local time with positive UTC offset as '+HHMM'" do
      @new_time_in_zone["CET", 1, 2005].strftime("%z").should == "+0100"
    end

    it "formats a local time with negative UTC offset as '-HHMM'" do
      @new_time_in_zone["PST", -8, 2005].strftime("%z").should == "-0800"
    end

    it "formats a time with fixed positive offset as '+HHMM'" do
      @new_time_with_offset[2012, 1, 1, 0, 0, 0, 3660].strftime("%z").should == "+0101"
    end

    it "formats a time with fixed negative offset as '-HHMM'" do
      @new_time_with_offset[2012, 1, 1, 0, 0, 0, -3660].strftime("%z").should == "-0101"
    end

    it "formats a time with fixed offset as '+/-HH:MM' with ':' specifier" do
      @new_time_with_offset[2012, 1, 1, 0, 0, 0, 3660].strftime("%:z").should == "+01:01"
    end

    it "formats a time with fixed offset as '+/-HH:MM:SS' with '::' specifier" do
      @new_time_with_offset[2012, 1, 1, 0, 0, 0, 3665].strftime("%::z").should == "+01:01:05"
    end
  end

  # Date/DateTime round at creation time, but Time does it in strftime.
  it "rounds an offset to the nearest second when formatting with %z" do
    time = @new_time_with_offset[2012, 1, 1, 0, 0, 0, Rational(36645, 10)]
    time.strftime("%::z").should == "+01:01:05"
  end

  it "supports RFC 3339 UTC for unknown offset local time, -0000, as %-z" do
    time = Time.gm(2022)

    time.strftime("%z").should == "+0000"
    time.strftime("%-z").should == "-0000"
    time.strftime("%-:z").should == "-00:00"
    time.strftime("%-::z").should == "-00:00:00"
  end

  it "applies '-' flag to UTC time" do
    time = Time.utc(2022)
    time.strftime("%-z").should == "-0000"

    time = Time.gm(2022)
    time.strftime("%-z").should == "-0000"

    CORAFIXME "Time.new with \"Z\" string offset does not set is_utc", exception: SpecFailedException do
      time = Time.new(2022, 1, 1, 0, 0, 0, "Z")
      time.strftime("%-z").should == "-0000"
    end

    CORAFIXME "Time.new with \"-00:00\" string offset does not set is_utc", exception: SpecFailedException do
      time = Time.new(2022, 1, 1, 0, 0, 0, "-00:00")
      time.strftime("%-z").should == "-0000"
    end

    time = Time.new(2022, 1, 1, 0, 0, 0, "+03:00").utc
    time.strftime("%-z").should == "-0000"
  end

  it "ignores '-' flag for non-UTC time" do
    time = Time.new(2022, 1, 1, 0, 0, 0, "+03:00")
    time.strftime("%-z").should == "+0300"
  end

  it "works correctly with width, _ and 0 flags, and :" do
    CORAFIXME "strftime width/padding flags not yet implemented", exception: SpecFailedException do
      Time.now.utc.strftime("%-_10z").should == "      -000"
      Time.now.utc.strftime("%-10z").should == "-000000000"
      Time.now.utc.strftime("%-010:z").should == "-000000:00"
      Time.now.utc.strftime("%-_10:z").should == "     -0:00"
      Time.now.utc.strftime("%-_10::z").should == "  -0:00:00"
    end
  end
end
