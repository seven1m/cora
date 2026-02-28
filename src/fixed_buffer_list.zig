const std = @import("std");

pub fn FixedBufferList(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        storage: [N]T = undefined,
        items: []T = undefined,
        capacity: usize = N,

        pub fn init() Self {
            var self: Self = undefined;
            self.storage = undefined;
            self.items = self.storage[0..0];
            self.capacity = N;
            return self;
        }

        pub fn append(self: *Self, _: std.mem.Allocator, item: T) !void {
            if (self.items.len >= self.capacity) return error.OutOfMemory;
            self.storage[self.items.len] = item;
            self.items = self.storage[0 .. self.items.len + 1];
        }

        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;
            const idx = self.items.len - 1;
            const val = self.storage[idx];
            self.items = self.storage[0..idx];
            return val;
        }

        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            if (new_len >= self.items.len) return;
            self.items = self.storage[0..new_len];
        }

        pub fn deinit(_: *Self, _: std.mem.Allocator) void {}
    };
}
