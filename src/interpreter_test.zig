const std = @import("std");
const prism = @import("prism.zig");
const Interpreter = @import("interpreter.zig").Interpreter;
const OutputWriter = @import("interpreter.zig").OutputWriter;
const Value = @import("value.zig").Value;
const bdwgc = @import("bdwgc");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

const StringWriter = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) StringWriter {
        return .{
            .buffer = std.ArrayList(u8).initCapacity(allocator, 256) catch unreachable,
            .allocator = allocator,
        };
    }

    fn deinit(self: *StringWriter) void {
        self.buffer.deinit(self.allocator);
    }

    fn write(ctx: *anyopaque, data: []const u8) void {
        var self = @as(*StringWriter, @ptrCast(@alignCast(ctx)));
        self.buffer.appendSlice(self.allocator, data) catch return;
    }

    fn getOutput(self: *const StringWriter) []const u8 {
        return self.buffer.items;
    }
};

fn createOutputWriter(string_writer: *StringWriter) OutputWriter {
    return OutputWriter.init(string_writer, StringWriter.write);
}

fn evalAndCheckOutput(ruby_code: []const u8, expected: []const u8) !void {
    bdwgc.init();
    const allocator = getAllocator();

    var string_writer = StringWriter.init(allocator);
    defer string_writer.deinit();

    var parser = try prism.Parser.init(allocator, ruby_code);
    defer parser.deinit();

    var interpreter = Interpreter.initWithWriter(allocator, bdwgc.allocator, &parser, createOutputWriter(&string_writer));
    defer interpreter.deinit();

    const root_node = try parser.root();
    _ = interpreter.eval(root_node);

    try std.testing.expectEqualSlices(u8, expected, string_writer.getOutput());
}

const EvalStatementsContext = struct {
    values: []Value,
    allocator: std.mem.Allocator,
    full_allocation: []Value,
    interpreter: Interpreter,
    parser: prism.Parser,

    fn deinit(self: *EvalStatementsContext) void {
        self.interpreter.deinit();
        self.parser.deinit();
        self.allocator.free(self.full_allocation);
    }
};

fn evalStatements(allocator: std.mem.Allocator, ruby_code: []const u8) !EvalStatementsContext {
    bdwgc.init();
    var parser = try prism.Parser.init(allocator, ruby_code);

    var interpreter = Interpreter.init(allocator, bdwgc.allocator, &parser);

    var full_results = try allocator.alloc(Value, 10); // Preallocate, adjust as needed
    var count: usize = 0;

    const root_node = try parser.root();
    switch (root_node) {
        .program => |program| {
            if (program.statements != null) {
                const stmt_node = try parser.asNode(@ptrCast(program.statements));
                switch (stmt_node) {
                    .statements => |statements| {
                        for (0..statements.body.size) |i| {
                            const stmt = try parser.asNode(statements.body.nodes[i]);
                            full_results[count] = interpreter.eval(stmt);
                            count += 1;
                        }
                    },
                    else => {
                        full_results[0] = interpreter.eval(stmt_node);
                        count = 1;
                    },
                }
            }
        },
        else => {},
    }

    return .{
        .values = full_results[0..count],
        .allocator = allocator,
        .full_allocation = full_results,
        .interpreter = interpreter,
        .parser = parser,
    };
}

test "Interpreter evaluates puts with string" {
    try evalAndCheckOutput("puts \"Hello, World!\"", "Hello, World!\n");
}

test "Interpreter evaluates puts with integer" {
    try evalAndCheckOutput("puts 42", "42\n");
}

test "Interpreter evaluates puts with symbol" {
    try evalAndCheckOutput("puts :world", "world\n");
}

test "Symbols are interned" {
    const allocator = std.testing.allocator;
    var context = try evalStatements(allocator, ":foo; :bar; :foo");
    defer context.deinit();

    const foo1 = context.values[0];
    const bar = context.values[1];
    const foo2 = context.values[2];

    try std.testing.expectEqual(foo1.data.symbol.ptr, foo2.data.symbol.ptr);
    try std.testing.expect(foo1.data.symbol.ptr != bar.data.symbol.ptr);
    try std.testing.expectEqualSlices(u8, "foo", foo1.data.symbol);
}

test "Constants can be set and read" {
    try evalAndCheckOutput("FOO = 42; puts FOO", "42\n");
}

test "modules can be defined" {
    try evalAndCheckOutput("module Foo; end; puts Foo", "Foo\n");
}

test "methods can be defined and called" {
    try evalAndCheckOutput("puts def foo; 'foo called'; end; puts foo", "foo\nfoo called\n");
    try evalAndCheckOutput("def increment(x); x + 1; end; puts increment(41)", "42\n");
}

test "classes can be defined" {
    try evalAndCheckOutput("class Foo; end; puts Foo", "Foo\n");
    try evalAndCheckOutput("class Foo; def foo; 'foo'; end; end; foo = Foo.new; puts foo.foo", "foo\n");
    try evalAndCheckOutput("class Foo; def foo; 'foo'; end; end; class Bar < Foo; end; bar = Bar.new; puts bar.foo", "foo\n");
}
