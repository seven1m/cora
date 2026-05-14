const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "top-level return warns and ignores value" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def side
        \\  puts "side"
        \\  5
        \\end
        \\return side
        \\puts "after"
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expect(result.value.isNil());
    try std.testing.expectEqualSlices(u8, "side\n", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "warning: argument of top-level return is ignored") != null);
}

test "return in class body raises SyntaxError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class C
        \\  return 1
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid return in class/module body") != null);
}

test "return in module body raises SyntaxError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\module M
        \\  return 1
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid return in class/module body") != null);
}
