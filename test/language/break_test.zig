const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "break outside loop - should error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\break
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid break") != null);
}

test "break outside loop with value - should error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\x = 5
        \\break x
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid break") != null);
}
