const std = @import("std");
const bdwgc = @import("bdwgc");
const cora = @import("cora");

test "large atomic allocations preserve data when grown" {
    bdwgc.init();
    defer bdwgc.deinit();

    const original_len = 256 * 1024;
    var bytes = try cora.gc_allocator.atomic.alloc(u8, original_len);
    @memset(bytes, 0xa5);

    bytes = try cora.gc_allocator.atomic.realloc(bytes, original_len * 2);
    defer cora.gc_allocator.atomic.free(bytes);
    for (bytes[0..original_len]) |byte| {
        try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
}

test "large scanned allocations preserve data when grown" {
    bdwgc.init();
    defer bdwgc.deinit();

    const original_len = 256 * 1024;
    var values = try cora.gc_allocator.scanned.alloc(usize, original_len / @sizeOf(usize));
    @memset(values, std.math.maxInt(usize));

    values = try cora.gc_allocator.scanned.realloc(values, original_len * 2 / @sizeOf(usize));
    defer cora.gc_allocator.scanned.free(values);
    for (values[0 .. original_len / @sizeOf(usize)]) |value| {
        try std.testing.expectEqual(std.math.maxInt(usize), value);
    }
}
