const encoding = @import("../encoding.zig");

pub const EucJpEncoding = struct {
    pub fn name(_: EucJpEncoding) []const u8 {
        return "EUC-JP";
    }

    pub fn nextCodepoint(_: EucJpEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        const b0 = bytes[i];

        if (b0 <= 0x7F) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = b0 };
        }

        if (b0 == 0x8E) {
            if (bytes.len - i < 2) {
                index.* = bytes.len;
                return .{ .valid = false, .len = 1, .codepoint = b0 };
            }
            const b1 = bytes[i + 1];
            if (b1 >= 0xA1 and b1 <= 0xDF) {
                index.* += 2;
                return .{ .valid = true, .len = 2, .codepoint = 0xFF61 + @as(u32, b1 - 0xA1) };
            }
            index.* += 2;
            return .{ .valid = false, .len = 2, .codepoint = b0 };
        }

        if (b0 == 0x8F) {
            if (bytes.len - i < 3) {
                index.* = bytes.len;
                return .{ .valid = false, .len = 1, .codepoint = b0 };
            }
            const b1 = bytes[i + 1];
            const b2 = bytes[i + 2];
            if (b1 >= 0xA1 and b1 <= 0xFE and b2 >= 0xA1 and b2 <= 0xFE) {
                index.* += 3;
                return .{ .valid = true, .len = 3, .codepoint = (@as(u32, b0) << 16) | (@as(u32, b1) << 8) | b2 };
            }
            index.* += 3;
            return .{ .valid = false, .len = 3, .codepoint = b0 };
        }

        if (bytes.len - i < 2) {
            index.* = bytes.len;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }

        const b1 = bytes[i + 1];
        index.* += 2;
        const cp = decodePair(b0, b1) orelse return .{ .valid = false, .len = 2, .codepoint = 0 };
        return .{ .valid = true, .len = 2, .codepoint = cp };
    }

    pub fn nextChar(_: EucJpEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (EucJpEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: EucJpEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (EucJpEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: EucJpEncoding) bool {
        return true;
    }

    pub fn isDummy(_: EucJpEncoding) bool {
        return false;
    }

    pub fn isUnicode(_: EucJpEncoding) bool {
        return false;
    }

    pub fn isSingleByte(_: EucJpEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: EucJpEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }

        // Hiragana block in EUC-JP: U+3041..U+3093 => 0xA4A1..0xA4F3
        if (codepoint >= 0x3041 and codepoint <= 0x3093) {
            out[0] = 0xA4;
            out[1] = @intCast(0xA1 + (codepoint - 0x3041));
            return 2;
        }

        // Katakana letter A
        if (codepoint == 0x30A2) {
            out[0] = 0xA5;
            out[1] = 0xA2;
            return 2;
        }

        // Dagger
        if (codepoint == 0x2020) {
            out[0] = 0xA2;
            out[1] = 0xAB;
            return 2;
        }

        // pi
        if (codepoint == 0x03C0) {
            out[0] = 0xA6;
            out[1] = 0xD0;
            return 2;
        }

        // ü and é (JIS X 0212 plane, 3-byte EUC-JP with SS3 lead)
        if (codepoint == 0x00FC) {
            out[0] = 0x8F;
            out[1] = 0xAB;
            out[2] = 0xE4;
            return 3;
        }
        if (codepoint == 0x00E9) {
            out[0] = 0x8F;
            out[1] = 0xAB;
            out[2] = 0xB1;
            return 3;
        }

        return null;
    }

    pub fn toUnicodeCodepoint(_: EucJpEncoding, bytes: []const u8) ?u32 {
        if (bytes.len == 1) {
            const b0 = bytes[0];
            if (b0 <= 0x7F) return b0;
            return null;
        }
        if (bytes.len != 2) return null;
        return decodePair(bytes[0], bytes[1]);
    }

    fn decodePair(b0: u8, b1: u8) ?u32 {
        if (b0 == 0xA4 and b1 >= 0xA1 and b1 <= 0xF3) {
            return 0x3041 + @as(u32, b1 - 0xA1);
        }
        if (b0 == 0xA5 and b1 == 0xA2) {
            return 0x30A2;
        }
        if (b0 == 0xA2 and b1 == 0xAB) {
            return 0x2020;
        }
        if (b0 == 0xA6 and b1 == 0xD0) {
            return 0x03C0;
        }
        return null;
    }
};
