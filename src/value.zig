pub const ModuleValue = struct {
    name: []const u8,
};

pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
        symbol: []const u8,
        module: ModuleValue,
    },

    pub fn nil() Value {
        return .{ .frozen = true, .data = .nil };
    }

    pub fn frozenString(str: []const u8) Value {
        return .{ .frozen = true, .data = .{ .string = str } };
    }

    pub fn integer(value: i64) Value {
        return .{ .frozen = true, .data = .{ .integer = value } };
    }

    pub fn symbol(str: []const u8) Value {
        return .{ .frozen = true, .data = .{ .symbol = str } };
    }

    pub fn module(name: []const u8) Value {
        return .{ .frozen = false, .data = .{ .module = .{ .name = name } } };
    }
};
