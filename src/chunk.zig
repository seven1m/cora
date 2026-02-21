const std = @import("std");
const bytecode = @import("bytecode.zig");

const LexicalScope = @import("value.zig").LexicalScope;
const MethodEntry = @import("value.zig").MethodEntry;
const ClassObject = @import("value.zig").ClassObject;
const SymbolObject = @import("value.zig").SymbolObject;

pub const ChunkId = u16;

/// Special marker value indicating that a block argument is on the stack
/// (passed via `&variable` syntax) rather than being a compiled chunk.
pub const BLOCK_ARG_ON_STACK: ChunkId = std.math.maxInt(ChunkId);

/// Maximum valid chunk ID (one less than the marker value).
pub const MAX_CHUNK_ID: ChunkId = BLOCK_ARG_ON_STACK - 1;

pub const Constant = union(enum) {
    integer: i64,
    big_integer_decimal: []const u8,
    float: f64,
    string: []const u8,
    symbol: *SymbolObject,
};

pub const RescueHandler = struct {
    exception_type_expr_chunks: std.ArrayList(ChunkId) = .empty, // Chunk IDs for rescue type expressions
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

pub const OptionalParam = struct {
    param_index: u8, // Local slot for this parameter
    default_chunk_id: ChunkId, // Chunk ID containing default expression
};

pub const KeywordMetadata = struct {
    names: std.ArrayList(u16) = .empty, // Symbol indices in constant pool
};

pub const RequiredKeyword = struct {
    name_idx: u16, // Constant pool index (symbol)
    param_slot: u8, // Local variable slot
};

pub const OptionalKeyword = struct {
    name_idx: u16, // Constant pool index (symbol)
    param_slot: u8, // Local variable slot
    default_chunk_id: ChunkId, // Chunk with default expression
};

pub const CallSiteCache = struct {
    receiver_class: *ClassObject,
    method_name: *SymbolObject,
    method_state_version: u64,
    owner_class: *ClassObject,
    entry: MethodEntry,
};

pub const CallSiteKind = enum {
    call,
    call_kw,
};

pub const CallSiteDescriptor = struct {
    kind: CallSiteKind,
    method_idx: u16,
    method_sym: ?*SymbolObject = null,
    argc: u8,
    call_flags: u8,
    kwargc: u8 = 0,
    kw_metadata_idx: u16 = 0,
    block_chunk_id: u16,
};

pub const Chunk = struct {
    code: std.ArrayList(u8) = .empty,
    constants: std.ArrayList(Constant) = .empty,
    constant_names: std.StringHashMap(u32), // Name -> constant index
    line_info: std.ArrayList(u32) = .empty,
    allocator: std.mem.Allocator,
    name: []const u8,
    name_owned: bool = false,
    chunk_id: ?ChunkId = null,
    arity: u8 = 0, // For block chunks: number of pre-rest required parameters
    is_lambda: bool = false, // Distinguishes lambda from proc
    optional_params: std.ArrayList(OptionalParam) = .empty, // Optional parameters with defaults
    rest_param_index: ?u8 = null, // Slot where rest array is stored
    post_required_count: u8 = 0, // Required params after rest
    lexical_scope: ?*LexicalScope = null,
    exception_handlers: std.ArrayList(ExceptionHandler) = .empty,
    source_file: ?[]const u8 = null,
    source_file_owned: bool = false,
    required_keywords: std.ArrayList(RequiredKeyword) = .empty,
    optional_keywords: std.ArrayList(OptionalKeyword) = .empty,
    keyword_rest_index: ?u8 = null, // Slot for **kwargs hash
    no_keywords: bool = false, // True if **nil specified
    keyword_metadata: std.ArrayList(KeywordMetadata) = .empty,
    block_param_index: ?u8 = null, // Local slot for &block parameter
    callsite_caches: std.ArrayList(?CallSiteCache) = .empty,
    callsite_descriptors: std.ArrayList(?CallSiteDescriptor) = .empty,

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
        if (self.name_owned) {
            self.allocator.free(self.name);
        }
        if (self.source_file_owned) {
            if (self.source_file) |source_file| {
                self.allocator.free(source_file);
            }
        }
        for (self.constants.items) |constant| {
            switch (constant) {
                .string => |s| self.allocator.free(s),
                .big_integer_decimal => |digits| self.allocator.free(digits),
                else => {},
            }
        }
        self.constants.deinit(self.allocator);
        var constant_name_iter = self.constant_names.keyIterator();
        while (constant_name_iter.next()) |name| {
            self.allocator.free(name.*);
        }
        self.constant_names.deinit();
        self.line_info.deinit(self.allocator);
        self.optional_params.deinit(self.allocator);

        // Free exception handler tables
        for (self.exception_handlers.items) |*handler| {
            for (handler.rescue_handlers.items) |*rescue| {
                rescue.exception_type_expr_chunks.deinit(self.allocator);
            }
            handler.rescue_handlers.deinit(self.allocator);
        }
        self.exception_handlers.deinit(self.allocator);

        // Free keyword structures
        self.required_keywords.deinit(self.allocator);
        self.optional_keywords.deinit(self.allocator);
        for (self.keyword_metadata.items) |*kw_meta| {
            kw_meta.names.deinit(self.allocator);
        }
        self.keyword_metadata.deinit(self.allocator);
        self.callsite_caches.deinit(self.allocator);
        self.callsite_descriptors.deinit(self.allocator);
    }

    pub fn setSourceFile(self: *Chunk, source_file: ?[]const u8) !void {
        if (self.source_file_owned) {
            if (self.source_file) |existing| {
                self.allocator.free(existing);
            }
            self.source_file_owned = false;
        }
        self.source_file = null;

        if (source_file) |path| {
            self.source_file = try self.allocator.dupe(u8, path);
            self.source_file_owned = true;
        }
    }

    /// Add a constant to the constant pool, return its index
    pub fn addConstant(self: *Chunk, const_val: Constant) !u32 {
        const owned = switch (const_val) {
            .string => |s| Constant{ .string = try self.allocator.dupe(u8, s) },
            .big_integer_decimal => |s| Constant{ .big_integer_decimal = try self.allocator.dupe(u8, s) },
            else => const_val,
        };
        try self.constants.append(self.allocator, owned);
        return @intCast(self.constants.items.len - 1);
    }

    /// Add a named constant (class, module, etc.)
    pub fn addNamedConstant(self: *Chunk, name: []const u8, const_val: Constant) !u32 {
        const idx = try self.addConstant(const_val);
        if (self.constant_names.contains(name)) {
            try self.constant_names.put(name, idx);
            return idx;
        }
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        try self.constant_names.put(owned_name, idx);
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

    /// Emit opcode with u16, u8, and u16 operands
    pub fn emitOpU16U8U16(self: *Chunk, op: bytecode.OpCode, a: u16, b: u8, c: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast((a >> 8) & 0xFF));
        try self.code.append(self.allocator, b);
        try self.code.append(self.allocator, @intCast(c & 0xFF));
        try self.code.append(self.allocator, @intCast((c >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with two u16 operands
    pub fn emitOpU16U16(self: *Chunk, op: bytecode.OpCode, a: u16, b: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast((a >> 8) & 0xFF));
        try self.code.append(self.allocator, @intCast(b & 0xFF));
        try self.code.append(self.allocator, @intCast((b >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit opcode with u8 and u16 operands
    pub fn emitOpU8U16(self: *Chunk, op: bytecode.OpCode, a: u8, b: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, a);
        try self.code.append(self.allocator, @intCast(b & 0xFF));
        try self.code.append(self.allocator, @intCast((b >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit CALL_KW instruction with keyword arguments
    pub fn emitCall(self: *Chunk, method_idx: u16, argc: u8, call_style: u8, block_chunk_id: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(bytecode.OpCode.CALL));
        try self.code.append(self.allocator, @intCast(method_idx & 0xFF));
        try self.code.append(self.allocator, @intCast((method_idx >> 8) & 0xFF));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, call_style);
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast((block_chunk_id >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    /// Emit CALL_KW instruction with keyword arguments
    pub fn emitCallKw(self: *Chunk, method_idx: u16, argc: u8, kwargc: u8, call_style: u8, kw_metadata_idx: u16, block_chunk_id: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(bytecode.OpCode.CALL_KW));
        try self.code.append(self.allocator, @intCast(method_idx & 0xFF));
        try self.code.append(self.allocator, @intCast((method_idx >> 8) & 0xFF));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, kwargc);
        try self.code.append(self.allocator, call_style);
        try self.code.append(self.allocator, @intCast(kw_metadata_idx & 0xFF));
        try self.code.append(self.allocator, @intCast((kw_metadata_idx >> 8) & 0xFF));
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast((block_chunk_id >> 8) & 0xFF));
        try self.line_info.append(self.allocator, line);
    }

    pub fn emitSuper(self: *Chunk, argc: u8, flags: u8, block_chunk_id: u16, line: u32) !void {
        try self.code.append(self.allocator, @intFromEnum(bytecode.OpCode.SUPER));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, flags);
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast((block_chunk_id >> 8) & 0xFF));
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

        // Print parameter info
        if (self.rest_param_index) |rest_idx| {
            try writer.print("  arity: {d}, rest param at slot {d}, post-required: {d}\n", .{ self.arity, rest_idx, self.post_required_count });
        } else if (self.arity > 0) {
            try writer.print("  arity: {d}\n", .{self.arity});
        }

        if (self.optional_params.items.len > 0) {
            try writer.print("  optional params: ", .{});
            for (self.optional_params.items, 0..) |opt, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("slot {d} (chunk {d})", .{ opt.param_index, opt.default_chunk_id });
            }
            try writer.print("\n", .{});
        }

        // Print keyword parameter info
        if (self.required_keywords.items.len > 0) {
            try writer.print("  required keywords: ", .{});
            for (self.required_keywords.items, 0..) |req_kw, i| {
                if (i > 0) try writer.print(", ", .{});
                const kw_name = self.constants.items[req_kw.name_idx].string;
                try writer.print("{s} (slot {d})", .{ kw_name, req_kw.param_slot });
            }
            try writer.print("\n", .{});
        }

        if (self.optional_keywords.items.len > 0) {
            try writer.print("  optional keywords: ", .{});
            for (self.optional_keywords.items, 0..) |opt_kw, i| {
                if (i > 0) try writer.print(", ", .{});
                const kw_name = self.constants.items[opt_kw.name_idx].string;
                try writer.print("{s} (slot {d}, chunk {d})", .{ kw_name, opt_kw.param_slot, opt_kw.default_chunk_id });
            }
            try writer.print("\n", .{});
        }

        if (self.keyword_rest_index) |rest_idx| {
            try writer.print("  keyword rest at slot {d}\n", .{rest_idx});
        }

        if (self.no_keywords) {
            try writer.print("  no keywords (**nil)\n", .{});
        }

        if (self.block_param_index) |block_idx| {
            try writer.print("  block param at slot {d}\n", .{block_idx});
        }

        // Print constants
        if (self.constants.items.len > 0) {
            try writer.print("constants: ", .{});
            for (self.constants.items, 0..) |constant, i| {
                if (i > 0) try writer.print(" ", .{});
                try writer.print("{d}=", .{i});
                switch (constant) {
                    .integer => |int_val| try writer.print("{d}", .{int_val}),
                    .big_integer_decimal => |digits| try writer.print("{s}", .{digits}),
                    .float => |float_val| try writer.print("{d}", .{float_val}),
                    .string => |str| try writer.print("\"{s}\"", .{str}),
                    .symbol => |sym| try writer.print(":\"{s}\"(interned)", .{sym.name}),
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
            .PUSH_NIL, .PUSH_TRUE, .PUSH_FALSE, .PUSH_SELF, .POP, .DUP, .SWAP, .CASE_MATCH, .HALT, .TRY_END, .CATCH_END, .ENSURE_START, .ENSURE_END, .RETRY, .BREAK, .MULTI_ASSIGN_PREPARE, .ARRAY_APPEND, .ARRAY_CONCAT_ARRAY, .YIELD_SPLAT => {
                try writer.print("{s}\n", .{bytecode.opcodeName(op)});
            },

            .DUP_N => {
                const count = bytecode.readU8(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), count });
                next_ip += 1;
            },

            .PUSH_CONST, .PUSH_SYMBOL, .GET_CONST, .GET_CONST_OR_NIL, .SET_CONST, .GET_CONST_PATH, .GET_GLOBAL, .GET_BACKREF, .SET_GLOBAL, .GET_CVAR, .GET_CVAR_OR_NIL, .SET_CVAR, .GET_IVAR, .SET_IVAR => {
                const idx = bytecode.readU16(self.code.items, next_ip);
                try writer.print("{s} {d}", .{ bytecode.opcodeName(op), idx });
                if (idx < self.constants.items.len) {
                    const constant = self.constants.items[idx];
                    switch (constant) {
                        .integer => |i| try writer.print(" ({d})", .{i}),
                        .big_integer_decimal => |digits| try writer.print(" ({s})", .{digits}),
                        .float => |f| try writer.print(" ({d})", .{f}),
                        .string => |s| try writer.print(" (\"{s}\")", .{s}),
                        .symbol => |s| try writer.print(" (:{s})", .{s.name}),
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

            .GET_LOCAL, .SET_LOCAL, .PUSH_RANGE, .INTERPOLATE_STRING, .RAISE, .CATCH_START => {
                const idx = bytecode.readU8(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), idx });
                next_ip += 1;
            },

            .PUSH_ARRAY, .PUSH_HASH => {
                const count = bytecode.readU16(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), count });
                next_ip += 2;
            },

            .GET_LOCAL_DEEP, .SET_LOCAL_DEEP => {
                const local_idx = bytecode.readU8(self.code.items, next_ip);
                const depth = bytecode.readU8(self.code.items, next_ip + 1);
                try writer.print("{s} {d} {d}\n", .{ bytecode.opcodeName(op), local_idx, depth });
                next_ip += 2;
            },

            .TRY_BEGIN => {
                const handler_idx = bytecode.readU16(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), handler_idx });
                next_ip += 2;
            },

            .JUMP, .JUMP_IF_FALSE, .JUMP_IF_TRUE => {
                const offset = bytecode.readI16(self.code.items, next_ip);
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), offset });
                next_ip += 2;
            },

            .CALL => {
                const method_idx = bytecode.readU16(self.code.items, next_ip);
                const argc = bytecode.readU8(self.code.items, next_ip + 2);
                const call_style = bytecode.readU8(self.code.items, next_ip + 3);
                const block_id = bytecode.readU16(self.code.items, next_ip + 4);
                try writer.print("CALL {d}, {d}, {d}, {d}\n", .{ method_idx, argc, call_style, block_id });
                next_ip += 6;
            },

            .CALL_KW => {
                const method_idx = bytecode.readU16(self.code.items, next_ip);
                const argc = bytecode.readU8(self.code.items, next_ip + 2);
                const kwargc = bytecode.readU8(self.code.items, next_ip + 3);
                const call_style = bytecode.readU8(self.code.items, next_ip + 4);
                const kw_metadata_idx = bytecode.readU16(self.code.items, next_ip + 5);
                const block_id = bytecode.readU16(self.code.items, next_ip + 7);

                try writer.print("CALL_KW {d}, {d}, {d}, {d}, {d}, {d}", .{ method_idx, argc, kwargc, call_style, kw_metadata_idx, block_id });

                // Show keyword names if metadata is available
                if (kw_metadata_idx < self.keyword_metadata.items.len) {
                    const kw_meta = self.keyword_metadata.items[kw_metadata_idx];
                    try writer.print(" (keywords: ", .{});
                    for (kw_meta.names.items, 0..) |name_idx, i| {
                        if (i > 0) try writer.print(", ", .{});
                        if (name_idx < self.constants.items.len) {
                            const kw_name = self.constants.items[name_idx].string;
                            try writer.print("{s}", .{kw_name});
                        }
                    }
                    try writer.print(")", .{});
                }
                try writer.print("\n", .{});
                next_ip += 9;
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

            .DEF_SINGLETON_CLASS => {
                const body_chunk_id = bytecode.readU16(self.code.items, next_ip);
                try writer.print("DEF_SINGLETON_CLASS {d} (chunk {d})\n", .{ body_chunk_id, body_chunk_id });
                next_ip += 2;
            },

            .DEF_METHOD => {
                const name_idx = bytecode.readU16(self.code.items, next_ip);
                const chunk_idx = bytecode.readU16(self.code.items, next_ip + 2);
                try writer.print("DEF_METHOD {d}", .{name_idx});
                if (name_idx < self.constants.items.len) {
                    const constant = self.constants.items[name_idx];
                    if (constant == .string) {
                        try writer.print(" (:{s})", .{constant.string});
                    }
                }
                try writer.print(" {d} (chunk {d})\n", .{ chunk_idx, chunk_idx });
                next_ip += 4;
            },

            .DEF_SINGLETON_METHOD => {
                const name_idx = bytecode.readU16(self.code.items, next_ip);
                const chunk_idx = bytecode.readU16(self.code.items, next_ip + 2);
                try writer.print("DEF_SINGLETON_METHOD {d}", .{name_idx});
                if (name_idx < self.constants.items.len) {
                    const constant = self.constants.items[name_idx];
                    if (constant == .string) {
                        try writer.print(" (:{s})", .{constant.string});
                    }
                }
                try writer.print(" {d} (chunk {d})\n", .{ chunk_idx, chunk_idx });
                next_ip += 4;
            },

            .YIELD => {
                const argc = bytecode.readU8(self.code.items, next_ip);
                try writer.print("YIELD {d}\n", .{argc});
                next_ip += 1;
            },

            .PUSH_LAMBDA => {
                const chunk_id = bytecode.readU16(self.code.items, next_ip);
                try writer.print("PUSH_LAMBDA {d}\n", .{chunk_id});
                next_ip += 2;
            },

            .RETURN => {
                const is_explicit = bytecode.readU8(self.code.items, next_ip);
                try writer.print("RETURN {s}\n", .{if (is_explicit == 1) "explicit" else "implicit"});
                next_ip += 1;
            },

            .SUPER => {
                const argc = bytecode.readU8(self.code.items, next_ip);
                const flags = bytecode.readU8(self.code.items, next_ip + 1);
                const block_id = bytecode.readU16(self.code.items, next_ip + 2);
                const args_array_mode = (flags & bytecode.SUPER_FLAG_ARGS_ARRAY) != 0;
                try writer.print("SUPER {d}, {d}", .{ argc, block_id });
                if (args_array_mode) {
                    try writer.print(" (args_array)", .{});
                }
                try writer.print("\n", .{});
                next_ip += 4;
            },

            .FORWARDING_SUPER => {
                const block_id = bytecode.readU16(self.code.items, next_ip);
                try writer.print("FORWARDING_SUPER {d}\n", .{block_id});
                next_ip += 2;
            },

            .PUSH_REGEXP => {
                const pattern_idx = bytecode.readU16(self.code.items, next_ip);
                const options = bytecode.readU16(self.code.items, next_ip + 2);
                try writer.print("PUSH_REGEXP {d} {d}", .{ pattern_idx, options });
                if (pattern_idx < self.constants.items.len) {
                    const constant = self.constants.items[pattern_idx];
                    if (constant == .string) {
                        try writer.print(" (/{s}/)", .{constant.string});
                    }
                }
                try writer.print("\n", .{});
                next_ip += 4;
            },

            .ALIAS_METHOD => {
                const new_name_idx = bytecode.readU16(self.code.items, next_ip);
                const old_name_idx = bytecode.readU16(self.code.items, next_ip + 2);
                try writer.print("ALIAS_METHOD {d} {d}", .{ new_name_idx, old_name_idx });
                if (new_name_idx < self.constants.items.len) {
                    const new_const = self.constants.items[new_name_idx];
                    if (new_const == .string) {
                        try writer.print(" (:{s}", .{new_const.string});
                        if (old_name_idx < self.constants.items.len) {
                            const old_const = self.constants.items[old_name_idx];
                            if (old_const == .string) {
                                try writer.print(" <- :{s}", .{old_const.string});
                            }
                        }
                        try writer.print(")", .{});
                    }
                }
                try writer.print("\n", .{});
                next_ip += 4;
            },
        }

        return next_ip;
    }
};
