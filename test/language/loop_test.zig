const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "loop - repeats until break" {
    const result = try evalCode(
        \\i = 0
        \\loop do
        \\  i = i + 1
        \\  break if i == 10
        \\end
        \\i
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "loop - returns break value" {
    const result = try evalCode(
        \\loop do
        \\  break 123
        \\end
    );
    try std.testing.expectEqual(@as(i64, 123), result.data.integer);
}

test "loop - bare break returns nil" {
    const result = try evalCode(
        \\loop do
        \\  break
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "loop - nested break exits innermost loop call" {
    const result = try evalCode(
        \\outer = 0
        \\loop do
        \\  outer = outer + 1
        \\  inner = loop do
        \\    break 99
        \\  end
        \\  break outer if inner == 99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "loop - propagates non-break exceptions" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\loop do
        \\  raise "boom"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RuntimeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "boom") != null);
}
