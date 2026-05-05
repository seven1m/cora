const std = @import("std");
const c = @cImport(@cInclude("onigmo.h"));

pub const OnigRegex = c.OnigRegex;
pub const OnigEncoding = c.OnigEncoding;
pub const OnigCaseFoldType = c.OnigCaseFoldType;

// Option constants
pub const OPTION_IGNORECASE = c.ONIG_OPTION_IGNORECASE;
pub const OPTION_EXTEND = c.ONIG_OPTION_EXTEND;
pub const OPTION_MULTILINE = c.ONIG_OPTION_MULTILINE;

pub const NORMAL = c.ONIG_NORMAL;
pub const CASE_UPCASE = c.ONIGENC_CASE_UPCASE;
pub const CASE_DOWNCASE = c.ONIGENC_CASE_DOWNCASE;
pub const CASE_MODIFIED = c.ONIGENC_CASE_MODIFIED;
pub const CASE_FOLD = c.ONIGENC_CASE_FOLD;
pub const CASE_FOLD_TURKISH_AZERI = c.ONIGENC_CASE_FOLD_TURKISH_AZERI;
pub const CASE_FOLD_LITHUANIAN = c.ONIGENC_CASE_FOLD_LITHUANIAN;
pub const CASE_ASCII_ONLY = c.ONIGENC_CASE_ASCII_ONLY;

pub const ENCODING_ASCII = c.ONIG_ENCODING_ASCII;
pub const ENCODING_UTF_8 = c.ONIG_ENCODING_UTF_8;
pub const ENCODING_UTF_16LE = c.ONIG_ENCODING_UTF_16LE;
pub const ENCODING_UTF_16BE = c.ONIG_ENCODING_UTF_16BE;
pub const ENCODING_UTF_32LE = c.ONIG_ENCODING_UTF_32LE;
pub const ENCODING_UTF_32BE = c.ONIG_ENCODING_UTF_32BE;
pub const ENCODING_SHIFT_JIS = c.ONIG_ENCODING_SHIFT_JIS;
pub const ENCODING_WINDOWS_31J = c.ONIG_ENCODING_WINDOWS_31J;
pub const ENCODING_EUC_JP = c.ONIG_ENCODING_EUC_JP;
pub const ENCODING_ISO_8859_1 = c.ONIG_ENCODING_ISO_8859_1;
pub const ENCODING_ISO_8859_9 = c.ONIG_ENCODING_ISO_8859_9;
pub const ENCODING_ISO_8859_15 = c.ONIG_ENCODING_ISO_8859_15;

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

pub const CaseMapError = error{
    OutOfMemory,
    InvalidByteSequence,
    UnsupportedEncoding,
};

pub const CaseMapResult = struct {
    bytes: []u8,
    flags: OnigCaseFoldType,
};

pub fn compileWithEncoding(
    pattern: [*]const u8,
    pattern_end: [*]const u8,
    options: c.OnigOptionType,
    encoding: OnigEncoding,
) struct { regex: ?OnigRegex, err: ?CompileError } {
    var regex: OnigRegex = undefined;
    var einfo: c.OnigErrorInfo = undefined;

    const r = c.onig_new(
        &regex,
        pattern,
        pattern_end,
        options,
        encoding,
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

pub fn compile(pattern: [*]const u8, pattern_end: [*]const u8, options: c.OnigOptionType) struct { regex: ?OnigRegex, err: ?CompileError } {
    return compileWithEncoding(pattern, pattern_end, options, c.ONIG_ENCODING_UTF_8);
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
    return searchWithCapturesAt(allocator, regex, text, 0);
}

pub fn searchWithCapturesAt(allocator: std.mem.Allocator, regex: OnigRegex, text: []const u8, start_offset: usize) !SearchCaptures {
    const region = c.onig_region_new() orelse return error.OutOfMemory;
    defer c.onig_region_free(region, 1);

    const start_ptr: [*c]const c.OnigUChar = @ptrCast(text.ptr);
    const end_ptr = start_ptr + text.len;
    const search_ptr = start_ptr + start_offset;
    const result = c.onig_search(regex, start_ptr, end_ptr, search_ptr, end_ptr, region, 0);
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
    if (result < 0) return error.InvalidByteSequence;

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

pub fn nameToBackrefNumber(regex: OnigRegex, text: []const u8, name: []const u8) i32 {
    const region = c.onig_region_new() orelse return -1;
    defer c.onig_region_free(region, 1);

    const start_ptr: [*c]const c.OnigUChar = @ptrCast(text.ptr);
    const end_ptr = start_ptr + text.len;
    const result = c.onig_search(regex, start_ptr, end_ptr, start_ptr, end_ptr, region, 0);
    if (result == c.ONIG_MISMATCH) return -1;

    const name_ptr: [*c]const c.OnigUChar = @ptrCast(name.ptr);
    const name_end = name_ptr + name.len;
    return c.onig_name_to_backref_number(regex, name_ptr, name_end, region);
}

pub fn caseMap(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    encoding: OnigEncoding,
    initial_flags: OnigCaseFoldType,
) CaseMapError!CaseMapResult {
    const case_map_fn = encoding.*.case_map orelse return error.UnsupportedEncoding;
    var flags = initial_flags;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const start: [*c]const c.OnigUChar = @ptrCast(bytes.ptr);
    const end = start + bytes.len;
    var current = start;
    while (@intFromPtr(current) < @intFromPtr(end)) {
        var chunk_capacity: usize = (@intFromPtr(end) - @intFromPtr(current)) * 2 + 32;
        while (true) {
            var chunk = allocator.alloc(u8, chunk_capacity) catch return error.OutOfMemory;
            defer allocator.free(chunk);

            var next = current;
            const chunk_start: [*c]c.OnigUChar = @ptrCast(chunk.ptr);
            const chunk_end = chunk_start + chunk.len;
            const written = case_map_fn(&flags, &next, end, chunk_start, chunk_end, encoding);
            if (written < 0) return error.InvalidByteSequence;
            if (@intFromPtr(next) == @intFromPtr(current)) {
                chunk_capacity *= 2;
                continue;
            }

            out.appendSlice(allocator, chunk[0..@intCast(written)]) catch return error.OutOfMemory;
            current = next;
            break;
        }
    }

    return .{
        .bytes = out.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .flags = flags,
    };
}
