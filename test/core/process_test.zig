const std = @import("std");
const builtin = @import("builtin");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Process constant exists and is a module" {
    const result = try evalCode("Process.is_a?(Module)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expect(result.data.integer >= 0);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expect(result.data.integer >= 0);
}
