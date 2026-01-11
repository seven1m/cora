const std = @import("std");
const Value = @import("value.zig").Value;
const ClassValue = @import("value.zig").ClassValue;
const InstanceValue = @import("value.zig").InstanceValue;
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

pub const CallFrame = struct {
    self: Value,
    locals: std.StringHashMap(Value),

    fn init(allocator: std.mem.Allocator, self_value: Value) CallFrame {
        return .{
            .self = self_value,
            .locals = std.StringHashMap(Value).init(allocator),
        };
    }

    fn deinit(self: *CallFrame) void {
        self.locals.deinit();
    }
};

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,
    parser: *prism.Parser,
    output_writer: OutputWriter,
    symbols: std.StringHashMap(void),
    constants: std.StringHashMap(Value),
    call_stack: std.ArrayList(CallFrame),

    const object_name = "Object";

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, parser: *prism.Parser) @This() {
        return initWithWriter(allocator, gc_allocator, parser, defaultOutputWriter());
    }

    pub fn initWithWriter(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, parser: *prism.Parser, output_writer: OutputWriter) @This() {
        const symbols = std.StringHashMap(void).init(allocator);
        var constants = std.StringHashMap(Value).init(allocator);
        var call_stack = std.ArrayList(CallFrame).initCapacity(allocator, 16) catch unreachable;

        const Object = Value.class(gc_allocator, object_name, null);
        constants.put(object_name, Object) catch unreachable;

        call_stack.append(allocator, CallFrame.init(allocator, Object)) catch unreachable;

        return .{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .parser = parser,
            .output_writer = output_writer,
            .symbols = symbols,
            .constants = constants,
            .call_stack = call_stack,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.symbols.deinit();

        while (self.call_stack.items.len > 0) {
            if (self.call_stack.pop()) |cf| {
                var call_frame = cf;
                call_frame.deinit();
            }
        }
        self.call_stack.deinit(self.allocator);

        var const_it = self.constants.valueIterator();
        while (const_it.next()) |value_ptr| {
            switch (value_ptr.data) {
                .module => {
                    value_ptr.data.module.methods.deinit();
                },
                .class => {
                    value_ptr.data.class.methods.deinit();
                },
                else => {},
            }
        }
        self.constants.deinit();
    }

    /// Get the current call frame
    fn frame(self: *Interpreter) *CallFrame {
        return &self.call_stack.items[self.call_stack.items.len - 1];
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
                const module = Value.module(self.gc_allocator, name);
                self.constants.put(name, module) catch unreachable;
                return module;
            },

            .class => |class_node| {
                const name = self.parser.getConstantName(class_node.name) catch unreachable;

                var superclass: ?*ClassValue = null;
                if (class_node.superclass) |superclass_ptr| {
                    const superclass_node = self.parser.asNode(superclass_ptr) catch unreachable;
                    const superclass_value = self.eval(superclass_node);
                    if (superclass_value.data == .class) {
                        superclass = superclass_value.data.class;
                    }
                } else {
                    // Default to Object if no superclass specified
                    if (!std.mem.eql(u8, name, object_name)) {
                        const object_value = self.constants.get(object_name);
                        if (object_value) |ov| {
                            if (ov.data == .class) {
                                superclass = ov.data.class;
                            }
                        }
                    }
                }

                const class_value = Value.class(self.gc_allocator, name, superclass);
                self.constants.put(name, class_value) catch unreachable;

                if (class_node.body) |body_ptr| {
                    self.call_stack.append(self.allocator, CallFrame.init(self.allocator, class_value)) catch unreachable;
                    defer {
                        if (self.call_stack.items.len > 0) {
                            if (self.call_stack.pop()) |cf| {
                                var call_frame = cf;
                                call_frame.deinit();
                            }
                        }
                    }

                    const body_node = self.parser.asNode(body_ptr) catch unreachable;
                    _ = self.eval(body_node);
                }

                return class_value;
            },

            .self => {
                return self.frame().self;
            },

            .def => |def_node| {
                const method_name = self.parser.getConstantName(def_node.name) catch unreachable;
                const current_self = self.frame().self;

                if (current_self.data == .class) {
                    current_self.data.class.methods.put(method_name, def_node) catch unreachable;
                } else {
                    // Top-level method on Object
                    const object_value = self.constants.get(object_name) orelse return Value.nil();
                    object_value.data.class.methods.put(method_name, def_node) catch unreachable;
                }
                return self.intern(method_name);
            },

            .local_variable_read => |var_node| {
                const var_name = self.parser.getLocalVariableName(var_node.name) catch unreachable;
                if (self.frame().locals.get(var_name)) |value| {
                    return value;
                }
                return Value.nil();
            },

            .local_variable_write => |var_node| {
                const var_name = self.parser.getLocalVariableName(var_node.name) catch unreachable;
                const value_node = self.parser.asNode(var_node.value) catch unreachable;
                const value = self.eval(value_node);
                self.frame().locals.put(var_name, value) catch unreachable;
                return value;
            },

            .required_parameter => {
                // This is just here to satisfy Zig. We shouldn't land here.
                unreachable;
            },

            .if_node => |if_node| {
                const predicate_node = self.parser.asNode(if_node.predicate) catch unreachable;
                const predicate_value = self.eval(predicate_node);

                const is_truthy = switch (predicate_value.data) {
                    .nil => false,
                    .boolean => predicate_value.data.boolean,
                    else => true,
                };

                if (is_truthy) {
                    if (if_node.statements) |statements_ptr| {
                        const statements_node = self.parser.asNode(@ptrCast(statements_ptr)) catch unreachable;
                        return self.eval(statements_node);
                    }
                    return Value.nil();
                } else {
                    if (if_node.subsequent) |subsequent_ptr| {
                        const subsequent_node = self.parser.asNode(@ptrCast(subsequent_ptr)) catch unreachable;
                        return self.eval(subsequent_node);
                    }
                    return Value.nil();
                }
            },

            .else_node => |else_node| {
                if (else_node.statements) |statements_ptr| {
                    const statements_node = self.parser.asNode(@ptrCast(statements_ptr)) catch unreachable;
                    return self.eval(statements_node);
                }
                return Value.nil();
            },

            .true_node => {
                return Value.boolean(true);
            },

            .false_node => {
                return Value.boolean(false);
            },

            .nil_node => {
                return Value.nil();
            },
        }
    }

    /// Look up a method in a class, walking the inheritance chain
    fn lookupMethod(_: *Interpreter, class: *const ClassValue, method_name: []const u8) ?*prism.DefNode {
        var current: ?*const ClassValue = class;
        while (current) |cls| {
            if (cls.methods.get(method_name)) |def_node| {
                return def_node;
            }
            current = cls.superclass;
        }
        return null;
    }

    /// Call a user-defined method with the given receiver
    fn callMethod(self: *Interpreter, receiver: Value, def_node: *prism.DefNode, call_node: *prism.CallNode) Value {
        var arg_values = std.ArrayList(Value).initCapacity(self.allocator, 8) catch unreachable;
        defer arg_values.deinit(self.allocator);

        if (call_node.arguments != null) {
            const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments));
            var arg_idx: usize = 0;
            while (arg_idx < args.arguments.size) : (arg_idx += 1) {
                const arg_node = self.parser.asNode(args.arguments.nodes[arg_idx]) catch unreachable;
                const arg_value = self.eval(arg_node);
                arg_values.appendAssumeCapacity(arg_value);
            }
        }

        // Push frame with receiver as self
        self.call_stack.append(self.allocator, CallFrame.init(self.allocator, receiver)) catch unreachable;
        defer {
            if (self.call_stack.items.len > 0) {
                if (self.call_stack.pop()) |cf| {
                    var call_frame = cf;
                    call_frame.deinit();
                }
            }
        }

        // Bind parameters to arguments
        if (def_node.parameters != null and arg_values.items.len > 0) {
            const params = @as(*prism.ParametersNode, @ptrCast(def_node.parameters));

            var param_idx: usize = 0;
            while (param_idx < params.requireds.size and param_idx < arg_values.items.len) : (param_idx += 1) {
                const param_node = self.parser.asNode(params.requireds.nodes[param_idx]) catch unreachable;
                const arg_value = arg_values.items[param_idx];

                if (param_node == .required_parameter) {
                    const param_name = self.parser.getLocalVariableName(param_node.required_parameter.name) catch unreachable;
                    self.frame().locals.put(param_name, arg_value) catch unreachable;
                }
            }
        }

        // Evaluate method body
        if (def_node.body) |body_ptr| {
            const body_node = self.parser.asNode(body_ptr) catch unreachable;
            return self.eval(body_node);
        }
        return Value.nil();
    }

    fn evalCall(self: *Interpreter, call_node: *prism.CallNode) Value {
        const method_name = self.parser.getConstantName(call_node.name) catch unreachable;

        if (std.mem.eql(u8, method_name, "puts")) {
            return self.evalPuts(call_node);
        }

        // Handle Class.new
        if (call_node.receiver != null and std.mem.eql(u8, method_name, "new")) {
            const receiver_node = self.parser.asNode(@ptrCast(call_node.receiver.?)) catch unreachable;
            const receiver_value = self.eval(receiver_node);

            if (receiver_value.data == .class) {
                const class_ptr = receiver_value.data.class;
                const instance_value = Value.instance(self.gc_allocator, class_ptr);

                // Look for initialize method and call it
                if (self.lookupMethod(class_ptr, "initialize")) |init_def| {
                    _ = self.callMethod(instance_value, init_def, call_node);
                }

                return instance_value;
            }
        }

        // FIXME: built-in binary functions... we'll move these later.
        if (call_node.receiver != null) {
            if (std.mem.eql(u8, method_name, "+")) {
                const receiver_node = self.parser.asNode(@ptrCast(call_node.receiver.?)) catch unreachable;
                const receiver_value = self.eval(receiver_node);

                if (call_node.arguments != null) {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments));
                    if (args.arguments.size > 0) {
                        const arg_node = self.parser.asNode(args.arguments.nodes[0]) catch unreachable;
                        const arg_value = self.eval(arg_node);

                        if (receiver_value.data == .integer and arg_value.data == .integer) {
                            return Value.integer(receiver_value.data.integer + arg_value.data.integer);
                        }
                    }
                }
            }

            if (std.mem.eql(u8, method_name, "-")) {
                const receiver_node = self.parser.asNode(@ptrCast(call_node.receiver.?)) catch unreachable;
                const receiver_value = self.eval(receiver_node);

                if (call_node.arguments != null) {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments));
                    if (args.arguments.size > 0) {
                        const arg_node = self.parser.asNode(args.arguments.nodes[0]) catch unreachable;
                        const arg_value = self.eval(arg_node);

                        if (receiver_value.data == .integer and arg_value.data == .integer) {
                            return Value.integer(receiver_value.data.integer - arg_value.data.integer);
                        }
                    }
                }
            }

            if (std.mem.eql(u8, method_name, "==")) {
                const receiver_node = self.parser.asNode(@ptrCast(call_node.receiver.?)) catch unreachable;
                const receiver_value = self.eval(receiver_node);

                if (call_node.arguments != null) {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments));
                    if (args.arguments.size > 0) {
                        const arg_node = self.parser.asNode(args.arguments.nodes[0]) catch unreachable;
                        const arg_value = self.eval(arg_node);

                        if (receiver_value.data == .integer and arg_value.data == .integer) {
                            return Value.boolean(receiver_value.data.integer == arg_value.data.integer);
                        }
                    }
                }
            }
        }

        // Handle instance method dispatch
        if (call_node.receiver != null) {
            const receiver_node = self.parser.asNode(@ptrCast(call_node.receiver.?)) catch unreachable;
            const receiver_value = self.eval(receiver_node);

            if (receiver_value.data == .instance) {
                const instance_ptr = receiver_value.data.instance;
                if (self.lookupMethod(instance_ptr.class, method_name)) |def_node| {
                    return self.callMethod(receiver_value, def_node, call_node);
                }
            }
        }

        const object_value = self.constants.get(object_name) orelse return Value.nil();
        if (object_value.data.class.methods.get(method_name)) |def_node| {
            return self.callMethod(self.frame().self, def_node, call_node);
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
                .boolean => |b| {
                    if (b) {
                        self.output_writer.write("true");
                    } else {
                        self.output_writer.write("false");
                    }
                    self.output_writer.write("\n");
                },
                .module => |mod| {
                    self.output_writer.write(mod.name);
                    self.output_writer.write("\n");
                },
                .class => |cls| {
                    self.output_writer.write(cls.name);
                    self.output_writer.write("\n");
                },
                .instance => |inst| {
                    self.output_writer.write("#<");
                    self.output_writer.write(inst.class.name);
                    self.output_writer.write(":0x");
                    var buffer: [32]u8 = undefined;
                    const addr = @intFromPtr(inst);
                    const hex_str = std.fmt.bufPrint(&buffer, "{x}", .{addr}) catch unreachable;
                    self.output_writer.write(hex_str);
                    self.output_writer.write(">\n");
                },
                .nil => {
                    self.output_writer.write("\n");
                },
            }
        }

        return Value.nil();
    }
};
