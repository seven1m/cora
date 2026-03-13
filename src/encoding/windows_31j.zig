const encoding = @import("../encoding.zig");

pub const Windows31JEncoding = struct {
    pub fn name(_: Windows31JEncoding) []const u8 {
        return "Windows-31J";
    }

    pub fn nextCodepoint(_: Windows31JEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        const b0 = bytes[i];

        if (b0 <= 0x7F) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = b0 };
        }

        if (b0 >= 0xA1 and b0 <= 0xDF) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = 0xFF61 + @as(u32, b0 - 0xA1) };
        }

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

    pub fn nextChar(_: Windows31JEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Windows31JEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Windows31JEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (Windows31JEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Windows31JEncoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Windows31JEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Windows31JEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }

        if (codepoint >= 0xFF61 and codepoint <= 0xFF9F) {
            out[0] = @intCast(0xA1 + (codepoint - 0xFF61));
            return 1;
        }

        if (codepoint >= 0x3041 and codepoint <= 0x3093) {
            const offset = codepoint - 0x3041;
            out[0] = 0x82;
            out[1] = @intCast(0x9F + offset);
            return 2;
        }

        if (codepoint == 0x30A2) {
            out[0] = 0x83;
            out[1] = 0x41;
            return 2;
        }

        if (codepoint == 0x2020) {
            out[0] = 0x81;
            out[1] = 0xE0;
            return 2;
        }

        if (codepoint == 0x2169) {
            out[0] = 0x87;
            out[1] = 0x5D;
            return 2;
        }

        return null;
    }

    pub fn toUnicodeCodepoint(_: Windows31JEncoding, bytes: []const u8) ?u32 {
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
        if (b0 == 0x82 and b1 >= 0x9F and b1 <= 0xF1) {
            return 0x3041 + @as(u32, b1 - 0x9F);
        }
        if (b0 == 0x83 and b1 == 0x41) {
            return 0x30A2;
        }
        if (b0 == 0x81 and b1 == 0xE0) {
            return 0x2020;
        }
        if (b0 == 0x87 and b1 == 0x5D) {
            return 0x2169;
        }
        return null;
    }
};
