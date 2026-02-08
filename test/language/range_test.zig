const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Range literal creates Range" {
    const result = try evalCode("r = 1..3\nr.is_a?(Range)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Range literal exclude end" {
    const result = try evalCode("r = 1...3\nr.is_a?(Range)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Endless range is constructible" {
    const result = try evalCode("r = (1..)\nr.is_a?(Range)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Range to_a inclusive" {
    const result = try evalCode("(1..3).to_a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(3, result.data.array.elements.items.len);
    try std.testing.expectEqual(1, result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(2, result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(3, result.data.array.elements.items[2].data.integer);
}

test "Range to_a exclusive" {
    const result = try evalCode("(1...3).to_a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(2, result.data.array.elements.items.len);
    try std.testing.expectEqual(1, result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(2, result.data.array.elements.items[1].data.integer);
}

test "Range to_a endless raises" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\(1..).to_a
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.startsWith(u8, result.stderr, "Unhandled exception: RangeError: cannot convert endless range to an array\n"));
}

test "Range to_a beginless raises" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\(..3).to_a
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.startsWith(u8, result.stderr, "Unhandled exception: RangeError: cannot convert beginless range to an array\n"));
}

test "Range to_a type error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\(1.."3").to_a
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.startsWith(u8, result.stderr, "Unhandled exception: TypeError: wrong argument type"));
}

test "Range inspect" {
    const inclusive = try evalCode("(1..3).inspect");
    try std.testing.expect(inclusive.data == .string);
    try std.testing.expectEqualSlices(u8, "1..3", inclusive.data.string.str);

    const exclusive = try evalCode("(1...3).inspect");
    try std.testing.expect(exclusive.data == .string);
    try std.testing.expectEqualSlices(u8, "1...3", exclusive.data.string.str);

    const endless = try evalCode("(1..).inspect");
    try std.testing.expect(endless.data == .string);
    try std.testing.expectEqualSlices(u8, "1..", endless.data.string.str);

    const beginless = try evalCode("(..3).inspect");
    try std.testing.expect(beginless.data == .string);
    try std.testing.expectEqualSlices(u8, "..3", beginless.data.string.str);
}
