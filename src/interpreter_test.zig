const std = @import("std");
const prism = @import("main.zig").prism;
const Interpreter = @import("interpreter.zig").Interpreter;
const OutputWriter = @import("interpreter.zig").OutputWriter;
const Value = @import("value.zig").Value;

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
    const allocator = std.testing.allocator;

    var string_writer = StringWriter.init(allocator);
    defer string_writer.deinit();

    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);
    defer prism.pm_parser_free(&parser);

    const ast = prism.pm_parse(&parser) orelse return;
    defer prism.pm_node_destroy(null, ast);

    var interpreter = Interpreter.initWithWriter(allocator, &parser, createOutputWriter(&string_writer));
    defer interpreter.deinit();
    _ = interpreter.eval(ast);

    try std.testing.expectEqualSlices(u8, expected, string_writer.getOutput());
}

const EvalStatementsContext = struct {
    values: []Value,
    interpreter: Interpreter,
    parser: prism.pm_parser_t,
    ast: *prism.pm_node_t,

    fn deinit(self: *EvalStatementsContext) void {
        self.interpreter.deinit();
        prism.pm_node_destroy(null, self.ast);
        prism.pm_parser_free(&self.parser);
    }
};

fn evalStatements(allocator: std.mem.Allocator, ruby_code: []const u8) !EvalStatementsContext {
    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);

    const ast = prism.pm_parse(&parser) orelse {
        prism.pm_parser_free(&parser);
        return error.ParseFailed;
    };

    var interpreter = Interpreter.init(allocator, &parser);

    const program = @as(*prism.pm_program_node_t, @ptrCast(ast));
    const statements = @as(*prism.pm_statements_node_t, @ptrCast(program.statements));

    var results = try allocator.alloc(Value, statements.body.size);
    for (0..statements.body.size) |i| {
        results[i] = interpreter.eval(statements.body.nodes[i]);
    }

    return .{
        .values = results,
        .interpreter = interpreter,
        .parser = parser,
        .ast = ast,
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
    var context = try evalStatements(allocator, ":foo; :foo");
    defer context.deinit();
    defer allocator.free(context.values);

    try std.testing.expect(context.values[0].data.symbol.ptr == context.values[1].data.symbol.ptr);
    try std.testing.expectEqualSlices(u8, "foo", context.values[0].data.symbol);
    try std.testing.expectEqualSlices(u8, "foo", context.values[1].data.symbol);
}

test "Constants can be set and read" {
    try evalAndCheckOutput("FOO = 42; puts FOO", "42\n");
}
