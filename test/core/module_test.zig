const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Modules" {
    const result = try evalCode(
        \\module Foo
        \\end
    );
    try std.testing.expect(result.isModule());
    try std.testing.expectEqualSlices(u8, "Foo", result.toModuleObject().name.name);
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
    try std.testing.expectEqualSlices(u8, "baz", result.toStringObject().str);

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
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "before 2", result.toStringObject().str);
}

test "Module define_method on class" {
    const result = try evalCode(
        \\class Foo
        \\  define_method(:sum) { |a, b| a + b }
        \\end
        \\Foo.new.sum(2, 3)
    );
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hi", result.toStringObject().str);
}

test "Module define_method with string name" {
    const result = try evalCode(
        \\class Foo
        \\  define_method("mul") { |a, b| a * b }
        \\end
        \\Foo.new.mul(2, 4)
    );
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Module define_method forwards blocks to proc-backed methods" {
    const result = try evalCode(
        \\class Foo
        \\  define_method(:wrap) do |value, &block|
        \\    [block.call(value), block.call(value + 1)]
        \\  end
        \\end
        \\Foo.new.wrap(4) { |n| n + 10 }
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 14), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 15), result.toArrayObject().elements.items[1].toInteger());
}

test "Module const_get resolves nested constant paths" {
    var result = try evalCode(
        \\module A
        \\  module B
        \\    X = 42
        \\  end
        \\end
        \\Object.const_get("A::B::X")
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());

    result = try evalCode(
        \\module A
        \\  module B
        \\    X = 42
        \\  end
        \\end
        \\A.const_get("::A::B")
    );
    try std.testing.expect(result.isModule());
    try std.testing.expectEqualSlices(u8, "B", result.toModuleObject().name.name);
}

test "Object const_get resolves Gem::Specification" {
    const result = try evalCode(
        \\$LOAD_PATH.unshift(File.expand_path("ext/rubygems/lib", Dir.pwd))
        \\require "rubygems"
        \\Object.const_get("Gem::Specification")
    );
    try std.testing.expect(result.isClass());
    try std.testing.expectEqualSlices(u8, "Specification", result.toClassObject().module.name.name);
}

test "qualified constant paths inherit constants from superclass" {
    var result = try evalCode(
        \\class A
        \\  X = 42
        \\end
        \\class B < A
        \\end
        \\B::X
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());

    result = try evalCode(
        \\class A
        \\  X = 42
        \\end
        \\class B < A
        \\end
        \\Object.const_get("B::X")
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());

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
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());

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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqualSlices(u8, "missing", result.toArrayObject().elements.items[1].toSymbolObject().name);
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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(result.toArrayObject().elements.items[0].toInteger(), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
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
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "equal?", result.toSymbolObject().name);
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
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
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
    try std.testing.expect(result.isArray());
    const names = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualSlices(u8, "A", names[0].toSymbolObject().name);
    try std.testing.expectEqualSlices(u8, "B", names[1].toSymbolObject().name);
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
    try std.testing.expect(result.isArray());
    const names = result.toArrayObject().elements.items;
    var has_child = false;
    var has_parent = false;
    for (names) |name| {
        if (std.mem.eql(u8, name.toSymbolObject().name, "CHILD_CONST")) has_child = true;
        if (std.mem.eql(u8, name.toSymbolObject().name, "PARENT_CONST")) has_parent = true;
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
    try std.testing.expect(result.isArray());
    const names = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualSlices(u8, "CHILD_CONST", names[0].toSymbolObject().name);
}

test "Module ancestors returns lookup chain for class with prepend/include" {
    const result = try evalCode(
        \\module ParentInc
        \\end
        \\module ChildInc
        \\end
        \\module ChildPre
        \\end
        \\class Parent
        \\  include ParentInc
        \\end
        \\class Child < Parent
        \\  include ChildInc
        \\  prepend ChildPre
        \\end
        \\Child.ancestors
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 8), entries.len);

    try std.testing.expect(entries[0].isModule());
    try std.testing.expectEqualSlices(u8, "ChildPre", entries[0].toModuleObject().name.name);
    try std.testing.expect(entries[1].isClass());
    try std.testing.expectEqualSlices(u8, "Child", entries[1].toClassObject().module.name.name);
    try std.testing.expect(entries[2].isModule());
    try std.testing.expectEqualSlices(u8, "ChildInc", entries[2].toModuleObject().name.name);
    try std.testing.expect(entries[3].isClass());
    try std.testing.expectEqualSlices(u8, "Parent", entries[3].toClassObject().module.name.name);
    try std.testing.expect(entries[4].isModule());
    try std.testing.expectEqualSlices(u8, "ParentInc", entries[4].toModuleObject().name.name);
    try std.testing.expect(entries[5].isClass());
    try std.testing.expectEqualSlices(u8, "Object", entries[5].toClassObject().module.name.name);
    try std.testing.expect(entries[6].isModule());
    try std.testing.expectEqualSlices(u8, "Kernel", entries[6].toModuleObject().name.name);
    try std.testing.expect(entries[7].isClass());
    try std.testing.expectEqualSlices(u8, "BasicObject", entries[7].toClassObject().module.name.name);
}

test "Module ancestors on module returns self" {
    const result = try evalCode(
        \\module M
        \\end
        \\M.ancestors
    );
    try std.testing.expect(result.isArray());
    const entries = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expect(entries[0].isModule());
    try std.testing.expectEqualSlices(u8, "M", entries[0].toModuleObject().name.name);
}

test "Module ancestors validates arg count" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("Module.ancestors(false)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "ArgumentError") != null);
}

test "Module comparison operators follow ancestry" {
    const result = try evalCode(
        \\module A
        \\end
        \\module B
        \\  include A
        \\end
        \\class C
        \\  include B
        \\end
        \\[
        \\  A >= B,
        \\  A >= C,
        \\  B > C,
        \\  C <= A,
        \\  C < A,
        \\  A >= A,
        \\  A > A,
        \\  A >= Module,
        \\  A >= Comparable
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 9), items.len);
    try std.testing.expect(items[0].isTruthy());
    try std.testing.expect(items[1].isTruthy());
    try std.testing.expect(items[2].isTruthy());
    try std.testing.expect(items[3].isTruthy());
    try std.testing.expect(items[4].isTruthy());
    try std.testing.expect(items[5].isTruthy());
    try std.testing.expect(!items[6].isTruthy());
    try std.testing.expect(!items[6].isNil());
    try std.testing.expect(items[7].isNil());
    try std.testing.expect(items[8].isNil());
}

test "Module comparison validates compared type" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const bad = evalCodeWithOutput("Module >= 1", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "TypeError") != null);
}

test "Module instance method visibility APIs filter correctly" {
    var result = try evalCode(
        \\class C
        \\  def pub; end
        \\  protected
        \\  def prot; end
        \\  private
        \\  def priv; end
        \\end
        \\C.instance_methods(false)
    );
    try std.testing.expect(result.isArray());
    var has_pub = false;
    var has_prot = false;
    var has_priv = false;
    for (result.toArrayObject().elements.items) |name| {
        if (std.mem.eql(u8, name.toSymbolObject().name, "pub")) has_pub = true;
        if (std.mem.eql(u8, name.toSymbolObject().name, "prot")) has_prot = true;
        if (std.mem.eql(u8, name.toSymbolObject().name, "priv")) has_priv = true;
    }
    try std.testing.expect(has_pub);
    try std.testing.expect(has_prot);
    try std.testing.expect(!has_priv);

    result = try evalCode(
        \\class C
        \\  def pub; end
        \\  protected
        \\  def prot; end
        \\  private
        \\  def priv; end
        \\end
        \\[C.public_instance_methods(false), C.protected_instance_methods(false), C.private_instance_methods(false)]
    );
    try std.testing.expect(result.isArray());
    const publics = result.toArrayObject().elements.items[0].toArrayObject().elements.items;
    const protecteds = result.toArrayObject().elements.items[1].toArrayObject().elements.items;
    const privates = result.toArrayObject().elements.items[2].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), publics.len);
    try std.testing.expectEqual(@as(usize, 1), protecteds.len);
    try std.testing.expectEqual(@as(usize, 1), privates.len);
    try std.testing.expectEqualSlices(u8, "pub", publics[0].toSymbolObject().name);
    try std.testing.expectEqualSlices(u8, "prot", protecteds[0].toSymbolObject().name);
    try std.testing.expectEqualSlices(u8, "priv", privates[0].toSymbolObject().name);
}

test "Module instance method APIs include inherited by default and exclude when false" {
    var result = try evalCode(
        \\class Parent
        \\  def parent_pub; end
        \\end
        \\class Child < Parent
        \\  def child_pub; end
        \\end
        \\Child.public_instance_methods
    );
    try std.testing.expect(result.isArray());
    var has_child = false;
    var has_parent = false;
    for (result.toArrayObject().elements.items) |name| {
        if (std.mem.eql(u8, name.toSymbolObject().name, "child_pub")) has_child = true;
        if (std.mem.eql(u8, name.toSymbolObject().name, "parent_pub")) has_parent = true;
    }
    try std.testing.expect(has_child);
    try std.testing.expect(has_parent);

    result = try evalCode(
        \\class Parent
        \\  def parent_pub; end
        \\end
        \\class Child < Parent
        \\  def child_pub; end
        \\end
        \\Child.public_instance_methods(false)
    );
    try std.testing.expect(result.isArray());
    has_child = false;
    has_parent = false;
    for (result.toArrayObject().elements.items) |name| {
        if (std.mem.eql(u8, name.toSymbolObject().name, "child_pub")) has_child = true;
        if (std.mem.eql(u8, name.toSymbolObject().name, "parent_pub")) has_parent = true;
    }
    try std.testing.expect(has_child);
    try std.testing.expect(!has_parent);
}

test "Module instance_methods omits methods undefined via undef_method" {
    const result = try evalCode(
        \\class Parent
        \\  def parent_pub; end
        \\end
        \\class Child < Parent
        \\  undef_method :parent_pub
        \\end
        \\Child.instance_methods
    );
    try std.testing.expect(result.isArray());
    for (result.toArrayObject().elements.items) |name| {
        try std.testing.expect(!std.mem.eql(u8, name.toSymbolObject().name, "parent_pub"));
    }
}

test "Module instance method APIs include included module methods by default" {
    const result = try evalCode(
        \\module Mixin
        \\  def mixed; end
        \\end
        \\module Host
        \\  include Mixin
        \\end
        \\Host.instance_methods.include?(:mixed)
    );
    try std.testing.expect(result.isTruthy());
}

test "Module private accepts methods from included modules" {
    const result = try evalCode(
        \\module Mixin
        \\  def mixed; end
        \\end
        \\module Host
        \\  include Mixin
        \\  private(*Mixin.instance_methods(false))
        \\end
        \\Host.private_instance_methods.include?(:mixed)
    );
    try std.testing.expect(result.isTruthy());
}
