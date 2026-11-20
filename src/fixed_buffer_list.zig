const std = @import("std");

pub fn FixedBufferList(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        // Allocate once, before execution. Live frames/environments can point
        // into this buffer, so its address must remain stable until detached.
        storage: []T = &.{},
        items: []T = &.{},
        capacity: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn ensureAllocated(self: *Self, allocator: std.mem.Allocator) !void {
            if (self.storage.len != 0) return;
            self.storage = try allocator.alloc(T, N);
            self.items = self.storage[0..0];
            self.capacity = N;
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
