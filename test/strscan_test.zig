const std = @import("std");
const test_helper = @import("test_helper.zig");

const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "strscan require exposes class" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "strscan"
        \\puts StringScanner.must_C_version == StringScanner
    , &stdout_buf, &stderr_buf);
    if (result.err != null) {
        std.debug.print("stderr: {s}\nstdout: {s}\n", .{ result.stderr, result.stdout });
    }
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("true\n", result.stdout);
}
