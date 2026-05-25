const std = @import("std");

pub const OpCode = enum(u8) {
    // Literals
    PUSH_NIL, // No operands
    PUSH_TRUE, // No operands
    PUSH_FALSE, // No operands
    PUSH_CONST, // Operand: u16 (constant pool index)
    PUSH_CSTRING, // Operand: u16 (constant pool index)
    PUSH_FSTRING, // Operand: u16 (constant pool index)
    PUSH_SYMBOL, // Operand: u16 (constant pool index containing symbol name string)
    PUSH_I8, // Operand: i8 (inline small integer)

    // Variables and Constants
    GET_LOCAL, // Operand: u16 (ep_offset; patched from local_idx at compile-finalise time)
    GET_LOCAL_DEEP, // Operands: u16 (local_idx), u8 (depth)
    SET_LOCAL, // Operand: u16 (ep_offset; patched from local_idx at compile-finalise time)
    SET_LOCAL_DEEP, // Operands: u16 (local_idx), u8 (depth)
    GET_GLOBAL, // Operand: u16 (constant pool index of variable name)
    GET_BACKREF, // Operand: u16 (1-indexed capture index)
    SET_GLOBAL, // Operand: u16 (constant pool index of variable name)
    GET_CVAR, // Operand: u16 (constant pool index of class variable name)
    GET_CVAR_OR_NIL, // Operand: u16 (constant pool index of class variable name)
    SET_CVAR, // Operand: u16 (constant pool index of class variable name)
    GET_CONST, // Operand: u16 (constant name index)
    GET_CONST_OR_NIL, // Operand: u16 (constant name index)
    SET_CONST, // Operand: u16 (constant name index)
    SET_CONST_PATH, // Operand: u16 (constant name index), receiver and value on stack
    GET_IVAR, // Operand: u16 (constant pool index of variable name)
    SET_IVAR, // Operand: u16 (constant pool index of variable name)

    // Control flow
    JUMP, // Operand: i16 (offset from next instruction)
    JUMP_IF_FALSE, // Operand: i16 (offset)
    JUMP_IF_TRUE, // Operand: i16 (offset)
    JUMP_IF_NIL, // Operand: i16 (offset)
    POP, // No operands
    DUP, // No operands
    DUP_N, // Operand: u8 (duplicate top N stack items in order)
    SWAP, // No operands - swaps top two stack items
    CASE_MATCH, // No operands
    WHEN_SPLAT, // Operand: u8 (0=truthy any, 1=case match any)

    // Method calls
    CALL, // Operands: u16 (method name index), u8 (argc), u8 (call_flags), u16 (block chunk id)
    CALL_KW, // Operands: u16 method_idx, u8 argc, u8 kwargc, u8 call_flags, u16 kw_metadata_idx, u16 block_chunk_id
    FORWARD_ARGS_CALL, // Operands: u16 method_idx, u8 call_flags, u16 block_chunk_id
    FORWARD_ARGS_CALL_WITH_PREFIX, // Operands: u16 method_idx, u8 call_flags, u16 block_chunk_id, u8 prefix_argc
    RETURN, // Operand: u8 (0=implicit, 1=explicit)

    // Optimized ops for integer math
    OPT_PLUS, // No operands
    OPT_MINUS, // No operands
    OPT_MULT, // No operands
    OPT_DIV, // No operands
    OPT_EQ, // No operands
    OPT_LT, // No operands
    OPT_GT, // No operands
    OPT_LE, // No operands
    OPT_GE, // No operands

    // OOP
    DEF_MODULE, // Operands: u16 (name index), u16 (body chunk id)
    DEF_CLASS, // Operands: u16 (name index), u16 (body chunk id)
    DEF_SINGLETON_CLASS, // Operand: u16 (body chunk id) - receiver on stack
    DEF_METHOD, // Operands: u16 (name index), u16 (chunk index)
    DEF_SINGLETON_METHOD, // Operands: u16 (name index), u16 (chunk index) - receiver on stack
    PUSH_SELF, // No operands

    // Collections
    PUSH_ARRAY, // Operand: u16 (element count)
    ARRAY_APPEND, // No operands
    ARRAY_CONCAT_ARRAY, // No operands
    PUSH_HASH, // Operand: u16 (pair count)
    HASH_SET_CONST_KEY, // Operand: u16 (constant pool index containing keyword name)
    HASH_MERGE_KW, // No operands
    PUSH_RANGE, // Operand: u8 (0=inclusive, 1=exclusive)
    INTERPOLATE_STRING, // Operand: u8 (part count)

    // Special
    HALT, // No operands

    // Blocks
    YIELD, // Operand: u8 (argc)
    YIELD_SPLAT, // No operands
    PUSH_LAMBDA, // Operand: u16 (chunk_id)

    // Constant path resolution
    GET_CONST_PATH, // Operand: u16 (constant name index)

    // Exception handling
    RAISE, // Operand: u8 (argc)
    TRY_BEGIN, // Operand: u16 (handler_idx)
    TRY_END, // No operands
    CATCH_START, // Operand: u8 (var_idx)
    CATCH_END, // No operands
    ENSURE_START, // No operands
    ENSURE_END, // No operands
    RETRY, // u16 retry target byte offset
    BREAK, // No operands
    NEXT, // No operands
    REDO, // Operand: u16 (target byte offset)

    // Super calls
    SUPER, // Operands: u8 (argc), u8 (flags), u16 (block_chunk_id)
    FORWARDING_SUPER, // Operand: u16 (block_chunk_id)

    // Regexp
    PUSH_REGEXP, // Operands: u16 (pattern constant index), u16 (options)

    // Aliasing
    ALIAS_METHOD, // Operands: u16 (new_name constant index), u16 (old_name constant index)
    UNDEF_METHOD, // Operand: u8 (argc) - method names are on the stack

    // Multi-assignment
    MULTI_ASSIGN_PREPARE, // No operands
};

pub const ReceiverCallStyle = enum(u8) {
    explicit = 0,
    implicit_self = 1,
};

pub const CALL_FLAG_IMPLICIT_SELF: u8 = 0x01;
pub const CALL_FLAG_ARGS_ARRAY: u8 = 0x02;
pub const CALL_FLAG_KW_HASH: u8 = 0x04;

pub const SUPER_FLAG_ARGS_ARRAY: u8 = CALL_FLAG_ARGS_ARRAY;

pub fn encodeCallFlags(receiver_style: ReceiverCallStyle, args_array_mode: bool) u8 {
    var flags: u8 = 0;
    if (receiver_style == .implicit_self) flags |= CALL_FLAG_IMPLICIT_SELF;
    if (args_array_mode) flags |= CALL_FLAG_ARGS_ARRAY;
    return flags;
}

pub fn addKwHashFlag(flags: u8, kw_hash_mode: bool) u8 {
    if (!kw_hash_mode) return flags;
    return flags | CALL_FLAG_KW_HASH;
}

pub fn decodeReceiverCallStyle(flags: u8) ReceiverCallStyle {
    return if ((flags & CALL_FLAG_IMPLICIT_SELF) != 0) .implicit_self else .explicit;
}

pub fn argsArrayMode(flags: u8) bool {
    return (flags & CALL_FLAG_ARGS_ARRAY) != 0;
}

pub fn kwHashMode(flags: u8) bool {
    return (flags & CALL_FLAG_KW_HASH) != 0;
}

pub const BuiltinId = enum(u8) {
    NEW = 1,
};

/// Returns the number of operand bytes for a given opcode (not counting the opcode byte itself).
pub fn opcodeOperandSize(op: OpCode) usize {
    return switch (op) {
        // No operands
        .PUSH_NIL,
        .PUSH_TRUE,
        .PUSH_FALSE,
        .PUSH_SELF,
        .POP,
        .DUP,
        .SWAP,
        .CASE_MATCH,
        .OPT_PLUS,
        .OPT_MINUS,
        .OPT_MULT,
        .OPT_DIV,
        .OPT_EQ,
        .OPT_LT,
        .OPT_GT,
        .OPT_LE,
        .OPT_GE,
        .ARRAY_APPEND,
        .ARRAY_CONCAT_ARRAY,
        .HASH_MERGE_KW,
        .HALT,
        .TRY_END,
        .CATCH_END,
        .ENSURE_START,
        .ENSURE_END,
        .BREAK,
        .NEXT,
        .YIELD_SPLAT,
        .MULTI_ASSIGN_PREPARE,
        => 0,

        // 1-byte operands
        .DUP_N,
        .YIELD,
        .RETURN,
        .WHEN_SPLAT,
        .PUSH_RANGE,
        .INTERPOLATE_STRING,
        .RAISE,
        .CATCH_START,
        .PUSH_I8,
        .UNDEF_METHOD,
        => 1,

        // 2-byte operands (u16)
        .GET_LOCAL,
        .SET_LOCAL,
        .GET_GLOBAL,
        .SET_GLOBAL,
        .GET_BACKREF,
        .GET_CVAR,
        .GET_CVAR_OR_NIL,
        .SET_CVAR,
        .GET_CONST,
        .GET_CONST_OR_NIL,
        .SET_CONST,
        .SET_CONST_PATH,
        .GET_IVAR,
        .SET_IVAR,
        .PUSH_CONST,
        .PUSH_CSTRING,
        .PUSH_FSTRING,
        .PUSH_SYMBOL,
        .JUMP,
        .JUMP_IF_FALSE,
        .JUMP_IF_TRUE,
        .JUMP_IF_NIL,
        .TRY_BEGIN,
        .REDO,
        .RETRY,
        .PUSH_LAMBDA,
        .GET_CONST_PATH,
        .PUSH_ARRAY,
        .PUSH_HASH,
        .HASH_SET_CONST_KEY,
        => 2,

        // 3-byte operands: GET_LOCAL_DEEP / SET_LOCAL_DEEP = u16 local_idx + u8 depth
        .GET_LOCAL_DEEP, .SET_LOCAL_DEEP => 3,

        // 4-byte operands
        .DEF_SINGLETON_CLASS, // u16 body_chunk_id (2 bytes)
        => 2,

        // DEF_MODULE: u16 name_idx + u16 body_chunk_id = 4 bytes
        .DEF_MODULE,
        .DEF_METHOD,
        .DEF_SINGLETON_METHOD,
        .DEF_CLASS,
        => 4,

        // SUPER: u8 argc + u8 flags + u16 block_chunk_id = 4 bytes
        .SUPER => 4,

        // FORWARDING_SUPER: u16 block_chunk_id = 2 bytes
        .FORWARDING_SUPER => 2,

        // PUSH_REGEXP: u16 pattern + u16 options = 4 bytes
        .PUSH_REGEXP => 4,

        // ALIAS_METHOD: u16 new_name + u16 old_name = 4 bytes
        .ALIAS_METHOD => 4,

        // CALL: u16 method_idx + u8 argc + u8 call_flags + u16 block_chunk_id = 6 bytes
        .CALL => 6,

        // CALL_KW: u16 method_idx + u8 argc + u8 kwargc + u8 call_flags + u16 kw_metadata_idx + u16 block_chunk_id = 9 bytes
        .CALL_KW => 9,

        // FORWARD_ARGS_CALL: u16 method_idx + u8 call_flags + u16 block_chunk_id = 5 bytes
        .FORWARD_ARGS_CALL => 5,

        // FORWARD_ARGS_CALL_WITH_PREFIX: u16 method_idx + u8 call_flags + u16 block_chunk_id + u8 prefix_argc = 6 bytes
        .FORWARD_ARGS_CALL_WITH_PREFIX => 6,
    };
}

pub fn opcodeName(op: OpCode) []const u8 {
    return switch (op) {
        .PUSH_NIL => "PUSH_NIL",
        .PUSH_TRUE => "PUSH_TRUE",
        .PUSH_FALSE => "PUSH_FALSE",
        .PUSH_CONST => "PUSH_CONST",
        .PUSH_CSTRING => "PUSH_CSTRING",
        .PUSH_FSTRING => "PUSH_FSTRING",
        .PUSH_SYMBOL => "PUSH_SYMBOL",
        .PUSH_I8 => "PUSH_I8",
        .GET_LOCAL => "GET_LOCAL",
        .GET_LOCAL_DEEP => "GET_LOCAL_DEEP",
        .SET_LOCAL => "SET_LOCAL",
        .SET_LOCAL_DEEP => "SET_LOCAL_DEEP",
        .GET_GLOBAL => "GET_GLOBAL",
        .GET_BACKREF => "GET_BACKREF",
        .SET_GLOBAL => "SET_GLOBAL",
        .GET_CVAR => "GET_CVAR",
        .GET_CVAR_OR_NIL => "GET_CVAR_OR_NIL",
        .SET_CVAR => "SET_CVAR",
        .GET_CONST => "GET_CONST",
        .GET_CONST_OR_NIL => "GET_CONST_OR_NIL",
        .SET_CONST => "SET_CONST",
        .SET_CONST_PATH => "SET_CONST_PATH",
        .GET_IVAR => "GET_IVAR",
        .SET_IVAR => "SET_IVAR",
        .PUSH_SELF => "PUSH_SELF",
        .JUMP => "JUMP",
        .JUMP_IF_FALSE => "JUMP_IF_FALSE",
        .JUMP_IF_TRUE => "JUMP_IF_TRUE",
        .JUMP_IF_NIL => "JUMP_IF_NIL",
        .POP => "POP",
        .DUP => "DUP",
        .DUP_N => "DUP_N",
        .SWAP => "SWAP",
        .CASE_MATCH => "CASE_MATCH",
        .WHEN_SPLAT => "WHEN_SPLAT",
        .CALL => "CALL",
        .CALL_KW => "CALL_KW",
        .OPT_PLUS => "OPT_PLUS",
        .OPT_MINUS => "OPT_MINUS",
        .OPT_MULT => "OPT_MULT",
        .OPT_DIV => "OPT_DIV",
        .OPT_EQ => "OPT_EQ",
        .OPT_LT => "OPT_LT",
        .OPT_GT => "OPT_GT",
        .OPT_LE => "OPT_LE",
        .OPT_GE => "OPT_GE",
        .RETURN => "RETURN",
        .DEF_MODULE => "DEF_MODULE",
        .DEF_CLASS => "DEF_CLASS",
        .DEF_SINGLETON_CLASS => "DEF_SINGLETON_CLASS",
        .DEF_METHOD => "DEF_METHOD",
        .PUSH_ARRAY => "PUSH_ARRAY",
        .ARRAY_APPEND => "ARRAY_APPEND",
        .ARRAY_CONCAT_ARRAY => "ARRAY_CONCAT_ARRAY",
        .PUSH_HASH => "PUSH_HASH",
        .HASH_SET_CONST_KEY => "HASH_SET_CONST_KEY",
        .HASH_MERGE_KW => "HASH_MERGE_KW",
        .PUSH_RANGE => "PUSH_RANGE",
        .INTERPOLATE_STRING => "INTERPOLATE_STRING",
        .HALT => "HALT",
        .DEF_SINGLETON_METHOD => "DEF_SINGLETON_METHOD",
        .YIELD => "YIELD",
        .YIELD_SPLAT => "YIELD_SPLAT",
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
        .NEXT => "NEXT",
        .REDO => "REDO",
        .SUPER => "SUPER",
        .FORWARDING_SUPER => "FORWARDING_SUPER",
        .FORWARD_ARGS_CALL => "FORWARD_ARGS_CALL",
        .FORWARD_ARGS_CALL_WITH_PREFIX => "FORWARD_ARGS_CALL_WITH_PREFIX",
        .PUSH_REGEXP => "PUSH_REGEXP",
        .ALIAS_METHOD => "ALIAS_METHOD",
        .UNDEF_METHOD => "UNDEF_METHOD",
        .MULTI_ASSIGN_PREPARE => "MULTI_ASSIGN_PREPARE",
    };
}
