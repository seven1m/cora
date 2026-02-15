const std = @import("std");
const c = @cImport(@cInclude("onigmo.h"));

pub const OnigRegex = c.OnigRegex;

// Option constants
pub const OPTION_IGNORECASE = c.ONIG_OPTION_IGNORECASE;
pub const OPTION_EXTEND = c.ONIG_OPTION_EXTEND;
pub const OPTION_MULTILINE = c.ONIG_OPTION_MULTILINE;

pub const NORMAL = c.ONIG_NORMAL;

pub const CompileError = struct {
    message: [c.ONIG_MAX_ERROR_MESSAGE_LEN]u8 = undefined,
    len: usize = 0,
};

pub const SearchCaptures = struct {
    matched: bool,
    match_index: i64,
    begin_offsets: []i64,
    end_offsets: []i64,
};

pub fn compile(pattern: [*]const u8, pattern_end: [*]const u8, options: c.OnigOptionType) struct { regex: ?OnigRegex, err: ?CompileError } {
    var regex: OnigRegex = undefined;
    var einfo: c.OnigErrorInfo = undefined;

    const r = c.onig_new(
        &regex,
        pattern,
        pattern_end,
        options,
        c.ONIG_ENCODING_UTF_8,
        c.ONIG_SYNTAX_RUBY,
        &einfo,
    );

    if (r != NORMAL) {
        var err = CompileError{};
        const len: usize = @intCast(c.onig_error_code_to_str(&err.message, r, &einfo));
        err.len = len;
        return .{ .regex = null, .err = err };
    }

    return .{ .regex = regex, .err = null };
}

pub fn free(regex: OnigRegex) void {
    c.onig_free(regex);
}

pub fn search(regex: OnigRegex, text: []const u8) bool {
    const region = c.onig_region_new() orelse return false;
    defer c.onig_region_free(region, 1);

    const start_ptr: [*c]const c.OnigUChar = @ptrCast(text.ptr);
    const end_ptr = start_ptr + text.len;
    const result = c.onig_search(regex, start_ptr, end_ptr, start_ptr, end_ptr, region, 0);
    return result != c.ONIG_MISMATCH;
}

pub fn searchWithCaptures(allocator: std.mem.Allocator, regex: OnigRegex, text: []const u8) !SearchCaptures {
    const region = c.onig_region_new() orelse return error.OutOfMemory;
    defer c.onig_region_free(region, 1);

    const start_ptr: [*c]const c.OnigUChar = @ptrCast(text.ptr);
    const end_ptr = start_ptr + text.len;
    const result = c.onig_search(regex, start_ptr, end_ptr, start_ptr, end_ptr, region, 0);
    if (result == c.ONIG_MISMATCH) {
        const empty_beg = try allocator.alloc(i64, 0);
        const empty_end = try allocator.alloc(i64, 0);
        return .{
            .matched = false,
            .match_index = -1,
            .begin_offsets = empty_beg,
            .end_offsets = empty_end,
        };
    }

    const regs: usize = @intCast(region.*.num_regs);
    const begins = try allocator.alloc(i64, regs);
    errdefer allocator.free(begins);
    const ends = try allocator.alloc(i64, regs);
    errdefer allocator.free(ends);

    var i: usize = 0;
    while (i < regs) : (i += 1) {
        begins[i] = region.*.beg[i];
        ends[i] = region.*.end[i];
    }

    return .{
        .matched = true,
        .match_index = result,
        .begin_offsets = begins,
        .end_offsets = ends,
    };
}
