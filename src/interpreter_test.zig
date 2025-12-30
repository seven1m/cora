const std = @import("std");
const prism = @import("main.zig").prism;
const Interpreter = @import("interpreter.zig").Interpreter;
const OutputWriter = @import("interpreter.zig").OutputWriter;

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

test "Interpreter evaluates puts with string" {
    const allocator = std.testing.allocator;

    var string_writer = StringWriter.init(allocator);
    defer string_writer.deinit();

    const ruby_code = "puts \"Hello, World!\"";

    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);
    defer prism.pm_parser_free(&parser);

    const ast = prism.pm_parse(&parser);
    if (ast == null) {
        return;
    }
    defer prism.pm_node_destroy(null, ast);

    var interpreter = Interpreter.initWithWriter(allocator, &parser, createOutputWriter(&string_writer));
    _ = interpreter.eval(ast);

    try std.testing.expectEqualSlices(u8, string_writer.getOutput(), "Hello, World!\n");
}

test "Interpreter evaluates puts with integer" {
    const allocator = std.testing.allocator;

    var string_writer = StringWriter.init(allocator);
    defer string_writer.deinit();

    const ruby_code = "puts 42";

    var parser: prism.pm_parser_t = undefined;
    prism.pm_parser_init(&parser, ruby_code.ptr, ruby_code.len, null);
    defer prism.pm_parser_free(&parser);

    const ast = prism.pm_parse(&parser);
    if (ast == null) {
        return;
    }
    defer prism.pm_node_destroy(null, ast);

    var interpreter = Interpreter.initWithWriter(allocator, &parser, createOutputWriter(&string_writer));
    _ = interpreter.eval(ast);

    try std.testing.expectEqualSlices(u8, string_writer.getOutput(), "42\n");
}
