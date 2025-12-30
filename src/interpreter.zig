const std = @import("std");
const Value = @import("value.zig").Value;
const prism = @import("main.zig").prism;

pub const OutputWriter = struct {
    ptr: *anyopaque,
    writeFn: *const fn (ptr: *anyopaque, data: []const u8) void,

    pub fn init(ptr: *anyopaque, writeFn: *const fn (ptr: *anyopaque, data: []const u8) void) OutputWriter {
        return .{
            .ptr = ptr,
            .writeFn = writeFn,
        };
    }

    pub fn write(self: OutputWriter, data: []const u8) void {
        self.writeFn(self.ptr, data);
    }
};

var default_output_state: u8 = 0;

pub fn defaultOutputWriter() OutputWriter {
    return OutputWriter.init(&default_output_state, struct {
        fn write(_: *anyopaque, data: []const u8) void {
            std.debug.print("{s}", .{data});
        }
    }.write);
}

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    parser: *prism.pm_parser_t,
    output_writer: OutputWriter,

    pub fn init(allocator: std.mem.Allocator, parser: *prism.pm_parser_t) @This() {
        return initWithWriter(allocator, parser, defaultOutputWriter());
    }

    pub fn initWithWriter(allocator: std.mem.Allocator, parser: *prism.pm_parser_t, output_writer: OutputWriter) @This() {
        return .{
            .allocator = allocator,
            .parser = parser,
            .output_writer = output_writer,
        };
    }

    pub fn eval(self: *Interpreter, node: *prism.pm_node_t) Value {
        const node_type = node.type;

        if (node_type == prism.PM_PROGRAM_NODE) {
            const program = @as(*prism.pm_program_node_t, @ptrCast(node));
            if (program.statements != null) {
                return self.eval(@ptrCast(program.statements));
            }
            return Value.nil();
        }

        if (node_type == prism.PM_STATEMENTS_NODE) {
            const statements = @as(*prism.pm_statements_node_t, @ptrCast(node));
            var result: Value = Value.nil();
            var i: usize = 0;
            while (i < statements.body.size) : (i += 1) {
                result = self.eval(statements.body.nodes[i]);
            }
            return result;
        }

        if (node_type == prism.PM_STRING_NODE) {
            const string_node = @as(*prism.pm_string_node_t, @ptrCast(node));
            const str = string_node.unescaped;
            return Value.frozenString(str.source[0..str.length]);
        }

        if (node_type == prism.PM_CALL_NODE) {
            return self.evalCall(@ptrCast(node));
        }

        return Value.nil();
    }

    fn evalCall(self: *Interpreter, call_node: *prism.pm_call_node_t) Value {
        const constant = prism.pm_constant_pool_id_to_constant(&self.parser.constant_pool, call_node.name);
        if (constant == null) {
            return Value.nil();
        }

        const method_name = constant.*.start[0..constant.*.length];

        if (std.mem.eql(u8, method_name, "puts")) {
            return self.evalPuts(call_node);
        }

        return Value.nil();
    }

    fn evalPuts(self: *Interpreter, call_node: *prism.pm_call_node_t) Value {
        if (call_node.arguments == null) {
            self.output_writer.write("\n");
            return Value.nil();
        }

        const args = @as(*prism.pm_arguments_node_t, @ptrCast(call_node.arguments));
        var i: usize = 0;
        while (i < args.arguments.size) : (i += 1) {
            const arg_value = self.eval(args.arguments.nodes[i]);
            switch (arg_value.data) {
                .string => |str| {
                    self.output_writer.write(str);
                    self.output_writer.write("\n");
                },
                .nil => {
                    self.output_writer.write("\n");
                },
            }
        }

        return Value.nil();
    }
};
