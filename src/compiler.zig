const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const prism = @import("prism.zig");
const value = @import("value.zig");

pub const CompiledProgram = struct {
    allocator: std.mem.Allocator,
    main_chunk: chunk.Chunk,
    method_chunks: std.AutoHashMap(u16, *chunk.Chunk),

    pub fn deinit(self: *CompiledProgram) void {
        self.main_chunk.deinit();
        var iter = self.method_chunks.iterator();
        while (iter.next()) |entry| {
            // Free the method chunk contents
            entry.value_ptr.*.deinit();
            // Free the chunk struct itself (allocated on heap)
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.method_chunks.deinit();
    }
};

const Local = struct {
    name: []const u8,
    depth: usize,
};

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    parser: *prism.Parser,

    current_chunk: *chunk.Chunk,
    locals: std.ArrayList(Local) = .empty,
    scope_depth: usize = 0,

    method_chunks: std.AutoHashMap(u16, *chunk.Chunk),
    chunk_counter: u16 = 1,

    pub fn init(allocator: std.mem.Allocator, parser: *prism.Parser) Compiler {
        return Compiler{
            .allocator = allocator,
            .parser = parser,
            .current_chunk = undefined,
            .method_chunks = std.AutoHashMap(u16, *chunk.Chunk).init(allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.locals.deinit(self.allocator);
        // self.method_chunks is transferred to CompiledProgram.
    }

    pub fn compile(allocator: std.mem.Allocator, parser: *prism.Parser) !CompiledProgram {
        var compiler = Compiler.init(allocator, parser);
        defer compiler.deinit();

        var main_chunk = chunk.Chunk.init(allocator, "main");
        compiler.current_chunk = &main_chunk;

        const root = try parser.root();
        try compiler.compileNode(root, 0);
        try compiler.current_chunk.emitOp(.HALT, 0);

        return CompiledProgram{
            .allocator = allocator,
            .main_chunk = main_chunk,
            .method_chunks = compiler.method_chunks,
        };
    }

    fn compileNode(self: *Compiler, node: prism.Node, line: u32) anyerror!void {
        switch (node) {
            .program => |program_node| {
                if (program_node.statements != null) {
                    const body = try self.parser.asNode(@ptrCast(program_node.statements));
                    try self.compileNode(body, line);
                }
            },

            .statements => |statements_node| {
                var i: usize = 0;
                while (i < statements_node.body.size) : (i += 1) {
                    const child = statements_node.body.nodes[i];
                    const child_node = try self.parser.asNode(child);
                    try self.compileNode(child_node, line);

                    // Pop the result of each statement except the last
                    if (i < statements_node.body.size - 1) {
                        try self.current_chunk.emitOp(.POP, line);
                    }
                }
            },

            .integer => |int_node| {
                var int_val: i64 = @intCast(int_node.value.value);
                if (int_node.value.negative) {
                    int_val = -int_val;
                }
                const idx = try self.current_chunk.addConstant(.{ .integer = int_val });
                try self.current_chunk.emitOpU16(.PUSH_INT, @intCast(idx), line);
            },

            .string => |string_node| {
                const str_val = string_node.unescaped;
                const str_slice = str_val.source[0..str_val.length];
                const idx = try self.current_chunk.addConstant(.{ .string = str_slice });
                try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
            },

            .symbol => |symbol_node| {
                const symbol_val = symbol_node.unescaped;
                const symbol_slice = symbol_val.source[0..symbol_val.length];
                const idx = try self.current_chunk.addConstant(.{ .symbol = symbol_slice });
                try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
            },

            .true_node => {
                try self.current_chunk.emitOp(.PUSH_TRUE, line);
            },

            .false_node => {
                try self.current_chunk.emitOp(.PUSH_FALSE, line);
            },

            .nil_node => {
                try self.current_chunk.emitOp(.PUSH_NIL, line);
            },

            .self => {
                try self.current_chunk.emitOp(.PUSH_SELF, line);
            },

            .local_variable_read => |var_read| {
                const var_name = try self.parser.getLocalVariableName(var_read.name);
                const local_idx = self.findLocal(var_name);
                if (local_idx) |idx| {
                    try self.current_chunk.emitOpU8(.GET_LOCAL, idx, line);
                } else {
                    std.debug.print("Error: undefined local variable '{s}'\n", .{var_name});
                    return error.UndefinedVariable;
                }
            },

            .local_variable_write => |var_write| {
                const var_name = try self.parser.getLocalVariableName(var_write.name);
                const value_node = try self.parser.asNode(@ptrCast(var_write.value));
                try self.compileNode(value_node, line);

                const local_idx = self.findLocal(var_name);
                if (local_idx) |idx| {
                    try self.current_chunk.emitOpU8(.SET_LOCAL, idx, line);
                } else {
                    // Create new local variable
                    try self.addLocal(var_name);
                    const idx = @as(u8, @intCast(self.locals.items.len - 1));
                    try self.current_chunk.emitOpU8(.SET_LOCAL, idx, line);
                }
            },

            .constant_read => |const_read| {
                const const_name = try self.parser.getConstantName(const_read.name);
                const idx = try self.current_chunk.addConstant(.{ .string = const_name });
                try self.current_chunk.emitOpU16(.GET_CONST, @intCast(idx), line);
            },

            .constant_write => |const_write| {
                const const_name = try self.parser.getConstantName(const_write.name);
                const value_node = try self.parser.asNode(@ptrCast(const_write.value));
                try self.compileNode(value_node, line);

                const idx = try self.current_chunk.addConstant(.{ .string = const_name });
                try self.current_chunk.emitOpU16(.SET_CONST, @intCast(idx), line);
            },

            .call => |call_node| {
                // Compile receiver if it exists
                if (call_node.receiver != null) {
                    const receiver = try self.parser.asNode(@ptrCast(call_node.receiver.?));
                    try self.compileNode(receiver, line);
                } else {
                    // Self is implicit receiver
                    try self.current_chunk.emitOp(.PUSH_SELF, line);
                }

                // Compile arguments
                var argc: u8 = 0;
                if (call_node.arguments != null) {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments.?));
                    var i: usize = 0;
                    while (i < args.arguments.size) : (i += 1) {
                        const arg = args.arguments.nodes[i];
                        const arg_node = try self.parser.asNode(arg);
                        try self.compileNode(arg_node, line);
                        argc += 1;
                    }
                }

                // Store method name and emit CALL
                const method_name = try self.parser.getConstantName(call_node.name);
                const method_idx = try self.current_chunk.addConstant(.{ .string = method_name });
                try self.current_chunk.emitOpU16U8(.CALL, @intCast(method_idx), argc, line);
            },

            .if_node => |if_node| {
                try self.compileIfStatement(if_node, line);
            },

            .module => |module_node| {
                try self.compileModule(module_node, line);
            },

            .class => |class_node| {
                try self.compileClass(class_node, line);
            },

            .def => |def_node| {
                try self.compileMethod(def_node, line);
            },

            .else_node => |else_node| {
                // Compile the statements in the else block
                if (else_node.statements) |statements_ptr| {
                    const statements_node = try self.parser.asNode(@ptrCast(statements_ptr));
                    try self.compileNode(statements_node, line);
                } else {
                    // No statements in else block, push nil
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }
            },

            .array => |array_node| {
                // Compile array elements in reverse order
                // (so they're in correct order when popped from stack)
                const element_count: u8 = @intCast(array_node.elements.size);
                var i: i32 = @intCast(array_node.elements.size);
                while (i > 0) : (i -= 1) {
                    const elem = array_node.elements.nodes[@intCast(i - 1)];
                    const elem_node = try self.parser.asNode(elem);
                    try self.compileNode(elem_node, line);
                }
                // Emit PUSH_ARRAY with element count
                try self.current_chunk.emitOpU8(.PUSH_ARRAY, element_count, line);
            },

            else => {
                std.debug.print("Error: unsupported node type\n", .{});
                return error.UnsupportedNode;
            },
        }
    }

    fn compileIfStatement(self: *Compiler, if_node: *prism.IfNode, line: u32) anyerror!void {
        // Compile condition
        const condition = try self.parser.asNode(@ptrCast(if_node.predicate));
        try self.compileNode(condition, line);

        // Jump if false (to the else/false case)
        const jump_false = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);

        // Compile then branch
        if (if_node.statements != null) {
            const then_branch = try self.parser.asNode(@ptrCast(if_node.statements));
            try self.compileNode(then_branch, line);
        } else {
            // If no then-branch, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Jump to end (skip the false/else case)
        const jump_end = try self.current_chunk.emitJump(.JUMP, line);

        // Patch the false jump to here (this is where the false branch starts)
        try self.current_chunk.patchJump(jump_false);

        // Compile subsequent (elsif or else), or push nil for when condition is false
        if (if_node.subsequent) |subsequent_ptr| {
            const subsequent_node = try self.parser.asNode(subsequent_ptr);
            try self.compileNode(subsequent_node, line);
        } else {
            // No else branch - when condition is false, evaluate to nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Patch the end jump
        try self.current_chunk.patchJump(jump_end);
    }

    fn compileModule(self: *Compiler, module_node: *prism.ModuleNode, line: u32) anyerror!void {
        // Get the module name
        const module_name = try self.parser.getConstantName(module_node.name);

        // Add the module name as a constant
        const idx = try self.current_chunk.addConstant(.{ .string = module_name });

        // Create a separate chunk for the module body
        var body_chunk_id: u8 = 0;
        if (module_node.body) |body_ptr| {
            // Allocate chunk on heap
            const body_chunk_ptr = try self.allocator.create(chunk.Chunk);
            body_chunk_ptr.* = chunk.Chunk.init(self.allocator, module_name);

            // Save the current chunk and switch to the body chunk
            const saved_chunk = self.current_chunk;
            self.current_chunk = body_chunk_ptr;

            // Compile the module body (method definitions, etc.)
            const body_node = try self.parser.asNode(@ptrCast(body_ptr));
            try self.compileNode(body_node, line);

            // Pop the last statement's result (we don't need it)
            try self.current_chunk.emitOp(.POP, line);
            // Return self (the module) as the result
            try self.current_chunk.emitOp(.PUSH_SELF, line);
            try self.current_chunk.emitOp(.RETURN, line);

            // Store the chunk and get its ID
            body_chunk_id = @intCast(self.chunk_counter);
            body_chunk_ptr.chunk_id = body_chunk_id;
            self.chunk_counter += 1;
            try self.method_chunks.put(body_chunk_id, body_chunk_ptr);

            // Restore the original chunk
            self.current_chunk = saved_chunk;
        }

        // Emit DEF_MODULE instruction with the body chunk ID
        try self.current_chunk.emitOpU16U8(.DEF_MODULE, @intCast(idx), body_chunk_id, line);
    }

    fn compileClass(self: *Compiler, class_node: *prism.ClassNode, line: u32) anyerror!void {
        // Get the class name
        const class_name = try self.parser.getConstantName(class_node.name);

        // Add the class name as a constant
        const idx = try self.current_chunk.addConstant(.{ .string = class_name });

        // If there's a superclass, compile code to look it up
        if (class_node.superclass) |superclass_ptr| {
            const superclass_node = try self.parser.asNode(@ptrCast(superclass_ptr));
            try self.compileNode(superclass_node, line);
        } else {
            // No superclass, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Create a separate chunk for the class body
        var body_chunk_id: u8 = 0;
        if (class_node.body) |body_ptr| {
            // Allocate chunk on heap
            const body_chunk_ptr = try self.allocator.create(chunk.Chunk);
            body_chunk_ptr.* = chunk.Chunk.init(self.allocator, class_name);

            // Save the current chunk and switch to the body chunk
            const saved_chunk = self.current_chunk;
            self.current_chunk = body_chunk_ptr;

            // Compile the class body (method definitions, etc.)
            const body_node = try self.parser.asNode(@ptrCast(body_ptr));
            try self.compileNode(body_node, line);

            // Pop the last statement's result (we don't need it)
            try self.current_chunk.emitOp(.POP, line);
            // Return self (the class) as the result
            try self.current_chunk.emitOp(.PUSH_SELF, line);
            try self.current_chunk.emitOp(.RETURN, line);


            // Store the chunk and get its ID
            body_chunk_id = @intCast(self.chunk_counter);
            body_chunk_ptr.chunk_id = body_chunk_id;
            self.chunk_counter += 1;
            try self.method_chunks.put(body_chunk_id, body_chunk_ptr);

            // Restore the original chunk
            self.current_chunk = saved_chunk;
        }

        // Emit DEF_CLASS instruction with the body chunk ID
        try self.current_chunk.emitOpU16U8(.DEF_CLASS, @intCast(idx), body_chunk_id, line);
    }

    fn compileMethod(self: *Compiler, def_node: *prism.DefNode, line: u32) anyerror!void {
        // Get the method name (will be interned later by VM)
        const method_name_slice = try self.parser.getConstantName(def_node.name);

        // Allocate chunk on heap
        const method_chunk_ptr = try self.allocator.create(chunk.Chunk);
        method_chunk_ptr.* = chunk.Chunk.init(self.allocator, method_name_slice);

        // Save the current chunk and switch to the method chunk
        const saved_chunk = self.current_chunk;
        const saved_locals_len = self.locals.items.len;
        self.current_chunk = method_chunk_ptr;

        // Process parameters (if any)
        if (def_node.parameters) |params_ptr| {
            const params = @as(*prism.ParametersNode, @ptrCast(params_ptr));
            if (params.requireds.size > 0) {
                var i: usize = 0;
                while (i < params.requireds.size) : (i += 1) {
                    const param_node = params.requireds.nodes[i];
                    const param = @as(*prism.RequiredParameterNode, @ptrCast(param_node));
                    const param_name = try self.parser.getLocalVariableName(param.name);
                    try self.addLocal(param_name);
                }
            }
        }

        // Compile the method body
        if (def_node.body) |body_ptr| {
            const body_node = try self.parser.asNode(@ptrCast(body_ptr));
            try self.compileNode(body_node, line);
        } else {
            // If no body, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Emit return instruction
        try self.current_chunk.emitOp(.RETURN, line);

        // Restore the previous chunk
        self.current_chunk = saved_chunk;
        self.locals.items.len = saved_locals_len;

        // Assign unique ID to this method chunk
        const chunk_id = self.chunk_counter;
        self.chunk_counter += 1;

        // Store the chunk ID on the chunk itself
        method_chunk_ptr.chunk_id = @intCast(chunk_id);

        // Store by ID
        try self.method_chunks.put(chunk_id, method_chunk_ptr);

        // Emit DEF_METHOD bytecode with method name and chunk ID
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = method_name_slice });
        try self.current_chunk.emitOpU16U8(.DEF_METHOD, @intCast(name_idx), @intCast(chunk_id), line);

        // Return a symbol of the method name
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(name_idx), line);
    }

    fn addLocal(self: *Compiler, name: []const u8) !void {
        try self.locals.append(self.allocator, Local{
            .name = name,
            .depth = self.scope_depth,
        });
    }

    fn findLocal(self: *Compiler, name: []const u8) ?u8 {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }
};
