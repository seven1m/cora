const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Exception with backtrace shows call stack" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def inner
        \\  raise "deep error"
        \\end
        \\def middle
        \\  inner
        \\end
        \\def outer
        \\  middle
        \\end
        \\outer
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "outer") != null);
}

test "Nested method calls show full backtrace" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def bar
        \\  raise "deep error"
        \\end
        \\
        \\def foo
        \\  bar
        \\end
        \\
        \\foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "deep error") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
    // Both methods should appear in backtrace
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "bar") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "foo") != null);
}
