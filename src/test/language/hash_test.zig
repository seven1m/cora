const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Empty hash literal" {
    const result = try evalCode("{}");
    try std.testing.expect(result.data == .hash);
    try std.testing.expectEqual(0, result.data.hash.entries.items.len);
}

test "Hash with symbol keys" {
    const result = try evalCode("{x: 1, y: 2}");
    try std.testing.expect(result.data == .hash);
    try std.testing.expectEqual(2, result.data.hash.entries.items.len);
}

test "Hash with string keys" {
    const result = try evalCode(
        \\{"name" => "Alice", "age" => 30}
    );
    try std.testing.expectEqual(2, result.data.hash.entries.items.len);
}

test "Mixed key types" {
    const result = try evalCode("{a: 1, \"b\" => 2, 3 => \"three\"}");
    try std.testing.expectEqual(3, result.data.hash.entries.items.len);
}

test "Hash element access" {
    const result = try evalCode("h = {x: 10}\nh[:x]");
    try std.testing.expectEqual(10, result.data.integer);
}

test "Hash element assignment" {
    const result = try evalCode("h = {}\nh[:key] = 42\nh[:key]");
    try std.testing.expectEqual(42, result.data.integer);
}

test "Hash preserves insertion order" {
    const result = try evalCode("h = {c: 3, a: 1, b: 2}\nh.keys");
    try std.testing.expectEqual(3, result.data.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "c", result.data.array.elements.items[0].data.symbol.name);
}

test "Duplicate keys - last wins" {
    const result = try evalCode("h = {x: 1, x: 2}\nh[:x]");
    try std.testing.expectEqual(2, result.data.integer);
}

test "Symbol vs string keys are different" {
    const result = try evalCode("h = {foo: 1, \"foo\" => 2}\nh.size");
    try std.testing.expectEqual(2, result.data.integer);
}

test "Hash keys method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.keys");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(2, result.data.array.elements.items.len);
}

test "Hash values method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.values");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(2, result.data.array.elements.items.len);
}

test "Hash size method" {
    const result = try evalCode("h = {a: 1, b: 2, c: 3}\nh.size");
    try std.testing.expectEqual(3, result.data.integer);
}

test "Hash length method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.length");
    try std.testing.expectEqual(2, result.data.integer);
}

test "Hash each iteration" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\{a: 1, b: 2, c: 3}.each { |k, v| p k; p v }
        , &stdout_buf, &stderr_buf
    );

    try std.testing.expectEqualSlices(u8, ":a\n1\n:b\n2\n:c\n3\n", result.stdout);
}

test "Hash to_s method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.to_s");
    try std.testing.expect(result.data == .string);
    // Symbol keys use shorthand syntax
    try std.testing.expect(std.mem.indexOf(u8, result.data.string.str, "a: 1") != null);
}

test "Hash inspect method with symbol keys" {
    const result = try evalCode("h = {x: 10}\nh.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "{x: 10}", result.data.string.str);
}

test "Hash inspect method with string keys" {
    const result = try evalCode("h = {'name' => 'Alice'}\nh.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "{\"name\" => \"Alice\"}", result.data.string.str);
}

test "Hash inspect method with mixed keys" {
    const result = try evalCode("{foo: 'bar', 'baz' => 'qux'}.inspect");
    try std.testing.expect(result.data == .string);
    // Mixed keys show both formats
    const str = result.data.string.str;
    try std.testing.expect(std.mem.indexOf(u8, str, "foo: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, " => ") != null);
}

test "Hash inspect method with integer keys" {
    const result = try evalCode("{1 => 'one', 2 => 'two'}.inspect");
    try std.testing.expect(result.data == .string);
    // Integer keys use hash rocket
    try std.testing.expect(std.mem.indexOf(u8, result.data.string.str, "1 => ") != null);
}

test "Hash with nil key" {
    const result = try evalCode("h = {nil => 1}\nh[nil]");
    try std.testing.expectEqual(1, result.data.integer);
}

test "Hash with integer key" {
    const result = try evalCode("h = {1 => 'one'}\nh[1]");
    try std.testing.expectEqualSlices(u8, "one", result.data.string.str);
}

test "Hash with boolean key" {
    const result = try evalCode("h = {true => 't', false => 'f'}\nh[true]");
    try std.testing.expectEqualSlices(u8, "t", result.data.string.str);
}
