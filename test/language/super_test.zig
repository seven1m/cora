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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(20, result.data.integer); // (5 * 2) + 10 = 20
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(30, result.data.integer);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(42, result.data.integer);
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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "A", result.data.string.str);
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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "Hello, World!", result.data.string.str);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(30, result.data.integer); // 10 + 20
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(111, result.data.integer); // 1 + 10 + 100
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(15, result.data.integer);
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
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(30, result.data.integer);
}
