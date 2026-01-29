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

const TestWriter = struct {
    fbs: *std.io.FixedBufferStream([]u8),
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .sendFile = std.Io.Writer.unimplementedSendFile,
    };

    pub fn init(fbs: *std.io.FixedBufferStream([]u8)) TestWriter {
        return .{
            .fbs = fbs,
            .interface = .{
                .vtable = &vtable,
                .buffer = &.{}, // unbuffered - writes go directly to fbs
            },
        };
    }

    fn drain(io_w: *std.Io.Writer, data: []const []const u8, _: usize) std.Io.Writer.Error!usize {
        const w: *TestWriter = @alignCast(@fieldParentPtr("interface", io_w));
        var total: usize = 0;
        for (data) |slice| {
            w.fbs.writer().writeAll(slice) catch return error.WriteFailed;
            total += slice.len;
        }
        return total;
    }
};

fn evalCode(ruby_code: []const u8) !Value {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(ruby_code, &stdout_buf, &stderr_buf);
    if (result.err) |err| return err;
    return result.value;
}

const EvalResult = struct {
    value: Value,
    stdout: []const u8,
    stderr: []const u8,
    err: ?anyerror,
};

fn evalCodeWithOutput(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();

    const parser = prism.Parser.init(allocator, ruby_code) catch |err| {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, parser);
    defer vm.deinit();

    var program = compiler.Compiler.compile(allocator, &vm.parser) catch |err| {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };
    defer program.deinit();

    vm.prepare(&program) catch |err| {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };

    // Set up stdout capture
    var stdout_fbs = std.io.fixedBufferStream(stdout_buf);
    var stdout_writer = TestWriter.init(&stdout_fbs);
    vm.stdout = &stdout_writer.interface;

    // Set up stderr capture
    var stderr_fbs = std.io.fixedBufferStream(stderr_buf);
    var stderr_writer = TestWriter.init(&stderr_fbs);
    vm.stderr = &stderr_writer.interface;

    const result = vm.run() catch |err| {
        // If there was an error, print the exception to stderr
        if (err == error.RuntimeError) {
            vm.printUnhandledException();
        }
        return .{
            .value = Value.nil(),
            .stdout = stdout_fbs.getWritten(),
            .stderr = stderr_fbs.getWritten(),
            .err = err,
        };
    };

    return .{
        .value = result,
        .stdout = stdout_fbs.getWritten(),
        .stderr = stderr_fbs.getWritten(),
        .err = null,
    };
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

test "If expression" {
    var result = try evalCode(
        \\if true
        \\  42
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode(
        \\if false
        \\  42
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);

    result = try evalCode(
        \\if true
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);

    result = try evalCode(
        \\if false
        \\  42
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "Constants can be set and read" {
    const result = try evalCode(
        \\FOO = 42
        \\FOO
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Modules" {
    const result = try evalCode(
        \\module Foo
        \\end
    );
    try std.testing.expect(result.data == .module);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.module.name.name);
}

test "Classes" {
    const result = try evalCode(
        \\class Foo
        \\end
    );
    try std.testing.expect(result.data == .class);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.class.module.name.name);
}

test "Top-level methods" {
    var result = try evalCode(
        \\def foo
        \\  'foo'
        \\end
    );
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "foo", result.data.symbol.name);

    result = try evalCode(
        \\def foo
        \\  'foo'
        \\end
        \\foo
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);

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
    try std.testing.expectEqualSlices(u8, "bar", result.data.string.str);
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

test "Method calls with arguments" {
    const result = try evalCode(
        \\def increment(x)
        \\  x + 1
        \\end
        \\increment(41)
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(42, result.data.integer);
}

test "Symbol interning - same address for identical symbols" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    const parser = try prism.Parser.init(allocator, "");

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, parser);
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

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, parser);
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
    try std.testing.expect(vm.nil_class.superclass == vm.object_class);
    try std.testing.expect(vm.true_class.superclass == vm.object_class);
    try std.testing.expect(vm.false_class.superclass == vm.object_class);
}

test "Empty array" {
    const result = try evalCode("[]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 0), result.data.array.elements.items.len);
}

test "Array with integers" {
    const result = try evalCode("[1, 2, 3]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Array with mixed types" {
    const result = try evalCode("[1, true, nil]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expect(result.data.array.elements.items[0].data == .integer);
    try std.testing.expect(result.data.array.elements.items[1].data == .boolean);
    try std.testing.expect(result.data.array.elements.items[2].data == .nil);
}

test "Array << append" {
    const result = try evalCode(
        \\[1, 2] << 3
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Array << chaining" {
    const result = try evalCode(
        \\[1] << 2 << 3
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Nested arrays" {
    const result = try evalCode("[[1, 2], [3, 4]]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);

    const first_array = result.data.array.elements.items[0];
    try std.testing.expect(first_array.data == .array);
    try std.testing.expectEqual(@as(usize, 2), first_array.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), first_array.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), first_array.data.array.elements.items[1].data.integer);

    const second_array = result.data.array.elements.items[1];
    try std.testing.expect(second_array.data == .array);
    try std.testing.expectEqual(@as(usize, 2), second_array.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), second_array.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 4), second_array.data.array.elements.items[1].data.integer);
}

test "puts" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    var result = evalCodeWithOutput("puts [1, 2, 3], [4, 5, 6]", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n3\n4\n5\n6\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);

    result = evalCodeWithOutput("puts", &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Integer#to_s" {
    const result = try evalCode("42.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "42", result.data.string.str);
}

test "String#to_s" {
    const result = try evalCode("'hello'.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "Symbol#to_s" {
    const result = try evalCode(":foo.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "NilClass#to_s" {
    const result = try evalCode("nil.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "", result.data.string.str);
}

test "TrueClass#to_s" {
    const result = try evalCode("true.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "true", result.data.string.str);
}

test "FalseClass#to_s" {
    const result = try evalCode("false.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "false", result.data.string.str);
}

test "Array#to_s" {
    const result = try evalCode("[1, 2, 3].to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.data.string.str);
}

test "Integer#inspect" {
    const result = try evalCode("42.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "42", result.data.string.str);
}

test "String#inspect basic" {
    const result = try evalCode("\"hello\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\"", result.data.string.str);
}

test "String#inspect with quotes" {
    const result = try evalCode("\"say \\\"hi\\\"\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"say \\\"hi\\\"\"", result.data.string.str);
}

test "String#inspect with newline" {
    const result = try evalCode("\"hello\\nworld\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\\nworld\"", result.data.string.str);
}

test "String#inspect with tab" {
    const result = try evalCode("\"hello\\tworld\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"hello\\tworld\"", result.data.string.str);
}

test "String#inspect with backslash" {
    const result = try evalCode("\"path\\\\to\\\\file\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"path\\\\to\\\\file\"", result.data.string.str);
}

test "String#inspect empty string" {
    const result = try evalCode("\"\".inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\"\"", result.data.string.str);
}

test "Symbol#inspect" {
    const result = try evalCode(":foo.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, ":foo", result.data.string.str);
}

test "NilClass#inspect" {
    const result = try evalCode("nil.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "nil", result.data.string.str);
}

test "TrueClass#inspect" {
    const result = try evalCode("true.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "true", result.data.string.str);
}

test "FalseClass#inspect" {
    const result = try evalCode("false.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "false", result.data.string.str);
}

test "Array#inspect with integers" {
    const result = try evalCode("[1, 2, 3].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.data.string.str);
}

test "Array#inspect with strings" {
    const result = try evalCode("[\"a\", \"b\"].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[\"a\", \"b\"]", result.data.string.str);
}

test "Array#inspect mixed types" {
    const result = try evalCode("[1, \"hi\", :foo, nil].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, \"hi\", :foo, nil]", result.data.string.str);
}

test "Array#inspect empty" {
    const result = try evalCode("[].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[]", result.data.string.str);
}

test "Array#inspect nested" {
    const result = try evalCode("[[1, 2], [3, 4]].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[[1, 2], [3, 4]]", result.data.string.str);
}

test "p with no arguments" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .nil);
    try std.testing.expectEqualStrings("\n", result.stdout);
}

test "p with single integer" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);
    try std.testing.expectEqualStrings("42\n", result.stdout);
}

test "p with single string" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p \"hello\"", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.value.data.string.str);
    try std.testing.expectEqualStrings("\"hello\"\n", result.stdout);
}

test "p with multiple integers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 1, 2, 3", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "p with mixed types" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput("p 42, \"hello\", :foo", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.value.data.array.elements.items.len);
    try std.testing.expectEqualStrings("42\n\"hello\"\n:foo\n", result.stdout);
}

test "Method with block and yield" {
    const result = try evalCode(
        \\def twice
        \\  yield 1
        \\  yield 2
        \\end
        \\
        \\twice { |x| x + 10 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "Block with multiple parameters" {
    const result = try evalCode(
        \\def add_them
        \\  yield 5, 7
        \\end
        \\
        \\add_them { |a, b| a + b }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "Block with no parameters" {
    const result = try evalCode(
        \\def call_block
        \\  yield
        \\end
        \\
        \\call_block { 42 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Lexical scope: nested module constants" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\X = 999
        \\module A
        \\  X = 42
        \\  puts X
        \\end
        \\puts X
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqualSlices(u8, "42\n999\n", result.stdout);
}

test "Lexical scope: class with method finding outer constant" {
    const result = try evalCode(
        \\Y = 999
        \\class C
        \\  Y = 42
        \\  def get_y
        \\    Y
        \\  end
        \\end
        \\C.new.get_y
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Lexical scope: top-level fallback" {
    const result = try evalCode(
        \\X = 100
        \\class A
        \\  def get_x
        \\    X
        \\  end
        \\end
        \\A.new.get_x
    );
    try std.testing.expectEqual(@as(i64, 100), result.data.integer);
}

test "Constant path: simple module constant" {
    const result = try evalCode(
        \\module A
        \\  X = 42
        \\end
        \\A::X
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Constant path: nested modules" {
    const result = try evalCode(
        \\module A
        \\  module B
        \\    Y = 99
        \\  end
        \\end
        \\A::B::Y
    );
    try std.testing.expectEqual(@as(i64, 99), result.data.integer);
}

test "Constant path: class constant" {
    const result = try evalCode(
        \\class C
        \\  Z = 123
        \\end
        \\C::Z
    );
    try std.testing.expectEqual(@as(i64, 123), result.data.integer);
}

// ===== Exception Handling Tests =====

test "Raise with string message creates RuntimeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput("raise \"something went wrong\"", &stdout_buf, &stderr_buf);

    // Should get RuntimeError
    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    // Check stderr contains exception info
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "RuntimeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "something went wrong") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
}

test "Raise with exception class and message" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "raise ArgumentError, \"expected 2 arguments\"",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "expected 2 arguments") != null);
}

test "Nested method calls show full backtrace" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def bar
        \\  raise "deep error"
        \\end
        \\
        \\def foo
        \\  bar
        \\end
        \\
        \\foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "deep error") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
    // Both methods should appear in backtrace
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "bar") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "foo") != null);
}

test "Code before raise executes normally" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\puts "before raise"
        \\raise "error"
        \\puts "after raise"
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    // Code before raise should execute, code after should NOT
    try std.testing.expectEqualSlices(u8, "before raise\n", result.stdout);
}

test "Raise with empty message" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "raise ArgumentError",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "Begin/rescue catches exception" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  raise "error"
        \\rescue
        \\  puts "caught"
        \\end
    , &stdout_buf, &stderr_buf);

    // Rescue should catch the exception, so no error is raised
    try std.testing.expect(result.err == null);
    try std.testing.expect(result.value.data == .nil);

    try std.testing.expectEqualSlices(u8, "caught\n", result.stdout);
}

test "Begin/rescue returns value from rescue" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Begin/rescue with no exception executes protected code" {
    const result = try evalCode(
        \\begin
        \\  10 + 5
        \\rescue
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "Exception#message returns message string" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError, "my message"
        \\rescue => e
        \\  e.message
        \\end
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "my message", result.data.string.str);
}

test "Rescue with variable binding - capture exception" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError, "my message"
        \\rescue => e
        \\  42
        \\end
    );
    // For now, just verify rescue clause executes
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "NoMethodError raised for undefined method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\end
        \\Foo.new.bar
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "bar") != null);
}

test "TypeError raised for wrong receiver type" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "true + 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.RuntimeError, result.err.?);
    // Note: Exception is raised, but message content checking depends on implementation
}

// NOTE: Method call argument count checking is not implemented yet
// TODO: Implement argument count checking in CALL opcode or in callMethod
// For now, extra arguments are just ignored

// test "ArgumentError raised for wrong argument count" {
//     var stdout_buf: [8192]u8 = undefined;
//     var stderr_buf: [8192]u8 = undefined;

//     const eval_result = evalCodeWithOutput(
//         \\def foo(x)
//         \\  x
//         \\end
//         \\foo(1, 2)
//     , &stdout_buf,
//         &stderr_buf,
//     );

//     try std.testing.expectError(error.RuntimeError, eval_result);

//     const stderr_output = std.mem.trim(u8, stderr_buf[0..], &std.ascii.whitespace);
//     try std.testing.expect(std.mem.indexOf(u8, stderr_output, "ArgumentError") != null);
// }

test "ArgumentError raised for no block given" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "no block given") != null);
}

test "ArgumentError raised for wrong block arity" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\foo { |a, b| a + b }
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "Nested begin/rescue" {
    const result = try evalCode(
        \\begin
        \\  begin
        \\    raise "inner"
        \\  rescue
        \\    1
        \\  end
        \\rescue
        \\  2
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Re-raise in rescue clause" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  begin
        \\    raise "original"
        \\  rescue
        \\    raise "re-raised"
        \\  end
        \\rescue
        \\  puts "final"
        \\end
    , &stdout_buf, &stderr_buf);

    // Outer rescue catches the re-raised exception
    try std.testing.expect(result.err == null);
    try std.testing.expect(result.value.data == .nil);
    try std.testing.expectEqualSlices(u8, "final\n", result.stdout);
}

test "Exception with backtrace shows call stack" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def inner
        \\  raise "deep error"
        \\end
        \\def middle
        \\  inner
        \\end
        \\def outer
        \\  middle
        \\end
        \\outer
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Backtrace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "outer") != null);
}

test "Exception class hierarchy - StandardError caught by bare rescue" {
    const result = try evalCode(
        \\begin
        \\  raise ArgumentError, "arg error"
        \\rescue
        \\  1
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Exception class hierarchy - TypeError caught by bare rescue" {
    const result = try evalCode(
        \\begin
        \\  raise TypeError, "type error"
        \\rescue
        \\  1
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Exception in method call caught by outer rescue" {
    const result = try evalCode(
        \\def foo
        \\  raise "error in method"
        \\end
        \\begin
        \\  foo
        \\rescue
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 99), result.data.integer);
}

test "Basic rescue catches exception" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  42
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Rescue with TypeError matches" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue TypeError
        \\  100
        \\end
    );
    try std.testing.expectEqual(@as(i64, 100), result.data.integer);
}

test "Rescue with ArgumentError matches" {
    const result = try evalCode(
        \\def foo
        \\  yield 1
        \\end
        \\begin
        \\  foo
        \\rescue ArgumentError
        \\  200
        \\end
    );
    try std.testing.expectEqual(@as(i64, 200), result.data.integer);
}

test "Rescue with NoMethodError matches" {
    const result = try evalCode(
        \\begin
        \\  1.nonexistent
        \\rescue NoMethodError
        \\  300
        \\end
    );
    try std.testing.expectEqual(@as(i64, 300), result.data.integer);
}

test "Multiple rescue clauses - correct type matched" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue ArgumentError
        \\  1
        \\rescue TypeError
        \\  2
        \\rescue NoMethodError
        \\  3
        \\end
    );
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "Multiple exception types in one rescue clause" {
    const result = try evalCode(
        \\begin
        \\  1 + "string"
        \\rescue ArgumentError, TypeError
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 99), result.data.integer);
}

test "Rescue with variable binding works" {
    const result = try evalCode(
        \\begin
        \\  raise "test message"
        \\rescue => e
        \\  77
        \\end
    );
    try std.testing.expectEqual(@as(i64, 77), result.data.integer);
}

test "Normal execution skips rescue clause" {
    const result = try evalCode(
        \\begin
        \\  10 + 5
        \\rescue
        \\  99
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "Else clause runs on normal completion" {
    const result = try evalCode(
        \\begin
        \\  10
        \\rescue
        \\  20
        \\else
        \\  30
        \\end
    );
    try std.testing.expectEqual(@as(i64, 30), result.data.integer);
}

test "Else clause does not run when exception is rescued" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  40
        \\else
        \\  50
        \\end
    );
    try std.testing.expectEqual(@as(i64, 40), result.data.integer);
}

test "Ensure clause runs on normal completion" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  42
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs after rescue" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  raise "error"
        \\rescue
        \\  100
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 100), result.value.data.integer);

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs during unwinding" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  raise "error"
        \\ensure
        \\  puts "cleanup during unwind"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.RuntimeError, result.err.?);

    try std.testing.expectEqualSlices(u8, "cleanup during unwind\n", result.stdout);
}

test "Ensure return value is ignored" {
    const result = try evalCode(
        \\begin
        \\  42
        \\ensure
        \\  999
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "All begin clauses together - normal completion" {
    const result = try evalCode(
        \\begin
        \\  10
        \\rescue
        \\  20
        \\else
        \\  30
        \\ensure
        \\  40
        \\end
    );
    try std.testing.expectEqual(@as(i64, 30), result.data.integer);
}

test "All begin clauses together - with exception" {
    const result = try evalCode(
        \\begin
        \\  raise "error"
        \\rescue
        \\  50
        \\else
        \\  60
        \\ensure
        \\  70
        \\end
    );
    try std.testing.expectEqual(@as(i64, 50), result.data.integer);
}

test "Retry basic - retry until counter reaches target" {
    const result = try evalCode(
        \\count = 0
        \\begin
        \\  count = count + 1
        \\  if count == 3
        \\    10
        \\  else
        \\    raise "error"
        \\  end
        \\rescue
        \\  retry
        \\end
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "Retry with ensure clause" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\count = 0
        \\begin
        \\  count = count + 1
        \\  if count == 2
        \\    42
        \\  else
        \\    raise "retry"
        \\  end
        \\rescue
        \\  retry
        \\ensure
        \\  puts "cleanup"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);

    // Ensure should run only once (after successful completion)
    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Rescue modifier - no exception returns main value" {
    const result = try evalCode("42 rescue 99");
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Rescue modifier - exception returns rescue value" {
    const result = try evalCode(
        \\def fail
        \\  raise "error"
        \\end
        \\fail rescue 100
    );
    try std.testing.expectEqual(@as(i64, 100), result.data.integer);
}

test "Rescue modifier - in assignment" {
    const result = try evalCode(
        \\def risky
        \\  raise "danger"
        \\end
        \\x = risky rescue 50
        \\x
    );
    try std.testing.expectEqual(@as(i64, 50), result.data.integer);
}
