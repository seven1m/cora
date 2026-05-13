const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "redo outside loop - should error" {
    const result = evalCode(
        \\redo
    );
    try std.testing.expectError(error.RedoOutsideLoop, result);
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
