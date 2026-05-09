const std = @import("std");
const builtin = @import("builtin");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Process constant exists and is a module" {
    const result = try evalCode("Process.is_a?(Module)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Process.uid returns current uid as Integer" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.uid", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.uid");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() >= 0);
}

test "Process.euid returns current effective uid as Integer" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.euid", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.euid");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() >= 0);
}

test "Process.clock_gettime returns float seconds by default" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.clock_gettime(Process::CLOCK_MONOTONIC)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.clock_gettime(Process::CLOCK_MONOTONIC)");
    try std.testing.expect(result.isFloat());
    try std.testing.expect(result.toFloatObject().val > 0);
}

test "Process.clock_gettime supports nanosecond unit" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode("Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() > 0);
}
