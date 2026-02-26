const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Empty hash literal" {
    const result = try evalCode("{}");
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(0, result.toHashObject().entries.items.len);
}

test "Hash with symbol keys" {
    const result = try evalCode("{x: 1, y: 2}");
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);
}

test "Hash with string keys" {
    const result = try evalCode(
        \\{"name" => "Alice", "age" => 30}
    );
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);
}

test "Mixed key types" {
    const result = try evalCode("{a: 1, \"b\" => 2, 3 => \"three\"}");
    try std.testing.expectEqual(3, result.toHashObject().entries.items.len);
}

test "Hash element access" {
    const result = try evalCode("h = {x: 10}\nh[:x]");
    try std.testing.expectEqual(10, result.toInteger());
}

test "Hash element assignment" {
    const result = try evalCode("h = {}\nh[:key] = 42\nh[:key]");
    try std.testing.expectEqual(42, result.toInteger());
}

test "Hash preserves insertion order" {
    const result = try evalCode("h = {c: 3, a: 1, b: 2}\nh.keys");
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "c", result.toArrayObject().elements.items[0].toSymbolObject().name);
}

test "Duplicate keys - last wins" {
    const result = try evalCode("h = {x: 1, x: 2}\nh[:x]");
    try std.testing.expectEqual(2, result.toInteger());
}

test "Symbol vs string keys are different" {
    const result = try evalCode("h = {foo: 1, \"foo\" => 2}\nh.size");
    try std.testing.expectEqual(2, result.toInteger());
}

test "Hash keys method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.keys");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items.len);
}

test "Hash values method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.values");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items.len);
}

test "Hash size method" {
    const result = try evalCode("h = {a: 1, b: 2, c: 3}\nh.size");
    try std.testing.expectEqual(3, result.toInteger());
}

test "Hash length method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.length");
    try std.testing.expectEqual(2, result.toInteger());
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

test "Hash#each propagates break value" {
    var result = try evalCode("h = {a: 1, b: 2}; h.each { |k, v| break :done if k == :b }");
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "done", result.toSymbolObject().name);

    result = try evalCode("h = {a: 1, b: 2}; h.each { break }");
    try std.testing.expect(result.isNil());
}

test "Hash to_s method" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.to_s");
    try std.testing.expect(result.isString());
    // Symbol keys use shorthand syntax
    try std.testing.expect(std.mem.indexOf(u8, result.toStringObject().str, "a: 1") != null);
}

test "Hash inspect method with symbol keys" {
    const result = try evalCode("h = {x: 10}\nh.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "{x: 10}", result.toStringObject().str);
}

test "Hash inspect method with string keys" {
    const result = try evalCode("h = {'name' => 'Alice'}\nh.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "{\"name\" => \"Alice\"}", result.toStringObject().str);
}

test "Hash inspect method with mixed keys" {
    const result = try evalCode("{foo: 'bar', 'baz' => 'qux'}.inspect");
    try std.testing.expect(result.isString());
    // Mixed keys show both formats
    const str = result.toStringObject().str;
    try std.testing.expect(std.mem.indexOf(u8, str, "foo: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, " => ") != null);
}

test "Hash inspect method with integer keys" {
    const result = try evalCode("{1 => 'one', 2 => 'two'}.inspect");
    try std.testing.expect(result.isString());
    // Integer keys use hash rocket
    try std.testing.expect(std.mem.indexOf(u8, result.toStringObject().str, "1 => ") != null);
}

test "Hash with nil key" {
    const result = try evalCode("h = {nil => 1}\nh[nil]");
    try std.testing.expectEqual(1, result.toInteger());
}

test "Hash with integer key" {
    const result = try evalCode("h = {1 => 'one'}\nh[1]");
    try std.testing.expectEqualSlices(u8, "one", result.toStringObject().str);
}

test "Hash with boolean key" {
    const result = try evalCode("h = {true => 't', false => 'f'}\nh[true]");
    try std.testing.expectEqualSlices(u8, "t", result.toStringObject().str);
}

test "Hash fetch with existing key" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.fetch(:a)");
    try std.testing.expectEqual(1, result.toInteger());
}

test "Hash fetch with default value" {
    const result = try evalCode("h = {a: 1}\nh.fetch(:b, 99)");
    try std.testing.expectEqual(99, result.toInteger());
}

test "Hash fetch with block" {
    const result = try evalCode("h = {a: 1}\nh.fetch(:b) { |k| k.to_s }");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "b", result.toStringObject().str);
}

test "Hash fetch raises error when key not found" {
    const result = evalCode("h = {a: 1}\nh.fetch(:b)");
    try std.testing.expectError(error.UnhandledException, result);
}

test "Hash fetch raises error with both default and block" {
    const result = evalCode("h = {a: 1}\nh.fetch(:b, 99) { 42 }");
    try std.testing.expectError(error.UnhandledException, result);
}

test "Hash dig with single key" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.dig(:a)");
    try std.testing.expectEqual(1, result.toInteger());
}

test "Hash dig with nested hashes" {
    const result = try evalCode("h = {a: {b: {c: 42}}}\nh.dig(:a, :b, :c)");
    try std.testing.expectEqual(42, result.toInteger());
}

test "Hash dig returns nil for missing key" {
    const result = try evalCode("h = {a: {b: 2}}\nh.dig(:a, :x, :y)");
    try std.testing.expect(result.isNil());
}

test "Hash dig returns nil when intermediate value is nil" {
    const result = try evalCode("h = {a: nil}\nh.dig(:a, :b)");
    try std.testing.expect(result.isNil());
}

test "Hash dig with arrays" {
    const result = try evalCode("h = {a: [1, 2, 3]}\nh.dig(:a, 1)");
    try std.testing.expectEqual(2, result.toInteger());
}

test "Hash select with block" {
    const result = try evalCode("h = {a: 1, b: 2, c: 3, d: 4}\nh.select { |k, v| v > 2 }");
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);

    // Check that it contains the correct keys by checking symbol names
    var found_c = false;
    var found_d = false;
    for (result.toHashObject().entries.items) |entry| {
        if (entry.key.isSymbol()) {
            const sym_name = entry.key.toSymbolObject().name;
            if (std.mem.eql(u8, sym_name, "c")) found_c = true;
            if (std.mem.eql(u8, sym_name, "d")) found_d = true;
        }
    }
    try std.testing.expect(found_c);
    try std.testing.expect(found_d);
}

test "Hash select preserves insertion order" {
    const result = try evalCode("h = {d: 4, a: 1, c: 3, b: 2}\nh.select { |k, v| v == 1 || v == 3 }");
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);

    // First entry should be a: 1 (since d comes first but d: 4 doesn't match)
    const first_key = result.toHashObject().entries.items[0].key;
    try std.testing.expectEqualSlices(u8, "a", first_key.toSymbolObject().name);
}

test "Hash select returns empty hash when nothing matches" {
    const result = try evalCode("h = {a: 1, b: 2}\nh.select { |k, v| v > 10 }");
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(0, result.toHashObject().entries.items.len);
}

test "Hash select without block returns Enumerator" {
    const result = try evalCode("h = {a: 1}\nh.select");
    try std.testing.expect(result.isEnumerator());
}

test "Hash literal evaluates pairs left-to-right" {
    const result = try evalCode(
        \\class HashEvalOrder
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
        \\obj = HashEvalOrder.new
        \\h = { obj.t(1) => obj.t(2), obj.t(3) => obj.t(4) }
        \\[obj.seen, h]
    );
    try std.testing.expect(result.isArray());
    const seen = result.toArrayObject().elements.items[0];
    try std.testing.expect(seen.isArray());
    try std.testing.expectEqual(@as(i64, 1), seen.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), seen.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), seen.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 4), seen.toArrayObject().elements.items[3].toInteger());
}
