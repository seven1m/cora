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
    symbols: std.StringHashMap(void),
    constants: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator, parser: *prism.pm_parser_t) @This() {
        return initWithWriter(allocator, parser, defaultOutputWriter());
    }

    pub fn initWithWriter(allocator: std.mem.Allocator, parser: *prism.pm_parser_t, output_writer: OutputWriter) @This() {
        return .{
            .allocator = allocator,
            .parser = parser,
            .output_writer = output_writer,
            .symbols = std.StringHashMap(void).init(allocator),
            .constants = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Interpreter) void {
        var it = self.symbols.keyIterator();
        while (it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.symbols.deinit();

        var const_it = self.constants.keyIterator();
        while (const_it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.constants.deinit();
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

        if (node_type == prism.PM_INTEGER_NODE) {
            const int_node = @as(*prism.pm_integer_node_t, @ptrCast(node));
            const int_value = int_node.value;
            var result: i64 = @intCast(int_value.value);
            if (int_value.negative) {
                result = -result;
            }
            return Value.integer(result);
        }

        if (node_type == prism.PM_SYMBOL_NODE) {
            const symbol_node = @as(*prism.pm_symbol_node_t, @ptrCast(node));
            const symbol_str = symbol_node.unescaped.source[0..symbol_node.unescaped.length];

            if (self.symbols.getEntry(symbol_str)) |entry| {
                return Value.symbol(entry.key_ptr.*);
            }

            const interned = self.allocator.dupe(u8, symbol_str) catch "";
            self.symbols.put(interned, {}) catch {};
            return Value.symbol(interned);
        }

        if (node_type == prism.PM_CONSTANT_READ_NODE) {
            const const_read_node = @as(*prism.pm_constant_read_node_t, @ptrCast(node));
            const constant = prism.pm_constant_pool_id_to_constant(&self.parser.constant_pool, const_read_node.name);
            if (constant == null) {
                return Value.nil();
            }
            const name = constant.*.start[0..constant.*.length];
            if (self.constants.get(name)) |value| {
                return value;
            }
            return Value.nil();
        }

        if (node_type == prism.PM_CONSTANT_WRITE_NODE) {
            const const_write_node = @as(*prism.pm_constant_write_node_t, @ptrCast(node));
            const constant = prism.pm_constant_pool_id_to_constant(&self.parser.constant_pool, const_write_node.name);
            if (constant == null) {
                return Value.nil();
            }
            const name = constant.*.start[0..constant.*.length];
            const interned = self.allocator.dupe(u8, name) catch "";
            const value = self.eval(const_write_node.value);
            self.constants.put(interned, value) catch {};
            return value;
        }

        if (node_type == prism.PM_CALL_NODE) {
            return self.evalCall(@ptrCast(node));
        }

        std.debug.panic("node_type {d} unhandled", .{node_type});
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
                .integer => |int| {
                    var buffer: [64]u8 = undefined;
                    const int_str = std.fmt.bufPrint(&buffer, "{d}", .{int}) catch "";
                    self.output_writer.write(int_str);
                    self.output_writer.write("\n");
                },
                .symbol => |sym| {
                    self.output_writer.write(sym);
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
