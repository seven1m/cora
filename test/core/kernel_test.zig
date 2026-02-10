const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "p with no arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .nil);
    try std.testing.expectEqualStrings("\n", result.stdout);
}

test "p with single integer" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);
    try std.testing.expectEqualStrings("42\n", result.stdout);
}

test "p with single string" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p \"hello\"", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.value.data.string.str);
    try std.testing.expectEqualStrings("\"hello\"\n", result.stdout);
}

test "p with multiple integers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 1, 2, 3", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "p with mixed types" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42, \"hello\", :foo", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
    try std.testing.expectEqualStrings("42\n\"hello\"\n:foo\n", result.stdout);
}

test "puts" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    var result = evalCodeWithOutput("puts [1, 2, 3], [4, 5, 6]", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n3\n4\n5\n6\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);

    result = evalCodeWithOutput("puts", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Kernel#nil? returns false for non-nil" {
    const result = try evalCode("1.nil?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Kernel#freeze returns receiver and marks String frozen" {
    const result = try evalCode("s = \"hello\"; s.freeze.object_id == s.object_id && s.frozen?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Kernel#freeze marks Hash frozen and prevents mutation" {
    const frozen_result = try evalCode("h = {}; h.freeze; h.frozen?");
    try std.testing.expect(frozen_result.data == .boolean);
    try std.testing.expectEqual(true, frozen_result.data.boolean);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const mutation = evalCodeWithOutput("h = {}; h.freeze; h[:x] = 1", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, mutation.err.?);
}

test "Kernel#freeze on Integer is a no-op and remains frozen" {
    const result = try evalCode("i = 42; i.freeze.object_id == i.object_id && i.frozen?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}
