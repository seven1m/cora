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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "class method", result.toStringObject().str);
}

test "Singleton method on instance" {
    const result = try evalCode(
        \\foo = Object.new
        \\def foo.special
        \\  'special'
        \\end
        \\foo.special
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "special", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "parent", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "class", result.toStringObject().str);

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
    try std.testing.expect(result2.isString());
    try std.testing.expectEqualSlices(u8, "instance", result2.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "module method", result.toStringObject().str);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "undefined method 'undefined_method' for class Foo") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "undefined method 'undefined_singleton_method' for an instance of Object") != null);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "child", result.toStringObject().str);

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
    try std.testing.expect(result2.isString());
    try std.testing.expectEqualSlices(u8, "parent", result2.toStringObject().str);
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
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Object#define_singleton_method defines and calls singleton method" {
    const result = try evalCode(
        \\obj = Object.new
        \\ret = obj.define_singleton_method(:hello) { 'hi' }
        \\[ret, obj.hello]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "hello", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualSlices(u8, "hi", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "Object#define_singleton_method supports super dispatch" {
    const result = try evalCode(
        \\obj = "abc"
        \\obj.define_singleton_method(:size) { super() + 1 }
        \\obj.size
    );
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());
}

test "Object#define_singleton_method forwards blocks to proc-backed methods" {
    const result = try evalCode(
        \\obj = Object.new
        \\obj.define_singleton_method(:wrap) do |value, &block|
        \\  [block.call(value), block.call(value + 1)]
        \\end
        \\obj.wrap(3) { |n| n * 2 }
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 6), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toArrayObject().elements.items[1].toInteger());
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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "singleton", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "class", result.toArrayObject().elements.items[1].toStringObject().str);
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
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 123), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqualSlices(u8, "hi", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "class << literals true false nil uses singleton class self" {
    const result = try evalCode(
        \\[
        \\  (class << true; self; end) == TrueClass,
        \\  (class << false; self; end) == FalseClass,
        \\  (class << nil; self; end) == NilClass
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[2].toBool());
}

test "def singleton method on nil true false defines class method" {
    const result = try evalCode(
        \\begin
        \\  def (nil).nil_marker() = 1
        \\  def (true).true_marker() = 2
        \\  def (false).false_marker() = 3
        \\  [nil.nil_marker, true.true_marker, false.false_marker]
        \\ensure
        \\  NilClass.send(:remove_method, :nil_marker) rescue nil
        \\  TrueClass.send(:remove_method, :true_marker) rescue nil
        \\  FalseClass.send(:remove_method, :false_marker) rescue nil
        \\end
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "class << object constant namespace stays on singleton class" {
    const result = try evalCode(
        \\obj = Object.new
        \\class << obj
        \\  CONST = 7
        \\end
        \\[class << obj; CONST; end, begin obj.class::CONST; false; rescue NameError; true; end]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
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
