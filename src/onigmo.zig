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
