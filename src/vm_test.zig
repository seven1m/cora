const std = @import("std");
const prism = @import("prism.zig");
const compiler = @import("compiler.zig");
const VM = @import("vm.zig").VM;
const Value = @import("value.zig").Value;
const bdwgc = @import("bdwgc");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

fn evalCode(ruby_code: []const u8) !Value {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();

    const parser = try prism.Parser.init(allocator, ruby_code);

    var vm = VM.initEmpty(allocator, bdwgc.allocator, parser);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &vm.parser);
    defer program.deinit();

    try vm.prepare(&program);
    return try vm.run();
}

test "Basic integer arithmetic" {
    const result = try evalCode("10 + 3");
    try std.testing.expectEqual(@as(i64, 13), result.data.integer);
}

test "Subtraction" {
    const result = try evalCode("10 - 3");
    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "Equality comparison - true" {
    const result = try evalCode("5 == 5");
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Equality comparison - false" {
    const result = try evalCode("6 == 7");
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Boolean true" {
    const result = try evalCode("true");
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Boolean false" {
    const result = try evalCode("false");
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Nil value" {
    const result = try evalCode("nil");
    try std.testing.expect(result.data == .nil);
}

test "If statement - true condition" {
    const result = try evalCode("if true; 42; else; 0; end");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "If statement - false condition" {
    const result = try evalCode("if false; 42; else; 0; end");
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);
}

test "If statement - no else" {
    const result = try evalCode("if true; 42; end");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Constants can be set and read" {
    const result = try evalCode("FOO = 42; FOO");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Modules" {
    const result = try evalCode("module Foo; end;");
    try std.testing.expect(result.data == .module);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.module.name.name);
}

test "Classes" {
    const result = try evalCode("class Foo; end;");
    try std.testing.expect(result.data == .class);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.class.module.name.name);
}

test "Top-level methods" {
    var result = try evalCode("def foo; 'foo'; end");
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "foo", result.data.symbol.name);

    result = try evalCode("def foo; 'foo'; end; foo");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string);
}

test "Class instantiation" {
    const result = try evalCode("class Foo; def foo; 'foo'; end; end; foo = Foo.new; foo.foo");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string);
}

test "Class inheritance" {
    const result = try evalCode("class Foo; def foo; 'foo'; end; end; class Bar < Foo; end; bar = Bar.new; bar.foo");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string);
}

test "Method calls with arguments" {
    const result = try evalCode("def increment(x); x + 1; end; increment(41)");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(42, result.data.integer);
}

test "Symbol interning - same address for identical symbols" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    const parser = try prism.Parser.init(allocator, "");

    var vm = VM.initEmpty(allocator, bdwgc.allocator, parser);
    defer vm.deinit();

    const symbol1 = try vm.intern("foo");
    const symbol2 = try vm.intern("foo");
    const symbol3 = try vm.intern("bar");

    try std.testing.expectEqual(@intFromPtr(symbol1), @intFromPtr(symbol2));
    try std.testing.expect(@intFromPtr(symbol1) != @intFromPtr(symbol3));
}

test "Class hierarchy is set up correctly" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    const parser = try prism.Parser.init(allocator, "");

    var vm = VM.initEmpty(allocator, bdwgc.allocator, parser);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &vm.parser);
    defer program.deinit();

    try vm.prepare(&program);

    try std.testing.expect(vm.basic_object_class.superclass == null);
    try std.testing.expect(vm.object_class.superclass == vm.basic_object_class);
    try std.testing.expect(vm.module_class.superclass == vm.object_class);
    try std.testing.expect(vm.class_class.superclass == vm.module_class);
    try std.testing.expect(vm.numeric_class.superclass == vm.object_class);
    try std.testing.expect(vm.integer_class.superclass == vm.numeric_class);
    try std.testing.expect(vm.symbol_class.superclass == vm.object_class);
}
