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

    // Arithmetic and comparison
    ADD = 9,
    SUB = 10,
    EQ = 11,

    // Control flow
    JUMP = 12, // Operand: i16 (offset)
    JUMP_IF_FALSE = 13, // Operand: i16 (offset)
    POP = 14,

    // Method calls
    CALL = 15, // Operands: u16 (method name index), u8 (argc)
    CALL_BUILTIN = 16, // Operands: u8 (builtin id), u8 (argc)
    RETURN = 17,

    // OOP
    DEF_MODULE = 18, // Operand: u16 (name index)
    DEF_CLASS = 19, // Operands: u16 (name index), u8 (has_super)
    DEF_METHOD = 20, // Operands: u16 (name index), u8 (chunk index)
    PUSH_SELF = 21,

    // Special
    HALT = 22,
};

pub const BuiltinId = enum(u8) {
    PUTS = 0,
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
        .ADD => "ADD",
        .SUB => "SUB",
        .EQ => "EQ",
        .JUMP => "JUMP",
        .JUMP_IF_FALSE => "JUMP_IF_FALSE",
        .POP => "POP",
        .CALL => "CALL",
        .CALL_BUILTIN => "CALL_BUILTIN",
        .RETURN => "RETURN",
        .DEF_MODULE => "DEF_MODULE",
        .DEF_CLASS => "DEF_CLASS",
        .DEF_METHOD => "DEF_METHOD",
        .HALT => "HALT",
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
            .PUSH_INT, .PUSH_CONST, .GET_CONST, .SET_CONST, .CALL, .DEF_MODULE, .DEF_CLASS, .DEF_METHOD => {
                try writer.print(" {d}", .{self.bx});
            },
            .GET_LOCAL, .SET_LOCAL, .CALL_BUILTIN => {
                try writer.print(" {d}", .{self.a});
            },
            .JUMP, .JUMP_IF_FALSE => {
                const offset: i16 = @bitCast(self.bx);
                try writer.print(" {}", .{offset});
            },
            else => {},
        }
    }
};
