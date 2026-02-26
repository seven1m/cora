const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Re-raise in rescue clause" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  begin
        \\    raise "original"
        \\  rescue
        \\    raise "re-raised"
        \\  end
        \\rescue
        \\  puts "final"
        \\end
    , &stdout_buf, &stderr_buf);

    // Outer rescue catches the re-raised exception
    try std.testing.expect(result.err == null);
    try std.testing.expect(result.value.isNil());
    try std.testing.expectEqualSlices(u8, "final\n", result.stdout);
}

test "Code before raise executes normally" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\puts "before raise"
        \\raise "error"
        \\puts "after raise"
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    // Code before raise should execute, code after should NOT
    try std.testing.expectEqualSlices(u8, "before raise\n", result.stdout);
}

test "Raise with empty message" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "raise ArgumentError",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "Raise with string message creates RuntimeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput("raise \"something went wrong\"", &stdout_buf, &stderr_buf);

    // Should get RuntimeError
    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    // Check stderr contains exception info
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RuntimeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "something went wrong") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
}

test "Raise with exception class and message" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "raise ArgumentError, \"expected 2 arguments\"",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "expected 2 arguments") != null);
}
