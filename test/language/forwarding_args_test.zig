const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "forwarding arguments forwards positional and block args" {
    const result = try evalCode(
        \\def target(*args)
        \\  [args, block_given? ? yield : :no_block]
        \\end
        \\
        \\def wrapper(...)
        \\  target(...)
        \\end
        \\
        \\wrapper(1, 2, 3) { 4 }
    );

    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expect(items[0].isArray());
    try std.testing.expectEqual(@as(usize, 3), items[0].toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), items[0].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), items[0].toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), items[0].toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 4), items[1].toInteger());
}

test "forwarding arguments forwards keyword args after defaults" {
    const result = try evalCode(
        \\def target(a, b: 9, c: 10)
        \\  [a, b, c]
        \\end
        \\
        \\def wrapper(...)
        \\  target(...)
        \\end
        \\
        \\wrapper(1, b: 2)
    );

    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 10), items[2].toInteger());
}

test "forwarding arguments supports explicit receiver calls" {
    const result = try evalCode(
        \\class Sink
        \\  def collect(*args, x:, &block)
        \\    [args, x, block.call]
        \\  end
        \\end
        \\
        \\SINK = Sink.new
        \\def wrapper(...)
        \\  SINK.collect(...)
        \\end
        \\
        \\wrapper(1, 2, x: 3) { 4 }
    );

    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expect(items[0].isArray());
    try std.testing.expectEqual(@as(usize, 2), items[0].toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), items[0].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), items[0].toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 4), items[2].toInteger());
}

test "mixed forwarding excludes method parameters from the forwarded rest" {
    const result = try evalCode(
        \\def target(*args)
        \\  args
        \\end
        \\def wrapper(first, ...)
        \\  target(:prefix, ...)
        \\end
        \\wrapper(:first, :rest)
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualStrings("prefix", items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("rest", items[1].toSymbolObject().name);
}

test "forwarding arguments from a nested block uses the enclosing method arguments" {
    const result = try evalCode(
        \\def target(a, b, c, on_duplicate:)
        \\  [a, b, c, on_duplicate, yield]
        \\end
        \\def wrapper(value, ...)
        \\  1.times { return target(:relation, :connection, value, ...) }
        \\end
        \\wrapper([], on_duplicate: :raise) { :original_block }
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 5), values.len);
    try std.testing.expectEqualStrings("relation", values[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("connection", values[1].toSymbolObject().name);
    try std.testing.expect(values[2].isArray());
    try std.testing.expectEqualStrings("raise", values[3].toSymbolObject().name);
    try std.testing.expectEqualStrings("original_block", values[4].toSymbolObject().name);
}

test "pure forwarding from nested blocks preserves positional and keyword arguments" {
    const result = try evalCode(
        \\def target(*args, enabled:)
        \\  [args, enabled]
        \\end
        \\def wrapper(...)
        \\  1.times { return 1.times { return target(...) } }
        \\end
        \\wrapper(1, 2, enabled: true)
    );
    const values = result.toArrayObject().elements.items;
    const positional = values[0].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), positional.len);
    try std.testing.expectEqual(@as(i64, 1), positional[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), positional[1].toInteger());
    try std.testing.expect(values[1].isTrue());
}

test "Proc ruby2_keywords preserves keywords through rest argument splats" {
    const result = try evalCode(
        \\class KeywordTarget
        \\  def initialize(**options)
        \\    @options = options
        \\  end
        \\  attr_reader :options
        \\end
        \\forwarding = proc { |_, *args| KeywordTarget.new(*args) }
        \\returned = forwarding.ruby2_keywords
        \\[returned.equal?(forwarding), forwarding.call(:ignored, enabled: true).options]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    const entries = values[1].toHashObject().entries.items;
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("enabled", entries[0].key.toSymbolObject().name);
    try std.testing.expect(entries[0].value.isTrue());
}
