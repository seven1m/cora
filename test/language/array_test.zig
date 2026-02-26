const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Array literal" {
    const result = try evalCode("[1, 2, 3]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
}

test "Empty array literal" {
    const result = try evalCode("[]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(0, result.toArrayObject().elements.items.len);
}

test "Array push operator" {
    const result = try evalCode("arr = [1, 2]\narr << 3\narr");
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(3, result.toArrayObject().elements.items[2].toInteger());
}

test "Array each iteration" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\[1, 2, 3].each { |n| p n }
        , &stdout_buf, &stderr_buf
    );

    try std.testing.expectEqualSlices(u8, "1\n2\n3\n", result.stdout);
}

test "Array each returns receiver" {
    const result = try evalCode("arr = [1, 2, 3]\nresult = arr.each { |n| n }\nresult");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
}

test "Array each with strings" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\["hello", "world"].each { |s| p s }
        , &stdout_buf, &stderr_buf
    );

    try std.testing.expectEqualSlices(u8, "\"hello\"\n\"world\"\n", result.stdout);
}

test "Array to_s method" {
    const result = try evalCode("[1, 2, 3].to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array inspect method" {
    const result = try evalCode("[1, 2, 3].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array literal evaluates elements left-to-right" {
    const result = try evalCode(
        \\class ArrayEvalOrder
        \\  def initialize
        \\    @seen = []
        \\  end
        \\  def t(n)
        \\    @seen << n
        \\    n
        \\  end
        \\  def seen
        \\    @seen
        \\  end
        \\end
        \\obj = ArrayEvalOrder.new
        \\arr = [obj.t(1), obj.t(2), obj.t(3)]
        \\[obj.seen, arr]
    );
    try std.testing.expect(result.isArray());
    const seen = result.toArrayObject().elements.items[0];
    const arr = result.toArrayObject().elements.items[1];
    try std.testing.expect(seen.isArray());
    try std.testing.expect(arr.isArray());
    try std.testing.expectEqual(@as(i64, 1), seen.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), seen.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), seen.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 1), arr.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), arr.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), arr.toArrayObject().elements.items[2].toInteger());
}
