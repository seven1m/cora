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
