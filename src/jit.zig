const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk_mod = @import("chunk.zig");
const tcc = @import("tcc.zig");

pub const available = tcc.available;
pub const CompiledFn = *const fn (u64, u64, *u8) callconv(.c) u64;

pub const State = struct {
    compilation: tcc.Compilation = .{},
    entry: ?CompiledFn = null,
    compiled_method_state_version: u64 = 0,
    failed_method_state_version: u64 = 0,
    last_error: ?[]u8 = null,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.compilation.deinit();
        self.entry = null;
        self.compiled_method_state_version = 0;
        self.failed_method_state_version = 0;
        if (self.last_error) |msg| {
            allocator.free(msg);
            self.last_error = null;
        }
    }
};

pub const GeneratedChunk = struct {
    symbol_name: [:0]u8,
    source_code: [:0]u8,
};

pub export fn cora_jit_add(a: u64, b: u64, ok: *u8) u64 {
    if ((a & b & 1) == 0) {
        ok.* = 0;
        return 0;
    }
    const a_signed: i64 = @bitCast(a);
    const b_signed: i64 = @bitCast(b);
    const result, const overflow = @addWithOverflow(a_signed, b_signed);
    if (overflow != 0) {
        ok.* = 0;
        return 0;
    }
    return @bitCast(result -% 1);
}

pub export fn cora_jit_sub(a: u64, b: u64, ok: *u8) u64 {
    if ((a & b & 1) == 0) {
        ok.* = 0;
        return 0;
    }
    const a_signed: i64 = @bitCast(a);
    const b_signed: i64 = @bitCast(b);
    const result, const overflow = @subWithOverflow(a_signed, b_signed);
    if (overflow != 0) {
        ok.* = 0;
        return 0;
    }
    return @bitCast(result +% 1);
}

pub fn validateChunk(ch: *chunk_mod.Chunk) !void {
    if (!available) return error.Unavailable;
    if (!ch.is_simple_positional or ch.arity != 1) return error.NotEligible;
    if (ch.optional_params.items.len != 0 or ch.rest_param_index != null or ch.post_required_count != 0) return error.NotEligible;
    if (ch.required_keywords.items.len != 0 or ch.optional_keywords.items.len != 0 or ch.keyword_rest_index != null or ch.no_keywords) return error.NotEligible;
    if (ch.block_param_index != null or ch.exception_handlers.items.len != 0) return error.NotEligible;

    var ip: usize = 0;
    while (ip < ch.code.items.len) {
        const op: bytecode.OpCode = @enumFromInt(ch.code.items[ip]);
        switch (op) {
            .GET_LOCAL => {
                const idx = ch.code.items[ip + 1];
                if (idx >= ch.locals_count) return error.NotEligible;
                ip += 2;
            },
            .PUSH_I8, .PUSH_SELF, .OPT_EQ, .OPT_PLUS, .OPT_MINUS => {
                ip += 1 + bytecode.opcodeOperandSize(op);
            },
            .JUMP_IF_FALSE, .JUMP => {
                _ = jumpDestination(ch.code.items, ip);
                ip += 3;
            },
            .CALL => {
                const desc = try decodeCallDescriptor(ch, ip);
                const method_name = try resolveMethodName(ch, desc.method_idx);
                if (desc.argc != 1 or desc.block_chunk_id != 0) return error.NotEligible;
                if (bytecode.decodeReceiverCallStyle(desc.call_flags) != .implicit_self) return error.NotEligible;
                if (bytecode.argsArrayMode(desc.call_flags) or bytecode.kwHashMode(desc.call_flags)) return error.NotEligible;
                if (!std.mem.eql(u8, method_name, ch.name)) return error.NotEligible;
                ip += 7;
            },
            .RETURN => {
                if (ch.code.items[ip + 1] != 0) return error.NotEligible;
                ip += 2;
            },
            else => return error.NotEligible,
        }
    }
}

pub fn generateChunk(allocator: std.mem.Allocator, ch: *chunk_mod.Chunk) !GeneratedChunk {
    if (!available) return error.Unavailable;
    try validateChunk(ch);

    const symbol_name = try dupeZ(allocator, try std.fmt.allocPrint(allocator, "cora_jit_chunk_{d}", .{ch.chunk_id orelse 0}));
    errdefer allocator.free(symbol_name);

    var source: std.Io.Writer.Allocating = .init(allocator);
    defer source.deinit();

    const writer = &source.writer;
    try writer.writeAll(
        \\typedef unsigned long long u64;
        \\typedef unsigned char u8;
        \\extern u64 cora_jit_add(u64 a, u64 b, u8 *ok);
        \\extern u64 cora_jit_sub(u64 a, u64 b, u8 *ok);
        \\
    );
    try writer.print("u64 {s}(u64 self_raw, u64 arg0_raw, u8 *ok) {{\n", .{symbol_name});
    try writer.writeAll("  u64 stack[64];\n");
    try writer.print("  u64 locals[{d}] = {{0}};\n", .{@max(ch.locals_count, 1)});
    try writer.writeAll(
        \\  unsigned long sp = 0;
        \\  locals[0] = arg0_raw;
        \\
    );

    var ip: usize = 0;
    while (ip < ch.code.items.len) {
        const op: bytecode.OpCode = @enumFromInt(ch.code.items[ip]);
        try writer.print("L{d}:\n", .{ip});
        switch (op) {
            .GET_LOCAL => {
                const idx = ch.code.items[ip + 1];
                try writer.print("  stack[sp++] = locals[{d}];\n", .{idx});
                ip += 2;
            },
            .PUSH_I8 => {
                const val: i8 = @bitCast(ch.code.items[ip + 1]);
                try writer.print("  stack[sp++] = ((((u64){d}) << 1) | 1ULL);\n", .{val});
                ip += 2;
            },
            .PUSH_SELF => {
                try writer.writeAll("  stack[sp++] = self_raw;\n");
                ip += 1;
            },
            .OPT_EQ => {
                try writer.writeAll(
                    \\  stack[sp - 2] = (stack[sp - 2] == stack[sp - 1]) ? 2ULL : 0ULL;
                    \\  sp -= 1;
                    \\
                );
                ip += 1;
            },
            .OPT_PLUS => {
                try writer.writeAll(
                    \\  stack[sp - 2] = cora_jit_add(stack[sp - 2], stack[sp - 1], ok);
                    \\  if (!*ok) return 0ULL;
                    \\  sp -= 1;
                    \\
                );
                ip += 1;
            },
            .OPT_MINUS => {
                try writer.writeAll(
                    \\  stack[sp - 2] = cora_jit_sub(stack[sp - 2], stack[sp - 1], ok);
                    \\  if (!*ok) return 0ULL;
                    \\  sp -= 1;
                    \\
                );
                ip += 1;
            },
            .JUMP_IF_FALSE => {
                const dest = jumpDestination(ch.code.items, ip);
                const next_ip = ip + 3;
                try writer.print("  if (((stack[--sp]) & ~4ULL) == 0) goto L{d};\n", .{dest});
                try writer.print("  goto L{d};\n", .{next_ip});
                ip = next_ip;
            },
            .JUMP => {
                const dest = jumpDestination(ch.code.items, ip);
                try writer.print("  goto L{d};\n", .{dest});
                ip += 3;
            },
            .CALL => {
                const next_ip = ip + 7;
                try writer.writeAll(
                    \\  if (stack[sp - 2] != self_raw) {
                    \\    *ok = 0;
                    \\    return 0ULL;
                    \\  }
                    \\
                );
                try writer.print("  stack[sp - 2] = {s}(self_raw, stack[sp - 1], ok);\n", .{symbol_name});
                try writer.writeAll(
                    \\  if (!*ok) return 0ULL;
                    \\  sp -= 1;
                    \\
                );
                if (next_ip < ch.code.items.len) {
                    try writer.print("  goto L{d};\n", .{next_ip});
                }
                ip = next_ip;
            },
            .RETURN => {
                try writer.writeAll("  return stack[sp - 1];\n");
                ip += 2;
            },
            else => return error.UnsupportedOpcode,
        }
    }

    try writer.writeAll("  return 0ULL;\n}\n");

    return .{
        .symbol_name = symbol_name,
        .source_code = try source.toOwnedSliceSentinel(0),
    };
}

pub fn compileState(
    allocator: std.mem.Allocator,
    state: *State,
    ch: *chunk_mod.Chunk,
    method_state_version: u64,
    dump_writer: ?*std.Io.Writer,
) !void {
    if (!available) return error.Unavailable;

    state.compilation.deinit();
    state.entry = null;
    state.compiled_method_state_version = 0;
    state.failed_method_state_version = 0;
    if (state.last_error) |msg| {
        allocator.free(msg);
        state.last_error = null;
    }

    const generated = try generateChunk(allocator, ch);
    defer allocator.free(generated.symbol_name);
    defer allocator.free(generated.source_code);

    if (dump_writer) |writer| {
        try writer.print("== jit {s} ==\n{s}\n", .{ generated.symbol_name, generated.source_code });
        try writer.flush();
    }

    var errors = tcc.initErrorCollector();
    const symbols = [_]tcc.ExternalSymbol{
        .{ .name = "cora_jit_add", .ptr = @ptrCast(&cora_jit_add) },
        .{ .name = "cora_jit_sub", .ptr = @ptrCast(&cora_jit_sub) },
    };

    state.compilation = tcc.compile("zig-out/tinycc", generated.source_code, generated.symbol_name, &symbols, &errors) catch |err| {
        const message = if (errors.slice().len != 0) errors.slice() else @errorName(err);
        state.last_error = try allocator.dupe(u8, message);
        state.failed_method_state_version = method_state_version;
        return err;
    };

    state.entry = tcc.getSymbol(CompiledFn, &state.compilation, generated.symbol_name) orelse {
        state.last_error = try allocator.dupe(u8, "missing compiled entry symbol");
        state.failed_method_state_version = method_state_version;
        return error.MissingSymbol;
    };
    state.compiled_method_state_version = method_state_version;
}

fn jumpDestination(code: []const u8, ip: usize) usize {
    const lo: u16 = code[ip + 1];
    const hi: u16 = code[ip + 2];
    const offset: i16 = @bitCast(lo | (hi << 8));
    const next_ip: i32 = @intCast(ip + 3);
    return @intCast(next_ip + offset);
}

fn dupeZ(allocator: std.mem.Allocator, owned: []u8) ![:0]u8 {
    defer allocator.free(owned);
    return allocator.dupeZ(u8, owned);
}

fn decodeCallDescriptor(ch: *chunk_mod.Chunk, ip: usize) !chunk_mod.CallSiteDescriptor {
    if (ip + 6 >= ch.code.items.len) return error.NotEligible;
    return .{
        .method_idx = readU16(ch.code.items, ip + 1),
        .argc = ch.code.items[ip + 3],
        .call_flags = ch.code.items[ip + 4],
        .block_chunk_id = readU16(ch.code.items, ip + 5),
    };
}

fn resolveMethodName(ch: *chunk_mod.Chunk, method_idx: u16) ![]const u8 {
    if (method_idx >= ch.constants.items.len) return error.NotEligible;
    return switch (ch.constants.items[method_idx]) {
        .string => |name| name,
        .encoded_string => |name| name.bytes,
        .symbol => |sym| sym.name,
        else => error.NotEligible,
    };
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    const lo: u16 = bytes[offset];
    const hi: u16 = bytes[offset + 1];
    return lo | (hi << 8);
}
