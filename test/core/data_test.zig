const std = @import("std");
const test_helper = @import("../test_helper.zig");

test "Data.define creates member readers and a bracket constructor" {
    const result = try test_helper.evalCode(
        \\klass = Data.define(:author, :year)
        \\book = klass["Tim", 2024]
        \\[book.author == "Tim", book.year == 2024, book.frozen?, klass.respond_to?(:[]), !Data.respond_to?(:[])]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Data subclasses inherit their members" {
    const result = try test_helper.evalCode(
        \\base = Data.define(:foo, :bar)
        \\child = Class.new(base)
        \\value = child.new(foo: 1, bar: 2)
        \\[value.foo == 1, value.bar == 2, value.members == [:foo, :bar], value.to_h == {foo: 1, bar: 2}]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Data converts positional constructor values to member keywords" {
    const result = try test_helper.evalCode(
        \\Base = Data.define(:foo)
        \\class Child < Base
        \\  def initialize(**)
        \\    super
        \\  end
        \\end
        \\[Base.new("bar").foo, Child.new("bar").foo, Child["bar"].foo, Child.new(foo: "bar").foo]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expectEqualStrings("bar", item.toStringObject().str);
}

test "Data member storage stays out of Ruby instance variables" {
    const result = try test_helper.evalCode(
        \\Base = Data.define(:foo)
        \\class WithIvar < Base
        \\  def initialize(**)
        \\    @bar = "hello"
        \\    super
        \\  end
        \\end
        \\value = WithIvar["bar"]
        \\[value.foo == "bar", value.instance_variables == [:@bar], Base.instance_variables.empty?]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Data member readers retain their source when aliased" {
    const result = try test_helper.evalCode(
        \\klass = Data.define(:foo)
        \\klass.class_eval { alias bar foo }
        \\klass.new(7).bar
    );
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Data copies preserve member values and frozen state" {
    const result = try test_helper.evalCode(
        \\value = Data.define(:x).new(3)
        \\copy = value.dup
        \\clone = value.clone(freeze: false)
        \\[copy.x == 3, clone.x == 3, copy.frozen?, clone.frozen?]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Data with applies keyword changes through the constructor" {
    const result = try test_helper.evalCode(
        \\klass = Data.define(:x, :y)
        \\origin = klass.new(1, 2)
        \\changed = origin.with(y: 3)
        \\error = begin
        \\  origin.with(z: 4)
        \\rescue => exception
        \\  exception
        \\end
        \\[origin.with.equal?(origin), changed.x == 1, changed.y == 3, changed.frozen?, origin.y == 2, error.is_a?(ArgumentError)]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}

test "Data with bypasses an overridden class new and calls initialize" {
    const result = try test_helper.evalCode(
        \\klass = Data.define(:x)
        \\instance = klass[1]
        \\def klass.new(**)
        \\  :overridden
        \\end
        \\klass.class_eval do
        \\  def initialize(x:)
        \\    super(x: x * 2)
        \\  end
        \\end
        \\updated = instance.with(x: 3)
        \\[updated.class == klass, updated.x == 6]
    );
    for (result.toArrayObject().elements.items) |item| try std.testing.expect(item.isTrue());
}
