const std = @import("std");
const value = @import("value.zig");

const Value = value.Value;

pub const Kind = enum {
    string_compare_fallback,
    array_inspect,
    object_inspect,
    hash_inspect,
    range_inspect,
    array_equal,
    array_eql,
    array_compare,
    struct_equal,
    struct_eql,
    data_equal,
    data_eql,
    comparable_equal,
    array_hash,
    struct_hash,
    hash_equal,
    hash_eql,
    hash_hash,
    file_join,
};

const Entry = struct {
    context: usize,
    kind: Kind,
    lhs_raw: u64,
    rhs_raw: u64,
};

pub const RecursionGuard = struct {
    stack: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *RecursionGuard, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
    }

    fn key(context: usize, kind: Kind, lhs: Value, rhs: Value) Entry {
        return .{
            .context = context,
            .kind = kind,
            .lhs_raw = lhs.raw,
            .rhs_raw = rhs.raw,
        };
    }

    pub fn enter(self: *RecursionGuard, allocator: std.mem.Allocator, context: usize, kind: Kind, lhs: Value, rhs: Value) !bool {
        const wanted = key(context, kind, lhs, rhs);
        for (self.stack.items) |entry| {
            if (entry.context == wanted.context and entry.kind == wanted.kind and entry.lhs_raw == wanted.lhs_raw and entry.rhs_raw == wanted.rhs_raw) {
                return true;
            }
        }
        try self.stack.append(allocator, wanted);
        return false;
    }

    pub fn leave(self: *RecursionGuard, context: usize, kind: Kind, lhs: Value, rhs: Value) void {
        const wanted = key(context, kind, lhs, rhs);
        var i = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            const entry = self.stack.items[i];
            if (entry.context == wanted.context and entry.kind == wanted.kind and entry.lhs_raw == wanted.lhs_raw and entry.rhs_raw == wanted.rhs_raw) {
                _ = self.stack.swapRemove(i);
                return;
            }
        }
    }
};
