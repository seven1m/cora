const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "required array pattern returns the matched value" {
    const result = try evalCode(
        \\value = [1, 2, 3]
        \\matched = (value => [Integer, Integer, Integer])
        \\[matched.equal?(value), matched]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expectEqual(@as(usize, 3), values[1].toArrayObject().elements.items.len);
}

test "required array pattern raises on a length mismatch" {
    const result = try evalCode(
        \\begin
        \\  [1, 2, 3] => [Integer, Integer]
        \\rescue NoMatchingPatternError => error
        \\  [error.class, error.message]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("NoMatchingPatternError", values[0].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("length mismatch", values[1].toStringObject().str);
}

test "required array pattern checks each element with case equality" {
    const result = try evalCode(
        \\begin
        \\  [1, "two"] => [Integer, Integer]
        \\rescue NoMatchingPatternError => error
        \\  [error.class, error.message]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("NoMatchingPatternError", values[0].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("pattern does not match", values[1].toStringObject().str);
}

test "rightward array pattern captures rest and post elements" {
    const result = try evalCode(
        \\[0, 1, 2, 3] => [first, *middle, last]
        \\[first, middle, last]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), items[0].toInteger());
    const middle = items[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), middle[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), middle[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), items[2].toInteger());
}

test "rightward find pattern searches nested hash patterns and captures surrounding elements" {
    const result = try evalCode(
        \\[0, {name: "first"}, {name: "target"}, 3] => [*pre, {name: "target"}, *post]
        \\[pre, post]
    );
    const items = result.toArrayObject().elements.items;
    const pre = items[0].toArrayObject().elements.items;
    const post = items[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), pre.len);
    try std.testing.expectEqual(@as(i64, 0), pre[0].toInteger());
    try std.testing.expectEqual(@as(usize, 1), post.len);
    try std.testing.expectEqual(@as(i64, 3), post[0].toInteger());
}
