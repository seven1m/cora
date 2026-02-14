const std = @import("std");

pub const OpCode = enum(u8) {
    // Literals
    PUSH_NIL, // No operands
    PUSH_TRUE, // No operands
    PUSH_FALSE, // No operands
    PUSH_CONST, // Operand: u16 (constant pool index)

    // Variables and Constants
    GET_LOCAL, // Operand: u8 (local index)
    GET_LOCAL_DEEP, // Operands: u8 (local index), u8 (depth)
    SET_LOCAL, // Operand: u8 (local index)
    SET_LOCAL_DEEP, // Operands: u8 (local index), u8 (depth)
    GET_GLOBAL, // Operand: u16 (constant pool index of variable name)
    SET_GLOBAL, // Operand: u16 (constant pool index of variable name)
    GET_CVAR, // Operand: u16 (constant pool index of class variable name)
    GET_CVAR_OR_NIL, // Operand: u16 (constant pool index of class variable name)
    SET_CVAR, // Operand: u16 (constant pool index of class variable name)
    GET_CONST, // Operand: u16 (constant name index)
    GET_CONST_OR_NIL, // Operand: u16 (constant name index)
    SET_CONST, // Operand: u16 (constant name index)
    GET_IVAR, // Operand: u16 (constant pool index of variable name)
    SET_IVAR, // Operand: u16 (constant pool index of variable name)

    // Control flow
    JUMP, // Operand: i16 (offset)
    JUMP_IF_FALSE, // Operand: i16 (offset)
    JUMP_IF_TRUE, // Operand: i16 (offset)
    POP, // No operands
    DUP, // No operands
    DUP_N, // Operand: u8 (duplicate top N stack items in order)
    SWAP, // No operands - swaps top two stack items
    CASE_MATCH, // No operands - stack: [predicate, condition] -> [predicate, condition === predicate]

    // Method calls
    CALL, // Operands: u16 (method name index), u8 (argc), u16 (block chunk id)
    CALL_KW, // Operands: u16 method_idx, u8 argc, u8 kwargc, u16 kw_metadata_idx, u16 block_chunk_id
    RETURN, // Operand: u8 (0=implicit, 1=explicit)

    // OOP
    DEF_MODULE, // Operands: u16 (name index), u16 (body chunk id)
    DEF_CLASS, // Operands: u16 (name index), u16 (body chunk id)
    DEF_METHOD, // Operands: u16 (name index), u16 (chunk index)
    DEF_SINGLETON_METHOD, // Operands: u16 (name index), u16 (chunk index) - receiver on stack
    PUSH_SELF, // No operands

    // Collections
    PUSH_ARRAY, // Operand: u16 (element count)
    ARRAY_APPEND, // No operands - stack: [..., array, value] -> [..., array]
    ARRAY_CONCAT_ARRAY, // No operands - stack: [..., array, other_array] -> [..., array]
    PUSH_HASH, // Operand: u16 (pair count)
    PUSH_RANGE, // Operand: u8 (0=inclusive, 1=exclusive) - pops start, end from stack
    INTERPOLATE_STRING, // Operand: u8 (part count)

    // Special
    HALT, // No operands

    // Blocks
    YIELD, // Operand: u8 (argc)
    PUSH_LAMBDA, // Operand: u16 (chunk_id)

    // Constant path resolution
    GET_CONST_PATH, // Operand: u16 (constant name index) - pops module/class, looks up constant

    // Exception handling
    RAISE, // Operand: u8 (argc) - 0=re-raise, 1=exception instance or class, 2=class+message
    TRY_BEGIN, // Operand: u16 (handler_idx) - points to exception_handlers table entry
    TRY_END, // No operands - marks end of protected region (normal completion)
    CATCH_START, // Operand: u8 (var_idx) - store exception in local var (255 = no binding)
    CATCH_END, // No operands - marks exit from rescue clause
    ENSURE_START, // No operands - marks entry to ensure block
    ENSURE_END, // No operands - marks exit from ensure block
    RETRY, // No operands - jump back to beginning of current begin block
    BREAK, // No operands - used for breaking from blocks

    // Super calls
    SUPER, // Operands: u8 (argc), u8 (flags), u16 (block_chunk_id)
    FORWARDING_SUPER, // Operand: u16 (block_chunk_id)

    // Regexp
    PUSH_REGEXP, // Operands: u16 (pattern constant index), u16 (options)

    // Aliasing
    ALIAS_METHOD, // Operands: u16 (new_name constant index), u16 (old_name constant index)

    // Multi-assignment
    MULTI_ASSIGN_PREPARE, // No operands - converts TOS to array via to_ary protocol
};

pub const ReceiverCallStyle = enum(u8) {
    explicit = 0,
    implicit_self = 1,
};

pub const CALL_FLAG_IMPLICIT_SELF: u8 = 0x01;
pub const CALL_FLAG_ARGS_ARRAY: u8 = 0x02;

pub const SUPER_FLAG_ARGS_ARRAY: u8 = CALL_FLAG_ARGS_ARRAY;

pub fn encodeCallFlags(receiver_style: ReceiverCallStyle, args_array_mode: bool) u8 {
    var flags: u8 = 0;
    if (receiver_style == .implicit_self) flags |= CALL_FLAG_IMPLICIT_SELF;
    if (args_array_mode) flags |= CALL_FLAG_ARGS_ARRAY;
    return flags;
}

pub fn decodeReceiverCallStyle(flags: u8) ReceiverCallStyle {
    return if ((flags & CALL_FLAG_IMPLICIT_SELF) != 0) .implicit_self else .explicit;
}

pub fn argsArrayMode(flags: u8) bool {
    return (flags & CALL_FLAG_ARGS_ARRAY) != 0;
}

pub const BuiltinId = enum(u8) {
    NEW = 1,
};

pub fn opcodeName(op: OpCode) []const u8 {
    return switch (op) {
        .PUSH_NIL => "PUSH_NIL",
        .PUSH_TRUE => "PUSH_TRUE",
        .PUSH_FALSE => "PUSH_FALSE",
        .PUSH_CONST => "PUSH_CONST",
        .GET_LOCAL => "GET_LOCAL",
        .GET_LOCAL_DEEP => "GET_LOCAL_DEEP",
        .SET_LOCAL => "SET_LOCAL",
        .SET_LOCAL_DEEP => "SET_LOCAL_DEEP",
        .GET_GLOBAL => "GET_GLOBAL",
        .SET_GLOBAL => "SET_GLOBAL",
        .GET_CVAR => "GET_CVAR",
        .GET_CVAR_OR_NIL => "GET_CVAR_OR_NIL",
        .SET_CVAR => "SET_CVAR",
        .GET_CONST => "GET_CONST",
        .GET_CONST_OR_NIL => "GET_CONST_OR_NIL",
        .SET_CONST => "SET_CONST",
        .GET_IVAR => "GET_IVAR",
        .SET_IVAR => "SET_IVAR",
        .PUSH_SELF => "PUSH_SELF",
        .JUMP => "JUMP",
        .JUMP_IF_FALSE => "JUMP_IF_FALSE",
        .JUMP_IF_TRUE => "JUMP_IF_TRUE",
        .POP => "POP",
        .DUP => "DUP",
        .DUP_N => "DUP_N",
        .SWAP => "SWAP",
        .CASE_MATCH => "CASE_MATCH",
        .CALL => "CALL",
        .CALL_KW => "CALL_KW",
        .RETURN => "RETURN",
        .DEF_MODULE => "DEF_MODULE",
        .DEF_CLASS => "DEF_CLASS",
        .DEF_METHOD => "DEF_METHOD",
        .PUSH_ARRAY => "PUSH_ARRAY",
        .ARRAY_APPEND => "ARRAY_APPEND",
        .ARRAY_CONCAT_ARRAY => "ARRAY_CONCAT_ARRAY",
        .PUSH_HASH => "PUSH_HASH",
        .PUSH_RANGE => "PUSH_RANGE",
        .INTERPOLATE_STRING => "INTERPOLATE_STRING",
        .HALT => "HALT",
        .DEF_SINGLETON_METHOD => "DEF_SINGLETON_METHOD",
        .YIELD => "YIELD",
        .PUSH_LAMBDA => "PUSH_LAMBDA",
        .GET_CONST_PATH => "GET_CONST_PATH",
        .RAISE => "RAISE",
        .TRY_BEGIN => "TRY_BEGIN",
        .TRY_END => "TRY_END",
        .CATCH_START => "CATCH_START",
        .CATCH_END => "CATCH_END",
        .ENSURE_START => "ENSURE_START",
        .ENSURE_END => "ENSURE_END",
        .RETRY => "RETRY",
        .BREAK => "BREAK",
        .SUPER => "SUPER",
        .FORWARDING_SUPER => "FORWARDING_SUPER",
        .PUSH_REGEXP => "PUSH_REGEXP",
        .ALIAS_METHOD => "ALIAS_METHOD",
        .MULTI_ASSIGN_PREPARE => "MULTI_ASSIGN_PREPARE",
    };
}

/// Read a u8 from bytecode at position
pub fn readU8(code: []const u8, pos: usize) u8 {
    return code[pos];
}

/// Read a u16 from bytecode at position (little-endian)
pub fn readU16(code: []const u8, pos: usize) u16 {
    const lo: u16 = code[pos];
    const hi: u16 = code[pos + 1];
    return lo | (hi << 8);
}

/// Read a signed i16 from bytecode at position (little-endian)
pub fn readI16(code: []const u8, pos: usize) i16 {
    const unsigned = readU16(code, pos);
    return @bitCast(unsigned);
}

pub const Instruction = struct {
    op: OpCode,
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    ax: u16 = 0,
    bx: u16 = 0,

    pub fn format(self: Instruction, comptime _: []const u8, _: std.fmt.FormatOptions, writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{opcodeName(self.op)});

        switch (self.op) {
            .PUSH_CONST, .GET_CONST, .GET_CONST_OR_NIL, .SET_CONST, .GET_CONST_PATH, .DEF_MODULE, .DEF_CLASS, .DEF_METHOD, .GET_GLOBAL, .SET_GLOBAL, .GET_CVAR, .GET_CVAR_OR_NIL, .SET_CVAR, .GET_IVAR, .SET_IVAR => {
                try writer.print(" {d}", .{self.bx});
            },
            .CALL => {
                try writer.print(" {d} {d} {d}", .{ self.bx, self.a, self.ax });
            },
            .GET_LOCAL, .SET_LOCAL, .PUSH_RANGE, .INTERPOLATE_STRING => {
                try writer.print(" {d}", .{self.a});
            },
            .PUSH_ARRAY, .PUSH_HASH => {
                try writer.print(" {d}", .{self.bx});
            },
            .GET_LOCAL_DEEP, .SET_LOCAL_DEEP => {
                try writer.print(" {d} {d}", .{ self.a, self.b });
            },
            .JUMP, .JUMP_IF_FALSE, .JUMP_IF_TRUE => {
                const offset: i16 = @bitCast(self.bx);
                try writer.print(" {}", .{offset});
            },
            .YIELD, .RETURN => {
                try writer.print(" {d}", .{self.a});
            },
            .PUSH_LAMBDA => {
                try writer.print(" {d}", .{self.ax});
            },
            .PUSH_REGEXP, .ALIAS_METHOD => {
                try writer.print(" {d} {d}", .{ self.bx, self.ax });
            },
            .DUP_N => {
                try writer.print(" {d}", .{self.a});
            },
            .PUSH_NIL, .PUSH_TRUE, .PUSH_FALSE, .PUSH_SELF, .POP, .DUP, .SWAP, .CASE_MATCH, .HALT, .TRY_END, .CATCH_END, .ENSURE_START, .ENSURE_END, .RETRY, .BREAK, .MULTI_ASSIGN_PREPARE, .ARRAY_APPEND, .ARRAY_CONCAT_ARRAY => {},
            else => {},
        }
    }
};
