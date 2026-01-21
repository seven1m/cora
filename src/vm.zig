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
    locals: [32]value.Value = undefined,
    locals_len: u8 = 0,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,

    parser: prism.Parser,

    stack: std.ArrayList(value.Value),
    frames: std.ArrayList(CallFrame),

    symbols: std.StringHashMap(value.Value),

    program: *compiler.CompiledProgram,

    object_class: *value.ClassValue,

    pub fn intern(self: *VM, str: []const u8) !value.Value {
        // Check if already interned
        if (self.symbols.get(str)) |symbol_val| {
            return symbol_val; // Return the cached symbol Value
        }

        // Create a symbol Value and store it
        const symbol_val = value.Value.symbol(self.gc_allocator, str);
        try self.symbols.put(str, symbol_val);

        return symbol_val;
    }

    pub fn initEmpty(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, parser: prism.Parser) VM {
        return VM{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .parser = parser,
            .stack = std.ArrayList(value.Value).initCapacity(allocator, 256) catch unreachable,
            .frames = std.ArrayList(CallFrame).initCapacity(allocator, 16) catch unreachable,
            .symbols = std.StringHashMap(value.Value).init(allocator),
            .program = undefined,
            .object_class = undefined,
        };
    }

    pub fn prepare(self: *VM, program: *compiler.CompiledProgram) !void {
        self.program = program;

        // Create Object class with interned name
        const object_name_val = try self.intern("Object");
        const object_name_sym = object_name_val.data.symbol;
        const object_class_val = value.Value.class(self.gc_allocator, object_name_sym, null);
        const object_class_ptr = object_class_val.data.class;
        self.object_class = object_class_ptr;
        try object_class_ptr.module.constants.put(object_name_sym, object_class_val);

        // Transfer method chunks to Object class
        var iter = program.method_chunks.iterator();
        while (iter.next()) |entry| {
            const chunk_ptr = entry.value_ptr.*;
            // chunk_ptr.name is an AST-borrowed slice
            const name_sym = (try self.intern(chunk_ptr.name)).data.symbol;
            try object_class_ptr.module.methods.put(name_sym, chunk_ptr);
        }
    }

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, parser: prism.Parser, program: *compiler.CompiledProgram) VM {
        var vm = initEmpty(allocator, gc_allocator, parser);
        vm.prepare(program) catch unreachable;
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();
        self.stack.deinit(self.allocator);
        self.frames.deinit(self.allocator);
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

    fn constantToValue(self: *VM, constant: chunk.Constant) !value.Value {
        return switch (constant) {
            .integer => |i| value.Value.integer(i),
            .string => |s| value.Value.frozenString(s),
            .symbol => |s| try self.intern(s),
        };
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
        });
    }

    fn popFrame(self: *VM) !void {
        if (self.frames.items.len > 0) {
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
                const constant = self.currentChunk().constants.items[idx];
                const val = try self.constantToValue(constant);
                try self.push(val);
            },

            .PUSH_CONST => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                const val = try self.constantToValue(constant);
                try self.push(val);
            },

            .GET_LOCAL => {
                const local_idx = self.readByte();
                const frame2 = self.currentFrame();
                const val = frame2.locals[local_idx];
                try self.push(val);
            },

            .SET_LOCAL => {
                const local_idx = self.readByte();
                const val = self.pop();
                var frame2 = self.currentFrame();

                frame2.locals[local_idx] = val;
                if (local_idx >= frame2.locals_len) {
                    frame2.locals_len = local_idx + 1;
                }
                try self.push(val);
            },

            .GET_CONST => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                // TODO: this should be a symbol I think
                if (constant == .string) {
                    const name_sym = (try self.intern(constant.string)).data.symbol;
                    if (self.object_class.module.constants.get(name_sym)) |const_val| {
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
                const constant = self.currentChunk().constants.items[idx];
                // TODO: this should be a symbol I think
                if (constant == .string) {
                    const name_sym = (try self.intern(constant.string)).data.symbol;
                    try self.object_class.module.constants.put(name_sym, val);
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
                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = (try self.intern(constant.string)).data.symbol;
                    const module_val = value.Value.module(self.gc_allocator, name_sym);
                    try self.object_class.module.constants.put(name_sym, module_val);
                    try self.push(module_val);
                } else {
                    return error.InvalidModuleName;
                }
            },

            .DEF_CLASS => {
                const name_idx = self.readU16();
                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = (try self.intern(constant.string)).data.symbol;
                    const class_val = value.Value.class(self.gc_allocator, name_sym, null);
                    try self.object_class.module.constants.put(name_sym, class_val);
                    try self.push(class_val);
                } else {
                    return error.InvalidClassName;
                }
            },

            .DEF_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant != .string) {
                    return error.InvalidMethodName;
                }

                const method_name = constant.string;
                const method_name_sym = (try self.intern(method_name)).data.symbol;

                // Look up the chunk by ID
                if (self.program.method_chunks.get(chunk_idx)) |chunk_ptr| {
                    // Get current self from the frame
                    const method_frame = self.currentFrame();
                    const current_self = method_frame.self_value;

                    if (current_self.data == .class) {
                        // Adding method to a class
                        try current_self.data.class.module.methods.put(method_name_sym, chunk_ptr);
                    } else if (current_self.data == .module) {
                        // Adding method to a module
                        try current_self.data.module.methods.put(method_name_sym, chunk_ptr);
                    } else {
                        // Top-level: add to Object (look it up from constants)
                        // TODO: we need `main` to clean this up a bit
                        try self.object_class.module.methods.put(method_name_sym, chunk_ptr);
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
                .symbol => a.data.symbol == b.data.symbol,
                else => false,
            },
            else => false,
        };
    }

    fn callMethod(self: *VM, method_idx: u16, receiver: value.Value, args: *[256]value.Value, argc: usize) !void {
        if (method_idx >= self.currentChunk().constants.items.len) {
            return error.InvalidMethodIndex;
        }

        const constant = self.currentChunk().constants.items[method_idx];
        if (constant != .string) {
            return error.InvalidMethodName;
        }

        // TODO: method name should be a symbol
        const method_name = constant.string;
        const method_name_sym = (try self.intern(method_name)).data.symbol;
        var method_chunk_ptr: ?*chunk.Chunk = null;

        // Try to find method in receiver's class first
        if (receiver.data == .instance) {
            const instance = receiver.data.instance;
            method_chunk_ptr = instance.class.module.methods.get(method_name_sym);
        }

        // Fallback to Object class for top-level methods
        if (method_chunk_ptr == null) {
            method_chunk_ptr = self.object_class.module.methods.get(method_name_sym);
        }

        if (method_chunk_ptr) |chunk_ptr| {
            // Push frame with receiver as self_value
            try self.pushFrame(chunk_ptr, receiver);

            // Copy arguments to locals
            var frame = self.currentFrame();
            var i: usize = 0;
            while (i < argc) : (i += 1) {
                frame.locals[i] = args[i];
                frame.locals_len += 1;
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
                std.debug.print(":{s}\n", .{val.data.symbol.name});
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
                std.debug.print("{s}\n", .{m.name.name});
            },
            .class => |c| {
                std.debug.print("{s}\n", .{c.module.name.name});
            },
            .instance => |i| {
                std.debug.print("<{s} instance>\n", .{i.class.module.name.name});
            },
        }
    }
};
