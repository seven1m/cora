pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        nil: void,
    },

    pub fn nil() Value {
        return Value{ .frozen = true, .data = .nil };
    }

    pub fn frozenString(str: []const u8) Value {
        return Value{ .frozen = true, .data = .{ .string = str } };
    }
};
