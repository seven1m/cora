const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Modules" {
    const result = try evalCode(
        \\module Foo
        \\end
    );
    try std.testing.expect(result.data == .module);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.module.name.name);
}

test "Module include" {
    var result = try evalCode(
        \\module Foo
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\module Baz
        \\  def call
        \\    'baz'
        \\  end
        \\end
        \\
        \\class Bar
        \\  include Foo
        \\  include Baz
        \\end
        \\
        \\bar = Bar.new
        \\bar.call
    );
    try std.testing.expectEqualSlices(u8, "baz", result.data.string.str);

    result = try evalCode(
        \\module Foo
        \\  def call
        \\    'nope'
        \\  end
        \\end
        \\
        \\class Bar
        \\  include Foo
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\bar = Bar.new
        \\bar.call
    );
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "Module prepend" {
    const result = try evalCode(
        \\module Before
        \\  def call
        \\    'before'
        \\  end
        \\end
        \\
        \\module Before2
        \\  def call
        \\    'before 2'
        \\  end
        \\end
        \\
        \\class Foo
        \\  prepend Before
        \\  prepend Before2
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\Foo.new.call
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "before 2", result.data.string.str);
}

test "Module define_method on class" {
    const result = try evalCode(
        \\class Foo
        \\  define_method(:sum) { |a, b| a + b }
        \\end
        \\Foo.new.sum(2, 3)
    );
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "Module define_method on module include" {
    const result = try evalCode(
        \\module M
        \\  define_method(:hello) { 'hi' }
        \\end
        \\class C
        \\  include M
        \\end
        \\C.new.hello
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hi", result.data.string.str);
}

test "Module define_method with string name" {
    const result = try evalCode(
        \\class Foo
        \\  define_method("mul") { |a, b| a * b }
        \\end
        \\Foo.new.mul(2, 4)
    );
    try std.testing.expectEqual(@as(i64, 8), result.data.integer);
}

test "Module attr_reader coerces names via to_str" {
    const result = try evalCode(
        \\class AttrNameObj
        \\  def to_str
        \\    "value"
        \\  end
        \\end
        \\class C
        \\  attr_reader AttrNameObj.new
        \\  def initialize
        \\    @value = 7
        \\  end
        \\end
        \\C.new.value
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "Module attr_reader defines getter and returns symbols" {
    var result = try evalCode(
        \\class C
        \\  def self.make
        \\    attr_reader :a, "b"
        \\  end
        \\  def initialize
        \\    @a = 1
        \\    @b = 2
        \\  end
        \\end
        \\C.make
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "b", result.data.array.elements.items[1].data.symbol.name);

    result = try evalCode(
        \\class C
        \\  attr_reader :a, "b"
        \\  def initialize
        \\    @a = 1
        \\    @b = 2
        \\  end
        \\end
        \\c = C.new
        \\[c.a, c.b]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
}

test "Module attr_writer defines setter and returns symbols" {
    var result = try evalCode(
        \\class C
        \\  def self.make
        \\    attr_writer :a, "b"
        \\  end
        \\end
        \\C.make
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a=", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "b=", result.data.array.elements.items[1].data.symbol.name);

    result = try evalCode(
        \\class C
        \\  attr_writer :a, "b"
        \\  def set
        \\    self.a = 10
        \\    self.b = 20
        \\    [@a, @b]
        \\  end
        \\end
        \\C.new.set
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 10), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 20), result.data.array.elements.items[1].data.integer);
}

test "Module attr_accessor defines getter and setter and returns symbols" {
    var result = try evalCode(
        \\class C
        \\  def self.make
        \\    attr_accessor :a, "b"
        \\  end
        \\end
        \\C.make
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 4), result.data.array.elements.items.len);
    try std.testing.expectEqualSlices(u8, "a", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "a=", result.data.array.elements.items[1].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "b", result.data.array.elements.items[2].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "b=", result.data.array.elements.items[3].data.symbol.name);

    result = try evalCode(
        \\class C
        \\  attr_accessor :a, "b"
        \\end
        \\c = C.new
        \\c.a = 1
        \\c.b = 2
        \\[c.a, c.b]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
}

test "Module module_function creates module singleton method and privatizes instance method" {
    var result = try evalCode(
        \\module M
        \\  def answer
        \\    42
        \\  end
        \\  module_function :answer
        \\end
        \\M.answer
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode(
        \\module M
        \\  def answer
        \\    42
        \\  end
        \\  module_function :answer
        \\end
        \\class C
        \\  include M
        \\  def call_answer
        \\    answer
        \\  end
        \\end
        \\C.new.call_answer
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\module M
        \\  def answer
        \\    42
        \\  end
        \\  module_function :answer
        \\end
        \\class C
        \\  include M
        \\end
        \\C.new.answer
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "answer") != null);
}

test "Module undef_method removes a directly defined method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  def greet
        \\    1
        \\  end
        \\  undef_method :greet
        \\end
        \\C.new.greet
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "greet") != null);
}

test "Module undef_method on subclass blocks inherited dispatch without mutating ancestor" {
    const result = try evalCode(
        \\class Parent
        \\  def call
        \\    1
        \\  end
        \\end
        \\class Child < Parent
        \\  undef_method :call
        \\end
        \\[
        \\  Parent.new.call,
        \\  begin
        \\    Child.new.call
        \\    :ok
        \\  rescue NoMethodError
        \\    :missing
        \\  end,
        \\]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqualSlices(u8, "missing", result.data.array.elements.items[1].data.symbol.name);
}

test "Module undef_method raises NameError for missing name" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  undef_method :not_defined_here
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "not_defined_here") != null);
}

test "Module undef_method with no args returns self and is a no-op" {
    const result = try evalCode(
        \\class C
        \\  def call
        \\    1
        \\  end
        \\end
        \\same = C.undef_method
        \\[same.object_id, C.object_id, C.new.call]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(result.data.array.elements.items[0].data.integer, result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[2].data.integer);
}

test "Module undef_method is callable publicly" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  def call
        \\    1
        \\  end
        \\end
        \\C.undef_method(:call)
        \\C.new.call
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "call") != null);
}

test "Module undef_method allows method_missing to handle equal?" {
    const result = try evalCode(
        \\class C
        \\  def method_missing(name, *args)
        \\    name
        \\  end
        \\  undef_method :equal?
        \\end
        \\C.new.equal?(1)
    );
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "equal?", result.data.symbol.name);
}

test "Module remove_method removes own method and allows superclass fallback" {
    const result = try evalCode(
        \\class Parent
        \\  def call
        \\    1
        \\  end
        \\end
        \\class Child < Parent
        \\  def call
        \\    2
        \\  end
        \\  remove_method :call
        \\end
        \\Child.new.call
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Module remove_method raises NameError when method is not defined on receiver" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class Parent
        \\  def call
        \\    1
        \\  end
        \\end
        \\class Child < Parent
        \\  remove_method :call
        \\end
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "call") != null);
}

test "Module constants returns module constants as symbols" {
    const result = try evalCode(
        \\module M
        \\  A = 1
        \\  B = 2
        \\end
        \\M.constants
    );
    try std.testing.expect(result.data == .array);
    const names = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualSlices(u8, "A", names[0].data.symbol.name);
    try std.testing.expectEqualSlices(u8, "B", names[1].data.symbol.name);
}

test "Class constants includes inherited constants by default" {
    const result = try evalCode(
        \\class Parent
        \\  PARENT_CONST = 1
        \\end
        \\class Child < Parent
        \\  CHILD_CONST = 2
        \\end
        \\Child.constants
    );
    try std.testing.expect(result.data == .array);
    const names = result.data.array.elements.items;
    var has_child = false;
    var has_parent = false;
    for (names) |name| {
        if (std.mem.eql(u8, name.data.symbol.name, "CHILD_CONST")) has_child = true;
        if (std.mem.eql(u8, name.data.symbol.name, "PARENT_CONST")) has_parent = true;
    }
    try std.testing.expect(has_child);
    try std.testing.expect(has_parent);
}

test "Class constants(false) excludes inherited constants" {
    const result = try evalCode(
        \\class Parent
        \\  PARENT_CONST = 1
        \\end
        \\class Child < Parent
        \\  CHILD_CONST = 2
        \\end
        \\Child.constants(false)
    );
    try std.testing.expect(result.data == .array);
    const names = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualSlices(u8, "CHILD_CONST", names[0].data.symbol.name);
}
