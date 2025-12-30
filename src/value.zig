pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
        symbol: []const u8,
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

    pub fn symbol(str: []const u8) Value {
        return Value{ .frozen = true, .data = .{ .symbol = str } };
    }
};
