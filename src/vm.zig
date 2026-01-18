const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const compiler = @import("compiler.zig");
const value = @import("value.zig");
const prism = @import("prism.zig");

pub const CallFrame = struct {
    chunk: *chunk.Chunk,
    ip: usize,
    stack_base: usize,
    self_value: value.Value,
    locals: std.ArrayList(value.Value),
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,

    parser: prism.Parser,

    stack: std.ArrayList(value.Value),
    frames: std.ArrayList(CallFrame),

    constants: std.StringHashMap(value.Value),
    symbols: std.StringHashMap(void),

    program: *compiler.CompiledProgram,

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, parser: prism.Parser, program: *compiler.CompiledProgram) VM {
        var vm = VM{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .parser = parser,
            .stack = std.ArrayList(value.Value).initCapacity(allocator, 256) catch unreachable,
            .frames = std.ArrayList(CallFrame).initCapacity(allocator, 16) catch unreachable,
            .constants = std.StringHashMap(value.Value).init(allocator),
            .symbols = std.StringHashMap(void).init(allocator),
            .program = program,
        };

        // Create the Object class
        const object_class_val = value.Value.class(gc_allocator, "Object", null);
        vm.constants.put("Object", object_class_val) catch unreachable;

        // Transfer top-level method chunks from program to Object.methods
        // The chunk name is the method name
        const object_class_ptr = object_class_val.data.class;
        var iter = program.method_chunks.iterator();
        while (iter.next()) |entry| {
            const chunk_ptr = entry.value_ptr.*;
            object_class_ptr.methods.put(chunk_ptr.name, chunk_ptr) catch unreachable;
        }

        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();
        self.stack.deinit(self.allocator);
        // Deinit any remaining frames (shouldn't be any after normal execution)
        for (self.frames.items) |*frame| {
            frame.locals.deinit(self.allocator);
        }
        self.frames.deinit(self.allocator);
        self.constants.deinit();
        self.symbols.deinit();
    }

    pub fn run(self: *VM) !value.Value {
        try self.pushFrame(&self.program.main_chunk, value.Value.nil());

        while (self.frames.items.len > 0) {
            try self.executeInstruction();
        }

        if (self.stack.pop()) |val| {
            return val;
        }
        return value.Value.nil();
    }

    fn currentFrame(self: *VM) *CallFrame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn currentChunk(self: *VM) *chunk.Chunk {
        return self.currentFrame().chunk;
    }

    fn push(self: *VM, val: value.Value) !void {
        try self.stack.append(self.allocator, val);
    }

    fn pop(self: *VM) value.Value {
        return self.stack.pop() orelse value.Value.nil();
    }

    fn peek(self: *VM, distance: usize) value.Value {
        return self.stack.items[self.stack.items.len - 1 - distance];
    }

    fn readByte(self: *VM) u8 {
        const frame = self.currentFrame();
        const byte = bytecode.readU8(frame.chunk.code.items, frame.ip);
        frame.ip += 1;
        return byte;
    }

    fn readU16(self: *VM) u16 {
        const frame = self.currentFrame();
        const val = bytecode.readU16(frame.chunk.code.items, frame.ip);
        frame.ip += 2;
        return val;
    }

    fn readI16(self: *VM) i16 {
        const frame = self.currentFrame();
        const val = bytecode.readI16(frame.chunk.code.items, frame.ip);
        frame.ip += 2;
        return val;
    }

    fn pushFrame(self: *VM, ch: *chunk.Chunk, self_value: value.Value) !void {
        try self.frames.append(self.allocator, CallFrame{
            .chunk = ch,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .locals = std.ArrayList(value.Value).initCapacity(self.allocator, 32) catch unreachable,
        });
    }

    fn popFrame(self: *VM) !void {
        if (self.frames.items.len > 0) {
            var frame = self.frames.items[self.frames.items.len - 1];
            frame.locals.deinit(self.allocator);
            _ = self.frames.pop();
        }
    }

    fn executeInstruction(self: *VM) !void {
        const frame = self.currentFrame();
        if (frame.ip >= frame.chunk.code.items.len) {
            try self.popFrame();
            return;
        }

        const op = @as(bytecode.OpCode, @enumFromInt(self.readByte()));

        switch (op) {
            .PUSH_NIL => {
                try self.push(value.Value.nil());
            },

            .PUSH_TRUE => {
                try self.push(value.Value.boolean(true));
            },

            .PUSH_FALSE => {
                try self.push(value.Value.boolean(false));
            },

            .PUSH_INT => {
                const idx = self.readU16();
                const val = self.currentChunk().constants.items[idx];
                try self.push(val);
            },

            .PUSH_CONST => {
                const idx = self.readU16();
                const val = self.currentChunk().constants.items[idx];
                try self.push(val);
            },

            .GET_LOCAL => {
                const local_idx = self.readByte();
                const frame2 = self.currentFrame();
                const val = frame2.locals.items[local_idx];
                try self.push(val);
            },

            .SET_LOCAL => {
                const local_idx = self.readByte();
                const val = self.pop();
                var frame2 = self.currentFrame();

                // Expand locals array if needed
                while (frame2.locals.items.len <= local_idx) {
                    try frame2.locals.append(self.allocator, value.Value.nil());
                }
                frame2.locals.items[local_idx] = val;

                try self.push(val);
            },

            .GET_CONST => {
                const idx = self.readU16();
                const const_name = self.currentChunk().constants.items[idx];
                if (const_name.data == .string) {
                    if (self.constants.get(const_name.data.string)) |const_val| {
                        try self.push(const_val);
                    } else {
                        try self.push(value.Value.nil());
                    }
                } else {
                    try self.push(value.Value.nil());
                }
            },

            .SET_CONST => {
                const idx = self.readU16();
                const val = self.pop();
                const const_name = self.currentChunk().constants.items[idx];
                if (const_name.data == .string) {
                    try self.constants.put(const_name.data.string, val);
                }
                try self.push(val);
            },

            .PUSH_SELF => {
                const frame2 = self.currentFrame();
                try self.push(frame2.self_value);
            },

            .ADD => {
                const b = self.pop();
                const a = self.pop();

                if (a.data == .integer and b.data == .integer) {
                    const result = a.data.integer + b.data.integer;
                    try self.push(value.Value.integer(result));
                } else {
                    return error.TypeError;
                }
            },

            .SUB => {
                const b = self.pop();
                const a = self.pop();

                if (a.data == .integer and b.data == .integer) {
                    const result = a.data.integer - b.data.integer;
                    try self.push(value.Value.integer(result));
                } else {
                    return error.TypeError;
                }
            },

            .EQ => {
                const b = self.pop();
                const a = self.pop();

                const equal = self.valuesEqual(a, b);
                try self.push(value.Value.boolean(equal));
            },

            .JUMP => {
                const offset = self.readI16();
                var frame2 = self.currentFrame();
                frame2.ip = @intCast(@as(i32, @intCast(frame2.ip)) + offset);
            },

            .JUMP_IF_FALSE => {
                const offset = self.readI16();
                const cond = self.pop();

                const is_falsy = switch (cond.data) {
                    .nil => true,
                    .boolean => !cond.data.boolean,
                    else => false,
                };

                if (is_falsy) {
                    var frame2 = self.currentFrame();
                    frame2.ip = @intCast(@as(i32, @intCast(frame2.ip)) + offset);
                }
            },

            .POP => {
                _ = self.pop();
            },

            .CALL => {
                const method_idx = self.readU16();
                const argc = self.readByte();

                // Pop arguments
                var args: [256]value.Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    args[argc - 1 - i] = self.pop();
                }

                // Pop receiver
                const receiver = self.pop();

                try self.callMethod(method_idx, receiver, &args, argc);
            },

            .CALL_BUILTIN => {
                const builtin_id = self.readByte();
                const argc = self.readByte();

                // Pop arguments
                var args: [256]value.Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    args[argc - 1 - i] = self.pop();
                }

                // Pop receiver (for method calls)
                const receiver = self.pop();

                try self.callBuiltin(@as(bytecode.BuiltinId, @enumFromInt(builtin_id)), receiver, &args, argc);
            },

            .RETURN => {
                const result = self.pop();
                try self.popFrame();

                if (self.frames.items.len > 0) {
                    try self.push(result);
                } else {
                    try self.push(result);
                }
            },

            .DEF_MODULE => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                if (name_val.data == .string) {
                    const module_val = value.Value.module(self.gc_allocator, name_val.data.string);
                    try self.constants.put(name_val.data.string, module_val);
                    try self.push(module_val);
                } else {
                    return error.InvalidModuleName;
                }
            },

            .DEF_CLASS => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                if (name_val.data == .string) {
                    const class_val = value.Value.class(self.gc_allocator, name_val.data.string, null);
                    try self.constants.put(name_val.data.string, class_val);
                    try self.push(class_val);
                } else {
                    return error.InvalidClassName;
                }
            },

            .DEF_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const name_val = self.currentChunk().constants.items[name_idx];
                if (name_val.data != .string) {
                    return error.InvalidMethodName;
                }

                const method_name = name_val.data.string;

                // Look up the chunk by ID
                if (self.program.method_chunks.get(chunk_idx)) |chunk_ptr| {
                    // Get current self from the frame
                    const method_frame = self.currentFrame();
                    const current_self = method_frame.self_value;

                    if (current_self.data == .class) {
                        // Adding method to a class
                        try current_self.data.class.methods.put(method_name, chunk_ptr);
                    } else if (current_self.data == .module) {
                        // Adding method to a module
                        try current_self.data.module.methods.put(method_name, chunk_ptr);
                    } else {
                        // Top-level: add to Object (look it up from constants)
                        // TODO: we need `main` to clean this up a bit
                        if (self.constants.get("Object")) |object_val| {
                            if (object_val.data == .class) {
                                try object_val.data.class.methods.put(method_name, chunk_ptr);
                            } else {
                                return error.ObjectIsNotAClass;
                            }
                        } else {
                            return error.ObjectClassNotFound;
                        }
                    }
                } else {
                    std.debug.print("Error: undefined method chunk {d}\n", .{chunk_idx});
                    return error.UndefinedChunk;
                }
            },

            .HALT => {
                try self.popFrame();
            },
        }
    }

    fn valuesEqual(self: *VM, a: value.Value, b: value.Value) bool {
        _ = self;
        return switch (a.data) {
            .integer => switch (b.data) {
                .integer => a.data.integer == b.data.integer,
                else => false,
            },
            .boolean => switch (b.data) {
                .boolean => a.data.boolean == b.data.boolean,
                else => false,
            },
            .nil => switch (b.data) {
                .nil => true,
                else => false,
            },
            .string => switch (b.data) {
                .string => std.mem.eql(u8, a.data.string, b.data.string),
                else => false,
            },
            .symbol => switch (b.data) {
                .symbol => std.mem.eql(u8, a.data.symbol, b.data.symbol),
                else => false,
            },
            else => false,
        };
    }

    fn callMethod(self: *VM, method_idx: u16, receiver: value.Value, args: *[256]value.Value, argc: usize) !void {
        if (method_idx >= self.currentChunk().constants.items.len) {
            return error.InvalidMethodIndex;
        }

        const method_name_val = self.currentChunk().constants.items[method_idx];
        if (method_name_val.data != .string) {
            return error.InvalidMethodName;
        }

        const method_name = method_name_val.data.string;
        var method_chunk_ptr: ?*chunk.Chunk = null;

        // Try to find method in receiver's class first
        if (receiver.data == .instance) {
            const instance = receiver.data.instance;
            method_chunk_ptr = instance.class.methods.get(method_name);
        }

        // Fallback to Object class for top-level methods
        if (method_chunk_ptr == null) {
            if (self.constants.get("Object")) |object_val| {
                if (object_val.data == .class) {
                    method_chunk_ptr = object_val.data.class.methods.get(method_name);
                }
            }
        }

        if (method_chunk_ptr) |chunk_ptr| {
            // Push frame with receiver as self_value
            try self.pushFrame(chunk_ptr, receiver);

            // Copy arguments to locals
            const frame = self.currentFrame();
            var i: usize = 0;
            while (i < argc) : (i += 1) {
                try frame.locals.append(self.allocator, args[i]);
            }
        } else {
            std.debug.print("Error: undefined method '{s}'\n", .{method_name});
            return error.UndefinedMethod;
        }
    }

    fn callBuiltin(self: *VM, builtin_id: bytecode.BuiltinId, receiver: value.Value, args: *[256]value.Value, argc: usize) !void {
        switch (builtin_id) {
            .PUTS => {
                if (argc > 0) {
                    try self.printValue(args[0]);
                } else {
                    std.debug.print("\n", .{});
                }
                try self.push(value.Value.nil());
            },

            .NEW => {
                // receiver should be a class
                if (receiver.data == .class) {
                    const class_ptr = receiver.data.class;
                    const instance = value.Value.instance(self.gc_allocator, class_ptr);
                    try self.push(instance);
                } else {
                    std.debug.print("Error: cannot call new on non-class value\n", .{});
                    return error.TypeError;
                }
            },
        }
    }

    fn printValue(self: *VM, val: value.Value) !void {
        _ = self;
        switch (val.data) {
            .integer => {
                std.debug.print("{d}\n", .{val.data.integer});
            },
            .string => {
                std.debug.print("{s}\n", .{val.data.string});
            },
            .symbol => {
                std.debug.print(":{s}\n", .{val.data.symbol});
            },
            .boolean => {
                if (val.data.boolean) {
                    std.debug.print("true\n", .{});
                } else {
                    std.debug.print("false\n", .{});
                }
            },
            .nil => {
                std.debug.print("\n", .{});
            },
            .module => |m| {
                std.debug.print("{s}\n", .{m.name});
            },
            .class => |c| {
                std.debug.print("{s}\n", .{c.name});
            },
            .instance => |i| {
                std.debug.print("<{s} instance>\n", .{i.class.name});
            },
        }
    }
};
