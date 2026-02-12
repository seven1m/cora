const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

// Phase 1: Simple multi-assignment with local variables

test "simple two-variable assignment" {
    var result = try evalCode("a, b = 1, 2; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("a, b = 1, 2; b");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "more targets than values - nil padding" {
    var result = try evalCode("a, b, c = 1, 2; c");
    try std.testing.expect(result.data == .nil);

    result = try evalCode("a, b, c, d = 1, 2; d");
    try std.testing.expect(result.data == .nil);
}

test "fewer targets than values - extras ignored" {
    var result = try evalCode("a, b = 1, 2, 3, 4; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("a, b = 1, 2, 3, 4; b");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "multi-assignment with array literal" {
    var result = try evalCode("a, b = [10, 20]; a");
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);

    result = try evalCode("a, b = [10, 20]; b");
    try std.testing.expectEqual(@as(i64, 20), result.data.integer);
}

test "swapping variables" {
    var result = try evalCode("a = 1; b = 2; a, b = b, a; a");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("a = 1; b = 2; a, b = b, a; b");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "trailing splat collects remaining elements" {
    var result = try evalCode("a, *b = 1, 2, 3, 4; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("a, *b = 1, 2, 3, 4; b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 4), result.data.array.elements.items[2].data.integer);
}

test "leading splat collects initial elements" {
    var result = try evalCode("*a, b, c = 1, 2, 3, 4; b");
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);

    result = try evalCode("*a, b, c = 1, 2, 3, 4; c");
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);

    result = try evalCode("*a, b, c = 1, 2, 3, 4; a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
}

test "middle splat collects middle elements" {
    var result = try evalCode("a, *b, c = 1, 2, 3, 4; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("a, *b, c = 1, 2, 3, 4; c");
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);

    result = try evalCode("a, *b, c = 1, 2, 3, 4; b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[1].data.integer);
}

test "splat with exact match returns empty array" {
    const result = try evalCode("a, *b, c = 1, 2; b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 0), result.data.array.elements.items.len);
}

test "splat only collects all elements" {
    const result = try evalCode("*a = 1, 2, 3; a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
}

test "simple nested destructuring" {
    var result = try evalCode("(a, b), c = [1, 2], 3; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("(a, b), c = [1, 2], 3; b");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("(a, b), c = [1, 2], 3; c");
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "multiple nested destructuring" {
    var result = try evalCode("(a, b), (c, d) = [1, 2], [3, 4]; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("(a, b), (c, d) = [1, 2], [3, 4]; d");
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}

test "deeply nested destructuring" {
    var result = try evalCode("((a, b), c), d = [[1, 2], 3], 4; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("((a, b), c), d = [[1, 2], 3], 4; b");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode("((a, b), c), d = [[1, 2], 3], 4; c");
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);

    result = try evalCode("((a, b), c), d = [[1, 2], 3], 4; d");
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}

test "nested destructuring with splat" {
    var result = try evalCode("(a, *b), c = [1, 2, 3], 4; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("(a, *b), c = [1, 2, 3], 4; b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[1].data.integer);

    result = try evalCode("(a, *b), c = [1, 2, 3], 4; c");
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}
