const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "while loop - basic execution" {
    const result = try evalCode(
        \\x = 3
        \\while x == 3
        \\  x = x + 1
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - condition false from start" {
    const result = try evalCode(
        \\x = 10
        \\while false
        \\  x = 999
        \\end
        \\x
    );
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "while loop - empty body" {
    const result = try evalCode(
        \\while false
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - modifier form" {
    const result = try evalCode(
        \\x = 5
        \\x = x - 1 while x == 5
        \\x
    );
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());
}

test "while loop - break without value" {
    const result = try evalCode(
        \\i = 0
        \\while true
        \\  i = i + 1
        \\  break if i == 3
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - break with value" {
    const result = try evalCode(
        \\i = 0
        \\while true
        \\  i = i + 1
        \\  break 42 if i == 3
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "while loop - break in nested loop" {
    const result = try evalCode(
        \\outer = 0
        \\while outer == 0
        \\  outer = outer + 1
        \\  inner = 0
        \\  while inner == 0
        \\    inner = inner + 1
        \\    break 99 if inner == 2
        \\  end
        \\end
        \\outer
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "while loop - break returns expression value" {
    const result = try evalCode(
        \\x = 10
        \\while true
        \\  break x + 5
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "while loop - next skips to the next iteration" {
    const result = try evalCode(
        \\i = 0
        \\out = []
        \\while i < 4
        \\  i = i + 1
        \\  next if i == 2
        \\  out << i
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
