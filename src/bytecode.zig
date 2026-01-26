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
    POP = 11,

    // Method calls
    CALL = 12, // Operands: u16 (method name index), u8 (argc)
    RETURN = 13,

    // OOP
    DEF_MODULE = 14, // Operand: u16 (name index)
    DEF_CLASS = 15, // Operands: u16 (name index), u8 (body chunk id)
    DEF_METHOD = 16, // Operands: u16 (name index), u8 (chunk index)
    PUSH_SELF = 17,

    // Collections
    PUSH_ARRAY = 18, // Operand: u8 (element count)

    // Special
    HALT = 19,
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
        .POP => "POP",
        .CALL => "CALL",
        .RETURN => "RETURN",
        .DEF_MODULE => "DEF_MODULE",
        .DEF_CLASS => "DEF_CLASS",
        .DEF_METHOD => "DEF_METHOD",
        .PUSH_ARRAY => "PUSH_ARRAY",
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
            .GET_LOCAL, .SET_LOCAL, .PUSH_ARRAY => {
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
