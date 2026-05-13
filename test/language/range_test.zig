const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Range literal creates Range" {
    const result = try evalCode("r = 1..3\nr.is_a?(Range)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Range literal exclude end" {
    const result = try evalCode("r = 1...3\nr.is_a?(Range)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Endless range is constructible" {
    const result = try evalCode("r = (1..)\nr.is_a?(Range)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Range to_a inclusive" {
    const result = try evalCode("(1..3).to_a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(1, result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items[2].toInteger());
}

test "Range to_a exclusive" {
    const result = try evalCode("(1...3).to_a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(1, result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items[1].toInteger());
}

test "Range to_a string inclusive" {
    const result = try evalCode("(\"A\"..\"C\").to_a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "A", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "B", result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "C", result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Range to_a string exclusive" {
    const result = try evalCode("(\"A\"...\"C\").to_a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "A", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "B", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Range each string" {
    const result = try evalCode("out = []; (\"A\"..\"C\").each { |s| out << s }; out");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "A", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "B", result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "C", result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Range to_a endless raises" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\(1..).to_a
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cannot convert endless range to an array (RangeError)") != null);
}

test "Range to_a beginless raises" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\(..3).to_a
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cannot convert beginless range to an array (RangeError)") != null);
}

test "Range inspect" {
    const inclusive = try evalCode("(1..3).inspect");
    try std.testing.expect(inclusive.isString());
    try std.testing.expectEqualSlices(u8, "1..3", inclusive.toStringObject().str);

    const exclusive = try evalCode("(1...3).inspect");
    try std.testing.expect(exclusive.isString());
    try std.testing.expectEqualSlices(u8, "1...3", exclusive.toStringObject().str);

    const endless = try evalCode("(1..).inspect");
    try std.testing.expect(endless.isString());
    try std.testing.expectEqualSlices(u8, "1..", endless.toStringObject().str);

    const beginless = try evalCode("(..3).inspect");
    try std.testing.expect(beginless.isString());
    try std.testing.expectEqualSlices(u8, "..3", beginless.toStringObject().str);
}
