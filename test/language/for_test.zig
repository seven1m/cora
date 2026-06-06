const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "for loop - basic array iteration" {
    const result = try evalCode(
        \\out = []
        \\for x in [1, 2, 3]
        \\  out << x
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), values[2].toInteger());
}

test "for loop - returns nil" {
    const result = try evalCode(
        \\for x in [1]
        \\  x
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "for loop - empty body" {
    const result = try evalCode(
        \\for x in []
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "for loop - multi-target destructuring" {
    const result = try evalCode(
        \\out_a = []
        \\out_b = []
        \\for a, b in [[1, 2], [3, 4]]
        \\  out_a << a
        \\  out_b << b
        \\end
        \\[out_a, out_b]
    );
    try std.testing.expect(result.isArray());
    const arr = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), arr.len);
    const out_a = arr[0].toArrayObject().elements.items;
    const out_b = arr[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), out_a[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), out_a[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), out_b[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), out_b[1].toInteger());
}

test "for loop - next skips iteration" {
    const result = try evalCode(
        \\out = []
        \\for x in [1, 2, 3, 4]
        \\  next if x == 2
        \\  out << x
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 4), values[2].toInteger());
}

test "for loop - break without value" {
    const result = try evalCode(
        \\out = []
        \\for x in [1, 2, 3]
        \\  break if x == 2
        \\  out << x
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
}
