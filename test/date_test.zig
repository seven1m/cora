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
