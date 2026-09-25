const std = @import("std");
const test_helper = @import("test_helper.zig");

const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "require lazily registers native Date classes" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\p defined?(Date)
        \\p defined?(DateTime)
        \\p require("date")
        \\p defined?(Date)
        \\p defined?(DateTime)
        \\p require("date.rb")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("nil\nnil\ntrue\n\"constant\"\n\"constant\"\nfalse\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date provides frozen month and weekday names" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p [Date::MONTHNAMES[0], Date::MONTHNAMES[12], Date::ABBR_MONTHNAMES[1], Date::DAYNAMES[0], Date::ABBR_DAYNAMES[6], Date::MONTHNAMES.frozen?, Date::DAYNAMES[0].frozen?]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[nil, \"December\", \"Jan\", \"Sunday\", \"Sat\", true, true]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date#to_time constructs local midnight" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date = Date.new(2001, 2, 3)
        \\p [date.to_time == Time.local(2001, 2, 3), date.to_time.class == Time, date.to_time.hour]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[true, true, 0]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "loading Date makes Time#to_time return itself" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\before = Time.now.respond_to?(:to_time)
        \\require "date"
        \\time = Time.now
        \\p [before, time.to_time.equal?(time)]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[false, true]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime.iso8601 parses calendar dates and offsets" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p [DateTime.iso8601("2004-11-24T01:04:44.001-05:00").iso8601(3), DateTime.iso8601("20041124T010444-0500").iso8601, DateTime.iso8601("2004-11-24").iso8601]
        \\p begin; DateTime.iso8601("bad"); rescue => error; [error.class, error.message]; end
        \\p begin; DateTime.iso8601("2004-11-24", limit: 3); rescue => error; [error.class, error.message]; end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"2004-11-24T01:04:44.001-05:00\", \"2004-11-24T01:04:44-05:00\", \"2004-11-24T00:00:00+00:00\"]\n[Date::Error, \"invalid date\"]\n[ArgumentError, \"string length (10) exceeds the limit 3\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime arithmetic inherits Date methods" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\time = DateTime.civil(2024, 1, 1, 12)
        \\p [DateTime.instance_method(:+).owner == Date, DateTime.instance_method(:-).owner == Date, (time + Rational(1, 2)).iso8601, (time - Rational(1, 2)).iso8601]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[true, true, \"2024-01-02T00:00:00+00:00\", \"2024-01-01T00:00:00+00:00\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime accepts compact and short string offsets" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p ["+7", "-3", "+0700", "+7:30", "UTC"].map { |offset| DateTime.new(2001, 2, 3, 4, 5, 6, offset).strftime("%:z") }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"+07:00\", \"-03:00\", \"+07:00\", \"+07:30\", \"+00:00\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Time#to_date is registered with Date support and preserves local civil date" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\before = Time.utc(2024, 1, 2).respond_to?(:to_date)
        \\require "date"
        \\utc = Time.utc(2024, 1, 2, 3, 4, 5).to_date
        \\fixed = Time.new(2024, 1, 1, 0, 30, 0, "+09:00").to_date
        \\local = Time.local(2024, 6, 15, 12, 34, 56).to_date
        \\p [before, utc.instance_of?(Date), [utc.year, utc.month, utc.day], [fixed.year, fixed.month, fixed.day], [local.year, local.month, local.day]]
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[false, true, [2024, 1, 2], [2024, 1, 1], [2024, 6, 15]]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date allocation uses native storage with formatting equality and hashing" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date_a = Date.allocate
        \\date_b = Date.allocate
        \\datetime = DateTime.allocate
        \\p [date_a.inspect, datetime.inspect]
        \\p [date_a.eql?(date_b), date_a.hash == date_b.hash]
        \\p [date_a.eql?(datetime), date_a.hash == datetime.hash]
        \\p [date_a.instance_variables, datetime.instance_variables]
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"#<Date: day=0>\", \"#<DateTime: day=0>\"]\n[true, true]\n[false, false]\n[[], []]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date#gregorian preserves the chronological day and converts civil fields" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\modern = Date.civil(2024, 1, 2)
        \\julian = Date.civil(1500, 3, 1, 2_400_000)
        \\custom = Date.civil(1500, 3, 1, 1)
        \\public_julian = Date.civil(1500, 3, 1, Date::JULIAN)
        \\public_gregorian = Date.civil(1500, 3, 1, Date::GREGORIAN)
        \\julian_gregorian = julian.gregorian
        \\custom_gregorian = custom.gregorian
        \\p [modern.gregorian.class, modern.gregorian.equal?(modern), [modern.gregorian.year, modern.gregorian.month, modern.gregorian.day], modern.gregorian.jd == modern.jd]
        \\p [[julian.year, julian.month, julian.day], [julian_gregorian.year, julian_gregorian.month, julian_gregorian.day], [julian.jd, julian_gregorian.jd], julian_gregorian.gregorian?]
        \\p [[custom.year, custom.month, custom.day], [custom_gregorian.year, custom_gregorian.month, custom_gregorian.day], [custom.jd, custom_gregorian.jd], custom_gregorian.gregorian?]
        \\p [Date::GREGORIAN, Date::JULIAN, Date::GREGORIAN.class, [public_gregorian.start, public_julian.start], [public_gregorian.year, public_gregorian.month, public_gregorian.day], [public_julian.year, public_julian.month, public_julian.day], public_gregorian.start == Date::GREGORIAN, public_julian.start == Date::JULIAN]
        \\p [public_julian.yday, public_julian.wday, public_julian.cwyear, public_julian.cweek, public_julian.cwday, public_julian.next_day.day, (public_julian + 1).day, (public_julian >> 1).day]
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "[Date, false, [2024, 1, 2], true]\n[[1500, 3, 1], [1500, 3, 11], [2268993, 2268993], true]\n[[1500, 3, 1], [1500, 3, 1], [2268983, 2268983], true]\n[-Infinity, Infinity, Float, [-Infinity, Infinity], [1500, 3, 1], [1500, 3, 1], true, true]\n[61, 0, 1500, 9, 7, 2, 2, 1]\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date calendar conversions preserve DateTime time and chronological day" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\original = DateTime.new(1500, 3, 1, 12, 30, 0, "+09:00", Date::JULIAN)
        \\converted = [original.italy, original.england, original.julian, original.gregorian, original.new_start, original.new_start(Date::ENGLAND)]
        \\p converted.map { |date| [date.class, date.jd == original.jd, date.hour == original.hour, date.offset == original.offset, date.start] }
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[[DateTime, true, true, true, 2299161], [DateTime, true, true, true, 2361222], [DateTime, true, true, true, Infinity], [DateTime, true, true, true, -Infinity], [DateTime, true, true, true, 2299161], [DateTime, true, true, true, 2361222]]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date.strptime accepts calendar start and default arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date = Date.strptime("1582-10-04", "%F", Date::GREGORIAN)
        \\p [date.year, date.month, date.day, date.start == Date::GREGORIAN]
        \\p [Date.strptime.class, Date.strptime.start]
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[1582, 10, 4, true]\n[Date, 2299161]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date.strptime requires implicit string conversion" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\begin
        \\  Date.strptime(1384190018, "%Y-%m-%d")
        \\rescue TypeError => error
        \\  p [error.class, error.message]
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[TypeError, \"no implicit conversion of Integer into String\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime.parse handles compact and offset timestamps" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p ["2013-11-12T0211Z", "2013-11-12T02:11Z", "2013-11-12T11:11+9", "2020-123"].map { |text| DateTime.parse(text).iso8601 }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"2013-11-12T00:00:00+00:00\", \"2013-11-12T02:11:00+00:00\", \"2013-11-12T11:11:00+09:00\", \"2020-05-02T00:00:00+00:00\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime equality follows overridden comparison" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date = DateTime.new(2013, 11, 12)
        \\def date.<=>(other)
        \\  0
        \\end
        \\p date == Object.new
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("true\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "DateTime#gregorian preserves class, time, offset, and chronological day" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\datetime = DateTime.civil(1500, 3, 1, 12, 34, 56, "+02:00", 2_400_000)
        \\gregorian = datetime.gregorian
        \\p [gregorian.class, [datetime.jd, gregorian.jd], [gregorian.year, gregorian.month, gregorian.day], [gregorian.hour, gregorian.minute, gregorian.second], gregorian.offset, [datetime.start, gregorian.start], [datetime.start == Date::JULIAN, gregorian.start == Date::GREGORIAN]]
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "[DateTime, [2268993, 2268993], [1500, 3, 11], [12, 34, 56], (1/12), [2400000, -Infinity], [false, true]]\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date#strftime formats Date and DateTime civil fields" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date = Date.new(2024, 6, 15)
        \\datetime = DateTime.new(2024, 6, 15, 12, 34, Rational(113, 2), "+09:30")
        \\p date.strftime("%F %T %N %z %:z %::z %Z %a %b")
        \\p datetime.strftime("%F %T %N %z %:z %::z %Z %a %b")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "\"2024-06-15 00:00:00 000000000 +0000 +00:00 +00:00:00 +00:00 Sat Jun\"\n\"2024-06-15 12:34:56 500000000 +0930 +09:30 +09:30:00 +09:30 Sat Jun\"\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}

test "shared strftime supports names calendar fields ISO weeks and padding" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\format = "%A|%B|%j|%u|%w|%V|%G"
        \\p Date.new(2024, 2, 29).strftime(format)
        \\p Date.new(2021, 1, 1).strftime(format)
        \\p DateTime.new(2018, 12, 31, 12).strftime(format)
        \\p Time.utc(2021, 1, 1).strftime(format)
        \\p Date.new(2024, 2, 3).strftime("%d|%-d|%_d|%0d|%5d|%-5d|%_5d|%05d")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "\"Thursday|February|060|4|4|09|2024\"\n\"Friday|January|001|5|5|53|2020\"\n\"Monday|December|365|1|1|01|2019\"\n\"Friday|January|001|5|5|53|2020\"\n\"03|3| 3|03|00003|3|    3|00003\"\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date compatibility parsing construction and conversion APIs" {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\date = Date.new(2024, 2, 29)
        \\datetime = date.to_datetime
        \\iso = Date._iso8601("2024-060")
        \\rfc = Date._rfc3339("2024-02-29T12:34:56.5+09:30")
        \\p [date.iso8601, date.to_s, [datetime.class, datetime.jd, datetime.hour, datetime.offset]]
        \\p [[Date.ordinal(2024, 60).month, Date.ordinal(2024, 60).day], [Date.ordinal(2023, -1).month, Date.ordinal(2023, -1).day]]
        \\p [Date.parse("2024-02-29").iso8601, Date.parse("20240229").iso8601, Date.parse("29 Feb 2024").iso8601, Date.parse.iso8601]
        \\p [iso[:year], iso[:yday], rfc[:year], rfc[:mon], rfc[:mday], rfc[:hour], rfc[:min], rfc[:sec], rfc[:sec_fraction], rfc[:offset]]
        \\p DateTime.new(2024, 2, 29, 12, 34, Rational(113, 2), "+09:30").iso8601(3)
        \\p [Date.today.class, Date.today == Time.now.to_date]
        \\begin
        \\  Date.parse("not a date")
        \\rescue => error
        \\  p [error.class, error.message]
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "[\"2024-02-29\", \"2024-02-29\", [DateTime, 2460370, 0, (0/1)]]\n[[2, 29], [12, 31]]\n[\"2024-02-29\", \"2024-02-29\", \"2024-02-29\", \"-4712-01-01\"]\n[2024, 60, 2024, 2, 29, 12, 34, 56, (1/2), 34200]\n\"2024-02-29T12:34:56.500+09:30\"\n[Date, true]\n[Date::Error, \"invalid date\"]\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date parses compact ordinal dates with two digit years" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._iso8601("21087")
        \\p Date._iso8601("68001")
        \\p Date._iso8601("69001")
        \\p Date._iso8601("21087T02:03:04Z")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("{yday: 87, year: 2021}\n{yday: 1, year: 2068}\n{yday: 1, year: 1969}\n{}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date parses month names without a day" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._parse("Feb")
        \\p Date._parse("Feb 2005")
        \\p Date._parse("February 2005")
        \\p Date._parse("Sep")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("{mon: 2}\n{year: 2005, mon: 2}\n{year: 2005, mon: 2}\n{mon: 9}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date parses JavaScript style timestamps with GMT offsets" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._parse("Mon May 28 2012 00:00:00 GMT-0700 (PDT)")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("{wday: 1, mon: 5, mday: 28, year: 2012, hour: 0, min: 0, sec: 0, zone: \"GMT-0700\", offset: -25200}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date strptime rejects incomplete and mismatched formats" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._strptime("1999-12-31", "%Y/%m/%d")
        \\p Date._strptime("2024-02-29", "%Y-%m-%d extra")
        \\p Date._strptime("2024-02-29extra", "%Y-%m-%d")
        \\p Date._strptime("abc", "abc")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("nil\nnil\n{year: 2024, mon: 2, mday: 29, leftover: \"extra\"}\n{}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date strptime parses Unix seconds and milliseconds" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._strptime("1470272280", "%s")
        \\p Date._strptime("1470272280000", "%Q")
        \\p Date._strptime("-1001", "%Q")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("{seconds: 1470272280}\n{seconds: (1470272280/1)}\n{seconds: (-1001/1000)}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Date strptime parses timezone offset directives" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "date"
        \\p Date._strptime("-08", "%:::z")
        \\p Date._strptime("-08:00", "%:z")
        \\p Date._strptime("-08:00:30", "%::z")
        \\p Date._strptime("-0800", "%z")
        \\p Date._strptime("Z", "%z")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("{zone: \"-08\", offset: -28800}\n{zone: \"-08:00\", offset: -28800}\n{zone: \"-08:00:30\", offset: -28830}\n{zone: \"-0800\", offset: -28800}\n{zone: \"Z\", offset: 0}\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
