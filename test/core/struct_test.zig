const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Struct.new creates subclass and instances with accessors" {
    const result = try evalCode(
        \\Customer = Struct.new(:name, :zip)
        \\customer = Customer.new("Dave", 90210)
        \\[customer.name, customer.zip, Customer.members, customer.members]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("Dave", entries[0].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 90210), entries[1].toInteger());
    try std.testing.expectEqualStrings("name", entries[2].toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("zip", entries[2].toArrayObject().elements.items[1].toSymbolObject().name);
    try std.testing.expectEqualStrings("name", entries[3].toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("zip", entries[3].toArrayObject().elements.items[1].toSymbolObject().name);
}

test "Struct instances allow omitted members and fill them with nil" {
    const result = try evalCode(
        \\Point = Struct.new(:x, :y)
        \\point = Point.new
        \\[point.x.nil?, point.y.nil?, Point.new(1).to_a]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expect(entries[0].toBool());
    try std.testing.expect(entries[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), entries[2].toArrayObject().elements.items[0].toInteger());
    try std.testing.expect(entries[2].toArrayObject().elements.items[1].isNil());
}

test "Struct.new with name registers constant under Struct" {
    const result = try evalCode(
        \\Struct.new("Point", :x, :y)
        \\[Struct::Point.name, Struct::Point == Struct::Point, Struct::Point.new(1, 2).is_a?(Struct)]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("Struct::Point", entries[0].toStringObject().str);
    try std.testing.expect(entries[1].toBool());
    try std.testing.expect(entries[2].toBool());
}

test "Struct subclass supports index access and assignment" {
    const result = try evalCode(
        \\Point = Struct.new(:x, :y)
        \\point = Point.new(1, 2)
        \\point[:x] = 10
        \\point[1] = 20
        \\[point[0], point[:y], point.to_a, point.values]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 10), entries[0].toInteger());
    try std.testing.expectEqual(@as(i64, 20), entries[1].toInteger());
    try std.testing.expectEqual(@as(i64, 10), entries[2].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 20), entries[2].toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 10), entries[3].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 20), entries[3].toArrayObject().elements.items[1].toInteger());
}

test "Struct instances enumerate and compare by member values" {
    const result = try evalCode(
        \\Point = Struct.new(:x, :y)
        \\left = Point.new(3, 4)
        \\right = Point.new(3, 4)
        \\[
        \\  left.map { |value| value * 2 },
        \\  left.each_pair.map { |name, value| [name, value] },
        \\  left == right,
        \\  left.eql?(right),
        \\  left.inspect
        \\]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 6), entries[0].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 8), entries[0].toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqualStrings("x", entries[1].toArrayObject().elements.items[0].toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 3), entries[1].toArrayObject().elements.items[0].toArrayObject().elements.items[1].toInteger());
    try std.testing.expect(entries[2].toBool());
    try std.testing.expect(entries[3].toBool());
    try std.testing.expect(std.mem.indexOf(u8, entries[4].toStringObject().str, "#<struct Point x=3, y=4>") != null);
}

test "Struct keyword_init forwards through bare super" {
    const result = try evalCode(
        \\Node = Struct.new(:pairs, :tag, :anchor, keyword_init: true) do
        \\  def initialize(pairs: [], tag: nil, anchor: nil)
        \\    super
        \\  end
        \\end
        \\node = Node.new(pairs: [[1, 2]])
        \\[node.pairs, node.tag.nil?, node.anchor.nil?]
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    const pairs = entries[0].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), pairs[0].toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), pairs[0].toArrayObject().elements.items[1].toInteger());
    try std.testing.expect(entries[1].toBool());
    try std.testing.expect(entries[2].toBool());
}
