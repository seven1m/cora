const encoding = @import("../encoding.zig");

pub const ShiftJisEncoding = struct {
    pub fn name(_: ShiftJisEncoding) []const u8 {
        return "Shift_JIS";
    }

    pub fn nextCodepoint(_: ShiftJisEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        const b0 = bytes[i];

        // ASCII
        if (b0 <= 0x7F) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = b0 };
        }

        // Half-width katakana block
        if (b0 >= 0xA1 and b0 <= 0xDF) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = 0xFF61 + @as(u32, b0 - 0xA1) };
        }

        // Double-byte lead byte
        if (!isLeadByte(b0)) {
            index.* += 1;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }
        if (bytes.len - i < 2) {
            index.* = bytes.len;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }

        const b1 = bytes[i + 1];
        if (!isTrailByte(b1)) {
            index.* += 1;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }

        index.* += 2;
        const cp = decodePair(b0, b1) orelse (@as(u32, b0) << 8) | b1;
        return .{ .valid = true, .len = 2, .codepoint = cp };
    }

    pub fn nextChar(_: ShiftJisEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (ShiftJisEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: ShiftJisEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (ShiftJisEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: ShiftJisEncoding) bool {
        return true;
    }

    pub fn isDummy(_: ShiftJisEncoding) bool {
        return false;
    }

    pub fn isUnicode(_: ShiftJisEncoding) bool {
        return false;
    }

    pub fn isSingleByte(_: ShiftJisEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: ShiftJisEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }

        // Half-width katakana
        if (codepoint >= 0xFF61 and codepoint <= 0xFF9F) {
            out[0] = @intCast(0xA1 + (codepoint - 0xFF61));
            return 1;
        }

        // Hiragana block in Shift_JIS: 0x82 0x9F..0xF1 maps to U+3041..U+3093
        if (codepoint >= 0x3041 and codepoint <= 0x3093) {
            const offset = codepoint - 0x3041;
            out[0] = 0x82;
            out[1] = @intCast(0x9F + offset);
            return 2;
        }

        // Katakana letter A
        if (codepoint == 0x30A2) {
            out[0] = 0x83;
            out[1] = 0x41;
            return 2;
        }

        // Dagger
        if (codepoint == 0x2020) {
            out[0] = 0x81;
            out[1] = 0xE0;
            return 2;
        }

        return null;
    }

    pub fn toUnicodeCodepoint(_: ShiftJisEncoding, bytes: []const u8) ?u32 {
        if (bytes.len == 1) {
            const b0 = bytes[0];
            if (b0 <= 0x7F) return b0;
            if (b0 >= 0xA1 and b0 <= 0xDF) return 0xFF61 + @as(u32, b0 - 0xA1);
            return null;
        }
        if (bytes.len != 2) return null;
        return decodePair(bytes[0], bytes[1]);
    }

    fn isLeadByte(b: u8) bool {
        return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC);
    }

    fn isTrailByte(b: u8) bool {
        return (b >= 0x40 and b <= 0x7E) or (b >= 0x80 and b <= 0xFC);
    }

    fn decodePair(b0: u8, b1: u8) ?u32 {
        // Hiragana block in Shift_JIS: 0x82 0x9F..0xF1 maps to U+3041..U+3093
        if (b0 == 0x82 and b1 >= 0x9F and b1 <= 0xF1) {
            return 0x3041 + @as(u32, b1 - 0x9F);
        }
        if (b0 == 0x83 and b1 == 0x41) {
            return 0x30A2;
        }
        if (b0 == 0x81 and b1 == 0xE0) {
            return 0x2020;
        }
        return null;
    }
};
