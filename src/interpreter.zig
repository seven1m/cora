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

    const object_name = "Object";

    pub fn init(allocator: std.mem.Allocator, parser: *prism.Parser) @This() {
        return initWithWriter(allocator, parser, defaultOutputWriter());
    }

    pub fn initWithWriter(allocator: std.mem.Allocator, parser: *prism.Parser, output_writer: OutputWriter) @This() {
        const symbols = std.StringHashMap(void).init(allocator);
        var constants = std.StringHashMap(Value).init(allocator);

        const Object = Value.module(allocator, object_name); // a module for now, until we get classes
        constants.put(object_name, Object) catch unreachable;

        return .{
            .allocator = allocator,
            .parser = parser,
            .output_writer = output_writer,
            .symbols = symbols,
            .constants = constants,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        // var it = self.symbols.keyIterator();
        // while (it.next()) |key_ptr| {
        //     self.allocator.free(key_ptr.*);
        // }
        self.symbols.deinit();

        // var const_it = self.constants.keyIterator();
        // while (const_it.next()) |key_ptr| {
        //     self.allocator.free(key_ptr.*);
        // }
        var const_it = self.constants.valueIterator();
        while (const_it.next()) |value_ptr| {
            if (value_ptr.data == .module) {
                value_ptr.data.module.methods.deinit();
                self.allocator.destroy(value_ptr.data.module);
            }
        }
        self.constants.deinit();
    }

    /// Intern a symbol: look it up by name and return it, or create a new one.
    /// The name slice should come from long-lived memory (e.g. AST) and won't be duplicated.
    pub fn intern(self: *Interpreter, name: []const u8) Value {
        if (self.symbols.getEntry(name)) |entry| {
            return Value.symbol(entry.key_ptr.*);
        }
        self.symbols.put(name, {}) catch unreachable;
        return Value.symbol(name);
    }

    pub fn eval(self: *Interpreter, node: prism.Node) Value {
        switch (node) {
            .program => |program| {
                if (program.statements != null) {
                    const stmt_node = self.parser.asNode(@ptrCast(program.statements)) catch unreachable;
                    return self.eval(stmt_node);
                }
                return Value.nil();
            },

            .statements => |statements| {
                var result: Value = Value.nil();
                var i: usize = 0;
                while (i < statements.body.size) : (i += 1) {
                    const stmt_node = self.parser.asNode(statements.body.nodes[i]) catch unreachable;
                    result = self.eval(stmt_node);
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
                return self.intern(symbol_str);
            },

            .constant_read => |const_read_node| {
                const name = self.parser.getConstantName(const_read_node.name) catch unreachable;
                if (self.constants.get(name)) |value| {
                    return value;
                }
                return Value.nil();
            },

            .constant_write => |const_write_node| {
                const name = self.parser.getConstantName(const_write_node.name) catch unreachable;
                const val_node = self.parser.asNode(const_write_node.value) catch unreachable;
                const value = self.eval(val_node);
                self.constants.put(name, value) catch unreachable;
                return value;
            },

            .call => |call_node| {
                return self.evalCall(call_node);
            },

            .module => |module_node| {
                const name = self.parser.getConstantName(module_node.name) catch unreachable;
                const module = Value.module(self.allocator, name);
                self.constants.put(name, module) catch unreachable;
                return module;
            },

            .def => |def_node| {
                const method_name = self.parser.getConstantName(def_node.name) catch unreachable;
                const object_value = self.constants.get(object_name) orelse return Value.nil();
                object_value.data.module.methods.put(method_name, def_node) catch unreachable;
                return self.intern(method_name);
            },
        }
    }

    fn evalCall(self: *Interpreter, call_node: *prism.CallNode) Value {
        const method_name = self.parser.getConstantName(call_node.name) catch unreachable;

        if (std.mem.eql(u8, method_name, "puts")) {
            return self.evalPuts(call_node);
        }

        // Check if this is a user-defined method
        const object_value = self.constants.get(object_name) orelse return Value.nil();
        if (object_value.data.module.methods.get(method_name)) |def_node| {
            // Execute the method body
            if (def_node.body) |body_ptr| {
                const body_node = self.parser.asNode(body_ptr) catch unreachable;
                return self.eval(body_node);
            }
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
            const arg_node = self.parser.asNode(args.arguments.nodes[i]) catch unreachable;
            const arg_value = self.eval(arg_node);
            switch (arg_value.data) {
                .string => |str| {
                    self.output_writer.write(str);
                    self.output_writer.write("\n");
                },
                .integer => |int| {
                    var buffer: [64]u8 = undefined;
                    const int_str = std.fmt.bufPrint(&buffer, "{d}", .{int}) catch unreachable;
                    self.output_writer.write(int_str);
                    self.output_writer.write("\n");
                },
                .symbol => |sym| {
                    self.output_writer.write(sym);
                    self.output_writer.write("\n");
                },
                .module => |mod| {
                    self.output_writer.write(mod.name);
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
