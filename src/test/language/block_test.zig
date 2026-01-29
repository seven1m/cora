const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Method with block and yield" {
    const result = try evalCode(
        \\def twice
        \\  yield 1
        \\  yield 2
        \\end
        \\
        \\twice { |x| x + 10 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "ArgumentError raised for no block given" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "no block given") != null);
}

test "ArgumentError raised for wrong block arity" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\foo { |a, b| a + b }
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "Block with multiple parameters" {
    const result = try evalCode(
        \\def add_them
        \\  yield 5, 7
        \\end
        \\
        \\add_them { |a, b| a + b }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "Block with no parameters" {
    const result = try evalCode(
        \\def call_block
        \\  yield
        \\end
        \\
        \\call_block { 42 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}
