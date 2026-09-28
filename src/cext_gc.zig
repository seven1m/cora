const std = @import("std");
const bdwgc = @import("bdwgc");
const value = @import("value.zig");

const MarkEntry = bdwgc.c.GC_ms_entry;

threadlocal var mark_top: [*c]MarkEntry = null;
threadlocal var mark_limit: [*c]MarkEntry = null;
var typed_data_kind: c_uint = 0;
var kind_state: std.atomic.Value(u8) = .init(0);

fn markTypedData(
    address: [*c]bdwgc.c.GC_word,
    top: [*c]MarkEntry,
    limit: [*c]MarkEntry,
    _: bdwgc.c.GC_word,
) callconv(.c) [*c]MarkEntry {
    const old_top = mark_top;
    const old_limit = mark_limit;
    mark_top = top;
    mark_limit = limit;

    const typed: *value.TypedDataObject = @ptrCast(@alignCast(address));
    if (!typed.mark_live) {
        mark_top = old_top;
        mark_limit = old_limit;
        return top;
    }
    if (typed.data) |data| {
        if (typed.callbacks.dmark) |dmark| dmark(data);
    }

    const result = bdwgc.c.GC_ms_push_all(
        @ptrCast(address),
        @ptrFromInt(@intFromPtr(address) + @sizeOf(value.TypedDataObject)),
        mark_top,
        limit,
    );
    mark_top = old_top;
    mark_limit = old_limit;
    return result;
}

pub fn markReference(raw: u64) void {
    if (mark_top == null or !(value.Value{ .raw = raw }).isObject()) return;

    const pointer: *anyopaque = @ptrFromInt(raw);
    var source: ?*anyopaque = pointer;
    mark_top = bdwgc.c.GC_mark_and_push(pointer, mark_top, mark_limit, &source);
}

pub fn allocateTypedData() ?*value.TypedDataObject {
    if (kind_state.load(.acquire) != 2) {
        if (kind_state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
            const free_list = bdwgc.c.GC_new_free_list();
            const proc = bdwgc.c.GC_new_proc(markTypedData);
            const descriptor = bdwgc.c.GC_MAKE_PROC(proc, 0);
            typed_data_kind = bdwgc.c.GC_new_kind(free_list, descriptor, 0, 1);
            kind_state.store(2, .release);
        } else {
            while (kind_state.load(.acquire) != 2) std.atomic.spinLoopHint();
        }
    }

    const allocation = bdwgc.c.GC_generic_malloc(
        @sizeOf(value.TypedDataObject),
        @intCast(typed_data_kind),
    ) orelse return null;
    return @ptrCast(@alignCast(allocation));
}
