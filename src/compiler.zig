const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const prism = @import("prism.zig");
const value = @import("value.zig");

const Chunk = chunk.Chunk;

pub const CompiledProgram = struct {
    allocator: std.mem.Allocator,
    main_chunk: Chunk,
    method_chunks: std.AutoHashMap(u16, *Chunk),

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
    is_captured: bool,
};

const LoopContext = struct {
    loop_type: enum { while_loop, until_loop, block },
    break_jumps: std.ArrayList(usize),
};

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    parser: *prism.Parser,

    current_chunk: *Chunk,
    locals: std.ArrayList(Local) = .empty,
    scope_depth: usize = 0,

    // Track all locals in current scope chain (for closure compilation)
    all_locals: std.ArrayList(std.ArrayList(Local)) = .empty,

    method_chunks: std.AutoHashMap(u16, *Chunk),
    chunk_counter: u16 = 1,
    loop_stack: std.ArrayList(LoopContext) = .empty,

    pub fn init(allocator: std.mem.Allocator, parser: *prism.Parser) Compiler {
        return Compiler{
            .allocator = allocator,
            .parser = parser,
            .current_chunk = undefined,
            .method_chunks = std.AutoHashMap(u16, *Chunk).init(allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.locals.deinit(self.allocator);
        for (self.loop_stack.items) |*ctx| {
            ctx.break_jumps.deinit(self.allocator);
        }
        self.loop_stack.deinit(self.allocator);
        for (self.all_locals.items) |*scope| {
            scope.deinit(self.allocator);
        }
        self.all_locals.deinit(self.allocator);
        // self.method_chunks is transferred to CompiledProgram.
    }

    pub fn compile(allocator: std.mem.Allocator, parser: *prism.Parser) !CompiledProgram {
        var compiler = Compiler.init(allocator, parser);
        defer compiler.deinit();

        var main_chunk = Chunk.init(allocator, "main");
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

            .parentheses => |paren_node| {
                if (paren_node.body != null) {
                    const body = try self.parser.asNode(@ptrCast(paren_node.body));
                    try self.compileNode(body, line);
                } else {
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }
            },

            .local_variable_read => |var_read| {
                const var_name = try self.parser.getLocalVariableName(var_read.name);
                // Try to find in current scope first
                if (self.findLocal(var_name)) |idx| {
                    try self.current_chunk.emitOpU8(.GET_LOCAL, idx, line);
                } else if (self.findLocalWithDepth(var_name)) |info| {
                    // Found in parent scope - emit deep access
                    try self.current_chunk.emitOpU8U8(.GET_LOCAL_DEEP, @intCast(info.idx), @intCast(info.depth), line);
                } else {
                    std.debug.print("Error: undefined local variable '{s}'\n", .{var_name});
                    return error.UndefinedVariable;
                }
            },

            .local_variable_write => |var_write| {
                const var_name = try self.parser.getLocalVariableName(var_write.name);
                const value_node = try self.parser.asNode(@ptrCast(var_write.value));
                try self.compileNode(value_node, line);

                // Try to find in current scope first
                if (self.findLocal(var_name)) |idx| {
                    try self.current_chunk.emitOpU8(.SET_LOCAL, idx, line);
                } else if (self.findLocalWithDepth(var_name)) |info| {
                    // Found in parent scope - emit deep access
                    try self.current_chunk.emitOpU8U8(.SET_LOCAL_DEEP, @intCast(info.idx), @intCast(info.depth), line);
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

            .constant_path => |const_path| {
                // Compile the parent (module/class) - this pushes it onto the stack
                if (const_path.parent) |parent| {
                    const parent_node = try self.parser.asNode(@ptrCast(parent));
                    try self.compileNode(parent_node, line);
                } else {
                    // No parent means ::X (top-level constant), not yet implemented
                    return error.TopLevelConstantPath;
                }

                // Get the constant name to look up
                const const_name = try self.parser.getConstantName(const_path.name);
                const idx = try self.current_chunk.addConstant(.{ .string = const_name });
                try self.current_chunk.emitOpU16(.GET_CONST_PATH, @intCast(idx), line);
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

                // Check if there's a block attached to the call
                var block_chunk_id: u8 = 0;
                if (call_node.block) |block_ptr| {
                    const block_node = try self.parser.asNode(@ptrCast(block_ptr));
                    if (block_node == .block) {
                        block_chunk_id = try self.compileBlock(block_node.block, line);
                    }
                }

                // Store method name and emit CALL with block chunk ID
                const method_name = try self.parser.getConstantName(call_node.name);
                const method_idx = try self.current_chunk.addConstant(.{ .string = method_name });
                try self.current_chunk.emitOpU16U8U8(.CALL, @intCast(method_idx), argc, block_chunk_id, line);
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

            .hash => |hash_node| {
                const pair_count: u8 = @intCast(hash_node.elements.size);

                if (pair_count > 255) {
                    return error.TooManyHashPairs;
                }

                // Compile key-value pairs in reverse order
                var i: i32 = @intCast(hash_node.elements.size);
                while (i > 0) : (i -= 1) {
                    const assoc_raw = hash_node.elements.nodes[@intCast(i - 1)];
                    const assoc_node = try self.parser.asNode(assoc_raw);

                    // Each element should be an AssocNode
                    if (assoc_node != .assoc) {
                        return error.ExpectedAssocNode;
                    }

                    // Compile value first
                    const value_node = try self.parser.asNode(@ptrCast(assoc_node.assoc.value));
                    try self.compileNode(value_node, line);

                    // Compile key second
                    const key_node = try self.parser.asNode(@ptrCast(assoc_node.assoc.key));
                    try self.compileNode(key_node, line);
                }

                // Emit PUSH_HASH with pair count
                try self.current_chunk.emitOpU8(.PUSH_HASH, pair_count, line);
            },

            .yield => |yield_node| {
                // Compile yield arguments
                var argc: u8 = 0;
                if (yield_node.arguments) |args_ptr| {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
                    var i: usize = 0;
                    while (i < args.arguments.size) : (i += 1) {
                        const arg = args.arguments.nodes[i];
                        const arg_node = try self.parser.asNode(arg);
                        try self.compileNode(arg_node, line);
                        argc += 1;
                    }
                }
                // Emit YIELD with argument count
                try self.current_chunk.emitOpU8(.YIELD, argc, line);
            },

            .block => |block_node| {
                _ = try self.compileBlock(block_node, line);
            },

            .lambda => |lambda_node| {
                const chunk_id = try self.compileLambda(lambda_node, line);
                try self.current_chunk.emitOpU8(.PUSH_LAMBDA, chunk_id, line);
            },

            .begin => |begin_node| {
                try self.compileBeginNode(begin_node, line);
            },

            .retry => {
                // Emit RETRY opcode to jump back to the beginning of the begin block
                try self.current_chunk.emitOp(.RETRY, line);
            },

            .return_node => |return_node| {
                // Compile return value if present
                if (return_node.arguments) |args_ptr| {
                    const args_node = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
                    if (args_node.arguments.size > 0) {
                        // Compile the first argument as the return value
                        const arg = args_node.arguments.nodes[0];
                        const arg_node = try self.parser.asNode(arg);
                        try self.compileNode(arg_node, line);
                    } else {
                        // No arguments, return nil
                        try self.current_chunk.emitOp(.PUSH_NIL, line);
                    }
                } else {
                    // No arguments, return nil
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }
                // Emit RETURN opcode (explicit return)
                try self.current_chunk.emitOpU8(.RETURN, 1, line);
            },

            .rescue_modifier => |rescue_modifier_node| {
                try self.compileRescueModifierNode(rescue_modifier_node, line);
            },

            .rescue => {
                std.debug.print("Error: rescue node should be handled by begin node\n", .{});
                return error.UnsupportedNode;
            },

            .while_node => |while_node| {
                try self.compileWhileStatement(while_node, line);
            },

            .until_node => |until_node| {
                try self.compileUntilStatement(until_node, line);
            },

            .break_node => |break_node| {
                try self.compileBreakStatement(break_node, line);
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
            const body_chunk_ptr = try self.allocator.create(Chunk);
            body_chunk_ptr.* = Chunk.init(self.allocator, module_name);

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
            try self.current_chunk.emitOpU8(.RETURN, 0, line);

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
            const body_chunk_ptr = try self.allocator.create(Chunk);
            body_chunk_ptr.* = Chunk.init(self.allocator, class_name);

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
            try self.current_chunk.emitOpU8(.RETURN, 0, line);

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

        // Check if this is a singleton method (has a receiver)
        const is_singleton_method = def_node.receiver != null;

        // If there's a receiver, compile it to leave the receiver object on the stack
        if (def_node.receiver) |receiver_ptr| {
            const receiver_node = try self.parser.asNode(@ptrCast(receiver_ptr));
            try self.compileNode(receiver_node, line);
            // Stack now has: [..., receiver_object]
        }

        // Allocate chunk on heap
        const method_chunk_ptr = try self.allocator.create(Chunk);
        method_chunk_ptr.* = Chunk.init(self.allocator, method_name_slice);

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
        try self.current_chunk.emitOpU8(.RETURN, 0, line);

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

        // Emit DEF_METHOD or DEF_SINGLETON_METHOD bytecode with method name and chunk ID
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = method_name_slice });
        if (is_singleton_method) {
            // DEF_SINGLETON_METHOD expects receiver on stack, pops it
            try self.current_chunk.emitOpU16U8(.DEF_SINGLETON_METHOD, @intCast(name_idx), @intCast(chunk_id), line);
        } else {
            // DEF_METHOD uses current self from frame
            try self.current_chunk.emitOpU16U8(.DEF_METHOD, @intCast(name_idx), @intCast(chunk_id), line);
        }

        // Return a symbol of the method name
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(name_idx), line);
    }

    fn compileBlock(self: *Compiler, block_node: *prism.BlockNode, line: u32) !u8 {
        // Allocate chunk on heap for the block
        const block_chunk_ptr = try self.allocator.create(Chunk);
        block_chunk_ptr.* = Chunk.init(self.allocator, "block");

        // Save the current chunk and switch to the block chunk
        const saved_chunk = self.current_chunk;
        self.current_chunk = block_chunk_ptr;

        // Push current locals onto all_locals stack (for closure lookups)
        try self.all_locals.append(self.allocator, self.locals);

        // Create new locals array for this block
        const saved_locals = self.locals;
        self.locals = .empty;

        // Push block context onto loop stack for break detection
        const loop_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{
            .loop_type = .block,
            .break_jumps = .empty,
        });

        defer {
            // Pop loop context when done compiling block
            var ctx = &self.loop_stack.items[loop_idx];
            ctx.break_jumps.deinit(self.allocator);
            _ = self.loop_stack.pop();
        }

        // Process block parameters (if any)
        var param_count: u8 = 0;
        if (block_node.parameters) |params_ptr| {
            // Block parameters are wrapped in BlockParametersNode
            const params_node = try self.parser.asNode(@ptrCast(params_ptr));
            if (params_node == .block_parameters) {
                const block_params = params_node.block_parameters;
                if (block_params.parameters) |actual_params_ptr| {
                    const params = @as(*prism.ParametersNode, @ptrCast(actual_params_ptr));
                    if (params.requireds.size > 0) {
                        if (params.requireds.size > 255) {
                            return error.TooManyParameters;
                        }
                        param_count = @as(u8, @intCast(params.requireds.size));
                        var i: usize = 0;
                        while (i < params.requireds.size) : (i += 1) {
                            const param_node = params.requireds.nodes[i];
                            const param = @as(*prism.RequiredParameterNode, @ptrCast(param_node));
                            const param_name = try self.parser.getLocalVariableName(param.name);
                            try self.addLocal(param_name);
                        }
                    }
                }
            }
        }

        // Set arity on the chunk
        block_chunk_ptr.arity = param_count;

        // Compile the block body
        if (block_node.body) |body_ptr| {
            const body_node = try self.parser.asNode(@ptrCast(body_ptr));
            try self.compileNode(body_node, line);
        } else {
            // If no body, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Emit return instruction
        try self.current_chunk.emitOpU8(.RETURN, 0, line);

        // Pop the all_locals stack
        _ = self.all_locals.pop();

        // Restore the previous chunk and locals
        self.current_chunk = saved_chunk;
        self.locals.deinit(self.allocator); // Clean up block's locals
        self.locals = saved_locals; // Restore parent's locals

        // Assign unique ID to this block chunk
        const chunk_id = self.chunk_counter;
        self.chunk_counter += 1;

        // Store the chunk ID on the chunk itself
        block_chunk_ptr.chunk_id = @intCast(chunk_id);

        // Store by ID
        try self.method_chunks.put(chunk_id, block_chunk_ptr);

        return @intCast(chunk_id);
    }

    fn compileLambda(self: *Compiler, lambda_node: *prism.LambdaNode, line: u32) !u8 {
        // Allocate chunk on heap for the lambda
        const lambda_chunk_ptr = try self.allocator.create(Chunk);
        lambda_chunk_ptr.* = Chunk.init(self.allocator, "lambda");
        lambda_chunk_ptr.is_lambda = true; // Mark as lambda

        // Save the current chunk and switch to the lambda chunk
        const saved_chunk = self.current_chunk;
        self.current_chunk = lambda_chunk_ptr;

        // Push current locals onto all_locals stack (for closure lookups)
        try self.all_locals.append(self.allocator, self.locals);

        // Create new locals array for this lambda
        const saved_locals = self.locals;
        self.locals = .empty;

        // Push block context onto loop stack for break detection
        const loop_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{
            .loop_type = .block,
            .break_jumps = .empty,
        });

        defer {
            // Pop loop context when done compiling lambda
            var ctx = &self.loop_stack.items[loop_idx];
            ctx.break_jumps.deinit(self.allocator);
            _ = self.loop_stack.pop();
        }

        // Process lambda parameters (if any)
        var param_count: u8 = 0;
        if (lambda_node.parameters) |params_ptr| {
            const params_node = try self.parser.asNode(@ptrCast(params_ptr));

            // Lambda parameters can be either BlockParametersNode or ParametersNode
            if (params_node == .block_parameters) {
                const block_params = params_node.block_parameters;
                if (block_params.parameters) |actual_params_ptr| {
                    const params = @as(*prism.ParametersNode, @ptrCast(actual_params_ptr));
                    if (params.requireds.size > 0) {
                        if (params.requireds.size > 255) {
                            return error.TooManyParameters;
                        }
                        param_count = @as(u8, @intCast(params.requireds.size));
                        var i: usize = 0;
                        while (i < params.requireds.size) : (i += 1) {
                            const param_node = params.requireds.nodes[i];
                            const param = @as(*prism.RequiredParameterNode, @ptrCast(param_node));
                            const param_name = try self.parser.getLocalVariableName(param.name);
                            try self.addLocal(param_name);
                        }
                    }
                }
            }
        }

        // Set arity on the chunk
        lambda_chunk_ptr.arity = param_count;

        // Compile the lambda body
        if (lambda_node.body) |body_ptr| {
            const body_node = try self.parser.asNode(@ptrCast(body_ptr));
            try self.compileNode(body_node, line);
        } else {
            // If no body, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Emit return instruction
        try self.current_chunk.emitOpU8(.RETURN, 0, line);

        // Pop the all_locals stack
        _ = self.all_locals.pop();

        // Restore the previous chunk and locals
        self.current_chunk = saved_chunk;
        self.locals.deinit(self.allocator); // Clean up lambda's locals
        self.locals = saved_locals; // Restore parent's locals

        // Assign unique ID to this lambda chunk
        const chunk_id = self.chunk_counter;
        self.chunk_counter += 1;

        // Store the chunk ID on the chunk itself
        lambda_chunk_ptr.chunk_id = @intCast(chunk_id);

        // Store by ID
        try self.method_chunks.put(chunk_id, lambda_chunk_ptr);

        return @intCast(chunk_id);
    }

    fn addLocal(self: *Compiler, name: []const u8) !void {
        try self.locals.append(self.allocator, Local{
            .name = name,
            .depth = self.scope_depth,
            .is_captured = false,
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

    fn findLocalWithDepth(self: *Compiler, name: []const u8) ?struct { idx: usize, depth: usize } {
        var scope_idx = self.all_locals.items.len;
        while (scope_idx > 0) : (scope_idx -= 1) {
            const scope_locals = &self.all_locals.items[scope_idx - 1];
            var local_idx = scope_locals.items.len;
            while (local_idx > 0) : (local_idx -= 1) {
                if (std.mem.eql(u8, scope_locals.items[local_idx - 1].name, name)) {
                    return .{
                        .idx = local_idx - 1,
                        .depth = self.all_locals.items.len - scope_idx + 1,
                    };
                }
            }
        }
        return null;
    }

    fn compileBeginNode(self: *Compiler, begin_node: *prism.BeginNode, line: u32) !void {
        // Create exception handler entry
        const handler_idx = self.current_chunk.exception_handlers.items.len;

        // Emit TRY_BEGIN with handler index
        try self.current_chunk.emitOpU16(.TRY_BEGIN, @intCast(handler_idx), line);

        const try_start_ip = self.current_chunk.code.items.len;

        // Compile the protected statements
        if (begin_node.statements) |statements_ptr| {
            const statements = try self.parser.asNode(@ptrCast(statements_ptr));
            try self.compileNode(statements, line);
        } else {
            // Empty begin block pushes nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Emit TRY_END to mark normal completion
        try self.current_chunk.emitOp(.TRY_END, line);
        const try_end_ip = self.current_chunk.code.items.len;

        // Jump over rescue clauses on normal completion
        const jump_over_rescue = try self.current_chunk.emitJump(.JUMP, line);

        // Compile rescue clauses
        var rescue_handlers: std.ArrayList(chunk.RescueHandler) = .empty;
        var rescue_end_jumps: std.ArrayList(usize) = .empty;
        defer rescue_end_jumps.deinit(self.allocator);

        var rescue_ptr = begin_node.rescue_clause;
        while (rescue_ptr != null) {
            const rescue_node = @as(*prism.RescueNode, @ptrCast(rescue_ptr));

            const catch_ip = self.current_chunk.code.items.len;

            // Collect exception types (if any)
            var exception_types: std.ArrayList(u16) = .empty;

            // Check if there are exception types specified
            if (rescue_node.exceptions.size > 0) {
                var i: usize = 0;
                while (i < rescue_node.exceptions.size) : (i += 1) {
                    const exc_node_raw = rescue_node.exceptions.nodes[i];
                    const exc_node = try self.parser.asNode(exc_node_raw);

                    // For now, we store the constant index for the exception class name
                    // The VM will resolve it at runtime
                    switch (exc_node) {
                        .constant_read => |const_read| {
                            const name = try self.parser.getConstantName(const_read.name);
                            const idx = try self.current_chunk.addConstant(.{ .string = name });
                            try exception_types.append(self.allocator, @intCast(idx));
                        },
                        else => {
                            std.debug.print("Error: unsupported exception type node\n", .{});
                            return error.UnsupportedNode;
                        },
                    }
                }
            }
            // If no exception types, it's a bare rescue (catches StandardError)

            // Handle variable binding (rescue => e)
            var var_idx: u8 = 255; // 255 means no binding
            if (rescue_node.reference) |reference_ptr| {
                const reference = try self.parser.asNode(@ptrCast(reference_ptr));
                switch (reference) {
                    .local_variable_target => |var_target| {
                        const var_name = try self.parser.getLocalVariableName(var_target.name);
                        // Add to locals
                        try self.addLocal(var_name);
                        var_idx = @intCast(self.locals.items.len - 1);
                    },
                    .local_variable_write => |var_write| {
                        const var_name = try self.parser.getLocalVariableName(var_write.name);
                        // Add to locals
                        try self.addLocal(var_name);
                        var_idx = @intCast(self.locals.items.len - 1);
                    },
                    else => {
                        std.debug.print("Error: unsupported rescue reference node\n", .{});
                        return error.UnsupportedNode;
                    },
                }
            }

            // Emit CATCH_START with variable index
            try self.current_chunk.emitOpU8(.CATCH_START, var_idx, line);

            // Compile rescue body
            if (rescue_node.statements) |statements_ptr| {
                const statements = try self.parser.asNode(@ptrCast(statements_ptr));
                try self.compileNode(statements, line);
            } else {
                // Empty rescue body pushes nil
                try self.current_chunk.emitOp(.PUSH_NIL, line);
            }

            // Emit CATCH_END
            try self.current_chunk.emitOp(.CATCH_END, line);
            const catch_end_ip = self.current_chunk.code.items.len;

            // Jump over remaining rescue clauses after executing this one
            const jump_to_end = try self.current_chunk.emitJump(.JUMP, line);
            try rescue_end_jumps.append(self.allocator, jump_to_end);

            // Store rescue handler info
            try rescue_handlers.append(self.allocator, .{
                .exception_types = exception_types,
                .catch_ip = catch_ip,
                .catch_end_ip = catch_end_ip,
                .var_idx = if (var_idx == 255) null else var_idx,
            });

            // Move to next rescue clause
            rescue_ptr = rescue_node.subsequent;
        }

        // Patch the jump over rescue clauses (from normal completion)
        try self.current_chunk.patchJump(jump_over_rescue);

        // Else clause (only runs if no exception was raised)
        var else_ip: ?usize = null;
        if (begin_node.else_clause) |else_ptr| {
            else_ip = self.current_chunk.code.items.len;
            const else_node = try self.parser.asNode(@ptrCast(else_ptr));

            // Compile else body
            if (else_node == .else_node) {
                if (else_node.else_node.statements) |statements_ptr| {
                    const statements = try self.parser.asNode(@ptrCast(statements_ptr));
                    try self.compileNode(statements, line);
                } else {
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }
            }
        }

        // Patch all rescue clause end jumps to skip the else clause
        for (rescue_end_jumps.items) |jump_pos| {
            try self.current_chunk.patchJump(jump_pos);
        }

        // Ensure clause (always runs)
        var ensure_ip: ?usize = null;
        var ensure_end_ip: ?usize = null;
        if (begin_node.ensure_clause) |ensure_ptr| {
            ensure_ip = self.current_chunk.code.items.len;

            // Emit ENSURE_START
            try self.current_chunk.emitOp(.ENSURE_START, line);

            const ensure_node = try self.parser.asNode(@ptrCast(ensure_ptr));

            // Compile ensure body
            if (ensure_node == .ensure) {
                if (ensure_node.ensure.statements) |statements_ptr| {
                    const statements = try self.parser.asNode(@ptrCast(statements_ptr));
                    try self.compileNode(statements, line);
                } else {
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }
            }

            // Emit ENSURE_END
            try self.current_chunk.emitOp(.ENSURE_END, line);
            ensure_end_ip = self.current_chunk.code.items.len;
        }

        // Create the exception handler entry
        try self.current_chunk.exception_handlers.append(self.allocator, .{
            .try_start_ip = try_start_ip,
            .try_end_ip = try_end_ip,
            .rescue_handlers = rescue_handlers,
            .else_ip = else_ip,
            .ensure_ip = ensure_ip,
            .ensure_end_ip = ensure_end_ip,
        });
    }

    fn compileRescueModifierNode(self: *Compiler, rescue_modifier_node: *prism.RescueModifierNode, line: u32) !void {
        // Rescue modifier is syntactic sugar for:
        // begin
        //   expression
        // rescue StandardError
        //   rescue_expression
        // end

        // Create exception handler entry
        const handler_idx = self.current_chunk.exception_handlers.items.len;

        // Emit TRY_BEGIN with handler index
        try self.current_chunk.emitOpU16(.TRY_BEGIN, @intCast(handler_idx), line);

        const try_start_ip = self.current_chunk.code.items.len;

        // Compile the main expression
        const expression = try self.parser.asNode(@ptrCast(rescue_modifier_node.expression));
        try self.compileNode(expression, line);

        // Emit TRY_END to mark normal completion
        try self.current_chunk.emitOp(.TRY_END, line);
        const try_end_ip = self.current_chunk.code.items.len;

        // Jump over rescue clause on normal completion
        const jump_over_rescue = try self.current_chunk.emitJump(.JUMP, line);

        // Compile rescue clause (catches StandardError by default)
        const catch_ip = self.current_chunk.code.items.len;

        // No specific exception types means bare rescue (StandardError)
        const exception_types: std.ArrayList(u16) = .empty;

        // No variable binding for rescue modifier
        const var_idx: u8 = 255; // 255 means no binding

        // Emit CATCH_START with no variable binding
        try self.current_chunk.emitOpU8(.CATCH_START, var_idx, line);

        // Compile the rescue expression (fallback value)
        const rescue_expression = try self.parser.asNode(@ptrCast(rescue_modifier_node.rescue_expression));
        try self.compileNode(rescue_expression, line);

        // Emit CATCH_END
        try self.current_chunk.emitOp(.CATCH_END, line);
        const catch_end_ip = self.current_chunk.code.items.len;

        // Patch the jump over rescue clause (from normal completion)
        try self.current_chunk.patchJump(jump_over_rescue);

        // Create the rescue handler
        var rescue_handlers: std.ArrayList(chunk.RescueHandler) = .empty;
        try rescue_handlers.append(self.allocator, .{
            .exception_types = exception_types,
            .catch_ip = catch_ip,
            .catch_end_ip = catch_end_ip,
            .var_idx = null,
        });

        // Create the exception handler entry (no else or ensure for rescue modifier)
        try self.current_chunk.exception_handlers.append(self.allocator, .{
            .try_start_ip = try_start_ip,
            .try_end_ip = try_end_ip,
            .rescue_handlers = rescue_handlers,
            .else_ip = null,
            .ensure_ip = null,
            .ensure_end_ip = null,
        });
    }

    fn compileBreakStatement(self: *Compiler, break_node: *prism.BreakNode, line: u32) !void {
        if (self.loop_stack.items.len == 0) {
            return error.BreakOutsideLoop;
        }

        const current_loop = &self.loop_stack.items[self.loop_stack.items.len - 1];

        // Compile break argument (value to return)
        if (break_node.arguments) |args_ptr| {
            const args = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
            if (args.arguments.size > 0) {
                const arg_node = try self.parser.asNode(args.arguments.nodes[0]);
                try self.compileNode(arg_node, line);
            } else {
                try self.current_chunk.emitOp(.PUSH_NIL, line);
            }
        } else {
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Different behavior for blocks vs loops
        switch (current_loop.loop_type) {
            .block => {
                // For blocks: emit BREAK opcode (sets flag and returns)
                try self.current_chunk.emitOp(.BREAK, line);
            },
            .while_loop, .until_loop => {
                // For loops: emit JUMP forward
                // Note: break value is already on stack from above
                const break_jump_pos = try self.current_chunk.emitJump(.JUMP, line);
                try current_loop.break_jumps.append(self.allocator, break_jump_pos);
            },
        }
    }

    fn compileWhileStatement(self: *Compiler, while_node: *prism.WhileNode, line: u32) anyerror!void {
        const loop_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{ .loop_type = .while_loop, .break_jumps = .empty });

        defer {
            var ctx = &self.loop_stack.items[loop_idx];
            ctx.break_jumps.deinit(self.allocator);
            _ = self.loop_stack.pop();
        }

        // Mark loop start position for backward jump
        const loop_start_ip = self.current_chunk.code.items.len;

        // 1. Compile condition expression
        const condition = try self.parser.asNode(@ptrCast(while_node.predicate));
        try self.compileNode(condition, line);

        // 2. Jump to end if condition is false (JUMP_IF_FALSE pops the condition)
        const jump_to_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);

        // 3. Compile loop body
        if (while_node.statements) |statements_ptr| {
            const body = try self.parser.asNode(@ptrCast(statements_ptr));
            try self.compileNode(body, line);
            // 4. Discard body result to prevent stack growth
            try self.current_chunk.emitOp(.POP, line);
        }

        // 5. Jump back to loop start (backward jump)
        const jump_back_pos = self.current_chunk.code.items.len;
        const offset: i16 = @intCast(@as(i32, @intCast(loop_start_ip)) -
            @as(i32, @intCast(jump_back_pos)) - 3);
        try self.current_chunk.emitOpI16(.JUMP, offset, line);

        // 6. Patch forward jump to here (after loop exits)
        try self.current_chunk.patchJump(jump_to_end);

        // Normal exit: push nil
        try self.current_chunk.emitOp(.PUSH_NIL, line);

        // Patch all break jumps to here (after nil push)
        const current_loop_ctx = &self.loop_stack.items[self.loop_stack.items.len - 1];
        for (current_loop_ctx.break_jumps.items) |break_pos| {
            try self.current_chunk.patchJump(break_pos);
        }
    }

    fn compileUntilStatement(self: *Compiler, until_node: *prism.UntilNode, line: u32) anyerror!void {
        const loop_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, .{ .loop_type = .until_loop, .break_jumps = .empty });

        defer {
            var ctx = &self.loop_stack.items[loop_idx];
            ctx.break_jumps.deinit(self.allocator);
            _ = self.loop_stack.pop();
        }

        // Mark loop start position for backward jump
        const loop_start_ip = self.current_chunk.code.items.len;

        // 1. Compile condition expression
        const condition = try self.parser.asNode(@ptrCast(until_node.predicate));
        try self.compileNode(condition, line);

        // 2. Jump to end if condition is TRUE
        const jump_to_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);

        // 3. Compile loop body
        if (until_node.statements) |statements_ptr| {
            const body = try self.parser.asNode(@ptrCast(statements_ptr));
            try self.compileNode(body, line);
            // 4. Discard body result to prevent stack growth
            try self.current_chunk.emitOp(.POP, line);
        }

        // 5. Jump back to loop start (backward jump)
        const jump_back_pos = self.current_chunk.code.items.len;
        const offset: i16 = @intCast(@as(i32, @intCast(loop_start_ip)) -
            @as(i32, @intCast(jump_back_pos)) - 3);
        try self.current_chunk.emitOpI16(.JUMP, offset, line);

        // 6. Patch forward jump to here (after loop exits)
        try self.current_chunk.patchJump(jump_to_end);

        // Normal exit: push nil
        try self.current_chunk.emitOp(.PUSH_NIL, line);

        // Patch all break jumps to here (after nil push)
        const current_loop_ctx = &self.loop_stack.items[self.loop_stack.items.len - 1];
        for (current_loop_ctx.break_jumps.items) |break_pos| {
            try self.current_chunk.patchJump(break_pos);
        }
    }
};
