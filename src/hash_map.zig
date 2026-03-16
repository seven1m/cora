// Derived in part from Zig's standard library hash_map.zig implementation.
// Copyright (c) Zig contributors.
// Adapted locally for Cora to support error-aware hash/equality callbacks.

const std = @import("std");

const assert = std.debug.assert;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const Alignment = std.mem.Alignment;

pub const default_max_load_percentage = std.hash_map.default_max_load_percentage;

pub fn HashMap(
    comptime K: type,
    comptime V: type,
    comptime Context: type,
    comptime max_load_percentage: u64,
) type {
    if (max_load_percentage <= 0 or max_load_percentage >= 100) {
        @compileError("max_load_percentage must be between 0 and 100.");
    }

    const ContextError = Context.Error;
    const MapError = Allocator.Error || ContextError;

    return struct {
        unmanaged: Unmanaged = .empty,
        allocator: Allocator,
        ctx: Context,

        const Self = @This();

        pub const Unmanaged = HashMapUnmanaged(K, V, Context, max_load_percentage);
        pub const Entry = Unmanaged.Entry;
        pub const KV = Unmanaged.KV;
        pub const GetOrPutResult = Unmanaged.GetOrPutResult;
        pub const Size = Unmanaged.Size;

        pub fn initContext(allocator: Allocator, ctx: Context) Self {
            return .{
                .allocator = allocator,
                .ctx = ctx,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.unmanaged.clearRetainingCapacity();
        }

        pub fn count(self: Self) Size {
            return self.unmanaged.count();
        }

        pub fn get(self: Self, key: K) ContextError!?V {
            return self.unmanaged.getContext(key, self.ctx);
        }

        pub fn getPtr(self: *Self, key: K) ContextError!?*V {
            return self.unmanaged.getPtrContext(key, self.ctx);
        }

        pub fn getEntry(self: *Self, key: K) ContextError!?Entry {
            return self.unmanaged.getEntryContext(key, self.ctx);
        }

        pub fn getOrPut(self: *Self, key: K) MapError!GetOrPutResult {
            return self.unmanaged.getOrPutContext(self.allocator, key, self.ctx);
        }

        pub fn put(self: *Self, key: K, value: V) MapError!void {
            return self.unmanaged.putContext(self.allocator, key, value, self.ctx);
        }

        pub fn fetchRemove(self: *Self, key: K) ContextError!?KV {
            return self.unmanaged.fetchRemoveContext(key, self.ctx);
        }
    };
}

pub fn HashMapUnmanaged(
    comptime K: type,
    comptime V: type,
    comptime Context: type,
    comptime max_load_percentage: u64,
) type {
    const ContextError = Context.Error;
    const MapError = Allocator.Error || ContextError;

    return struct {
        metadata: ?[*]Metadata = null,
        size: Size = 0,
        available: Size = 0,

        const Self = @This();

        const minimal_capacity = 8;

        pub const empty: Self = .{};
        pub const Size = u32;
        pub const Hash = u64;

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const KV = struct {
            key: K,
            value: V,
        };

        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        const Header = struct {
            values: [*]V,
            keys: [*]K,
            capacity: Size,
        };

        const Metadata = packed struct {
            const FingerPrint = u7;

            const free: FingerPrint = 0;
            const tombstone: FingerPrint = 1;

            fingerprint: FingerPrint = free,
            used: u1 = 0,

            const slot_free = @as(u8, @bitCast(Metadata{ .fingerprint = free }));
            const slot_tombstone = @as(u8, @bitCast(Metadata{ .fingerprint = tombstone }));

            fn isUsed(self: Metadata) bool {
                return self.used == 1;
            }

            fn isTombstone(self: Metadata) bool {
                return @as(u8, @bitCast(self)) == slot_tombstone;
            }

            fn isFree(self: Metadata) bool {
                return @as(u8, @bitCast(self)) == slot_free;
            }

            fn takeFingerprint(hash: Hash) FingerPrint {
                const hash_bits = @typeInfo(Hash).int.bits;
                const fp_bits = @typeInfo(FingerPrint).int.bits;
                return @as(FingerPrint, @truncate(hash >> (hash_bits - fp_bits)));
            }

            fn fill(self: *Metadata, fp: FingerPrint) void {
                self.used = 1;
                self.fingerprint = fp;
            }

            fn remove(self: *Metadata) void {
                self.used = 0;
                self.fingerprint = tombstone;
            }
        };

        comptime {
            assert(@sizeOf(Metadata) == 1);
            assert(@alignOf(Metadata) == 1);
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.deallocate(allocator);
            self.* = undefined;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            if (self.metadata == null) return;
            self.initMetadatas();
            self.size = 0;
            self.available = @truncate((self.capacity() * max_load_percentage) / 100);
        }

        pub fn count(self: Self) Size {
            return self.size;
        }

        pub fn getContext(self: Self, key: K, ctx: Context) ContextError!?V {
            if (try self.getIndex(key, ctx)) |idx| {
                return self.values()[idx];
            }
            return null;
        }

        pub fn getPtrContext(self: *Self, key: K, ctx: Context) ContextError!?*V {
            if (try self.getIndex(key, ctx)) |idx| {
                return &self.values()[idx];
            }
            return null;
        }

        pub fn getEntryContext(self: *Self, key: K, ctx: Context) ContextError!?Entry {
            if (try self.getIndex(key, ctx)) |idx| {
                return Entry{
                    .key_ptr = &self.keys()[idx],
                    .value_ptr = &self.values()[idx],
                };
            }
            return null;
        }

        pub fn putContext(self: *Self, allocator: Allocator, key: K, value: V, ctx: Context) MapError!void {
            const result = try self.getOrPutContext(allocator, key, ctx);
            result.value_ptr.* = value;
        }

        pub fn fetchRemoveContext(self: *Self, key: K, ctx: Context) ContextError!?KV {
            if (try self.getIndex(key, ctx)) |idx| {
                const result = KV{
                    .key = self.keys()[idx],
                    .value = self.values()[idx],
                };
                self.removeByIndex(idx);
                return result;
            }
            return null;
        }

        pub fn getOrPutContext(self: *Self, allocator: Allocator, key: K, ctx: Context) MapError!GetOrPutResult {
            self.growIfNeeded(allocator, 1, ctx) catch |err| {
                const idx = try self.getIndex(key, ctx) orelse return err;
                return GetOrPutResult{
                    .key_ptr = &self.keys()[idx],
                    .value_ptr = &self.values()[idx],
                    .found_existing = true,
                };
            };
            return self.getOrPutAssumeCapacityContext(key, ctx);
        }

        fn getOrPutAssumeCapacityContext(self: *Self, key: K, ctx: Context) ContextError!GetOrPutResult {
            const hash = try ctx.hash(key);
            const mask = self.capacity() - 1;
            const fingerprint = Metadata.takeFingerprint(hash);
            var limit = self.capacity();
            var idx = @as(usize, @truncate(hash & mask));

            var first_tombstone_idx: usize = self.capacity();
            var metadata = self.metadata.? + idx;
            while (!metadata[0].isFree() and limit != 0) {
                if (metadata[0].isUsed() and metadata[0].fingerprint == fingerprint) {
                    const test_key = &self.keys()[idx];
                    if (try ctx.eql(key, test_key.*)) {
                        return GetOrPutResult{
                            .key_ptr = test_key,
                            .value_ptr = &self.values()[idx],
                            .found_existing = true,
                        };
                    }
                } else if (first_tombstone_idx == self.capacity() and metadata[0].isTombstone()) {
                    first_tombstone_idx = idx;
                }

                limit -= 1;
                idx = (idx + 1) & mask;
                metadata = self.metadata.? + idx;
            }

            if (first_tombstone_idx < self.capacity()) {
                idx = first_tombstone_idx;
                metadata = self.metadata.? + idx;
            }

            self.available -= 1;
            metadata[0].fill(fingerprint);

            const new_key = &self.keys()[idx];
            const new_value = &self.values()[idx];
            new_key.* = key;
            new_value.* = undefined;
            self.size += 1;

            return GetOrPutResult{
                .key_ptr = new_key,
                .value_ptr = new_value,
                .found_existing = false,
            };
        }

        fn getIndex(self: Self, key: K, ctx: Context) ContextError!?usize {
            if (self.size == 0) return null;

            const hash = try ctx.hash(key);
            const mask = self.capacity() - 1;
            const fingerprint = Metadata.takeFingerprint(hash);
            var limit = self.capacity();
            var idx = @as(usize, @truncate(hash & mask));

            var metadata = self.metadata.? + idx;
            while (!metadata[0].isFree() and limit != 0) {
                if (metadata[0].isUsed() and metadata[0].fingerprint == fingerprint) {
                    if (try ctx.eql(key, self.keys()[idx])) {
                        return idx;
                    }
                }
                limit -= 1;
                idx = (idx + 1) & mask;
                metadata = self.metadata.? + idx;
            }

            return null;
        }

        fn removeByIndex(self: *Self, idx: usize) void {
            self.metadata.?[idx].remove();
            self.keys()[idx] = undefined;
            self.values()[idx] = undefined;
            self.size -= 1;
            self.available += 1;
        }

        fn initMetadatas(self: *Self) void {
            @memset(@as([*]u8, @ptrCast(self.metadata.?))[0 .. @sizeOf(Metadata) * self.capacity()], 0);
        }

        fn load(self: Self) Size {
            const max_load = (self.capacity() * max_load_percentage) / 100;
            assert(max_load >= self.available);
            return @as(Size, @truncate(max_load - self.available));
        }

        fn growIfNeeded(self: *Self, allocator: Allocator, new_count: Size, ctx: Context) MapError!void {
            if (new_count > self.available) {
                try self.grow(allocator, capacityForSize(self.load() + new_count), ctx);
            }
        }

        fn capacityForSize(size: Size) Size {
            var new_cap: u32 = @intCast((@as(u64, size) * 100) / max_load_percentage + 1);
            new_cap = math.ceilPowerOfTwo(u32, new_cap) catch unreachable;
            return new_cap;
        }

        fn header(self: Self) *Header {
            return @ptrCast(@as([*]Header, @ptrCast(@alignCast(self.metadata.?))) - 1);
        }

        fn keys(self: Self) [*]K {
            return self.header().keys;
        }

        fn values(self: Self) [*]V {
            return self.header().values;
        }

        fn capacity(self: Self) Size {
            if (self.metadata == null) return 0;
            return self.header().capacity;
        }

        fn grow(self: *Self, allocator: Allocator, new_capacity: Size, ctx: Context) MapError!void {
            const new_cap = @max(new_capacity, minimal_capacity);
            assert(new_cap > self.capacity());
            assert(std.math.isPowerOfTwo(new_cap));

            var map: Self = .{};
            try map.allocate(allocator, new_cap);
            map.initMetadatas();
            map.available = @truncate((new_cap * max_load_percentage) / 100);

            if (self.size != 0) {
                const old_capacity = self.capacity();
                for (self.metadata.?[0..old_capacity], self.keys()[0..old_capacity], self.values()[0..old_capacity]) |m, k, v| {
                    if (!m.isUsed()) continue;
                    try map.putAssumeCapacityNoClobberContext(k, v, ctx);
                    if (map.size == self.size) break;
                }
            }

            const old = self.*;
            self.* = map;
            var old_map = old;
            old_map.deallocate(allocator);
        }

        fn putAssumeCapacityNoClobberContext(self: *Self, key: K, value: V, ctx: Context) ContextError!void {
            const hash = try ctx.hash(key);
            const mask = self.capacity() - 1;
            var idx = @as(usize, @truncate(hash & mask));
            var metadata = self.metadata.? + idx;
            while (metadata[0].isUsed()) {
                idx = (idx + 1) & mask;
                metadata = self.metadata.? + idx;
            }

            self.available -= 1;
            metadata[0].fill(Metadata.takeFingerprint(hash));
            self.keys()[idx] = key;
            self.values()[idx] = value;
            self.size += 1;
        }

        fn allocate(self: *Self, allocator: Allocator, new_capacity: Size) Allocator.Error!void {
            const header_align = @alignOf(Header);
            const key_align = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const val_align = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const max_align: Alignment = comptime .fromByteUnits(@max(header_align, key_align, val_align));

            const new_cap: usize = new_capacity;
            const meta_size = @sizeOf(Header) + new_cap * @sizeOf(Metadata);

            const keys_start = std.mem.alignForward(usize, meta_size, key_align);
            const keys_end = keys_start + new_cap * @sizeOf(K);
            const vals_start = std.mem.alignForward(usize, keys_end, val_align);
            const vals_end = vals_start + new_cap * @sizeOf(V);
            const total_size = max_align.forward(vals_end);

            const slice = try allocator.alignedAlloc(u8, max_align, total_size);
            const ptr: [*]u8 = @ptrCast(slice.ptr);
            const metadata = ptr + @sizeOf(Header);
            const hdr = @as(*Header, @ptrCast(@alignCast(ptr)));
            if (@sizeOf([*]V) != 0) {
                hdr.values = @ptrCast(@alignCast(ptr + vals_start));
            }
            if (@sizeOf([*]K) != 0) {
                hdr.keys = @ptrCast(@alignCast(ptr + keys_start));
            }
            hdr.capacity = new_capacity;
            self.metadata = @ptrCast(@alignCast(metadata));
        }

        fn deallocate(self: *Self, allocator: Allocator) void {
            if (self.metadata == null) return;

            const header_align = @alignOf(Header);
            const key_align = if (@sizeOf(K) == 0) 1 else @alignOf(K);
            const val_align = if (@sizeOf(V) == 0) 1 else @alignOf(V);
            const max_align = comptime @max(header_align, key_align, val_align);

            const cap: usize = self.capacity();
            const meta_size = @sizeOf(Header) + cap * @sizeOf(Metadata);
            const keys_start = std.mem.alignForward(usize, meta_size, key_align);
            const keys_end = keys_start + cap * @sizeOf(K);
            const vals_start = std.mem.alignForward(usize, keys_end, val_align);
            const vals_end = vals_start + cap * @sizeOf(V);
            const total_size = std.mem.alignForward(usize, vals_end, max_align);

            const slice = @as([*]align(max_align) u8, @ptrCast(@alignCast(self.header())))[0..total_size];
            allocator.free(slice);
            self.metadata = null;
        }
    };
}
