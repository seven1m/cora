const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Basic super with explicit arguments" {
    const result = try evalCode(
        \\class A
        \\  def foo(x)
        \\    x + 10
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo(x)
        \\    super(x * 2)
        \\  end
        \\end
        \\
        \\B.new.foo(5)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(20, result.toInteger()); // (5 * 2) + 10 = 20
}

test "Bare super forwards all arguments" {
    const result = try evalCode(
        \\class A
        \\  def foo(x, y)
        \\    x + y
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo(x, y)
        \\    super
        \\  end
        \\end
        \\
        \\B.new.foo(10, 20)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(30, result.toInteger());
}

test "bare super in a block forwards enclosing method arguments and block" {
    const result = try evalCode(
        \\class A
        \\  def foo(x, y = 2, *rest, flag:, **kwargs)
        \\    [x, y, rest, flag, kwargs, block_given? ? yield : :no_block]
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo(x, y = 2, *rest, flag:, **kwargs)
        \\    1.times do
        \\      1.times { return super }
        \\    end
        \\  end
        \\end
        \\
        \\B.new.foo(1, 3, 4, flag: true, extra: 5) { :original_block }
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 6), values.len);
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 4), values[2].toArrayObject().elements.items[0].toInteger());
    try std.testing.expect(values[3].isTrue());
    try std.testing.expectEqual(@as(i64, 5), values[4].toHashObject().entries.items[0].value.toInteger());
    try std.testing.expectEqualSlices(u8, "original_block", values[5].toSymbolObject().name);
}

test "super() with no arguments" {
    const result = try evalCode(
        \\class A
        \\  def foo
        \\    42
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo
        \\    super()
        \\  end
        \\end
        \\
        \\B.new.foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(42, result.toInteger());
}

test "Multi-level inheritance super" {
    // super in B#foo should call A#foo, not itself even when called on C
    const result = try evalCode(
        \\class A
        \\  def foo
        \\    "A"
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo
        \\    super
        \\  end
        \\end
        \\
        \\class C < B
        \\end
        \\
        \\C.new.foo
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "A", result.toStringObject().str);
}

test "super with modification" {
    const result = try evalCode(
        \\class A
        \\  def greet(name)
        \\    "Hello, " + name
        \\  end
        \\end
        \\
        \\class B < A
        \\  def greet(name)
        \\    super(name) + "!"
        \\  end
        \\end
        \\
        \\B.new.greet("World")
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "Hello, World!", result.toStringObject().str);
}

test "super with different arguments than received" {
    const result = try evalCode(
        \\class A
        \\  def add(a, b)
        \\    a + b
        \\  end
        \\end
        \\
        \\class B < A
        \\  def add(a, b)
        \\    super(a * 10, b * 10)
        \\  end
        \\end
        \\
        \\B.new.add(1, 2)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(30, result.toInteger()); // 10 + 20
}

test "super in an aliased prepended method uses the original method name" {
    const result = try evalCode(
        \\module Wrapper
        \\  def original
        \\    "wrapper:" + super
        \\  end
        \\  alias wrapped original
        \\end
        \\class Target
        \\  def original
        \\    "target"
        \\  end
        \\  prepend Wrapper
        \\end
        \\singleton = Object.new
        \\def singleton.original
        \\  "singleton"
        \\end
        \\singleton.singleton_class.prepend(Wrapper)
        \\[Target.new.wrapped, Target.new.wrapped, singleton.wrapped, singleton.wrapped]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("wrapper:target", items[0].toStringObject().str);
    try std.testing.expectEqualStrings("wrapper:target", items[1].toStringObject().str);
    try std.testing.expectEqualStrings("wrapper:singleton", items[2].toStringObject().str);
    try std.testing.expectEqualStrings("wrapper:singleton", items[3].toStringObject().str);
}

test "NoMethodError when no superclass method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class A
        \\end
        \\
        \\class B < A
        \\  def foo
        \\    super
        \\  end
        \\end
        \\
        \\B.new.foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
}

test "super in deeply nested inheritance" {
    const result = try evalCode(
        \\class A
        \\  def value
        \\    1
        \\  end
        \\end
        \\
        \\class B < A
        \\  def value
        \\    super + 10
        \\  end
        \\end
        \\
        \\class C < B
        \\  def value
        \\    super + 100
        \\  end
        \\end
        \\
        \\C.new.value
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(111, result.toInteger()); // 1 + 10 + 100
}

test "super with optional parameters" {
    const result = try evalCode(
        \\class A
        \\  def foo(x, y = 5)
        \\    x + y
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo(x, y = 5)
        \\    super
        \\  end
        \\end
        \\
        \\B.new.foo(10)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(15, result.toInteger());
}

test "bare super forwards correctly with side-effect locals in defaults" {
    const result = try evalCode(
        \\class A
        \\  def foo(a, b)
        \\    a + b
        \\  end
        \\end
        \\
        \\class B < A
        \\  def foo(a=(x=10), b=(y=20))
        \\    super
        \\  end
        \\end
        \\
        \\B.new.foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(30, result.toInteger());
}

test "super reaches included module after defining class" {
    const result = try evalCode(
        \\module HeaderMethods
        \\  def []=(key, value)
        \\    @stored = value
        \\  end
        \\end
        \\
        \\class Request
        \\  include HeaderMethods
        \\
        \\  def []=(key, value)
        \\    super
        \\  end
        \\
        \\  def stored
        \\    @stored
        \\  end
        \\end
        \\
        \\class Head < Request
        \\end
        \\
        \\req = Head.new
        \\req[:accept] = 41
        \\req.stored + 1
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(42, result.toInteger());
}
