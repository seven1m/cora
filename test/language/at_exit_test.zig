const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Kernel#at_exit returns a Proc" {
    const result = try evalCode(
        \\at_exit { }.is_a?(Proc)
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel#at_exit runs handlers in LIFO order" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\at_exit { puts "first" }
        \\at_exit { puts "second" }
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualSlices(u8, "second\nfirst\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "", result.stderr);
}

test "Kernel#at_exit continues after handler exception and surfaces it" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\puts "body"
        \\at_exit { puts "first" }
        \\at_exit { puts "second"; raise "boom" }
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expectEqualSlices(u8, "body\nsecond\nfirst\n", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "boom (RuntimeError)") != null);
}

test "Kernel#at_exit can run nested Array#each blocks" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\at_exit do
        \\  a = [1]
        \\  a.each do
        \\    a.each do
        \\      a.each do
        \\        a.each do
        \\          a.each do
        \\            a.each do
        \\              puts :ok
        \\            end
        \\          end
        \\        end
        \\      end
        \\    end
        \\  end
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualSlices(u8, "ok\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "", result.stderr);
}
