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

test "global variable targets" {
    var result = try evalCode("$a, $b = 10, 20; $a");
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);

    result = try evalCode("$a, $b = 10, 20; $b");
    try std.testing.expectEqual(@as(i64, 20), result.data.integer);
}

test "instance variable targets" {
    const code =
        \\class Foo
        \\  def test
        \\    @a, @b = 1, 2
        \\    @a
        \\  end
        \\end
        \\Foo.new.test
    ;
    const result = try evalCode(code);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "constant targets" {
    var result = try evalCode("A, B = 100, 200; A");
    try std.testing.expectEqual(@as(i64, 100), result.data.integer);

    result = try evalCode("A, B = 100, 200; B");
    try std.testing.expectEqual(@as(i64, 200), result.data.integer);
}

test "indexed assignment targets" {
    var result = try evalCode("arr = [0, 0, 0]; arr[0], arr[1] = 10, 20; arr[0]");
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);

    result = try evalCode("arr = [0, 0, 0]; arr[0], arr[1] = 10, 20; arr[1]");
    try std.testing.expectEqual(@as(i64, 20), result.data.integer);
}

test "attribute assignment targets" {
    const code =
        \\class Point
        \\  def x=(val); @x = val; end
        \\  def y=(val); @y = val; end
        \\  def x; @x; end
        \\  def y; @y; end
        \\end
        \\p = Point.new
        \\p.x, p.y = 5, 10
        \\p.x
    ;
    const result = try evalCode(code);
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "mixed complex targets" {
    const code =
        \\arr = [0, 0]
        \\$g, arr[0], @i = 1, 2, 3
        \\$g
    ;
    var result = try evalCode(code);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("arr = [0, 0]; $g, arr[0], @i = 1, 2, 3; arr[0]");
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "splat with complex targets" {
    var result = try evalCode("$a, *$b = 1, 2, 3; $a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("$a, *$b = 1, 2, 3; $b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
}

test "single non-array RHS assigns to first target" {
    var result = try evalCode("a, b, c = 1; a");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("a, b, c = 1; b");
    try std.testing.expect(result.data == .nil);

    result = try evalCode("a, b, c = 1; c");
    try std.testing.expect(result.data == .nil);
}

test "single array variable RHS is destructured" {
    var result = try evalCode("x = [10, 20]; a, b = x; a");
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);

    result = try evalCode("x = [10, 20]; a, b = x; b");
    try std.testing.expectEqual(@as(i64, 20), result.data.integer);
}

test "to_ary is called on non-array objects" {
    const code =
        \\class Converter
        \\  def to_ary
        \\    [1, 2, 3]
        \\  end
        \\end
        \\a, b, c = Converter.new
        \\a
    ;
    var result = try evalCode(code);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    const code2 =
        \\class Converter
        \\  def to_ary
        \\    [1, 2, 3]
        \\  end
        \\end
        \\a, b, c = Converter.new
        \\c
    ;
    result = try evalCode(code2);
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "to_ary returning nil treats as single value" {
    const code =
        \\class NilConverter
        \\  def to_ary
        \\    nil
        \\  end
        \\end
        \\a, b = NilConverter.new
        \\b
    ;
    const result = try evalCode(code);
    try std.testing.expect(result.data == .nil);
}

test "splat with single non-array value" {
    var result = try evalCode("a, *b = 5; a");
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);

    result = try evalCode("a, *b = 5; b");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 0), result.data.array.elements.items.len);
}

test "return value is original RHS" {
    var result = try evalCode("x = (a, b = 5); x");
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);

    result = try evalCode("x = (a, b = [1, 2]); x");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
}
