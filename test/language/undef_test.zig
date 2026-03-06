const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "undef keyword in a class removes a method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  undef :greet
        \\end
        \\Foo.new.greet
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
}

test "undef keyword at top-level removes the method from Object" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def greet
        \\  "hello"
        \\end
        \\undef :greet
        \\greet
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
}

test "undef keyword works in singleton class scope" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\obj = Object.new
        \\def obj.greet
        \\  "hello"
        \\end
        \\class << obj
        \\  undef :greet
        \\end
        \\obj.greet
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
}
