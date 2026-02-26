const std = @import("std");
const prism = @import("prism.zig");

const OpCode = enum(u8) {
    push_i64,
    load_local_n,
    add,
    sub,
    eq,
    pop,
    jump_if_false,
    jump,
    call_fib,
    print,
    ret,
    halt,
};

const Chunk = struct {
    code: std.ArrayList(u8) = .empty,
    imm_i64_by_ip: std.ArrayList(i64) = .empty,
    imm_u32_by_ip: std.ArrayList(u32) = .empty,

    fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
        self.imm_i64_by_ip.deinit(allocator);
        self.imm_u32_by_ip.deinit(allocator);
    }

    fn appendSlot(self: *Chunk, allocator: std.mem.Allocator, op: OpCode) !usize {
        try self.code.append(allocator, @intFromEnum(op));
        try self.imm_i64_by_ip.append(allocator, 0);
        try self.imm_u32_by_ip.append(allocator, 0);
        return self.code.items.len - 1;
    }

    fn emit(self: *Chunk, allocator: std.mem.Allocator, op: OpCode) !usize {
        return self.appendSlot(allocator, op);
    }

    fn emitI64(self: *Chunk, allocator: std.mem.Allocator, op: OpCode, imm: i64) !usize {
        const ip = try self.appendSlot(allocator, op);
        self.imm_i64_by_ip.items[ip] = imm;
        return ip;
    }

    fn emitU32(self: *Chunk, allocator: std.mem.Allocator, op: OpCode, imm: u32) !usize {
        const ip = try self.appendSlot(allocator, op);
        self.imm_u32_by_ip.items[ip] = imm;
        return ip;
    }
};

const LiteCompiler = struct {
    allocator: std.mem.Allocator,
    parser: *prism.Parser,
    fib_chunk: Chunk = .{},
    main_chunk: Chunk = .{},
    top_call_n: i64 = -1,

    fn deinit(self: *LiteCompiler) void {
        self.fib_chunk.deinit(self.allocator);
        self.main_chunk.deinit(self.allocator);
    }

    fn compile(self: *LiteCompiler) !void {
        const root = try self.parser.root();
        if (root != .program) return error.UnsupportedProgram;

        const stmts_ptr = root.program.statements orelse return error.UnsupportedProgram;
        const stmts = try self.parser.asNode(@ptrCast(stmts_ptr));
        if (stmts != .statements) return error.UnsupportedProgram;
        if (stmts.statements.body.size < 2) return error.UnsupportedProgram;

        const def_node = try self.parser.asNode(stmts.statements.body.nodes[0]);
        if (def_node != .def) return error.UnsupportedProgram;
        try self.compileFibDef(def_node.def);

        const call_node = try self.parser.asNode(stmts.statements.body.nodes[1]);
        if (call_node != .call) return error.UnsupportedProgram;
        try self.compileTopLevelCall(call_node.call);
        _ = try self.main_chunk.emit(self.allocator, .halt);

        if (self.top_call_n < 0) return error.UnsupportedProgram;
    }

    fn compileFibDef(self: *LiteCompiler, def_node: *prism.DefNode) !void {
        const method_name = try self.parser.getConstantName(def_node.name);
        if (!std.mem.eql(u8, method_name, "fib")) return error.UnsupportedProgram;
        if (def_node.receiver != null) return error.UnsupportedProgram;

        const params_ptr = def_node.parameters orelse return error.UnsupportedProgram;
        const params = @as(*prism.ParametersNode, @ptrCast(params_ptr));
        if (params.requireds.size != 1 or params.optionals.size != 0 or params.rest != null or params.posts.size != 0 or params.keywords.size != 0 or params.keyword_rest != null or params.block != null) {
            return error.UnsupportedProgram;
        }

        const req_node = try self.parser.asNode(params.requireds.nodes[0]);
        if (req_node != .required_parameter) return error.UnsupportedProgram;
        const param_name = try self.parser.getLocalVariableName(req_node.required_parameter.name);
        if (!std.mem.eql(u8, param_name, "n")) return error.UnsupportedProgram;

        const body_ptr = def_node.body orelse return error.UnsupportedProgram;
        const body_node = try self.parser.asNode(@ptrCast(body_ptr));
        try self.compileExprToChunk(body_node, &self.fib_chunk);
        _ = try self.fib_chunk.emit(self.allocator, .ret);
    }

    fn compileTopLevelCall(self: *LiteCompiler, call_node: *prism.CallNode) !void {
        if (call_node.receiver != null) return error.UnsupportedProgram;
        const name = try self.parser.getConstantName(call_node.name);
        if (!std.mem.eql(u8, name, "puts")) return error.UnsupportedProgram;
        const args_ptr = call_node.arguments orelse return error.UnsupportedProgram;
        const args = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
        if (args.arguments.size != 1) return error.UnsupportedProgram;

        const fib_call = try self.parser.asNode(args.arguments.nodes[0]);
        if (fib_call != .call) return error.UnsupportedProgram;

        const fib_name = try self.parser.getConstantName(fib_call.call.name);
        if (fib_call.call.receiver != null or !std.mem.eql(u8, fib_name, "fib")) return error.UnsupportedProgram;
        const fib_args_ptr = fib_call.call.arguments orelse return error.UnsupportedProgram;
        const fib_args = @as(*prism.ArgumentsNode, @ptrCast(fib_args_ptr));
        if (fib_args.arguments.size != 1) return error.UnsupportedProgram;
        const n_node = try self.parser.asNode(fib_args.arguments.nodes[0]);
        if (n_node != .integer) return error.UnsupportedProgram;

        const n = self.parser.integerNodeToI64(n_node.integer) orelse return error.UnsupportedProgram;
        self.top_call_n = n;
        _ = try self.main_chunk.emitI64(self.allocator, .push_i64, n);
        _ = try self.main_chunk.emit(self.allocator, .call_fib);
        _ = try self.main_chunk.emit(self.allocator, .print);
    }

    fn compileExprToChunk(self: *LiteCompiler, node: prism.Node, chunk: *Chunk) anyerror!void {
        switch (node) {
            .statements => |stmts| {
                var i: usize = 0;
                while (i < stmts.body.size) : (i += 1) {
                    const child = try self.parser.asNode(stmts.body.nodes[i]);
                    try self.compileExprToChunk(child, chunk);
                    if (i + 1 < stmts.body.size) {
                        _ = try chunk.emit(self.allocator, .pop);
                    }
                }
            },
            .integer => |int_node| {
                const v = self.parser.integerNodeToI64(int_node) orelse return error.UnsupportedProgram;
                _ = try chunk.emitI64(self.allocator, .push_i64, v);
            },
            .local_variable_read => |var_read| {
                const name = try self.parser.getLocalVariableName(var_read.name);
                if (!std.mem.eql(u8, name, "n")) return error.UnsupportedProgram;
                _ = try chunk.emit(self.allocator, .load_local_n);
            },
            .if_node => |if_node| {
                try self.compileExprToChunk(try self.parser.asNode(@ptrCast(if_node.predicate)), chunk);
                const jfalse_idx = try chunk.emitU32(self.allocator, .jump_if_false, 0);

                if (if_node.statements) |then_ptr| {
                    try self.compileExprToChunk(try self.parser.asNode(@ptrCast(then_ptr)), chunk);
                } else {
                    _ = try chunk.emitI64(self.allocator, .push_i64, 0);
                }
                const jend_idx = try chunk.emitU32(self.allocator, .jump, 0);

                chunk.imm_u32_by_ip.items[jfalse_idx] = @intCast(chunk.code.items.len);
                if (if_node.subsequent) |sub_ptr| {
                    const sub = try self.parser.asNode(@ptrCast(sub_ptr));
                    switch (sub) {
                        .if_node, .else_node => try self.compileExprToChunk(sub, chunk),
                        else => return error.UnsupportedProgram,
                    }
                } else {
                    _ = try chunk.emitI64(self.allocator, .push_i64, 0);
                }
                chunk.imm_u32_by_ip.items[jend_idx] = @intCast(chunk.code.items.len);
            },
            .else_node => |else_node| {
                if (else_node.statements) |else_ptr| {
                    try self.compileExprToChunk(try self.parser.asNode(@ptrCast(else_ptr)), chunk);
                } else {
                    _ = try chunk.emitI64(self.allocator, .push_i64, 0);
                }
            },
            .call => |call_node| {
                const method_name = try self.parser.getConstantName(call_node.name);
                const args_ptr = call_node.arguments orelse return error.UnsupportedProgram;
                const args = @as(*prism.ArgumentsNode, @ptrCast(args_ptr));
                if (args.arguments.size != 1) return error.UnsupportedProgram;
                const arg0 = try self.parser.asNode(args.arguments.nodes[0]);

                if (call_node.receiver) |recv_ptr| {
                    const recv = try self.parser.asNode(@ptrCast(recv_ptr));
                    try self.compileExprToChunk(recv, chunk);
                    try self.compileExprToChunk(arg0, chunk);
                    if (std.mem.eql(u8, method_name, "+")) {
                        _ = try chunk.emit(self.allocator, .add);
                    } else if (std.mem.eql(u8, method_name, "-")) {
                        _ = try chunk.emit(self.allocator, .sub);
                    } else if (std.mem.eql(u8, method_name, "==")) {
                        _ = try chunk.emit(self.allocator, .eq);
                    } else {
                        return error.UnsupportedProgram;
                    }
                    return;
                }

                if (std.mem.eql(u8, method_name, "fib")) {
                    try self.compileExprToChunk(arg0, chunk);
                    _ = try chunk.emit(self.allocator, .call_fib);
                    return;
                }

                return error.UnsupportedProgram;
            },
            .parentheses => |paren| {
                if (paren.body) |body_ptr| {
                    try self.compileExprToChunk(try self.parser.asNode(@ptrCast(body_ptr)), chunk);
                } else {
                    _ = try chunk.emitI64(self.allocator, .push_i64, 0);
                }
            },
            else => return error.UnsupportedProgram,
        }
    }
};

const LiteVm = struct {
    fib_chunk: *const Chunk,
    main_chunk: *const Chunk,

    const Frame = struct {
        chunk: *const Chunk,
        ip: usize,
        local_n: i64,
        base_sp: usize,
    };

    fn run(self: *LiteVm, print_output: bool) !i64 {
        var value_stack: [8192]i64 = undefined;
        var sp: usize = 0;

        var frames: [2048]Frame = undefined;
        var frame_len: usize = 1;
        frames[0] = .{
            .chunk = self.main_chunk,
            .ip = 0,
            .local_n = 0,
            .base_sp = 0,
        };

        var final_result: i64 = 0;

        while (frame_len > 0) {
            var frame = &frames[frame_len - 1];
            if (frame.ip >= frame.chunk.code.items.len) {
                const ret = if (sp > frame.base_sp) value_stack[sp - 1] else 0;
                sp = frame.base_sp;
                frame_len -= 1;
                if (frame_len == 0) {
                    final_result = ret;
                    break;
                }
                value_stack[sp] = ret;
                sp += 1;
                continue;
            }

            const ip = frame.ip;
            const op: OpCode = @enumFromInt(frame.chunk.code.items[ip]);
            switch (op) {
                .push_i64 => {
                    value_stack[sp] = frame.chunk.imm_i64_by_ip.items[ip];
                    sp += 1;
                    frame.ip += 1;
                },
                .load_local_n => {
                    value_stack[sp] = frame.local_n;
                    sp += 1;
                    frame.ip += 1;
                },
                .add => {
                    const rhs = value_stack[sp - 1];
                    const lhs = value_stack[sp - 2];
                    sp -= 2;
                    value_stack[sp] = lhs + rhs;
                    sp += 1;
                    frame.ip += 1;
                },
                .sub => {
                    const rhs = value_stack[sp - 1];
                    const lhs = value_stack[sp - 2];
                    sp -= 2;
                    value_stack[sp] = lhs - rhs;
                    sp += 1;
                    frame.ip += 1;
                },
                .eq => {
                    const rhs = value_stack[sp - 1];
                    const lhs = value_stack[sp - 2];
                    sp -= 2;
                    value_stack[sp] = if (lhs == rhs) 1 else 0;
                    sp += 1;
                    frame.ip += 1;
                },
                .pop => {
                    sp -= 1;
                    frame.ip += 1;
                },
                .jump_if_false => {
                    const cond = value_stack[sp - 1];
                    sp -= 1;
                    frame.ip = if (cond == 0) frame.chunk.imm_u32_by_ip.items[ip] else ip + 1;
                },
                .jump => {
                    frame.ip = frame.chunk.imm_u32_by_ip.items[ip];
                },
                .call_fib => {
                    const n = value_stack[sp - 1];
                    sp -= 1;
                    frame.ip += 1;

                    if (frame_len >= frames.len) return error.CallStackOverflow;
                    frames[frame_len] = .{
                        .chunk = self.fib_chunk,
                        .ip = 0,
                        .local_n = n,
                        .base_sp = sp,
                    };
                    frame_len += 1;
                },
                .print => {
                    const val = value_stack[sp - 1];
                    sp -= 1;
                    if (print_output) {
                        std.debug.print("{d}\n", .{val});
                    }
                    frame.ip += 1;
                },
                .ret => {
                    const ret = if (sp > frame.base_sp) value_stack[sp - 1] else 0;
                    sp = frame.base_sp;
                    frame_len -= 1;
                    if (frame_len == 0) {
                        final_result = ret;
                        break;
                    }
                    value_stack[sp] = ret;
                    sp += 1;
                },
                .halt => {
                    final_result = if (sp > 0) value_stack[sp - 1] else 0;
                    break;
                },
            }
        }

        return final_result;
    }
};

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const allocator = gpa_impl.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const filename = if (args.len >= 2) args[1] else "examples/fib.rb";
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const size = try file.getEndPos();
    const src = try allocator.alloc(u8, size);
    defer allocator.free(src);
    const read_n = try file.readAll(src);
    if (read_n != size) return error.ShortRead;

    var parser = try prism.Parser.init(allocator, src, filename);
    defer parser.deinit();

    var compiler: LiteCompiler = .{
        .allocator = allocator,
        .parser = &parser,
    };
    defer compiler.deinit();
    try compiler.compile();

    var vm: LiteVm = .{
        .fib_chunk = &compiler.fib_chunk,
        .main_chunk = &compiler.main_chunk,
    };

    // Run once and print only program output.
    _ = try vm.run(true);
}
