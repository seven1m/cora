pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
    },

    pub fn nil() Value {
        return Value{ .frozen = true, .data = .nil };
    }

    pub fn frozenString(str: []const u8) Value {
        return Value{ .frozen = true, .data = .{ .string = str } };
    }

    pub fn integer(value: i64) Value {
        return Value{ .frozen = true, .data = .{ .integer = value } };
    }
};
