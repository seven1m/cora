const encoding = @import("../encoding.zig");

pub const Utf8Encoding = struct {
    pub fn name(_: Utf8Encoding) []const u8 {
        return "UTF-8";
    }

    pub fn nextCodepoint(_: Utf8Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        const first = bytes[i];

        var codepoint: u32 = 0;
        var expected_len: usize = 0;
        if ((first >> 3) == 0b11110) {
            codepoint = @as(u32, first ^ 0xF0) << 18;
            expected_len = 4;
        } else if ((first >> 4) == 0b1110) {
            codepoint = @as(u32, first ^ 0xE0) << 12;
            expected_len = 3;
        } else if ((first >> 5) == 0b110) {
            codepoint = @as(u32, first ^ 0xC0) << 6;
            expected_len = 2;
        } else if ((first >> 7) == 0b0) {
            codepoint = first;
            expected_len = 1;
        } else {
            index.* += 1;
            return .{ .valid = false, .len = 1, .codepoint = first };
        }

        if (expected_len > 1 and i + 1 < bytes.len) {
            const value = bytes[i + 1];
            if ((value >> 6) != 0b10) {
                index.* += 1;
                return .{ .valid = false, .len = 1, .codepoint = codepoint };
            }
            codepoint += @as(u32, value ^ 0x80) << @intCast((expected_len - 2) * 6);
        }

        if (expected_len > 2 and i + 2 < bytes.len) {
            const value = bytes[i + 2];
            if ((value >> 6) != 0b10) {
                index.* += 2;
                return .{ .valid = false, .len = 2, .codepoint = codepoint };
            }
            codepoint += @as(u32, value ^ 0x80) << @intCast((expected_len - 3) * 6);
        }

        if (expected_len > 3 and i + 3 < bytes.len) {
            const value = bytes[i + 3];
            if ((value >> 6) != 0b10) {
                index.* += 3;
                return .{ .valid = false, .len = 3, .codepoint = codepoint };
            }
            codepoint += value ^ 0x80;
        }

        if (i + expected_len > bytes.len) {
            const remaining = bytes.len - i;
            index.* = bytes.len;
            return .{ .valid = false, .len = remaining, .codepoint = codepoint };
        }

        var valid = true;
        var result_len = expected_len;
        switch (expected_len) {
            1 => {},
            2 => {
                if (codepoint < 0x80) {
                    valid = false;
                    result_len = 1;
                }
            },
            3 => {
                if (codepoint < 0x800 or (codepoint >= 0xD800 and codepoint <= 0xDFFF)) {
                    valid = false;
                    result_len = 1;
                }
            },
            4 => {
                if (codepoint < 0x10000 or codepoint > 0x10FFFF) {
                    valid = false;
                    result_len = 1;
                }
            },
            else => unreachable,
        }

        index.* += result_len;
        return .{ .valid = valid, .len = result_len, .codepoint = codepoint };
    }

    pub fn nextChar(_: Utf8Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const start = index.*;
        const parsed = (Utf8Encoding{}).nextCodepoint(bytes, index);
        var len = parsed.len;

        if (!parsed.valid and parsed.len > 1) {
            index.* = start + 1;
            len = 1;
        }

        return .{ .valid = parsed.valid, .len = len };
    }

    pub fn isValid(_: Utf8Encoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const result = (Utf8Encoding{}).nextCodepoint(bytes, &i);
            if (!result.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Utf8Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Utf8Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Utf8Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Utf8Encoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Utf8Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        if (codepoint <= 0x7FF) {
            out[0] = 0xC0 | @as(u8, @intCast(codepoint >> 6));
            out[1] = 0x80 | @as(u8, @intCast(codepoint & 0x3F));
            return 2;
        }
        if (codepoint >= 0xD800 and codepoint <= 0xDFFF) {
            return null; // UTF-16 surrogate range is invalid in UTF-8
        }
        if (codepoint <= 0xFFFF) {
            out[0] = 0xE0 | @as(u8, @intCast(codepoint >> 12));
            out[1] = 0x80 | @as(u8, @intCast((codepoint >> 6) & 0x3F));
            out[2] = 0x80 | @as(u8, @intCast(codepoint & 0x3F));
            return 3;
        }
        if (codepoint <= 0x10FFFF) {
            out[0] = 0xF0 | @as(u8, @intCast(codepoint >> 18));
            out[1] = 0x80 | @as(u8, @intCast((codepoint >> 12) & 0x3F));
            out[2] = 0x80 | @as(u8, @intCast((codepoint >> 6) & 0x3F));
            out[3] = 0x80 | @as(u8, @intCast(codepoint & 0x3F));
            return 4;
        }
        return null;
    }

    pub fn toUnicodeCodepoint(_: Utf8Encoding, bytes: []const u8) ?u32 {
        if (bytes.len == 0 or bytes.len > 4) return null;
        var i: usize = 0;
        const parsed = (Utf8Encoding{}).nextCodepoint(bytes, &i);
        if (!parsed.valid or parsed.len != bytes.len or i != bytes.len) return null;
        return parsed.codepoint;
    }
};
