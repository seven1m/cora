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
