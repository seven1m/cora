const std = @import("std");
const bytecode = @import("bytecode.zig");
const enc = @import("encoding.zig");

const LexicalScope = @import("value.zig").LexicalScope;
const MethodEntry = @import("value.zig").MethodEntry;
const ClassObject = @import("value.zig").ClassObject;
const SymbolObject = @import("value.zig").SymbolObject;
const OpCode = bytecode.OpCode;

pub const ChunkId = u16;

/// Special marker value indicating that a block argument is on the stack
/// (passed via `&variable` syntax) rather than being a compiled chunk.
pub const BLOCK_ARG_ON_STACK: ChunkId = std.math.maxInt(ChunkId);

/// Maximum valid chunk ID (one less than the marker value).
pub const MAX_CHUNK_ID: ChunkId = BLOCK_ARG_ON_STACK - 1;

pub const Constant = union(enum) {
    pub const EncodedString = struct {
        bytes: []const u8,
        encoding: enc.Encoding,
    };

    integer: i64,
    big_integer_decimal: []const u8,
    float: f64,
    string: []const u8,
    encoded_string: EncodedString,
    symbol: *SymbolObject,
};

pub const RescueHandler = struct {
    pub const TypeExpression = struct {
        chunk_id: ChunkId,
        splat: bool,
    };

    exception_type_exprs: std.ArrayList(TypeExpression) = .empty,
    catch_byte_offset: usize,
    catch_end_byte_offset: usize,
    var_idx: ?u16,
};

pub const ExceptionHandler = struct {
    try_start_byte_offset: usize,
    try_end_byte_offset: usize,
    rescue_handlers: std.ArrayList(RescueHandler) = .empty,
    else_byte_offset: ?usize,
    ensure_byte_offset: ?usize,
    ensure_end_byte_offset: ?usize,
};

pub const OptionalParam = struct {
    param_index: u16,
    default_chunk_id: ChunkId,
};

pub const KeywordMetadata = struct {
    names: std.ArrayList(u16) = .empty,
};

pub const RequiredKeyword = struct {
    name_idx: u16,
    param_slot: u16,
};

pub const OptionalKeyword = struct {
    name_idx: u16,
    param_slot: u16,
    default_chunk_id: ChunkId,
};

pub const CallSiteCache = struct {
    receiver_class: *ClassObject,
    method_name: *SymbolObject,
    method_state_version: u64,
    owner_class: *ClassObject,
    entry: MethodEntry,
};

pub const CallSiteDescriptor = struct {
    method_idx: u16,
    method_sym: ?*SymbolObject = null,
    argc: u8,
    call_flags: u8,
    kwargc: u8 = 0,
    kw_metadata_idx: u16 = 0,
    block_chunk_id: u16,
};

pub const LineInfo = struct {
    byte_offset: u32,
    line: u32,
};

pub const Chunk = struct {
    // Flat bytecode stream
    code: std.ArrayList(u8) = .empty,

    constants: std.ArrayList(Constant) = .empty,
    constant_names: std.StringHashMap(u32),
    line_info: std.ArrayList(LineInfo) = .empty,
    allocator: std.mem.Allocator,
    name: []const u8,
    name_owned: bool = false,
    chunk_id: ?ChunkId = null,
    arity: u8 = 0,
    locals_count: u16 = 0, // Total number of locals (including params)
    is_lambda: bool = false,
    optional_params: std.ArrayList(OptionalParam) = .empty,
    rest_param_index: ?u16 = null,
    post_required_count: u8 = 0,
    lexical_scope: ?*LexicalScope = null,
    exception_handlers: std.ArrayList(ExceptionHandler) = .empty,
    source_file: ?[]const u8 = null,
    source_file_owned: bool = false,
    source_encoding: enc.Encoding = .{ .utf8 = .{} },
    required_keywords: std.ArrayList(RequiredKeyword) = .empty,
    optional_keywords: std.ArrayList(OptionalKeyword) = .empty,
    keyword_rest_index: ?u16 = null,
    no_keywords: bool = false,
    keyword_metadata: std.ArrayList(KeywordMetadata) = .empty,
    block_param_index: ?u16 = null,

    /// Set by compiler: true if this chunk has a simple positional-only signature
    /// (no optional/rest/keyword/block params).
    is_simple_positional: bool = false,

    // Callsite caches indexed by callsite_id
    callsite_caches: std.ArrayList(?CallSiteCache) = .empty,
    callsite_descriptors: std.ArrayList(?CallSiteDescriptor) = .empty,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Chunk {
        return Chunk{
            .constant_names = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
            .name = name,
        };
    }

    pub fn deinit(self: *Chunk) void {
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
                .encoded_string => |s| self.allocator.free(s.bytes),
                .big_integer_decimal => |digits| self.allocator.free(digits),
                else => {},
            }
        }
        self.constants.deinit(self.allocator);
        var constant_name_iter = self.constant_names.keyIterator();
        while (constant_name_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.constant_names.deinit();
        self.line_info.deinit(self.allocator);
        self.code.deinit(self.allocator);
        self.optional_params.deinit(self.allocator);

        for (self.exception_handlers.items) |*handler| {
            for (handler.rescue_handlers.items) |*rescue| {
                rescue.exception_type_exprs.deinit(self.allocator);
            }
            handler.rescue_handlers.deinit(self.allocator);
        }
        self.exception_handlers.deinit(self.allocator);

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
            .encoded_string => |s| Constant{ .encoded_string = .{
                .bytes = try self.allocator.dupe(u8, s.bytes),
                .encoding = s.encoding,
            } },
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

    // =========================================================================
    // Emit helpers - write packed bytes to the code stream
    // =========================================================================

    fn recordLine(self: *Chunk, line: u32) !void {
        const offset: u32 = @intCast(self.code.items.len);
        // Only record if line changed from last entry
        if (self.line_info.items.len > 0) {
            const last = &self.line_info.items[self.line_info.items.len - 1];
            if (last.line == line) return;
        }
        try self.line_info.append(self.allocator, .{ .byte_offset = offset, .line = line });
    }

    /// Current byte offset (for jump patching)
    pub fn currentOffset(self: *Chunk) usize {
        return self.code.items.len;
    }

    /// Emit opcode with no operands
    pub fn emitOp(self: *Chunk, op: OpCode, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
    }

    /// Emit opcode with u8 operand
    pub fn emitOpU8(self: *Chunk, op: OpCode, operand: u8, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, operand);
    }

    /// Emit opcode with i8 operand
    pub fn emitOpI8(self: *Chunk, op: OpCode, operand: i8, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @bitCast(operand));
    }

    /// Emit opcode with u16 operand (little-endian)
    pub fn emitOpU16(self: *Chunk, op: OpCode, operand: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(operand & 0xFF));
        try self.code.append(self.allocator, @intCast(operand >> 8));
    }

    /// Emit opcode with two u8 operands
    pub fn emitOpU8U8(self: *Chunk, op: OpCode, a: u8, b: u8, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, a);
        try self.code.append(self.allocator, b);
    }

    /// Emit opcode with u16 + u8 operands
    pub fn emitOpU16U8(self: *Chunk, op: OpCode, a: u16, b: u8, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast(a >> 8));
        try self.code.append(self.allocator, b);
    }

    /// Emit opcode with u16 + u8 + u8 operands
    pub fn emitOpU16U8U8(self: *Chunk, op: OpCode, a: u16, b: u8, c: u8, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast(a >> 8));
        try self.code.append(self.allocator, b);
        try self.code.append(self.allocator, c);
    }

    /// Emit opcode with u16 + u8 + u16 operands
    pub fn emitOpU16U8U16(self: *Chunk, op: OpCode, a: u16, b: u8, c: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast(a >> 8));
        try self.code.append(self.allocator, b);
        try self.code.append(self.allocator, @intCast(c & 0xFF));
        try self.code.append(self.allocator, @intCast(c >> 8));
    }

    /// Emit opcode with two u16 operands
    pub fn emitOpU16U16(self: *Chunk, op: OpCode, a: u16, b: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, @intCast(a & 0xFF));
        try self.code.append(self.allocator, @intCast(a >> 8));
        try self.code.append(self.allocator, @intCast(b & 0xFF));
        try self.code.append(self.allocator, @intCast(b >> 8));
    }

    /// Emit opcode with u8 + u16 operands
    pub fn emitOpU8U16(self: *Chunk, op: OpCode, a: u8, b: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, a);
        try self.code.append(self.allocator, @intCast(b & 0xFF));
        try self.code.append(self.allocator, @intCast(b >> 8));
    }

    /// Emit CALL: u16 method_idx, u8 argc, u8 call_flags, u16 block_chunk_id
    pub fn emitCall(self: *Chunk, method_idx: u16, argc: u8, call_style: u8, block_chunk_id: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(OpCode.CALL));
        try self.code.append(self.allocator, @intCast(method_idx & 0xFF));
        try self.code.append(self.allocator, @intCast(method_idx >> 8));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, call_style);
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast(block_chunk_id >> 8));
    }

    /// Emit CALL_KW: u16 method_idx, u8 argc, u8 kwargc, u8 call_flags, u16 kw_metadata_idx, u16 block_chunk_id
    pub fn emitCallKw(self: *Chunk, method_idx: u16, argc: u8, kwargc: u8, call_style: u8, kw_metadata_idx: u16, block_chunk_id: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(OpCode.CALL_KW));
        try self.code.append(self.allocator, @intCast(method_idx & 0xFF));
        try self.code.append(self.allocator, @intCast(method_idx >> 8));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, kwargc);
        try self.code.append(self.allocator, call_style);
        try self.code.append(self.allocator, @intCast(kw_metadata_idx & 0xFF));
        try self.code.append(self.allocator, @intCast(kw_metadata_idx >> 8));
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast(block_chunk_id >> 8));
    }

    pub fn emitSuper(self: *Chunk, argc: u8, flags: u8, block_chunk_id: u16, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(OpCode.SUPER));
        try self.code.append(self.allocator, argc);
        try self.code.append(self.allocator, flags);
        try self.code.append(self.allocator, @intCast(block_chunk_id & 0xFF));
        try self.code.append(self.allocator, @intCast(block_chunk_id >> 8));
    }

    /// Emit a jump instruction and return the byte offset of the i16 operand (for patching).
    pub fn emitJump(self: *Chunk, op: OpCode, line: u32) !usize {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        const patch_offset = self.code.items.len;
        try self.code.append(self.allocator, 0); // placeholder lo
        try self.code.append(self.allocator, 0); // placeholder hi
        return patch_offset;
    }

    /// Emit a backward jump to a known target byte offset.
    pub fn emitBackwardJump(self: *Chunk, op: OpCode, target: usize, line: u32) !void {
        try self.recordLine(line);
        try self.code.append(self.allocator, @intFromEnum(op));
        // Offset is relative to the byte after the i16 operand
        const next_ip = self.code.items.len + 2;
        const offset: i16 = @intCast(@as(i32, @intCast(target)) - @as(i32, @intCast(next_ip)));
        const unsigned: u16 = @bitCast(offset);
        try self.code.append(self.allocator, @intCast(unsigned & 0xFF));
        try self.code.append(self.allocator, @intCast(unsigned >> 8));
    }

    /// Patch a jump at the given byte offset. Target is current code end.
    /// Offset is relative to the byte after the i16 operand (next instruction).
    pub fn patchJump(self: *Chunk, patch_offset: usize) !void {
        const target = self.code.items.len;
        const next_ip = patch_offset + 2; // byte after the i16 operand
        const offset: i16 = @intCast(@as(i32, @intCast(target)) - @as(i32, @intCast(next_ip)));
        const unsigned: u16 = @bitCast(offset);
        self.code.items[patch_offset] = @intCast(unsigned & 0xFF);
        self.code.items[patch_offset + 1] = @intCast(unsigned >> 8);
    }

    /// Allocate a new callsite ID and return it.
    pub fn nextCallsiteId(self: *Chunk) !u16 {
        const id: u16 = @intCast(self.callsite_caches.items.len);
        try self.callsite_caches.append(self.allocator, null);
        try self.callsite_descriptors.append(self.allocator, null);
        return id;
    }

    /// Look up line number for a byte offset (binary search on line_info).
    pub fn getLine(self: *Chunk, byte_offset: usize) u32 {
        if (self.line_info.items.len == 0) return 0;
        // Binary search for the last entry with byte_offset <= target
        var lo: usize = 0;
        var hi: usize = self.line_info.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.line_info.items[mid].byte_offset <= byte_offset) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo == 0) return self.line_info.items[0].line;
        return self.line_info.items[lo - 1].line;
    }

    /// Print disassembly of this chunk
    pub fn disassemble(self: *Chunk, writer: *std.Io.Writer) !void {
        if (self.chunk_id) |id| {
            try writer.print("== {s} == (chunk {d})\n", .{ self.name, id });
        } else {
            try writer.print("== {s} ==\n", .{self.name});
        }

        if (self.rest_param_index) |rest_idx| {
            try writer.print("  arity: {d}, rest param at slot {d}, post-required: {d}\n", .{ self.arity, rest_idx, self.post_required_count });
        } else if (self.arity > 0) {
            try writer.print("  arity: {d}\n", .{self.arity});
        }

        if (self.locals_count > 0) {
            try writer.print("  locals: {d}\n", .{self.locals_count});
        }

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
                    .encoded_string => |str| try writer.print("\"{s}\"[{s}]", .{ str.bytes, str.encoding.name() }),
                    .symbol => |sym| try writer.print(":\"{s}\"(interned)", .{sym.name}),
                }
            }
            try writer.print("\n-----------\n", .{});
        }

        // Disassemble byte stream
        var offset: usize = 0;
        while (offset < self.code.items.len) {
            offset = try self.disassembleInstruction(offset, writer);
        }
    }

    fn disassembleInstruction(self: *Chunk, offset: usize, writer: *std.Io.Writer) !usize {
        try writer.print("{:0>4} ", .{offset});

        const line = self.getLine(offset);
        if (offset > 0 and line == self.getLine(offset - 1)) {
            try writer.print("   | ", .{});
        } else {
            try writer.print("{:4} ", .{line});
        }

        const op: OpCode = @enumFromInt(self.code.items[offset]);
        var ip = offset + 1;

        switch (op) {
            .PUSH_NIL, .PUSH_TRUE, .PUSH_FALSE, .PUSH_SELF, .POP, .DUP, .SWAP, .CASE_MATCH, .OPT_PLUS, .OPT_MINUS, .OPT_MULT, .OPT_DIV, .OPT_EQ, .OPT_LT, .OPT_GT, .OPT_LE, .OPT_GE, .HALT, .TRY_END, .CATCH_END, .ENSURE_START, .ENSURE_END, .BREAK, .NEXT, .MULTI_ASSIGN_PREPARE, .ARRAY_APPEND, .ARRAY_CONCAT_ARRAY, .HASH_MERGE_KW, .YIELD_SPLAT => {
                try writer.print("{s}\n", .{bytecode.opcodeName(op)});
            },

            .PUSH_I8 => {
                const val: i8 = @bitCast(self.code.items[ip]);
                ip += 1;
                try writer.print("PUSH_I8 {d}\n", .{val});
            },

            .WHEN_SPLAT => {
                const mode = self.code.items[ip];
                ip += 1;
                try writer.print("WHEN_SPLAT {d}\n", .{mode});
            },

            .GET_LOCAL, .SET_LOCAL => {
                const lo: u16 = self.code.items[ip];
                const hi: u16 = self.code.items[ip + 1];
                const idx = lo | (hi << 8);
                ip += 2;
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), idx });
            },

            .PUSH_RANGE, .INTERPOLATE_STRING, .RAISE, .CATCH_START, .DUP_N, .YIELD => {
                const idx = self.code.items[ip];
                ip += 1;
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), idx });
            },

            .GET_LOCAL_DEEP, .SET_LOCAL_DEEP => {
                const lo: u16 = self.code.items[ip];
                const hi: u16 = self.code.items[ip + 1];
                const local_idx = lo | (hi << 8);
                const depth = self.code.items[ip + 2];
                ip += 3;
                try writer.print("{s} {d} {d}\n", .{ bytecode.opcodeName(op), local_idx, depth });
            },

            .RETURN => {
                const return_mode = self.code.items[ip];
                ip += 1;
                const mode_name = switch (return_mode) {
                    0 => "implicit",
                    1 => "explicit",
                    2 => "top-level-explicit-ignored",
                    3 => "top-level-bare",
                    else => "unknown",
                };
                try writer.print("RETURN {s}\n", .{mode_name});
            },

            .PUSH_CONST, .PUSH_CSTRING, .PUSH_FSTRING, .PUSH_SYMBOL, .GET_CONST, .GET_CONST_OR_NIL, .SET_CONST, .SET_CONST_PATH, .GET_CONST_PATH, .GET_GLOBAL, .GET_BACKREF, .SET_GLOBAL, .GET_CVAR, .GET_CVAR_OR_NIL, .SET_CVAR, .GET_IVAR, .SET_IVAR, .PUSH_ARRAY, .PUSH_HASH, .HASH_SET_CONST_KEY, .TRY_BEGIN, .REDO, .RETRY, .PUSH_LAMBDA, .DEF_SINGLETON_CLASS, .FORWARDING_SUPER => {
                const idx = readU16(self.code.items, &ip);
                try writer.print("{s} {d}", .{ bytecode.opcodeName(op), idx });
                if ((op == .PUSH_CONST or op == .PUSH_CSTRING or op == .PUSH_FSTRING or op == .PUSH_SYMBOL or op == .GET_CONST or op == .GET_CONST_OR_NIL or op == .SET_CONST or op == .SET_CONST_PATH or op == .GET_CONST_PATH or op == .GET_GLOBAL or op == .SET_GLOBAL or op == .GET_CVAR or op == .GET_CVAR_OR_NIL or op == .SET_CVAR or op == .GET_IVAR or op == .SET_IVAR) and idx < self.constants.items.len) {
                    const constant = self.constants.items[idx];
                    switch (constant) {
                        .integer => |i| try writer.print(" ({d})", .{i}),
                        .big_integer_decimal => |digits| try writer.print(" ({s})", .{digits}),
                        .float => |f| try writer.print(" ({d})", .{f}),
                        .string => |s| try writer.print(" (\"{s}\")", .{s}),
                        .encoded_string => |s| try writer.print(" (\"{s}\"[{s}])", .{ s.bytes, s.encoding.name() }),
                        .symbol => |s| try writer.print(" (:{s})", .{s.name}),
                    }
                }
                try writer.print("\n", .{});
            },

            .JUMP, .JUMP_IF_FALSE, .JUMP_IF_TRUE, .JUMP_IF_NIL => {
                const signed_offset = readI16(self.code.items, &ip);
                const target: i32 = @as(i32, @intCast(ip)) + signed_offset;
                try writer.print("{s} {d} (-> {d})\n", .{ bytecode.opcodeName(op), signed_offset, target });
            },

            .CALL => {
                const method_idx = readU16(self.code.items, &ip);
                const argc = self.code.items[ip];
                ip += 1;
                const call_flags = self.code.items[ip];
                ip += 1;
                const block_id = readU16(self.code.items, &ip);
                try writer.print("CALL {d}", .{method_idx});
                if (method_idx < self.constants.items.len) {
                    const c = self.constants.items[method_idx];
                    if (c == .string) try writer.print(" (\"{s}\")", .{c.string});
                }
                try writer.print(", argc={d}, flags={d}, block={d}\n", .{ argc, call_flags, block_id });
            },

            .CALL_KW => {
                const method_idx = readU16(self.code.items, &ip);
                const argc = self.code.items[ip];
                ip += 1;
                const kwargc = self.code.items[ip];
                ip += 1;
                const call_flags = self.code.items[ip];
                ip += 1;
                const kw_metadata_idx = readU16(self.code.items, &ip);
                const block_id = readU16(self.code.items, &ip);
                try writer.print("CALL_KW {d}, {d}, {d}, {d}, {d}, {d}\n", .{ method_idx, argc, kwargc, call_flags, kw_metadata_idx, block_id });
            },

            .DEF_METHOD, .DEF_SINGLETON_METHOD, .ALIAS_METHOD, .PUSH_REGEXP, .DEF_MODULE => {
                const a = readU16(self.code.items, &ip);
                const b = readU16(self.code.items, &ip);
                try writer.print("{s} {d} {d}", .{ bytecode.opcodeName(op), a, b });
                if (a < self.constants.items.len) {
                    const c = self.constants.items[a];
                    if (c == .string) try writer.print(" (\"{s}\")", .{c.string});
                }
                try writer.print("\n", .{});
            },

            .UNDEF_METHOD => {
                const argc = self.code.items[ip];
                ip += 1;
                try writer.print("{s} {d}\n", .{ bytecode.opcodeName(op), argc });
            },

            .DEF_CLASS => {
                const name_idx = readU16(self.code.items, &ip);
                const body_chunk_id = readU16(self.code.items, &ip);
                try writer.print("DEF_CLASS {d}", .{name_idx});
                if (name_idx < self.constants.items.len) {
                    const c = self.constants.items[name_idx];
                    if (c == .string) try writer.print(" (\"{s}\")", .{c.string});
                }
                try writer.print(" {d}\n", .{body_chunk_id});
            },

            .SUPER => {
                const argc = self.code.items[ip];
                ip += 1;
                const flags = self.code.items[ip];
                ip += 1;
                const block_id = readU16(self.code.items, &ip);
                try writer.print("SUPER {d}, {d}, {d}\n", .{ argc, flags, block_id });
            },
        }

        return ip;
    }

    // =========================================================================
    // Byte reading helpers (for disassembly and VM)
    // =========================================================================

    pub fn readU16(code: []const u8, ip: *usize) u16 {
        const lo: u16 = code[ip.*];
        const hi: u16 = code[ip.* + 1];
        ip.* += 2;
        return lo | (hi << 8);
    }

    pub fn readI16(code: []const u8, ip: *usize) i16 {
        return @bitCast(readU16(code, ip));
    }

    /// Post-compilation pass: rewrite depth-0 GET_LOCAL/SET_LOCAL operands from
    /// `local_idx` (0-based) to `ep_offset` (= locals_count - local_idx).
    /// Must be called after locals_count is finalised.
    /// Pass an explicit `lc` override for default-expression sub-chunks that share
    /// the parent scope's locals (their own locals_count is 0).
    /// GET_LOCAL_DEEP / SET_LOCAL_DEEP keep local_idx as emitted; the VM resolves
    /// ep_offset at runtime via ep[2] (the stored locals_count env-data slot).
    pub fn patchEpOffsets(self: *Chunk, lc_override: ?u16) void {
        const lc = lc_override orelse self.locals_count;
        var ip: usize = 0;
        while (ip < self.code.items.len) {
            const op: OpCode = @enumFromInt(self.code.items[ip]);
            const operand_size = bytecode.opcodeOperandSize(op);
            ip += 1;
            switch (op) {
                .GET_LOCAL, .SET_LOCAL => {
                    // 2-byte local_idx → ep_offset
                    const lo: u16 = self.code.items[ip];
                    const hi: u16 = self.code.items[ip + 1];
                    const local_idx: u16 = lo | (hi << 8);
                    const ep_offset: u16 = lc - local_idx;
                    self.code.items[ip] = @intCast(ep_offset & 0xFF);
                    self.code.items[ip + 1] = @intCast(ep_offset >> 8);
                },
                else => {},
            }
            ip += operand_size;
        }
    }
};
