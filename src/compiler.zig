const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const prism = @import("prism.zig");
const value = @import("value.zig");

const Chunk = chunk.Chunk;

pub const CompiledProgram = struct {
    allocator: std.mem.Allocator,
    main_chunk: Chunk,
    method_chunks: std.AutoHashMap(chunk.ChunkId, *Chunk),
    next_chunk_id: chunk.ChunkId,

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

    method_chunks: std.AutoHashMap(chunk.ChunkId, *Chunk),
    chunk_counter: chunk.ChunkId = 1,
    loop_stack: std.ArrayList(LoopContext) = .empty,

    pub fn init(allocator: std.mem.Allocator, parser: *prism.Parser, starting_chunk_id: chunk.ChunkId) Compiler {
        return Compiler{
            .allocator = allocator,
            .parser = parser,
            .current_chunk = undefined,
            .method_chunks = std.AutoHashMap(chunk.ChunkId, *Chunk).init(allocator),
            .chunk_counter = starting_chunk_id,
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

    /// Allocate the next chunk ID, returning an error if we've exceeded the limit.
    fn nextChunkId(self: *Compiler) !chunk.ChunkId {
        if (self.chunk_counter > chunk.MAX_CHUNK_ID) {
            return error.TooManyChunks;
        }
        const id = self.chunk_counter;
        self.chunk_counter += 1;
        return id;
    }

    pub fn compile(allocator: std.mem.Allocator, parser: *prism.Parser, starting_chunk_id: u16) !CompiledProgram {
        var compiler = Compiler.init(allocator, parser, starting_chunk_id);
        defer compiler.deinit();

        var main_chunk = Chunk.init(allocator, "main");
        main_chunk.source_file = parser.source_file;
        compiler.current_chunk = &main_chunk;

        // On error, clean up chunks that were allocated during compilation
        errdefer {
            main_chunk.deinit();
            var iter = compiler.method_chunks.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                allocator.destroy(entry.value_ptr.*);
            }
            compiler.method_chunks.deinit();
        }

        const root = try parser.root();
        try compiler.compileNode(root, 0);
        try compiler.current_chunk.emitOp(.HALT, 0);

        return CompiledProgram{
            .allocator = allocator,
            .main_chunk = main_chunk,
            .method_chunks = compiler.method_chunks,
            .next_chunk_id = compiler.chunk_counter,
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
                try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
            },

            .float => |float_node| {
                const idx = try self.current_chunk.addConstant(.{ .float = float_node.value });
                try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
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

            .regular_expression => |regexp_node| {
                const pattern = regexp_node.unescaped;
                const pattern_slice = pattern.source[0..pattern.length];
                const idx = try self.current_chunk.addConstant(.{ .string = pattern_slice });
                // Map Prism flags to Onigmo option bits
                const flags = regexp_node.base.flags;
                var options: u16 = 0;
                if ((flags & prism.REGEXP_FLAGS_IGNORE_CASE) != 0) options |= 1; // ONIG_OPTION_IGNORECASE
                if ((flags & prism.REGEXP_FLAGS_EXTENDED) != 0) options |= 2; // ONIG_OPTION_EXTEND
                if ((flags & prism.REGEXP_FLAGS_MULTI_LINE) != 0) options |= 4; // ONIG_OPTION_MULTILINE
                try self.current_chunk.emitOpU16U16(.PUSH_REGEXP, @intCast(idx), options, line);
            },

            .interpolated_string => |interp_node| {
                const part_count = try self.compileInterpolatedParts(interp_node.parts, line);
                try self.current_chunk.emitOpU8(.INTERPOLATE_STRING, part_count, line);
            },

            .x_string => |xstring_node| {
                try self.current_chunk.emitOp(.PUSH_SELF, line);
                const str_val = xstring_node.unescaped;
                const str_slice = str_val.source[0..str_val.length];
                const idx = try self.current_chunk.addConstant(.{ .string = str_slice });
                try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
                try self.emitBacktickCall(line);
            },

            .interpolated_x_string => |interp_x_node| {
                try self.current_chunk.emitOp(.PUSH_SELF, line);
                const part_count = try self.compileInterpolatedParts(interp_x_node.parts, line);
                try self.current_chunk.emitOpU8(.INTERPOLATE_STRING, part_count, line);
                try self.emitBacktickCall(line);
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

            .range => |range_node| {
                // Compile left endpoint (nil for beginless)
                if (range_node.left != null) {
                    const left_node = try self.parser.asNode(@ptrCast(range_node.left));
                    if (left_node == .missing) {
                        try self.current_chunk.emitOp(.PUSH_NIL, line);
                    } else {
                        try self.compileNode(left_node, line);
                    }
                } else {
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }

                // Compile right endpoint (nil for endless)
                if (range_node.right != null) {
                    const right_node = try self.parser.asNode(@ptrCast(range_node.right));
                    if (right_node == .missing) {
                        try self.current_chunk.emitOp(.PUSH_NIL, line);
                    } else {
                        try self.compileNode(right_node, line);
                    }
                } else {
                    try self.current_chunk.emitOp(.PUSH_NIL, line);
                }

                // Emit PUSH_RANGE with exclude_end flag
                const exclude_end = (range_node.base.flags & prism.RANGE_FLAGS_EXCLUDE_END) != 0;
                const exclude_end_flag: u8 = if (exclude_end) 1 else 0;
                try self.current_chunk.emitOpU8(.PUSH_RANGE, exclude_end_flag, line);
            },

            .local_variable_read => |var_read| {
                const var_name = try self.parser.getLocalVariableName(var_read.name);
                const slot = try self.resolveExistingLocalSlot(var_name);
                try self.emitGetLocalSlot(slot, line);
            },

            .local_variable_write => |var_write| {
                const var_name = try self.parser.getLocalVariableName(var_write.name);
                const value_node = try self.parser.asNode(@ptrCast(var_write.value));
                try self.compileNode(value_node, line);

                const slot = try self.resolveOrCreateLocalSlot(var_name);
                try self.emitSetLocalSlot(slot, line);
            },

            .local_variable_and_write => |var_write| {
                try self.compileLocalAndWrite(var_write, line);
            },

            .local_variable_or_write => |var_write| {
                try self.compileLocalOrWrite(var_write, line);
            },

            .local_variable_operator_write => |var_write| {
                try self.compileLocalOperatorWrite(var_write, line);
            },

            .constant_read => |const_read| {
                const const_name = try self.parser.getConstantName(const_read.name);
                const idx = try self.current_chunk.addConstant(.{ .symbol = const_name });
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
                const idx = try self.current_chunk.addConstant(.{ .symbol = const_name });
                try self.current_chunk.emitOpU16(.GET_CONST_PATH, @intCast(idx), line);
            },

            .constant_write => |const_write| {
                const const_name = try self.parser.getConstantName(const_write.name);
                const value_node = try self.parser.asNode(@ptrCast(const_write.value));
                try self.compileNode(value_node, line);

                const idx = try self.current_chunk.addConstant(.{ .symbol = const_name });
                try self.current_chunk.emitOpU16(.SET_CONST, @intCast(idx), line);
            },

            .constant_and_write => |const_write| {
                try self.compileConstantAndWrite(const_write, line);
            },

            .constant_or_write => |const_write| {
                try self.compileConstantOrWrite(const_write, line);
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
                const receiver_style: bytecode.ReceiverCallStyle = if (call_node.receiver != null) .explicit else .implicit_self;

                // Compile arguments, detecting keywords and splats
                var argc: u8 = 0; // fixed positional argc for non-array mode
                var kwargc: u8 = 0;
                var kw_names: std.ArrayList(u16) = .empty;
                defer kw_names.deinit(self.allocator);
                var args_array_mode = false;

                if (call_node.arguments != null) {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(call_node.arguments.?));
                    var has_splat = false;
                    var i: usize = 0;
                    while (i < args.arguments.size) : (i += 1) {
                        const arg_node = try self.parser.asNode(args.arguments.nodes[i]);
                        if (arg_node == .splat) {
                            has_splat = true;
                            break;
                        }
                    }

                    if (!has_splat) {
                        i = 0;
                        while (i < args.arguments.size) : (i += 1) {
                            const arg = args.arguments.nodes[i];
                            const arg_node = try self.parser.asNode(arg);

                            if (arg_node == .keyword_hash) {
                                const kw_hash = arg_node.keyword_hash;
                                var j: usize = 0;
                                while (j < kw_hash.elements.size) : (j += 1) {
                                    const elem = try self.parser.asNode(kw_hash.elements.nodes[j]);
                                    const assoc = elem.assoc;
                                    const key_node = try self.parser.asNode(@ptrCast(assoc.key));
                                    const symbol_val = key_node.symbol.unescaped;
                                    const symbol_name = symbol_val.source[0..symbol_val.length];
                                    const symbol_idx = try self.current_chunk.addConstant(.{ .symbol = symbol_name });
                                    try kw_names.append(self.allocator, @intCast(symbol_idx));

                                    // Compile value onto stack
                                    const value_node = try self.parser.asNode(@ptrCast(assoc.value));
                                    try self.compileNode(value_node, line);
                                    kwargc += 1;
                                }
                            } else {
                                // Regular positional argument
                                try self.compileNode(arg_node, line);
                                argc += 1;
                            }
                        }
                    } else {
                        args_array_mode = true;
                        try self.current_chunk.emitOpU8(.PUSH_ARRAY, 0, line);

                        var seen_keyword_hash = false;
                        i = 0;
                        while (i < args.arguments.size) : (i += 1) {
                            const arg = args.arguments.nodes[i];
                            const arg_node = try self.parser.asNode(arg);

                            if (arg_node == .keyword_hash) {
                                seen_keyword_hash = true;
                                const kw_hash = arg_node.keyword_hash;
                                var j: usize = 0;
                                while (j < kw_hash.elements.size) : (j += 1) {
                                    const elem = try self.parser.asNode(kw_hash.elements.nodes[j]);
                                    const assoc = elem.assoc;
                                    const key_node = try self.parser.asNode(@ptrCast(assoc.key));
                                    const symbol_val = key_node.symbol.unescaped;
                                    const symbol_name = symbol_val.source[0..symbol_val.length];
                                    const symbol_idx = try self.current_chunk.addConstant(.{ .symbol = symbol_name });
                                    try kw_names.append(self.allocator, @intCast(symbol_idx));

                                    const value_node = try self.parser.asNode(@ptrCast(assoc.value));
                                    try self.compileNode(value_node, line);
                                    kwargc += 1;
                                }
                                continue;
                            }

                            if (seen_keyword_hash) {
                                std.debug.print("Error: positional arguments after keyword args with splat are not supported\n", .{});
                                return error.UnsupportedNode;
                            }

                            if (arg_node == .splat) {
                                const expr_ptr = arg_node.splat.expression orelse return error.UnsupportedNode;
                                const expr = try self.parser.asNode(@ptrCast(expr_ptr));
                                try self.compileNode(expr, line);
                                try self.current_chunk.emitOp(.ARRAY_CONCAT_ARRAY, line);
                            } else {
                                try self.compileNode(arg_node, line);
                                try self.current_chunk.emitOp(.ARRAY_APPEND, line);
                            }
                        }
                    }
                }

                // Check if there's a block attached to the call
                var block_chunk_id: chunk.ChunkId = 0;
                if (call_node.block) |block_ptr| {
                    const block_node = try self.parser.asNode(@ptrCast(block_ptr));

                    if (block_node == .block) {
                        // Literal block: compile to separate chunk
                        block_chunk_id = try self.compileBlock(block_node.block, line);
                    } else if (block_node == .block_argument) {
                        // Block argument (&variable): compile expression to push Proc onto stack
                        const expr = try self.parser.asNode(@ptrCast(block_node.block_argument.expression));
                        try self.compileNode(expr, line);
                        block_chunk_id = chunk.BLOCK_ARG_ON_STACK;
                    }
                }

                // Emit appropriate instruction
                const method_name = try self.parser.getConstantName(call_node.name);
                const method_idx = try self.current_chunk.addConstant(.{ .string = method_name });
                const call_flags = bytecode.encodeCallFlags(receiver_style, args_array_mode);

                if (kwargc > 0) {
                    // Create keyword metadata
                    var kw_meta = chunk.KeywordMetadata{ .names = .empty };
                    try kw_meta.names.appendSlice(self.allocator, kw_names.items);
                    try self.current_chunk.keyword_metadata.append(self.allocator, kw_meta);
                    const kw_metadata_idx = self.current_chunk.keyword_metadata.items.len - 1;

                    try self.current_chunk.emitCallKw(@intCast(method_idx), argc, kwargc, call_flags, @intCast(kw_metadata_idx), block_chunk_id, line);
                } else {
                    try self.current_chunk.emitCall(@intCast(method_idx), argc, call_flags, block_chunk_id, line);
                }
            },

            .case_node => |case_node| {
                try self.compileCaseNode(case_node, line);
            },

            .if_node => |if_node| {
                try self.compileIfStatement(if_node, line);
            },

            .unless_node => |unless_node| {
                try self.compileUnlessStatement(unless_node, line);
            },

            .and_node => |and_node| {
                try self.compileAndNode(and_node, line);
            },

            .or_node => |or_node| {
                try self.compileOrNode(or_node, line);
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
                try self.current_chunk.emitOpU16(.PUSH_LAMBDA, chunk_id, line);
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

            .global_variable_read => |var_read| {
                const var_name = try self.parser.getConstantName(@intCast(var_read.name));
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.GET_GLOBAL, @intCast(name_idx), line);
            },

            .global_variable_write => |var_write| {
                const var_name = try self.parser.getConstantName(@intCast(var_write.name));
                const value_node = try self.parser.asNode(@ptrCast(var_write.value));

                try self.compileNode(value_node, line);

                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_GLOBAL, @intCast(name_idx), line);
            },

            .global_variable_and_write => |var_write| {
                try self.compileGlobalAndWrite(var_write, line);
            },

            .global_variable_or_write => |var_write| {
                try self.compileGlobalOrWrite(var_write, line);
            },

            .instance_variable_read => |var_read| {
                const var_name = try self.parser.getConstantName(@intCast(var_read.name));
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.GET_IVAR, @intCast(name_idx), line);
            },

            .instance_variable_write => |var_write| {
                const var_name = try self.parser.getConstantName(@intCast(var_write.name));
                const value_node = try self.parser.asNode(@ptrCast(var_write.value));

                try self.compileNode(value_node, line);

                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_IVAR, @intCast(name_idx), line);
            },

            .instance_variable_and_write => |var_write| {
                try self.compileInstanceVariableAndWrite(var_write, line);
            },

            .instance_variable_or_write => |var_write| {
                try self.compileInstanceVariableOrWrite(var_write, line);
            },

            .multi_write => |multi_write| {
                try self.compileMultiWrite(multi_write, line);
            },

            .forwarding_super => |super_node| {
                // Bare super: forwards all original arguments
                // Compile optional block
                var block_chunk_id: chunk.ChunkId = 0;
                if (super_node.block) |block_ptr| {
                    const block_node = try self.parser.asNode(@ptrCast(block_ptr));
                    if (block_node == .block) {
                        block_chunk_id = try self.compileBlock(block_node.block, line);
                    } else if (block_node == .block_argument) {
                        const expr = try self.parser.asNode(@ptrCast(block_node.block_argument.expression));
                        try self.compileNode(expr, line);
                        block_chunk_id = chunk.BLOCK_ARG_ON_STACK;
                    }
                }

                try self.current_chunk.emitOpU16(.FORWARDING_SUPER, block_chunk_id, line);
            },

            .super_node => |super_node| {
                // super() or super(args): explicit arguments
                var argc: u8 = 0;
                var args_array_mode = false;
                if (super_node.arguments) |args_ptr| {
                    const args = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
                    var has_splat = false;
                    var i: usize = 0;
                    while (i < args.arguments.size) : (i += 1) {
                        const arg_node = try self.parser.asNode(args.arguments.nodes[i]);
                        if (arg_node == .splat) {
                            has_splat = true;
                            break;
                        }
                    }

                    if (!has_splat) {
                        i = 0;
                        while (i < args.arguments.size) : (i += 1) {
                            const arg = args.arguments.nodes[i];
                            const arg_node = try self.parser.asNode(arg);
                            try self.compileNode(arg_node, line);
                            argc += 1;
                        }
                    } else {
                        args_array_mode = true;
                        try self.current_chunk.emitOpU8(.PUSH_ARRAY, 0, line);

                        i = 0;
                        while (i < args.arguments.size) : (i += 1) {
                            const arg = args.arguments.nodes[i];
                            const arg_node = try self.parser.asNode(arg);

                            if (arg_node == .splat) {
                                const expr_ptr = arg_node.splat.expression orelse return error.UnsupportedNode;
                                const expr = try self.parser.asNode(@ptrCast(expr_ptr));
                                try self.compileNode(expr, line);
                                try self.current_chunk.emitOp(.ARRAY_CONCAT_ARRAY, line);
                            } else {
                                try self.compileNode(arg_node, line);
                                try self.current_chunk.emitOp(.ARRAY_APPEND, line);
                            }
                        }
                    }
                }

                // Compile optional block
                var block_chunk_id: chunk.ChunkId = 0;
                if (super_node.block) |block_ptr| {
                    const block_node = try self.parser.asNode(@ptrCast(block_ptr));
                    if (block_node == .block) {
                        block_chunk_id = try self.compileBlock(block_node.block, line);
                    } else if (block_node == .block_argument) {
                        const expr = try self.parser.asNode(@ptrCast(block_node.block_argument.expression));
                        try self.compileNode(expr, line);
                        block_chunk_id = chunk.BLOCK_ARG_ON_STACK;
                    }
                }

                const super_flags: u8 = if (args_array_mode) bytecode.SUPER_FLAG_ARGS_ARRAY else 0;
                try self.current_chunk.emitSuper(argc, super_flags, block_chunk_id, line);
            },

            .alias_method => |alias_node| {
                try self.compileAliasMethod(alias_node, line);
            },

            else => {
                std.debug.print("Error: unsupported node type: {}\n", .{node});
                return error.UnsupportedNode;
            },
        }
    }

    fn compileInterpolatedParts(self: *Compiler, parts: anytype, line: u32) !u8 {
        if (parts.size > 255) {
            return error.TooManyInterpolationParts;
        }
        const part_count: u8 = @intCast(parts.size);

        if (part_count == 0) {
            const idx = try self.current_chunk.addConstant(.{ .string = "" });
            try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
            return 0;
        }

        var i: i32 = @intCast(parts.size);
        while (i > 0) : (i -= 1) {
            const part = parts.nodes[@intCast(i - 1)];
            const part_node = try self.parser.asNode(part);

            switch (part_node) {
                .string => |string_node| {
                    const str_val = string_node.unescaped;
                    const str_slice = str_val.source[0..str_val.length];
                    const idx = try self.current_chunk.addConstant(.{ .string = str_slice });
                    try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
                },
                .embedded_statements => |embed_node| {
                    if (embed_node.statements) |stmts_raw| {
                        const stmts = try self.parser.asNode(@ptrCast(stmts_raw));
                        try self.compileNode(stmts, line);
                    } else {
                        const idx = try self.current_chunk.addConstant(.{ .string = "" });
                        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx), line);
                    }
                },
                .embedded_variable => |embed_var| {
                    const var_node = try self.parser.asNode(@ptrCast(embed_var.variable));
                    try self.compileNode(var_node, line);
                },
                else => {
                    std.debug.print("Error: unexpected node type in interpolated string/xstring\n", .{});
                    return error.UnsupportedNode;
                },
            }
        }

        return part_count;
    }

    fn emitBacktickCall(self: *Compiler, line: u32) !void {
        const method_idx = try self.current_chunk.addConstant(.{ .string = "`" });
        const call_flags = bytecode.encodeCallFlags(.implicit_self, false);
        try self.current_chunk.emitCall(@intCast(method_idx), 1, call_flags, 0, line);
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

    fn compileUnlessStatement(self: *Compiler, unless_node: *prism.UnlessNode, line: u32) anyerror!void {
        // Compile condition
        const condition = try self.parser.asNode(@ptrCast(unless_node.predicate));
        try self.compileNode(condition, line);

        // Jump if true (to the else/false case) - inverted from if_node
        const jump_true = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);

        // Compile then branch (executed when condition is false)
        if (unless_node.statements != null) {
            const then_branch = try self.parser.asNode(@ptrCast(unless_node.statements));
            try self.compileNode(then_branch, line);
        } else {
            // If no then-branch, push nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Jump to end (skip the else case)
        const jump_end = try self.current_chunk.emitJump(.JUMP, line);

        // Patch the true jump to here (this is where the else branch starts)
        try self.current_chunk.patchJump(jump_true);

        // Compile else clause, or push nil when condition is true
        if (unless_node.else_clause) |else_ptr| {
            const else_node = try self.parser.asNode(@ptrCast(else_ptr));
            try self.compileNode(else_node, line);
        } else {
            // No else branch - when condition is true, evaluate to nil
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        // Patch the end jump
        try self.current_chunk.patchJump(jump_end);
    }

    fn compileWhenBody(self: *Compiler, when_node: *prism.WhenNode, line: u32) !void {
        if (when_node.statements) |statements_ptr| {
            const statements = try self.parser.asNode(@ptrCast(statements_ptr));
            try self.compileNode(statements, line);
        } else {
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }
    }

    fn compileCaseNode(self: *Compiler, case_node: *prism.CaseNode, line: u32) !void {
        const has_predicate = case_node.predicate != null;
        if (has_predicate) {
            const predicate_node = try self.parser.asNode(@ptrCast(case_node.predicate.?));
            // Keep predicate on stack for all when comparisons.
            try self.compileNode(predicate_node, line);
        }

        var end_jumps: std.ArrayList(usize) = .empty;
        defer end_jumps.deinit(self.allocator);

        var i: usize = 0;
        while (i < case_node.conditions.size) : (i += 1) {
            const when_raw = case_node.conditions.nodes[i];
            const when_node = try self.parser.asNode(when_raw);
            if (when_node != .when_node) {
                return error.UnsupportedNode;
            }

            var next_when_jumps: std.ArrayList(usize) = .empty;
            defer next_when_jumps.deinit(self.allocator);

            var j: usize = 0;
            while (j < when_node.when_node.conditions.size) : (j += 1) {
                const condition_raw = when_node.when_node.conditions.nodes[j];
                const condition_node = try self.parser.asNode(condition_raw);

                if (has_predicate) {
                    try self.compileNode(condition_node, line);
                    try self.current_chunk.emitOp(.CASE_MATCH, line);
                } else {
                    try self.compileNode(condition_node, line);
                }

                const jump_on_match = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);
                try next_when_jumps.append(self.allocator, jump_on_match);
            }

            // No condition matched in this clause, proceed to next `when`.
            const jump_to_next_when = try self.current_chunk.emitJump(.JUMP, line);

            // Condition matched, run this clause body.
            for (next_when_jumps.items) |jump_on_match| {
                try self.current_chunk.patchJump(jump_on_match);
            }

            if (has_predicate) {
                // Clause matched; discard saved predicate before evaluating branch body.
                try self.current_chunk.emitOp(.POP, line);
            }
            try self.compileWhenBody(when_node.when_node, line);
            const jump_to_end = try self.current_chunk.emitJump(.JUMP, line);
            try end_jumps.append(self.allocator, jump_to_end);

            try self.current_chunk.patchJump(jump_to_next_when);
        }

        if (has_predicate) {
            // No clause matched; discard saved predicate before else/nil result.
            try self.current_chunk.emitOp(.POP, line);
        }

        // No when clause matched.
        if (case_node.else_clause) |else_ptr| {
            const else_node = try self.parser.asNode(@ptrCast(else_ptr));
            try self.compileNode(else_node, line);
        } else {
            try self.current_chunk.emitOp(.PUSH_NIL, line);
        }

        for (end_jumps.items) |jump_to_end| {
            try self.current_chunk.patchJump(jump_to_end);
        }
    }

    fn compileAndNode(self: *Compiler, and_node: *prism.AndNode, line: u32) anyerror!void {
        const left = try self.parser.asNode(@ptrCast(and_node.left));
        try self.compileNode(left, line);

        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);

        // Left was truthy: discard it and evaluate the right side.
        try self.current_chunk.emitOp(.POP, line);
        const right = try self.parser.asNode(@ptrCast(and_node.right));
        try self.compileNode(right, line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileOrNode(self: *Compiler, or_node: *prism.OrNode, line: u32) anyerror!void {
        const left = try self.parser.asNode(@ptrCast(or_node.left));
        try self.compileNode(left, line);

        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);

        // Left was falsey: discard it and evaluate the right side.
        try self.current_chunk.emitOp(.POP, line);
        const right = try self.parser.asNode(@ptrCast(or_node.right));
        try self.compileNode(right, line);

        try self.current_chunk.patchJump(jump_end);
    }

    const LocalSlot = struct {
        idx: u8,
        depth: u8,
    };

    fn resolveOrCreateLocalSlot(self: *Compiler, var_name: []const u8) !LocalSlot {
        if (self.findLocal(var_name)) |idx| {
            return .{ .idx = idx, .depth = 0 };
        }
        if (self.findLocalWithDepth(var_name)) |info| {
            return .{
                .idx = @intCast(info.idx),
                .depth = @intCast(info.depth),
            };
        }

        try self.addLocal(var_name);
        return .{
            .idx = @intCast(self.locals.items.len - 1),
            .depth = 0,
        };
    }

    fn resolveExistingLocalSlot(self: *Compiler, var_name: []const u8) !LocalSlot {
        if (self.findLocal(var_name)) |idx| {
            return .{ .idx = idx, .depth = 0 };
        }
        if (self.findLocalWithDepth(var_name)) |info| {
            return .{
                .idx = @intCast(info.idx),
                .depth = @intCast(info.depth),
            };
        }
        std.debug.print("Error: undefined local variable '{s}'\n", .{var_name});
        return error.UndefinedVariable;
    }

    fn emitGetLocalSlot(self: *Compiler, slot: LocalSlot, line: u32) !void {
        if (slot.depth == 0) {
            try self.current_chunk.emitOpU8(.GET_LOCAL, slot.idx, line);
        } else {
            try self.current_chunk.emitOpU8U8(.GET_LOCAL_DEEP, slot.idx, slot.depth, line);
        }
    }

    fn emitSetLocalSlot(self: *Compiler, slot: LocalSlot, line: u32) !void {
        if (slot.depth == 0) {
            try self.current_chunk.emitOpU8(.SET_LOCAL, slot.idx, line);
        } else {
            try self.current_chunk.emitOpU8U8(.SET_LOCAL_DEEP, slot.idx, slot.depth, line);
        }
    }

    fn compileMultiWrite(self: *Compiler, node: *prism.MultiWriteNode, line: u32) !void {
        // Compile RHS value onto stack
        const value_node = try self.parser.asNode(@ptrCast(node.value));
        try self.compileNode(value_node, line);

        // DUP the original value for return value (Ruby returns original RHS, not converted array)
        try self.current_chunk.emitOp(.DUP, line);

        // If RHS is not an array literal, convert top value to array via to_ary protocol
        // Stack: [original_value, value_to_convert]
        if (value_node != .array) {
            try self.current_chunk.emitOp(.MULTI_ASSIGN_PREPARE, line);
            // Stack is now: [original_value, converted_array]
        }

        // DUP the array for destructuring (preserve one copy)
        try self.current_chunk.emitOp(.DUP, line);
        // Stack: [original_value, array, array]

        // Count targets
        const left_count = node.lefts.size;
        const right_count = node.rights.size;

        // Assign to left targets (indices 0, 1, 2, ...)
        var i: usize = 0;
        while (i < left_count) : (i += 1) {
            const target = try self.parser.asNode(node.lefts.nodes[i]);
            try self.compileMultiTarget(target, @intCast(i), line);
        }

        // Handle splat operator (Phase 3)
        if (node.rest) |rest_ptr| {
            const rest_node = try self.parser.asNode(@ptrCast(rest_ptr));
            switch (rest_node) {
                .splat => |splat| {
                    // Splat with variable: *var
                    if (splat.expression) |expr_ptr| {
                        const target = try self.parser.asNode(@ptrCast(expr_ptr));
                        try self.compileSplatAssignment(target, @intCast(left_count), @intCast(right_count), line);
                    }
                    // else: bare * without variable, just discard the middle elements
                },
                .implicit_rest => {
                    // Implicit rest (trailing comma), discard extras
                },
                else => {},
            }
        }

        // Assign to right targets (negative indices -1, -2, ... from end)
        i = 0;
        while (i < right_count) : (i += 1) {
            const target = try self.parser.asNode(node.rights.nodes[i]);
            const negative_index: i64 = -@as(i64, @intCast(right_count - i));
            try self.compileMultiTarget(target, negative_index, line);
        }

        // Pop the working array copy
        try self.current_chunk.emitOp(.POP, line);
        // Pop the preserved array copy (leave only original RHS value for return)
        try self.current_chunk.emitOp(.POP, line);
    }

    fn compileMultiTarget(self: *Compiler, target: prism.Node, index: i64, line: u32) anyerror!void {
        switch (target) {
            .local_variable_target => |var_target| {
                // Extract array element at index and assign to local variable
                const var_name = try self.parser.getLocalVariableName(var_target.name);
                try self.extractArrayElement(index, line);
                const slot = try self.resolveOrCreateLocalSlot(var_name);
                try self.emitSetLocalSlot(slot, line);
                // Pop the assigned value (SET_LOCAL pushes it back) to keep only array on stack
                try self.current_chunk.emitOp(.POP, line);
            },
            .multi_target => |multi_target| {
                // Nested destructuring: (a, b), c = [[1, 2], 3]
                // Extract the element at this index (should be an array)
                try self.extractArrayElement(index, line);

                // Now recursively destructure this nested array
                try self.compileNestedMultiTarget(multi_target, line);

                // Pop the nested array result
                try self.current_chunk.emitOp(.POP, line);
            },
            .global_variable_target => |var_target| {
                // Extract array element at index and assign to global variable
                const var_name = try self.parser.getConstantName(@intCast(var_target.name));
                try self.extractArrayElement(index, line);
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_GLOBAL, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .instance_variable_target => |var_target| {
                // Extract array element at index and assign to instance variable
                const var_name = try self.parser.getConstantName(@intCast(var_target.name));
                try self.extractArrayElement(index, line);
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_IVAR, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .constant_target => |const_target| {
                // Extract array element at index and assign to constant
                const const_name = try self.parser.getConstantName(@intCast(const_target.name));
                try self.extractArrayElement(index, line);
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = const_name });
                try self.current_chunk.emitOpU16(.SET_CONST, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .index_target => |index_target| {
                // arr[i], arr[j] = 1, 2  =>  arr.[]=(i, 1); arr.[]=(j, 2)
                // Stack: [array]
                try self.extractArrayElement(index, line);
                // Stack: [array, value]

                // Compile receiver
                const receiver_node = try self.parser.asNode(@ptrCast(index_target.receiver));
                try self.compileNode(receiver_node, line);
                // Stack: [array, value, receiver]

                // Swap to get: [array, receiver, value]
                try self.current_chunk.emitOp(.SWAP, line);
                // Stack: [array, receiver, value]

                // Compile index arguments
                const args_node = @as(*prism.ArgumentsNode, @ptrCast(index_target.arguments));
                const argc = args_node.arguments.size;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    const arg_node = try self.parser.asNode(args_node.arguments.nodes[i]);
                    try self.compileNode(arg_node, line);
                }
                // Stack: [array, receiver, value, index]

                // Swap to move value to end: [array, receiver, index, value]
                try self.current_chunk.emitOp(.SWAP, line);
                // Stack: [array, receiver, index, value]

                // Call []=(index, value)
                const bracket_eq = try self.current_chunk.addConstant(.{ .string = "[]=" });
                const receiver_style: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
                try self.current_chunk.emitCall(@intCast(bracket_eq), @intCast(argc + 1), receiver_style, 0, line);
                // Stack: [array, return_value]
                try self.current_chunk.emitOp(.POP, line);
                // Stack: [array]
            },
            .call_target => |call_target| {
                // obj.attr, obj.attr2 = 1, 2  =>  obj.attr=(1); obj.attr2=(2)
                try self.extractArrayElement(index, line);
                // Stack: [array, value]

                // Compile receiver
                const receiver_node = try self.parser.asNode(@ptrCast(call_target.receiver));
                try self.compileNode(receiver_node, line);
                // Stack: [array, value, receiver]

                // Swap to get: [array, receiver, value]
                try self.current_chunk.emitOp(.SWAP, line);

                // Get setter method name (Prism already includes the '=' in the name)
                const setter_name = try self.parser.getConstantName(@intCast(call_target.name));

                const setter_idx = try self.current_chunk.addConstant(.{ .string = setter_name });
                const receiver_style: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
                try self.current_chunk.emitCall(@intCast(setter_idx), 1, receiver_style, 0, line);
                // Stack: [array, return_value]
                try self.current_chunk.emitOp(.POP, line);
            },
            .constant_path_target => {
                // TODO: Foo::Bar = value - requires compiling the path
                std.debug.print("Constant path targets not yet supported in multi-assignment\n", .{});
                return error.UnsupportedAssignmentTarget;
            },
            .class_variable_target => {
                // TODO: @@var = value - requires class variable support
                std.debug.print("Class variable targets not yet supported in multi-assignment\n", .{});
                return error.UnsupportedAssignmentTarget;
            },
            else => {
                std.debug.print("Unsupported multi-assignment target type\n", .{});
                return error.UnsupportedAssignmentTarget;
            },
        }
    }

    fn compileNestedMultiTarget(self: *Compiler, node: *prism.MultiTargetNode, line: u32) anyerror!void {
        // At this point, the nested array is on top of the stack
        // We need to destructure it like we do in compileMultiWrite

        // DUP the array to preserve it (similar to compileMultiWrite)
        try self.current_chunk.emitOp(.DUP, line);

        // Count targets
        const left_count = node.lefts.size;
        const right_count = node.rights.size;

        // Assign to left targets
        var i: usize = 0;
        while (i < left_count) : (i += 1) {
            const target = try self.parser.asNode(node.lefts.nodes[i]);
            try self.compileMultiTarget(target, @intCast(i), line);
        }

        // Handle splat operator
        if (node.rest) |rest_ptr| {
            const rest_node = try self.parser.asNode(@ptrCast(rest_ptr));
            switch (rest_node) {
                .splat => |splat| {
                    if (splat.expression) |expr_ptr| {
                        const target = try self.parser.asNode(@ptrCast(expr_ptr));
                        try self.compileSplatAssignment(target, @intCast(left_count), @intCast(right_count), line);
                    }
                },
                .implicit_rest => {},
                else => {},
            }
        }

        // Assign to right targets
        i = 0;
        while (i < right_count) : (i += 1) {
            const target = try self.parser.asNode(node.rights.nodes[i]);
            const negative_index: i64 = -@as(i64, @intCast(right_count - i));
            try self.compileMultiTarget(target, negative_index, line);
        }

        // Pop the working array copy
        try self.current_chunk.emitOp(.POP, line);
    }

    fn extractArrayElement(self: *Compiler, index: i64, line: u32) !void {
        // Assumes array is on stack
        // Emits: DUP, PUSH_CONST(index), CALL([], 1)
        try self.current_chunk.emitOp(.DUP, line);

        const idx_const = try self.current_chunk.addConstant(.{ .integer = index });
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(idx_const), line);

        const bracket_sym = try self.current_chunk.addConstant(.{ .string = "[]" });
        const receiver_style: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
        try self.current_chunk.emitCall(@intCast(bracket_sym), 1, receiver_style, 0, line);
    }

    fn compileSplatAssignment(self: *Compiler, target: prism.Node, left_count: u8, right_count: u8, line: u32) !void {
        // Extract middle elements using array slicing with SWAP
        // Stack has: [array, ...]
        // Goal: array[left_count, array.length - left_count - right_count]

        const receiver_style: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);

        // Calculate length: array.length - left_count - right_count
        try self.current_chunk.emitOp(.DUP, line);
        const length_sym = try self.current_chunk.addConstant(.{ .string = "length" });
        try self.current_chunk.emitCall(@intCast(length_sym), 0, receiver_style, 0, line);
        // Stack: [array, length]

        const left_const = try self.current_chunk.addConstant(.{ .integer = left_count });
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(left_const), line);
        const minus_sym = try self.current_chunk.addConstant(.{ .string = "-" });
        try self.current_chunk.emitCall(@intCast(minus_sym), 1, receiver_style, 0, line);
        // Stack: [array, length - left]

        const right_const = try self.current_chunk.addConstant(.{ .integer = right_count });
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(right_const), line);
        try self.current_chunk.emitCall(@intCast(minus_sym), 1, receiver_style, 0, line);
        // Stack: [array, final_length]

        // Push start index
        const start_const = try self.current_chunk.addConstant(.{ .integer = left_count });
        try self.current_chunk.emitOpU16(.PUSH_CONST, @intCast(start_const), line);
        // Stack: [array, final_length, start]

        // Use SWAP to reorder: [array, final_length, start] → [array, start, final_length]
        try self.current_chunk.emitOp(.SWAP, line);
        // Stack: [array, start, final_length]

        // Call array[start, length]
        const bracket_sym = try self.current_chunk.addConstant(.{ .string = "[]" });
        try self.current_chunk.emitCall(@intCast(bracket_sym), 2, receiver_style, 0, line);
        // Stack: [result_array]

        // Assign to target variable
        // Stack: [result_array]
        switch (target) {
            .local_variable_target => |var_target| {
                const var_name = try self.parser.getLocalVariableName(var_target.name);
                const slot = try self.resolveOrCreateLocalSlot(var_name);
                try self.emitSetLocalSlot(slot, line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .global_variable_target => |var_target| {
                const var_name = try self.parser.getConstantName(@intCast(var_target.name));
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_GLOBAL, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .instance_variable_target => |var_target| {
                const var_name = try self.parser.getConstantName(@intCast(var_target.name));
                const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });
                try self.current_chunk.emitOpU16(.SET_IVAR, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .constant_target => |const_target| {
                const const_name = try self.parser.getConstantName(@intCast(const_target.name));
                const name_idx = try self.current_chunk.addConstant(.{ .string = const_name });
                try self.current_chunk.emitOpU16(.SET_CONST, @intCast(name_idx), line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .index_target => |index_target| {
                // *rest, arr[0] = ...  =>  arr.[]=(0, result_array)
                // Stack: [result_array]

                // Compile receiver
                const receiver_node = try self.parser.asNode(@ptrCast(index_target.receiver));
                try self.compileNode(receiver_node, line);
                // Stack: [result_array, receiver]

                // Swap to get: [receiver, result_array]
                try self.current_chunk.emitOp(.SWAP, line);

                // Compile index arguments
                const args_node = @as(*prism.ArgumentsNode, @ptrCast(index_target.arguments));
                const argc = args_node.arguments.size;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    const arg_node = try self.parser.asNode(args_node.arguments.nodes[i]);
                    try self.compileNode(arg_node, line);
                }
                // Stack: [receiver, result_array, index]

                // Swap to move value to end: [receiver, index, result_array]
                try self.current_chunk.emitOp(.SWAP, line);

                // Call []=(index, result_array)
                const bracket_eq = try self.current_chunk.addConstant(.{ .string = "[]=" });
                const rs: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
                try self.current_chunk.emitCall(@intCast(bracket_eq), @intCast(argc + 1), rs, 0, line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .call_target => |call_target| {
                // *rest, obj.attr = ...  =>  obj.attr=(result_array)
                // Stack: [result_array]

                // Compile receiver
                const receiver_node = try self.parser.asNode(@ptrCast(call_target.receiver));
                try self.compileNode(receiver_node, line);
                // Stack: [result_array, receiver]

                // Swap to get: [receiver, result_array]
                try self.current_chunk.emitOp(.SWAP, line);

                // Get setter method name (Prism already includes the '=' in the name)
                const setter_name = try self.parser.getConstantName(@intCast(call_target.name));

                const setter_idx = try self.current_chunk.addConstant(.{ .string = setter_name });
                const rs: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
                try self.current_chunk.emitCall(@intCast(setter_idx), 1, rs, 0, line);
                try self.current_chunk.emitOp(.POP, line);
            },
            .constant_path_target => {
                // TODO: Foo::Bar = value - requires compiling the path
                std.debug.print("Constant path targets not yet supported in splat assignment\n", .{});
                return error.UnsupportedSplatTarget;
            },
            .class_variable_target => {
                // TODO: @@var = value - requires class variable support
                std.debug.print("Class variable targets not yet supported in splat assignment\n", .{});
                return error.UnsupportedSplatTarget;
            },
            else => {
                std.debug.print("Unsupported splat target type\n", .{});
                return error.UnsupportedSplatTarget;
            },
        }
    }

    fn compileLocalAndWrite(self: *Compiler, var_write: *prism.LocalVariableAndWriteNode, line: u32) !void {
        const var_name = try self.parser.getLocalVariableName(var_write.name);
        const slot = try self.resolveOrCreateLocalSlot(var_name);

        try self.emitGetLocalSlot(slot, line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.emitSetLocalSlot(slot, line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileLocalOrWrite(self: *Compiler, var_write: *prism.LocalVariableOrWriteNode, line: u32) !void {
        const var_name = try self.parser.getLocalVariableName(var_write.name);
        const slot = try self.resolveOrCreateLocalSlot(var_name);

        try self.emitGetLocalSlot(slot, line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.emitSetLocalSlot(slot, line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileLocalOperatorWrite(self: *Compiler, var_write: *prism.LocalVariableOperatorWriteNode, line: u32) !void {
        const var_name = try self.parser.getLocalVariableName(var_write.name);
        const slot = try self.resolveExistingLocalSlot(var_name);

        try self.emitGetLocalSlot(slot, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);

        const operator_name = try self.parser.getConstantName(@intCast(var_write.binary_operator));
        const method_idx = try self.current_chunk.addConstant(.{ .string = operator_name });
        const receiver_style: u8 = @intFromEnum(bytecode.ReceiverCallStyle.explicit);
        try self.current_chunk.emitCall(@intCast(method_idx), 1, receiver_style, 0, line);

        try self.emitSetLocalSlot(slot, line);
    }

    fn compileGlobalAndWrite(self: *Compiler, var_write: *prism.GlobalVariableAndWriteNode, line: u32) !void {
        const var_name = try self.parser.getConstantName(@intCast(var_write.name));
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });

        try self.current_chunk.emitOpU16(.GET_GLOBAL, @intCast(name_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_GLOBAL, @intCast(name_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileGlobalOrWrite(self: *Compiler, var_write: *prism.GlobalVariableOrWriteNode, line: u32) !void {
        const var_name = try self.parser.getConstantName(@intCast(var_write.name));
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });

        try self.current_chunk.emitOpU16(.GET_GLOBAL, @intCast(name_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_GLOBAL, @intCast(name_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileInstanceVariableAndWrite(self: *Compiler, var_write: *prism.InstanceVariableAndWriteNode, line: u32) !void {
        const var_name = try self.parser.getConstantName(@intCast(var_write.name));
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });

        try self.current_chunk.emitOpU16(.GET_IVAR, @intCast(name_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_IVAR, @intCast(name_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileInstanceVariableOrWrite(self: *Compiler, var_write: *prism.InstanceVariableOrWriteNode, line: u32) !void {
        const var_name = try self.parser.getConstantName(@intCast(var_write.name));
        const name_idx = try self.current_chunk.addConstant(.{ .symbol = var_name });

        try self.current_chunk.emitOpU16(.GET_IVAR, @intCast(name_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(var_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_IVAR, @intCast(name_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileConstantAndWrite(self: *Compiler, const_write: *prism.ConstantAndWriteNode, line: u32) !void {
        const const_name = try self.parser.getConstantName(const_write.name);
        const const_idx = try self.current_chunk.addConstant(.{ .symbol = const_name });

        try self.current_chunk.emitOpU16(.GET_CONST, @intCast(const_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_FALSE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(const_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_CONST, @intCast(const_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileConstantOrWrite(self: *Compiler, const_write: *prism.ConstantOrWriteNode, line: u32) !void {
        const const_name = try self.parser.getConstantName(const_write.name);
        const const_idx = try self.current_chunk.addConstant(.{ .symbol = const_name });

        try self.current_chunk.emitOpU16(.GET_CONST_OR_NIL, @intCast(const_idx), line);
        try self.current_chunk.emitOp(.DUP, line);
        const jump_end = try self.current_chunk.emitJump(.JUMP_IF_TRUE, line);
        try self.current_chunk.emitOp(.POP, line);

        const value_node = try self.parser.asNode(@ptrCast(const_write.value));
        try self.compileNode(value_node, line);
        try self.current_chunk.emitOpU16(.SET_CONST, @intCast(const_idx), line);

        try self.current_chunk.patchJump(jump_end);
    }

    fn compileAliasMethod(self: *Compiler, alias_node: *prism.AliasMethodNode, line: u32) anyerror!void {
        // Both new_name and old_name are SymbolNodes in `alias new_name old_name`
        const new_name_node: *prism.SymbolNode = @ptrCast(alias_node.new_name);
        const new_name = new_name_node.unescaped.source[0..new_name_node.unescaped.length];
        const new_name_idx = try self.current_chunk.addConstant(.{ .symbol = new_name });

        const old_name_node: *prism.SymbolNode = @ptrCast(alias_node.old_name);
        const old_name = old_name_node.unescaped.source[0..old_name_node.unescaped.length];
        const old_name_idx = try self.current_chunk.addConstant(.{ .symbol = old_name });

        try self.current_chunk.emitOpU16U16(.ALIAS_METHOD, @intCast(new_name_idx), @intCast(old_name_idx), line);
    }

    fn compileModule(self: *Compiler, module_node: *prism.ModuleNode, line: u32) anyerror!void {
        // Get the module name
        const module_name = try self.parser.getConstantName(module_node.name);

        // Add the module name as a constant
        const idx = try self.current_chunk.addConstant(.{ .string = module_name });

        // Create a separate chunk for the module body
        var body_chunk_id: u16 = 0;
        if (module_node.body) |body_ptr| {
            // Allocate chunk on heap and track it immediately (before compilation can fail)
            const body_chunk_ptr = try self.allocator.create(Chunk);
            body_chunk_ptr.* = Chunk.init(self.allocator, module_name);
            body_chunk_ptr.source_file = self.parser.source_file;
            body_chunk_id = try self.nextChunkId();
            body_chunk_ptr.chunk_id = body_chunk_id;
            try self.method_chunks.put(body_chunk_id, body_chunk_ptr);

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

            // Restore the original chunk
            self.current_chunk = saved_chunk;
        }

        // Emit DEF_MODULE instruction with the body chunk ID
        try self.current_chunk.emitOpU16U16(.DEF_MODULE, @intCast(idx), body_chunk_id, line);
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
        var body_chunk_id: u16 = 0;
        if (class_node.body) |body_ptr| {
            // Allocate chunk on heap and track it immediately (before compilation can fail)
            const body_chunk_ptr = try self.allocator.create(Chunk);
            body_chunk_ptr.* = Chunk.init(self.allocator, class_name);
            body_chunk_ptr.source_file = self.parser.source_file;
            body_chunk_id = try self.nextChunkId();
            body_chunk_ptr.chunk_id = body_chunk_id;
            try self.method_chunks.put(body_chunk_id, body_chunk_ptr);

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

            // Restore the original chunk
            self.current_chunk = saved_chunk;
        }

        // Emit DEF_CLASS instruction with the body chunk ID
        try self.current_chunk.emitOpU16U16(.DEF_CLASS, @intCast(idx), body_chunk_id, line);
    }

    /// Process optional parameters and compile their default expressions
    /// Phase 1: Register optional parameter names as locals (no default compilation).
    /// Default expressions are compiled later by compileOptionalDefaults to keep
    /// parameter slots contiguous (side-effect locals go after all params).
    fn processOptionalParameters(
        self: *Compiler,
        params: *prism.ParametersNode,
    ) !void {
        if (params.optionals.size > 0) {
            if (params.optionals.size > 255) {
                return error.TooManyParameters;
            }

            var i: usize = 0;
            while (i < params.optionals.size) : (i += 1) {
                const opt_node_ptr = params.optionals.nodes[i];
                const opt_node = try self.parser.asNode(@ptrCast(opt_node_ptr));

                if (opt_node != .optional_parameter) {
                    return error.UnexpectedNode;
                }

                const opt_param = opt_node.optional_parameter;
                const param_name = try self.parser.getLocalVariableName(opt_param.name);
                try self.addLocal(param_name);
            }
        }
    }

    /// Phase 2: Compile default expressions for optional parameters.
    /// Called after all parameter names are registered so side-effect locals
    /// (e.g., x in `a=(x=23)`) get slots after all parameters.
    fn compileOptionalDefaults(
        self: *Compiler,
        params: *prism.ParametersNode,
        target_chunk: *Chunk,
        optional_start_slot: u8,
        line: u32,
    ) !void {
        if (params.optionals.size == 0) return;

        var i: usize = 0;
        while (i < params.optionals.size) : (i += 1) {
            const opt_node_ptr = params.optionals.nodes[i];
            const opt_node = try self.parser.asNode(@ptrCast(opt_node_ptr));
            const opt_param = opt_node.optional_parameter;

            const param_idx = optional_start_slot + @as(u8, @intCast(i));

            // Compile default expression into a mini-chunk
            const default_chunk_ptr = try self.allocator.create(chunk.Chunk);
            default_chunk_ptr.* = chunk.Chunk.init(self.allocator, "default");
            default_chunk_ptr.source_file = self.parser.source_file;
            const default_chunk_id = try self.nextChunkId();
            default_chunk_ptr.chunk_id = default_chunk_id;
            try self.method_chunks.put(default_chunk_id, default_chunk_ptr);

            const saved_chunk_for_default = self.current_chunk;
            self.current_chunk = default_chunk_ptr;

            // Compile the default value expression
            const value_node = try self.parser.asNode(@ptrCast(opt_param.value));
            try self.compileNode(value_node, line);

            // Default chunks implicitly return their value
            try self.current_chunk.emitOpU8(.RETURN, 0, line);

            // Restore chunk (but NOT locals — side-effect locals persist)
            self.current_chunk = saved_chunk_for_default;

            // Record optional param metadata
            try target_chunk.optional_params.append(self.allocator, .{
                .param_index = param_idx,
                .default_chunk_id = @intCast(default_chunk_id),
            });
        }
    }

    const ParameterCounts = struct {
        param_count: u8,
        rest_param_idx: ?u8,
        post_count: u8,
    };

    /// Process all parameters for a chunk (required, optional, rest, post-rest, keywords)
    fn processAllParameters(
        self: *Compiler,
        params: *prism.ParametersNode,
        target_chunk: *Chunk,
        line: u32,
    ) !ParameterCounts {
        var param_count: u8 = 0;
        var rest_param_idx: ?u8 = null;
        var post_count: u8 = 0;

        // 1. Process pre-rest required parameters
        if (params.requireds.size > 0) {
            var i: usize = 0;
            while (i < params.requireds.size) : (i += 1) {
                const param_node = params.requireds.nodes[i];
                const param = @as(*prism.RequiredParameterNode, @ptrCast(param_node));
                const param_name = try self.parser.getLocalVariableName(param.name);
                try self.addLocal(param_name);
                param_count += 1;
            }
        }

        // 2. Process optional parameters (names only — defaults compiled in step 7)
        const optional_start_slot = @as(u8, @intCast(self.locals.items.len));
        try self.processOptionalParameters(params);

        // 3. Process rest parameter
        if (params.rest) |rest_ptr| {
            const rest_node = try self.parser.asNode(@ptrCast(rest_ptr));
            if (rest_node == .rest_parameter) {
                const rest_param = rest_node.rest_parameter;

                // Rest parameter can have a name or be anonymous (*)
                if (rest_param.name != 0) {
                    const rest_name = try self.parser.getLocalVariableName(rest_param.name);
                    try self.addLocal(rest_name);
                } else {
                    // Anonymous rest: still need a slot, use placeholder
                    try self.addLocal("*");
                }

                rest_param_idx = @intCast(self.locals.items.len - 1);
            }
        }

        // 4. Process post-rest required parameters
        if (params.posts.size > 0) {
            if (params.posts.size > 255) {
                return error.TooManyParameters;
            }
            post_count = @as(u8, @intCast(params.posts.size));
            var i: usize = 0;
            while (i < params.posts.size) : (i += 1) {
                const param_node = params.posts.nodes[i];
                const param = @as(*prism.RequiredParameterNode, @ptrCast(param_node));
                const param_name = try self.parser.getLocalVariableName(param.name);
                try self.addLocal(param_name);
            }
        }

        // 5. Process keyword parameters
        try self.processKeywordParameters(target_chunk, params, line);

        // 6. Process block parameter
        if (params.block) |block_ptr| {
            const block_node = try self.parser.asNode(@ptrCast(block_ptr));
            if (block_node == .block_parameter) {
                const block_param = block_node.block_parameter;
                const block_name = try self.parser.getLocalVariableName(block_param.name);
                try self.addLocal(block_name);
                const block_idx = @as(u8, @intCast(self.locals.items.len - 1));
                target_chunk.block_param_index = block_idx;
            } else {
                unreachable;
            }
        }

        // 7. Compile optional defaults (after all param names are registered,
        // so side-effect locals get slots after all parameters)
        try self.compileOptionalDefaults(params, target_chunk, optional_start_slot, line);

        return .{
            .param_count = param_count,
            .rest_param_idx = rest_param_idx,
            .post_count = post_count,
        };
    }

    /// Process keyword parameters (required, optional, keyword rest) for a chunk
    fn processKeywordParameters(
        self: *Compiler,
        target_chunk: *Chunk,
        params: *prism.ParametersNode,
        line: u32,
    ) !void {
        // Process keyword parameters
        if (params.keywords.size > 0) {
            var i: usize = 0;
            while (i < params.keywords.size) : (i += 1) {
                const kw_node_ptr = params.keywords.nodes[i];
                const kw_node = try self.parser.asNode(@ptrCast(kw_node_ptr));

                if (kw_node == .required_keyword_parameter) {
                    const kw_param = kw_node.required_keyword_parameter;
                    const param_name = try self.parser.getLocalVariableName(kw_param.name);
                    try self.addLocal(param_name);
                    const slot = @as(u8, @intCast(self.locals.items.len - 1));
                    const name_idx = try target_chunk.addConstant(.{ .symbol = param_name });
                    try target_chunk.required_keywords.append(self.allocator, .{
                        .name_idx = @intCast(name_idx),
                        .param_slot = slot,
                    });
                } else if (kw_node == .optional_keyword_parameter) {
                    const kw_param = kw_node.optional_keyword_parameter;
                    const param_name = try self.parser.getLocalVariableName(kw_param.name);
                    try self.addLocal(param_name);
                    const slot = @as(u8, @intCast(self.locals.items.len - 1));

                    // Compile default expression into separate chunk (track immediately before compilation)
                    const default_chunk_ptr = try self.allocator.create(Chunk);
                    default_chunk_ptr.* = Chunk.init(self.allocator, "keyword_default");
                    default_chunk_ptr.source_file = self.parser.source_file;
                    const default_chunk_id = try self.nextChunkId();
                    default_chunk_ptr.chunk_id = default_chunk_id;
                    try self.method_chunks.put(default_chunk_id, default_chunk_ptr);

                    const saved_chunk_kw = self.current_chunk;
                    self.current_chunk = default_chunk_ptr;

                    const default_expr = try self.parser.asNode(@ptrCast(kw_param.value));
                    try self.compileNode(default_expr, line);
                    try self.current_chunk.emitOpU8(.RETURN, 0, line);

                    self.current_chunk = saved_chunk_kw;

                    const name_idx = try target_chunk.addConstant(.{ .symbol = param_name });
                    try target_chunk.optional_keywords.append(self.allocator, .{
                        .name_idx = @intCast(name_idx),
                        .param_slot = slot,
                        .default_chunk_id = @intCast(default_chunk_id),
                    });
                }
            }
        }

        // Process keyword rest parameter
        if (params.keyword_rest) |kw_rest_ptr| {
            const kw_rest_node = try self.parser.asNode(@ptrCast(kw_rest_ptr));

            if (kw_rest_node == .keyword_rest_parameter) {
                const kw_rest = kw_rest_node.keyword_rest_parameter;
                if (kw_rest.name != 0) {
                    const rest_name = try self.parser.getLocalVariableName(kw_rest.name);
                    try self.addLocal(rest_name);
                } else {
                    try self.addLocal("**");
                }
                target_chunk.keyword_rest_index = @intCast(self.locals.items.len - 1);
            } else if (kw_rest_node == .no_keywords_parameter) {
                target_chunk.no_keywords = true;
            }
        }
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

        // Allocate chunk on heap and track it immediately (before compilation can fail)
        const method_chunk_ptr = try self.allocator.create(Chunk);
        method_chunk_ptr.* = Chunk.init(self.allocator, method_name_slice);
        method_chunk_ptr.source_file = self.parser.source_file;
        const chunk_id = try self.nextChunkId();
        method_chunk_ptr.chunk_id = chunk_id;
        try self.method_chunks.put(chunk_id, method_chunk_ptr);

        // Save the current chunk and switch to the method chunk
        const saved_chunk = self.current_chunk;
        const saved_locals_len = self.locals.items.len;
        self.current_chunk = method_chunk_ptr;

        // Process parameters (if any)
        var param_count: u8 = 0;
        var rest_param_idx: ?u8 = null;
        var post_count: u8 = 0;

        if (def_node.parameters) |params_ptr| {
            const params = @as(*prism.ParametersNode, @ptrCast(params_ptr));
            const counts = try self.processAllParameters(params, method_chunk_ptr, line);
            param_count = counts.param_count;
            rest_param_idx = counts.rest_param_idx;
            post_count = counts.post_count;
        }

        // Store parameter metadata on chunk
        method_chunk_ptr.arity = param_count;
        method_chunk_ptr.rest_param_index = rest_param_idx;
        method_chunk_ptr.post_required_count = post_count;

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

    fn compileBlock(self: *Compiler, block_node: *prism.BlockNode, line: u32) !u16 {
        // Allocate chunk on heap and track it immediately (before compilation can fail)
        const block_chunk_ptr = try self.allocator.create(Chunk);
        block_chunk_ptr.* = Chunk.init(self.allocator, "block");
        block_chunk_ptr.source_file = self.parser.source_file;
        const chunk_id = try self.nextChunkId();
        block_chunk_ptr.chunk_id = chunk_id;
        try self.method_chunks.put(chunk_id, block_chunk_ptr);

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
        var param_count: u8 = 0; // Pre-rest required count
        var rest_param_idx: ?u8 = null;
        var post_count: u8 = 0;

        if (block_node.parameters) |params_ptr| {
            // Block parameters are wrapped in BlockParametersNode
            const params_node = try self.parser.asNode(@ptrCast(params_ptr));
            if (params_node == .block_parameters) {
                const block_params = params_node.block_parameters;
                if (block_params.parameters) |actual_params_ptr| {
                    const params = @as(*prism.ParametersNode, @ptrCast(actual_params_ptr));
                    const counts = try self.processAllParameters(params, block_chunk_ptr, line);
                    param_count = counts.param_count;
                    rest_param_idx = counts.rest_param_idx;
                    post_count = counts.post_count;
                }
            }
        }

        // Store parameter metadata on chunk
        block_chunk_ptr.arity = param_count;
        block_chunk_ptr.rest_param_index = rest_param_idx;
        block_chunk_ptr.post_required_count = post_count;

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

        return @intCast(chunk_id);
    }

    fn compileLambda(self: *Compiler, lambda_node: *prism.LambdaNode, line: u32) !u16 {
        // Allocate chunk on heap and track it immediately (before compilation can fail)
        const lambda_chunk_ptr = try self.allocator.create(Chunk);
        lambda_chunk_ptr.* = Chunk.init(self.allocator, "lambda");
        lambda_chunk_ptr.is_lambda = true; // Mark as lambda
        lambda_chunk_ptr.source_file = self.parser.source_file;
        const chunk_id = try self.nextChunkId();
        lambda_chunk_ptr.chunk_id = chunk_id;
        try self.method_chunks.put(chunk_id, lambda_chunk_ptr);

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
        var param_count: u8 = 0; // Pre-rest required count
        var rest_param_idx: ?u8 = null;
        var post_count: u8 = 0;

        if (lambda_node.parameters) |params_ptr| {
            const params_node = try self.parser.asNode(@ptrCast(params_ptr));

            // Lambda parameters can be either BlockParametersNode or ParametersNode
            if (params_node == .block_parameters) {
                const block_params = params_node.block_parameters;
                if (block_params.parameters) |actual_params_ptr| {
                    const params = @as(*prism.ParametersNode, @ptrCast(actual_params_ptr));
                    const counts = try self.processAllParameters(params, lambda_chunk_ptr, line);
                    param_count = counts.param_count;
                    rest_param_idx = counts.rest_param_idx;
                    post_count = counts.post_count;
                }
            }
        }

        // Store parameter metadata on chunk
        lambda_chunk_ptr.arity = param_count;
        lambda_chunk_ptr.rest_param_index = rest_param_idx;
        lambda_chunk_ptr.post_required_count = post_count;

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
