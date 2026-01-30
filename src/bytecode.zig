const std = @import("std");

pub const OpCode = enum(u8) {
    // Literals
    PUSH_NIL = 0,
    PUSH_TRUE = 1,
    PUSH_FALSE = 2,
    PUSH_INT = 3, // Operand: u16 (constant pool index)
    PUSH_CONST = 4, // Operand: u16 (constant pool index)

    // Variables and Constants
    GET_LOCAL = 5, // Operand: u8 (local index)
    SET_LOCAL = 6, // Operand: u8 (local index)
    GET_CONST = 7, // Operand: u16 (constant name index)
    SET_CONST = 8, // Operand: u16 (constant name index)

    // Control flow
    JUMP = 9, // Operand: i16 (offset)
    JUMP_IF_FALSE = 10, // Operand: i16 (offset)
    JUMP_IF_TRUE = 11, // Operand: i16 (offset)
    POP = 12,

    // Method calls
    CALL = 13, // Operands: u16 (method name index), u8 (argc), u8 (block chunk id)
    RETURN = 14,

    // OOP
    DEF_MODULE = 15, // Operand: u16 (name index)
    DEF_CLASS = 16, // Operands: u16 (name index), u8 (body chunk id)
    DEF_METHOD = 17, // Operands: u16 (name index), u8 (chunk index)
    DEF_SINGLETON_METHOD = 18, // Operands: u16 (name index), u8 (chunk index) - receiver on stack
    PUSH_SELF = 19,

    // Collections
    PUSH_ARRAY = 20, // Operand: u8 (element count)

    // Special
    HALT = 21,

    // Blocks
    YIELD = 22, // Operand: u8 (argc)

    // Constant path resolution
    GET_CONST_PATH = 23, // Operand: u16 (constant name index) - pops module/class, looks up constant

    // Exception handling
    RAISE = 24, // Operand: u8 (argc) - 0=re-raise, 1=exception instance or class, 2=class+message
    TRY_BEGIN = 25, // Operand: u16 (handler_idx) - points to exception_handlers table entry
    TRY_END = 26, // No operands - marks end of protected region (normal completion)
    CATCH_START = 27, // Operand: u8 (var_idx) - store exception in local var (255 = no binding)
    CATCH_END = 28, // No operands - marks exit from rescue clause
    ENSURE_START = 29, // No operands - marks entry to ensure block
    ENSURE_END = 30, // No operands - marks exit from ensure block
    RETRY = 31, // No operands - jump back to beginning of current begin block
    BREAK = 32, // No operands - used for breaking from blocks
};

pub const BuiltinId = enum(u8) {
    NEW = 1,
};

pub fn opcodeName(op: OpCode) []const u8 {
    return switch (op) {
        .PUSH_NIL => "PUSH_NIL",
        .PUSH_TRUE => "PUSH_TRUE",
        .PUSH_FALSE => "PUSH_FALSE",
        .PUSH_INT => "PUSH_INT",
        .PUSH_CONST => "PUSH_CONST",
        .GET_LOCAL => "GET_LOCAL",
        .SET_LOCAL => "SET_LOCAL",
        .GET_CONST => "GET_CONST",
        .SET_CONST => "SET_CONST",
        .PUSH_SELF => "PUSH_SELF",
        .JUMP => "JUMP",
        .JUMP_IF_FALSE => "JUMP_IF_FALSE",
        .JUMP_IF_TRUE => "JUMP_IF_TRUE",
        .POP => "POP",
        .CALL => "CALL",
        .RETURN => "RETURN",
        .DEF_MODULE => "DEF_MODULE",
        .DEF_CLASS => "DEF_CLASS",
        .DEF_METHOD => "DEF_METHOD",
        .PUSH_ARRAY => "PUSH_ARRAY",
        .HALT => "HALT",
        .DEF_SINGLETON_METHOD => "DEF_SINGLETON_METHOD",
        .YIELD => "YIELD",
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
            .PUSH_INT, .PUSH_CONST, .GET_CONST, .SET_CONST, .GET_CONST_PATH, .DEF_MODULE, .DEF_CLASS, .DEF_METHOD => {
                try writer.print(" {d}", .{self.bx});
            },
            .CALL => {
                try writer.print(" {d} {d} {d}", .{ self.bx, self.a, self.b });
            },
            .GET_LOCAL, .SET_LOCAL, .PUSH_ARRAY => {
                try writer.print(" {d}", .{self.a});
            },
            .JUMP, .JUMP_IF_FALSE, .JUMP_IF_TRUE => {
                const offset: i16 = @bitCast(self.bx);
                try writer.print(" {}", .{offset});
            },
            .YIELD => {
                try writer.print(" {d}", .{self.a});
            },
            else => {},
        }
    }
};
