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

test "Process::WNOHANG exists" {
    const result = try evalCode("Process::WNOHANG");
    try std.testing.expect(result.isInteger());
    try std.testing.expect(result.toInteger() != 0);
}

test "Process.kill and Process.wait with WNOHANG work for popen child" {
    if (builtin.os.tag == .windows) {
        var stdout_buf: [1024]u8 = undefined;
        var stderr_buf: [1024]u8 = undefined;
        const bad = evalCodeWithOutput("Process.kill('TERM', 1)", &stdout_buf, &stderr_buf);
        try std.testing.expectEqual(error.UnhandledException, bad.err.?);
        try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "RuntimeError") != null);
        return;
    }

    const result = try evalCode(
        \\io = IO.popen(["/usr/bin/env", "sh", "-lc", "sleep 10"], err: [:child, :out])
        \\pid = io.pid
        \\first = Process.wait(pid, Process::WNOHANG)
        \\kill_count = Process.kill("KILL", pid)
        \\second = Process.wait(pid)
        \\status = $?
        \\io.close
        \\[
        \\  first.nil?,
        \\  kill_count,
        \\  second == pid,
        \\  status.signaled?,
        \\  status.termsig
        \\]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(true, elems[0].toBool());
    try std.testing.expectEqual(@as(i64, 1), elems[1].toInteger());
    try std.testing.expectEqual(true, elems[2].toBool());
    try std.testing.expectEqual(true, elems[3].toBool());
    try std.testing.expect(elems[4].toInteger() > 0);
}
