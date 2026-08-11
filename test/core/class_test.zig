const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const bdwgc = @import("bdwgc");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;
const getAllocator = test_helper.getAllocator;

test "Classes" {
    const result = try evalCode(
        \\class Foo
        \\end
    );
    try std.testing.expect(result.isClass());
    try std.testing.expectEqualSlices(u8, "Foo", result.toClassObject().module.name.name);
}

test "Class instantiation" {
    const result = try evalCode(
        \\class Foo
        \\  def foo
        \\    'foo'
        \\  end
        \\end
        \\foo = Foo.new
        \\foo.foo
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);
}

test "non-allocatable value classes and their subclasses reject construction" {
    const result = try evalCode(
        \\def new_is_undefined?(klass)
        \\  klass.new
        \\  false
        \\rescue NoMethodError
        \\  true
        \\end
        \\def allocator_is_unavailable?(klass)
        \\  klass.allocate
        \\  false
        \\rescue TypeError
        \\  true
        \\end
        \\def allocator_is_undefined?(klass)
        \\  klass.allocate
        \\  false
        \\rescue NoMethodError
        \\  true
        \\end
        \\unavailable = [Integer, Float, Symbol, NilClass, TrueClass, FalseClass]
        \\unavailable.all? do |parent|
        \\  child = Class.new(parent)
        \\  new_is_undefined?(parent) && new_is_undefined?(child) &&
        \\    allocator_is_unavailable?(parent) && allocator_is_unavailable?(child)
        \\end &&
        \\  new_is_undefined?(Rational) && new_is_undefined?(Class.new(Rational)) &&
        \\  allocator_is_undefined?(Rational) && allocator_is_undefined?(Class.new(Rational))
    );
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
}

test "Class inheritance" {
    var result = try evalCode(
        \\class Foo
        \\  def foo = 'foo'
        \\end
        \\class Bar < Foo
        \\end
        \\bar = Bar.new
        \\bar.foo
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);

    result = try evalCode(
        \\class Foo
        \\  def foo = 'foo'
        \\end
        \\class Bar < Foo
        \\  def foo = 'bar'
        \\end
        \\bar = Bar.new
        \\bar.foo
    );
    try std.testing.expectEqualSlices(u8, "bar", result.toStringObject().str);
}

test "class definition target does not reuse Object constant inside module" {
    const result = try evalCode(
        \\module M
        \\  class LoadError < ::LoadError
        \\  end
        \\end
        \\M::LoadError.name
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "M::LoadError", result.toStringObject().str);
}

test "class definition target does not reuse outer lexical constant" {
    const result = try evalCode(
        \\module A
        \\  class C
        \\  end
        \\  module B
        \\    class C
        \\    end
        \\    A::B::C == A::C
        \\  end
        \\end
    );
    try std.testing.expect(!result.toBool());
}

test "class definition evaluates a local namespace target" {
    const result = try evalCode(
        \\owner = Class.new
        \\class owner::Child < owner
        \\end
        \\[owner::Child.superclass == owner, owner.constants]
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].toBool());
    const constants = elems[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), constants.len);
    try std.testing.expectEqualStrings("Child", constants[0].toSymbolObject().name);
}

test "Class hierarchy is set up correctly" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    var parser = try prism.Parser.init(allocator, "", null);
    defer parser.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, std.testing.io, std.testing.environ);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    try vm.prepare(&program);

    try std.testing.expect(vm.basic_object_class.superclass == null);
    try std.testing.expect(vm.object_class.superclass == vm.basic_object_class);
    try std.testing.expect(vm.module_class.superclass == vm.object_class);
    try std.testing.expect(vm.class_class.superclass == vm.module_class);
    try std.testing.expect(vm.numeric_class.superclass == vm.object_class);
    try std.testing.expect(vm.integer_class.superclass == vm.numeric_class);
    try std.testing.expect(vm.symbol_class.superclass == vm.object_class);
    try std.testing.expect(vm.nil_class.superclass == vm.object_class);
    try std.testing.expect(vm.true_class.superclass == vm.object_class);
    try std.testing.expect(vm.false_class.superclass == vm.object_class);
}

test "Class.new creates an instantiable anonymous class" {
    const result = try evalCode(
        \\C = Class.new do
        \\  def foo
        \\    'ok'
        \\  end
        \\end
        \\C.new.foo
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ok", result.toStringObject().str);
}

test "Class.new accepts superclass argument" {
    const result = try evalCode(
        \\class Parent
        \\  def greet
        \\    'hi'
        \\  end
        \\end
        \\C = Class.new(Parent)
        \\C.new.greet
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hi", result.toStringObject().str);
}

test "Class.new with non-class superclass raises TypeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\Class.new(123)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "superclass must be a Class") != null);
}
