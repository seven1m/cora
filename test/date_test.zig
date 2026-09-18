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
