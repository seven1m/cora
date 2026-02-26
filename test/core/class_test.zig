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

test "Class hierarchy is set up correctly" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    var parser = try prism.Parser.init(allocator, "", null);
    defer parser.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
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
