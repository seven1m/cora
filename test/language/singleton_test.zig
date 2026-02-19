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

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
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

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
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

test "Object#new does not panic with singleton coercion in Class.new block" {
    const result = try evalCode(
        \\name = Object.new
        \\def name.to_str
        \\  "value"
        \\end
        \\
        \\C = Class.new do
        \\  attr_reader name
        \\  def initialize
        \\    @value = 7
        \\  end
        \\end
        \\C.new.value
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "Object#define_singleton_method defines and calls singleton method" {
    const result = try evalCode(
        \\obj = Object.new
        \\ret = obj.define_singleton_method(:hello) { 'hi' }
        \\[ret, obj.hello]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqualSlices(u8, "hello", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "hi", result.data.array.elements.items[1].data.string.str);
}

test "Object#define_singleton_method supports super dispatch" {
    const result = try evalCode(
        \\obj = "abc"
        \\obj.define_singleton_method(:size) { super() + 1 }
        \\obj.size
    );
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}

test "singleton_class.remove_method removes singleton override and falls back to class method" {
    const result = try evalCode(
        \\class Greeter
        \\  def greet
        \\    'class'
        \\  end
        \\end
        \\g = Greeter.new
        \\g.define_singleton_method(:greet) { 'singleton' }
        \\before = g.greet
        \\g.singleton_class.remove_method(:greet)
        \\[before, g.greet]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqualSlices(u8, "singleton", result.data.array.elements.items[0].data.string.str);
    try std.testing.expectEqualSlices(u8, "class", result.data.array.elements.items[1].data.string.str);
}

test "singleton_class.remove_method raises NameError for inherited-only method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class Greeter
        \\  def greet
        \\    'class'
        \\  end
        \\end
        \\g = Greeter.new
        \\g.singleton_class.remove_method(:greet)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "greet") != null);
}

test "class << self defines class methods" {
    const result = try evalCode(
        \\class ClassSingletonSpec
        \\  class << self
        \\    def value
        \\      42
        \\    end
        \\  end
        \\end
        \\ClassSingletonSpec.value
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "class << object returns last expression and defines singleton method" {
    const result = try evalCode(
        \\obj = Object.new
        \\ret = class << obj
        \\  def greet
        \\    "hi"
        \\  end
        \\  123
        \\end
        \\[ret, obj.greet]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 123), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqualSlices(u8, "hi", result.data.array.elements.items[1].data.string.str);
}

test "class << literals true false nil uses singleton class self" {
    const result = try evalCode(
        \\[
        \\  (class << true; self; end) == TrueClass,
        \\  (class << false; self; end) == FalseClass,
        \\  (class << nil; self; end) == NilClass
        \\]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(true, result.data.array.elements.items[0].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[1].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[2].data.boolean);
}

test "class << object constant namespace stays on singleton class" {
    const result = try evalCode(
        \\obj = Object.new
        \\class << obj
        \\  CONST = 7
        \\end
        \\[class << obj; CONST; end, begin obj.class::CONST; false; rescue NameError; true; end]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 7), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(true, result.data.array.elements.items[1].data.boolean);
}

test "class << non-singleton-capable literals raises TypeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    var bad = evalCodeWithOutput("class << 1; self; end", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);

    bad = evalCodeWithOutput("class << :symbol; self; end", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}
