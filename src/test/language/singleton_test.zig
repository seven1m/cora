const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Class method with self" {
    const result = try evalCode(
        \\class Foo
        \\  def self.bar
        \\    'class method'
        \\  end
        \\end
        \\Foo.bar
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "class method", result.data.string.str);
}

test "Singleton method on instance" {
    const result = try evalCode(
        \\foo = Object.new
        \\def foo.special
        \\  'special'
        \\end
        \\foo.special
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "special", result.data.string.str);
}

test "Class method inheritance" {
    const result = try evalCode(
        \\class Parent
        \\  def self.foo
        \\    'parent'
        \\  end
        \\end
        \\class Child < Parent
        \\end
        \\Child.foo
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "parent", result.data.string.str);
}

test "Instance vs class methods" {
    const result = try evalCode(
        \\class Foo
        \\  def bar
        \\    'instance'
        \\  end
        \\  def self.bar
        \\    'class'
        \\  end
        \\end
        \\Foo.bar
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "class", result.data.string.str);

    const result2 = try evalCode(
        \\class Foo
        \\  def bar
        \\    'instance'
        \\  end
        \\  def self.bar
        \\    'class'
        \\  end
        \\end
        \\Foo.new.bar
    );
    try std.testing.expect(result2.data == .string);
    try std.testing.expectEqualSlices(u8, "instance", result2.data.string.str);
}

test "Singleton method on module" {
    const result = try evalCode(
        \\module MyModule
        \\  def self.foo
        \\    'module method'
        \\  end
        \\end
        \\MyModule.foo
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "module method", result.data.string.str);
}

test "Calling undefined class method raises NoMethodError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\end
        \\Foo.undefined_method
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "undefined_method") != null);
}

test "Calling undefined singleton method on instance raises NoMethodError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\foo = Object.new
        \\foo.undefined_singleton_method
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
}

test "Class method overriding" {
    const result = try evalCode(
        \\class Parent
        \\  def self.foo
        \\    'parent'
        \\  end
        \\end
        \\class Child < Parent
        \\  def self.foo
        \\    'child'
        \\  end
        \\end
        \\Child.foo
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "child", result.data.string.str);

    const result2 = try evalCode(
        \\class Parent
        \\  def self.foo
        \\    'parent'
        \\  end
        \\end
        \\class Child < Parent
        \\  def self.foo
        \\    'child'
        \\  end
        \\end
        \\Parent.foo
    );
    try std.testing.expect(result2.data == .string);
    try std.testing.expectEqualSlices(u8, "parent", result2.data.string.str);
}
