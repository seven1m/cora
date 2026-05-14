const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "redo outside loop - should error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\redo
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid redo") != null);
}

test "while loop - redo restarts the body without rechecking the condition" {
    const result = try evalCode(
        \\i = 0
        \\out = []
        \\while i < 1
        \\  out << i
        \\  i = 1
        \\  redo if out.length == 1
        \\  out << 99
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 99), values[2].toInteger());
}

test "until loop - redo restarts the body without rechecking the condition" {
    const result = try evalCode(
        \\i = 0
        \\out = []
        \\until i == 1
        \\  out << i
        \\  i = 1
        \\  redo if out.length == 1
        \\  out << 99
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 99), values[2].toInteger());
}

test "block redo reruns the current yield without yielding again" {
    const result = try evalCode(
        \\def run(out)
        \\  out << 10
        \\  yield 1
        \\  out << 20
        \\end
        \\
        \\out = []
        \\run(out) do |x|
        \\  out << x
        \\  redo if out.length == 2
        \\  out << x + 1
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 5), values.len);
    try std.testing.expectEqual(@as(i64, 10), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[2].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[3].toInteger());
    try std.testing.expectEqual(@as(i64, 20), values[4].toInteger());
}

test "block redo runs ensure before restarting body" {
    const result = try evalCode(
        \\out = []
        \\i = 0
        \\[1].each do
        \\  begin
        \\    out << i
        \\    i = i + 1
        \\    redo if i < 2
        \\  ensure
        \\    out << 9
        \\  end
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 4), values.len);
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 9), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), values[2].toInteger());
    try std.testing.expectEqual(@as(i64, 9), values[3].toInteger());
}
