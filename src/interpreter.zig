const std = @import("std");
const Value = @import("value.zig").Value;
const prism = @import("prism.zig");

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
    parser: *prism.Parser,
    output_writer: OutputWriter,
    symbols: std.StringHashMap(void),
    constants: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator, parser: *prism.Parser) @This() {
        return initWithWriter(allocator, parser, defaultOutputWriter());
    }

    pub fn initWithWriter(allocator: std.mem.Allocator, parser: *prism.Parser, output_writer: OutputWriter) @This() {
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

    pub fn eval(self: *Interpreter, node: prism.Node) Value {
        switch (node) {
            .program => |program| {
                if (program.statements != null) {
                    if (self.parser.asNode(@ptrCast(program.statements))) |stmt_node| {
                        return self.eval(stmt_node);
                    }
                }
                return Value.nil();
            },

            .statements => |statements| {
                var result: Value = Value.nil();
                var i: usize = 0;
                while (i < statements.body.size) : (i += 1) {
                    if (self.parser.asNode(statements.body.nodes[i])) |stmt_node| {
                        result = self.eval(stmt_node);
                    }
                }
                return result;
            },

            .string => |string_node| {
                const str = string_node.unescaped;
                return Value.frozenString(str.source[0..str.length]);
            },

            .integer => |int_node| {
                const int_value = int_node.value;
                var result: i64 = @intCast(int_value.value);
                if (int_value.negative) {
                    result = -result;
                }
                return Value.integer(result);
            },

            .symbol => |symbol_node| {
                const symbol_str = symbol_node.unescaped.source[0..symbol_node.unescaped.length];

                if (self.symbols.getEntry(symbol_str)) |entry| {
                    return Value.symbol(entry.key_ptr.*);
                }

                const interned = self.allocator.dupe(u8, symbol_str) catch "";
                self.symbols.put(interned, {}) catch {};
                return Value.symbol(interned);
            },

            .constant_read => |const_read_node| {
                const name = self.parser.getConstantName(const_read_node.name) orelse {
                    return Value.nil();
                };
                if (self.constants.get(name)) |value| {
                    return value;
                }
                return Value.nil();
            },

            .constant_write => |const_write_node| {
                const name = self.parser.getConstantName(const_write_node.name) orelse {
                    return Value.nil();
                };
                const interned = self.allocator.dupe(u8, name) catch "";
                if (self.parser.asNode(const_write_node.value)) |val_node| {
                    const value = self.eval(val_node);
                    self.constants.put(interned, value) catch {};
                    return value;
                }
                return Value.nil();
            },

            .call => |call_node| {
                return self.evalCall(call_node);
            },
        }
    }

    fn evalCall(self: *Interpreter, call_node: *prism.CallNode) Value {
        const method_name = self.parser.getConstantName(call_node.name) orelse {
            return Value.nil();
        };

        if (std.mem.eql(u8, method_name, "puts")) {
            return self.evalPuts(call_node);
        }

        return Value.nil();
    }

    fn evalPuts(self: *Interpreter, call_node: *prism.CallNode) Value {
        if (call_node.arguments == null) {
            self.output_writer.write("\n");
            return Value.nil();
        }

        const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments));
        var i: usize = 0;
        while (i < args.arguments.size) : (i += 1) {
            if (self.parser.asNode(args.arguments.nodes[i])) |arg_node| {
                const arg_value = self.eval(arg_node);
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
        }

        return Value.nil();
    }
};
