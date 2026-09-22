const std = @import("std");
const bdwgc = @import("bdwgc");

// Ignore off-page interior pointers for large allocations. Cora retains the
// base pointer for every live heap object and byte buffer, satisfying BDWGC's
// requirement for these allocation functions.
const large_allocation_threshold = 256 * 1024;
const Options = struct {
    atomic: bool,
};

pub const atomic: std.mem.Allocator = .{
    .ptr = @constCast(&Options{ .atomic = true }),
    .vtable = &vtable,
};

pub const scanned: std.mem.Allocator = .{
    .ptr = @constCast(&Options{ .atomic = false }),
    .vtable = &vtable,
};

const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn allocationStrategy(alignment: std.mem.Alignment) enum { direct, manual_alignment } {
    return if (std.mem.Alignment.compare(alignment, .lte, .of(std.c.max_align_t)))
        .direct
    else
        .manual_alignment;
}

fn manualAlignmentHeader(aligned_ptr: [*]u8) *[*]u8 {
    return @ptrCast(@alignCast(aligned_ptr - @sizeOf(usize)));
}

fn allocateRaw(options: *const Options, len: usize) ?[*]u8 {
    const ptr = if (options.atomic)
        if (len >= large_allocation_threshold)
            bdwgc.c.GC_malloc_atomic_ignore_off_page(len)
        else
            bdwgc.c.GC_malloc_atomic(len)
    else if (len >= large_allocation_threshold)
        bdwgc.c.GC_malloc_ignore_off_page(len)
    else
        bdwgc.c.GC_malloc(len);
    return @ptrCast(ptr);
}

fn alloc(
    context: *anyopaque,
    len: usize,
    alignment: std.mem.Alignment,
    _: usize,
) ?[*]u8 {
    std.debug.assert(len > 0);
    const options: *const Options = @ptrCast(@alignCast(context));
    switch (allocationStrategy(alignment)) {
        .direct => {
            const actual_len = @max(len, @alignOf(std.c.max_align_t));
            const ptr = allocateRaw(options, actual_len) orelse return null;
            std.debug.assert(alignment.check(@intFromPtr(ptr)));
            return ptr;
        },
        .manual_alignment => {
            const padded_len = len + @sizeOf(usize) + alignment.toByteUnits() - 1;
            const unaligned_ptr = allocateRaw(options, padded_len) orelse return null;
            const unaligned_addr = @intFromPtr(unaligned_ptr);
            const aligned_addr = alignment.forward(unaligned_addr + @sizeOf(usize));
            const aligned_ptr = unaligned_ptr + (aligned_addr - unaligned_addr);
            manualAlignmentHeader(aligned_ptr).* = unaligned_ptr;
            return aligned_ptr;
        },
    }
}

fn resize(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    _: usize,
) bool {
    std.debug.assert(new_len > 0);
    if (new_len <= memory.len) return true;

    const usable_len: usize = switch (allocationStrategy(alignment)) {
        .direct => bdwgc.c.GC_size(memory.ptr),
        .manual_alignment => usable: {
            const unaligned_ptr = manualAlignmentHeader(memory.ptr).*;
            const full_len = bdwgc.c.GC_size(unaligned_ptr);
            const padding = @intFromPtr(memory.ptr) - @intFromPtr(unaligned_ptr);
            break :usable full_len - padding;
        },
    };
    return new_len <= usable_len;
}

fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    std.debug.assert(new_len > 0);
    if (resize(context, memory, alignment, new_len, return_address)) return memory.ptr;

    if (allocationStrategy(alignment) == .direct and
        memory.len < large_allocation_threshold and
        new_len < large_allocation_threshold)
    {
        const actual_len = @max(new_len, @alignOf(std.c.max_align_t));
        const ptr = bdwgc.c.GC_realloc(memory.ptr, actual_len) orelse return null;
        std.debug.assert(alignment.check(@intFromPtr(ptr)));
        return @ptrCast(ptr);
    }

    // GC_realloc does not preserve ignore-off-page allocation behavior.
    const new_ptr = alloc(context, new_len, alignment, return_address) orelse return null;
    @memcpy(new_ptr[0..memory.len], memory);
    free(context, memory, alignment, return_address);
    return new_ptr;
}

fn free(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    _: usize,
) void {
    switch (allocationStrategy(alignment)) {
        .direct => bdwgc.c.GC_free(memory.ptr),
        .manual_alignment => bdwgc.c.GC_free(manualAlignmentHeader(memory.ptr).*),
    }
}
