const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Ensure clause runs on normal completion" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  42
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs after rescue" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  raise "error"
        \\rescue
        \\  100
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 100), result.value.data.integer);

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs during unwinding" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  raise "error"
        \\ensure
        \\  puts "cleanup during unwind"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.Unwind, result.err.?);

    try std.testing.expectEqualSlices(u8, "cleanup during unwind\n", result.stdout);
}

test "Ensure return value is ignored" {
    const result = try evalCode(
        \\begin
        \\  42
        \\ensure
        \\  999
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}
