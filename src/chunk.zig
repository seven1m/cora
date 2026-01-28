const std = @import("std");
const bytecode = @import("bytecode.zig");

const LexicalScope = @import("value.zig").LexicalScope;

pub const Constant = union(enum) {
    integer: i64,
    string: []const u8,
    symbol: []const u8,
};

pub const RescueHandler = struct {
    exception_types: std.ArrayList(u16) = .empty, // Constant pool indices for exception classes
    catch_ip: usize, // IP to jump to for this rescue
    catch_end_ip: usize, // End of rescue clause
    var_idx: ?u8, // Local var index for exception binding (=> e)
};

pub const ExceptionHandler = struct {
    try_start_ip: usize, // Start of protected region
    try_end_ip: usize, // End of protected region
    rescue_handlers: std.ArrayList(RescueHandler) = .empty,
    else_ip: ?usize, // Else clause IP (runs if no exception)
    ensure_ip: ?usize, // Ensure clause IP (always runs)
    ensure_end_ip: ?usize, // End of ensure block
};

pub const Chunk = struct {
    code: std.ArrayList(u8) = .empty,
    constants: std.ArrayList(Constant) = .empty,
    constant_names: std.StringHashMap(u32), // Name -> constant index
    line_info: std.ArrayList(u32) = .empty,
    allocator: std.mem.Allocator,
    name: []const u8,
    chunk_id: ?u8 = null,
    arity: u8 = 0, // For block chunks: number of parameters
    lexical_scope: ?*LexicalScope = null,
    exception_handlers: std.ArrayList(ExceptionHandler) = .empty,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Chunk {
        return Chunk{
            .code = .empty,
            .constants = .empty,
            .constant_names = std.StringHashMap(u32).init(allocator),
            .line_info = .empty,
            .allocator = allocator,
            .name = name,
            .chunk_id = null,
            .arity = 0,
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.constant_names.deinit();
        self.line_info.deinit(self.allocator);

        // Free exception handler tables
        for (self.exception_handlers.items) |*handler| {
            for (handler.rescue_handlers.items) |*rescue| {
                rescue.exception_types.deinit(self.allocator);
            }
            handler.rescue_handlers.deinit(self.allocator);
        }
        self.exception_handlers.deinit(self.allocator);
    }

    /// Add a constant to the constant pool, return its index
    pub fn addConstant(self: *Chunk, const_val: Constant) !u32 {
        try self.constants.append(self.allocator, const_val);
        return @intCast(self.constants.items.len - 1);
    }

    /// Add a named constant (class, module, etc.)
    pub fn addNamedConstant(self: *Chunk, name: []const u8, const_val: Constant) !u32 {
        const idx = try self.addConstant(const_val);
        try self.constant_names.put(name, idx);
        return idx;
    }

    /// Get constant by name
    pub fn getConstant(self: *Chunk, name: []const u8) ?u32 {
        return self.constant_names.get(name);
    }

    /// Emit an opcode without operands
    pub fn emitOp(self: *Chunk, op: bytecode.OpCode, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with u8 operand
    pub fn emitOpU8(self: *Chunk, op: bytecode.OpCode, operand: u8, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, operand);
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with u16 operand
    pub fn emitOpU16(self: *Chunk, op: bytecode.OpCode, operand: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(operand & 0xFF));
        try self.code.append(self.allocator, @intCast((operand >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with i16 operand (for jumps)
    pub fn emitOpI16(self: *Chunk, op: bytecode.OpCode, operand: i16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        const unsigned: u16 = @bitCast(operand);
        try self.code.append(self.allocator, @intCast(unsigned & 0xFF));
        try self.code.append(self.allocator, @intCast((unsigned >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with two u8 operands
    pub fn emitOpU8U8(self: *Chunk, op: bytecode.OpCode, a: u8, b: u8, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, a);
        try self.code.append(self.allocator, b);
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with u16 and u8 operands
    pub fn emitOpU16U8(self: *Chunk, op: bytecode.OpCode, a: u16, b: u8, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast((a >> 8) & 0xFF));
        try self.code.append(self.allocator, b);
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with u16 and two u8 operands
    pub fn emitOpU16U8U8(self: *Chunk, op: bytecode.OpCode, a: u16, b: u8, c: u8, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast((a >> 8) & 0xFF));
        try self.code.append(self.allocator, b);
        try self.code.append(self.allocator, c);
        try self.line_info.append(self.allocator, line);
    }

    /// Emit a jump instruction and return the position to patch
    pub fn emitJump(self: *Chunk, op: bytecode.OpCode, line: u32) !usize {
        const pos = self.code.items.len;
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, 0); // Placeholder lo byte
        try self.code.append(self.allocator, 0); // Placeholder hi byte
        try self.line_info.append(self.allocator, line);
        return pos;
    }

    /// Patch a jump instruction at the given position
    pub fn patchJump(self: *Chunk, pos: usize) !void {
        const jump_target = self.code.items.len;
        const offset: i16 = @intCast(@as(i32, @intCast(jump_target)) - @as(i32, @intCast(pos)) - 3);
        const unsigned: u16 = @bitCast(offset);
        self.code.items[pos + 1] = @intCast(unsigned & 0xFF);
        self.code.items[pos + 2] = @intCast((unsigned >> 8) & 0xFF);
    }

    /// Print disassembly of this chunk
    pub fn disassemble(self: *Chunk, writer: *std.Io.Writer) !void {
        if (self.chunk_id) |id| {
            try writer.print("== {s} == (chunk {d})\n", .{ self.name, id });
        } else {
            try writer.print("== {s} ==\n", .{self.name});
        }

        // Print constants
        if (self.constants.items.len > 0) {
            try writer.print("constants: ", .{});
            for (self.constants.items, 0..) |constant, i| {
                if (i > 0) try writer.print(" ", .{});
                try writer.print("{d}=", .{i});
                switch (constant) {
                    .integer => |int_val| try writer.print("{d}", .{int_val}),
                    .string => |str| try writer.print("\"{s}\"", .{str}),
                    .symbol => |sym| try writer.print(":{s}", .{sym}),
                }
            }
            try writer.print("\n-----------\n", .{});
        }

        var ip: usize = 0;
        var instr_idx: usize = 0;
        while (ip < self.code.items.len) {
            ip = try self.disassembleInstruction(ip, instr_idx, writer);
            instr_idx += 1;
        }
    }

    fn disassembleInstruction(self: *Chunk, ip: usize, instr_idx: usize, writer: *std.Io.Writer) !usize {
        try writer.print("{:0>4} ", .{ip});

        if (instr_idx > 0 and instr_idx < self.line_info.items.len and
            self.line_info.items[instr_idx] == self.line_info.items[instr_idx - 1])
        {
            try writer.print("   | ", .{});
        } else if (instr_idx < self.line_info.items.len) {
            try writer.print("{:4} ", .{self.line_info.items[instr_idx]});
        } else {
            try writer.print("   ? ", .{});
        }

        const op = @as(bytecode.OpCode, @enumFromInt(self.code.items[ip]));
        var next_ip = ip + 1;

        switch (op) {
            .PUSH_NIL, .PUSH_TRUE, .PUSH_FALSE, .PUSH_SELF, .POP, .RETURN, .HALT, .TRY_END, .CATCH_END, .ENSURE_START, .ENSURE_END, .RETRY => {
                try writer.print("{s}\n", .{bytecode.opcodeName(op)});
            },

            .PUSH_INT, .PUSH_CONST, .GET_CONST, .SET_CONST, .GET_CONST_PATH => {
                const idx = bytecode.readU16(self.code.items, next_ip);
                try writer.print("{s} {d}", .{ bytecode.opcodeName(op), idx });
                if (idx < self.constants.items.len) {
                    const constant = self.constants.items[idx];
                    switch (constant) {
                        .integer => |i| try writer.print(" ({d})", .{i}),
                        .string => |s| try writer.print(" (\"{s}\")", .{s}),
                        .symbol => |s| try writer.print(" (:{s})", .{s}),
                    }
                }
                try writer.print("\n", .{});
                next_ip += 2;
            },

            .DEF_MODULE => {
                const idx = bytecode.readU16(self.code.items, next_ip);
                const chunk_id = bytecode.readU8(self.code.items, next_ip + 2);
                try writer.print("{s} {d} {d}", .{ bytecode.opcodeName(op), idx, chunk_id });
                if (idx < self.constants.items.len) {
                    const constant = self.constants.items[idx];
                    if (constant == .string) {
                        try writer.print(" (\"{s}\")", .{constant.string});
                    }
                }
                try writer.print("\n", .{});
                next_ip += 3;
            },

            .GET_LOCAL, .SET_LOCAL, .PUSH_ARRAY, .RAISE, .CATCH_START => {
                const idx = bytecode.readU8(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), idx });
                next_ip += 1;
            },

            .TRY_BEGIN => {
                const handler_idx = bytecode.readU16(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), handler_idx });
                next_ip += 2;
            },

            .JUMP, .JUMP_IF_FALSE => {
                const offset = bytecode.readI16(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), offset });
                next_ip += 2;
            },

            .CALL => {
                const method_idx = bytecode.readU16(self.code.items, next_ip);
                const argc = bytecode.readU8(self.code.items, next_ip + 2);
                const block_id = bytecode.readU8(self.code.items, next_ip + 3);
                try writer.print("CALL {d}, {d}, {d}\n", .{ method_idx, argc, block_id });
                next_ip += 4;
            },

            .DEF_CLASS => {
                const name_idx = bytecode.readU16(self.code.items, next_ip);
                const body_chunk_id = bytecode.readU8(self.code.items, next_ip + 2);
                try writer.print("DEF_CLASS {d}", .{name_idx});
                if (name_idx < self.constants.items.len) {
                    const constant = self.constants.items[name_idx];
                    if (constant == .string) {
                        try writer.print(" (\"{s}\")", .{constant.string});
                    }
                }
                try writer.print(" {d} (chunk {d})\n", .{ body_chunk_id, body_chunk_id });
                next_ip += 3;
            },

            .DEF_METHOD => {
                const name_idx = bytecode.readU16(self.code.items, next_ip);
                const chunk_idx = bytecode.readU8(self.code.items, next_ip + 2);
                try writer.print("DEF_METHOD {d}", .{name_idx});
                if (name_idx < self.constants.items.len) {
                    const constant = self.constants.items[name_idx];
                    if (constant == .symbol) {
                        try writer.print(" (:{s})", .{constant.symbol});
                    }
                }
                try writer.print(" {d} (chunk {d})\n", .{ chunk_idx, chunk_idx });
                next_ip += 3;
            },

            .YIELD => {
                const argc = bytecode.readU8(self.code.items, next_ip);
                try writer.print("YIELD {d}\n", .{argc});
                next_ip += 1;
            },
        }

        return next_ip;
    }
};
