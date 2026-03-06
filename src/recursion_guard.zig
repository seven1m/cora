const std = @import("std");
const value = @import("value.zig");

const Value = value.Value;

pub const Kind = enum {
    string_compare_fallback,
    array_inspect,
    array_equal,
};

const Entry = struct {
    kind: Kind,
    lhs_raw: u64,
    rhs_raw: u64,
};

pub const RecursionGuard = struct {
    stack: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *RecursionGuard, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
    }

    fn key(kind: Kind, lhs: Value, rhs: Value) Entry {
        return .{
            .kind = kind,
            .lhs_raw = lhs.raw,
            .rhs_raw = rhs.raw,
        };
    }

    pub fn enter(self: *RecursionGuard, allocator: std.mem.Allocator, kind: Kind, lhs: Value, rhs: Value) !bool {
        const wanted = key(kind, lhs, rhs);
        for (self.stack.items) |entry| {
            if (entry.kind == wanted.kind and entry.lhs_raw == wanted.lhs_raw and entry.rhs_raw == wanted.rhs_raw) {
                return true;
            }
        }
        try self.stack.append(allocator, wanted);
        return false;
    }

    pub fn leave(self: *RecursionGuard, kind: Kind, lhs: Value, rhs: Value) void {
        const wanted = key(kind, lhs, rhs);
        var i = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            const entry = self.stack.items[i];
            if (entry.kind == wanted.kind and entry.lhs_raw == wanted.lhs_raw and entry.rhs_raw == wanted.rhs_raw) {
                _ = self.stack.swapRemove(i);
                return;
            }
        }
    }
};
