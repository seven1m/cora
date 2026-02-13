const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Simple string interpolation" {
    const result = try evalCode("name = \"world\"\n\"Hello, #{name}!\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "Hello, world!", result.data.string.str);
}

test "String interpolation with integer" {
    const result = try evalCode("\"The number is #{42}\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "The number is 42", result.data.string.str);
}

test "String interpolation with array" {
    const result = try evalCode("arr = [1, 2, 3]\n\"array: #{arr}\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "array: [1, 2, 3]", result.data.string.str);
}

test "String interpolation with hash" {
    const result = try evalCode("h = {a: 1, b: 2}\n\"hash: #{h}\"");
    try std.testing.expect(result.data == .string);
}

test "Multiple interpolations in one string" {
    const result = try evalCode("x = 1\ny = 2\n\"#{x} and #{y}\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "1 and 2", result.data.string.str);
}

test "Interpolation with expressions" {
    const result = try evalCode("\"1 + 2 = #{1 + 2}\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "1 + 2 = 3", result.data.string.str);
}

test "Empty string interpolation" {
    const result = try evalCode("\"#{\"\"}\"");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "", result.data.string.str);
}

test "Alternative %Q syntax with interpolation" {
    const result = try evalCode("name = \"Ruby\"\n%Q{Hello, #{name}!}");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "Hello, Ruby!", result.data.string.str);
}

test "Interpolated string evaluates embedded expressions left-to-right" {
    const result = try evalCode(
        \\class InterpEvalOrder
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
        \\obj = InterpEvalOrder.new
        \\s = "#{obj.t(1)}#{obj.t(2)}#{obj.t(3)}"
        \\[obj.seen, s]
    );
    try std.testing.expect(result.data == .array);
    const seen = result.data.array.elements.items[0];
    const str = result.data.array.elements.items[1];
    try std.testing.expect(seen.data == .array);
    try std.testing.expect(str.data == .string);
    try std.testing.expectEqual(@as(i64, 1), seen.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), seen.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), seen.data.array.elements.items[2].data.integer);
    try std.testing.expectEqualSlices(u8, "123", str.data.string.str);
}
