const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "logical and basic values" {
    var result = try evalCode("1 && 2");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("nil && 2");
    try std.testing.expect(result.data == .nil);

    result = try evalCode("false && 2");
    try std.testing.expect(result.data == .boolean and !result.data.boolean);
}

test "logical or basic values" {
    var result = try evalCode("1 || 2");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("nil || 2");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("false || 2");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "logical operators honor Ruby truthiness" {
    var result = try evalCode("0 && 5");
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);

    result = try evalCode("0 || 5");
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);
}

test "logical operators short-circuit side effects" {
    var result = try evalCode(
        \\x = 0
        \\false && (x = 1)
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);

    result = try evalCode(
        \\x = 0
        \\true || (x = 1)
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);

    result = try evalCode(
        \\x = 0
        \\true && (x = 1)
        \\x
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode(
        \\x = 0
        \\false || (x = 1)
        \\x
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "keyword forms and/or use same short-circuit semantics" {
    var result = try evalCode("1 and 2");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("nil or 2");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "chained logical expressions" {
    var result = try evalCode("1 && 2 && 3");
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);

    result = try evalCode("nil || false || 3");
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "unary negation with ! and not" {
    var result = try evalCode("!true");
    try std.testing.expect(result.data == .boolean and !result.data.boolean);

    result = try evalCode("!false");
    try std.testing.expect(result.data == .boolean and result.data.boolean);

    result = try evalCode("!nil");
    try std.testing.expect(result.data == .boolean and result.data.boolean);

    result = try evalCode("!1");
    try std.testing.expect(result.data == .boolean and !result.data.boolean);

    result = try evalCode("not true");
    try std.testing.expect(result.data == .boolean and !result.data.boolean);

    result = try evalCode("not false");
    try std.testing.expect(result.data == .boolean and result.data.boolean);
}

test "unary negation composes with logical operators" {
    var result = try evalCode("!false && 42");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode("(not nil) || 7");
    try std.testing.expect(result.data == .boolean and result.data.boolean);
}
