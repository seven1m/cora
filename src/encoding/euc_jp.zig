const encoding = @import("../encoding.zig");
const jis = @import("jis.zig");

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
                const cp = jis.decode0212(b1 - 0x80, b2 - 0x80) orelse (@as(u32, b0) << 16) | (@as(u32, b1) << 8) | b2;
                return .{ .valid = true, .len = 3, .codepoint = cp };
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

        if (codepoint >= 0xFF61 and codepoint <= 0xFF9F) {
            out[0] = 0x8E;
            out[1] = @intCast(0xA1 + codepoint - 0xFF61);
            return 2;
        }

        if (jis.encode0208(codepoint)) |pair| {
            out[0] = @as(u8, @truncate(pair >> 8)) + 0x80;
            out[1] = @as(u8, @truncate(pair)) + 0x80;
            return 2;
        }
        if (jis.encode0212(codepoint)) |pair| {
            out[0] = 0x8F;
            out[1] = @as(u8, @truncate(pair >> 8)) + 0x80;
            out[2] = @as(u8, @truncate(pair)) + 0x80;
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
        if (bytes.len == 2) {
            if (bytes[0] == 0x8E and bytes[1] >= 0xA1 and bytes[1] <= 0xDF) return 0xFF61 + @as(u32, bytes[1] - 0xA1);
            return decodePair(bytes[0], bytes[1]);
        }
        if (bytes.len == 3 and bytes[0] == 0x8F and bytes[1] >= 0xA1 and bytes[2] >= 0xA1) {
            return jis.decode0212(bytes[1] - 0x80, bytes[2] - 0x80);
        }
        return null;
    }

    fn decodePair(b0: u8, b1: u8) ?u32 {
        if (b0 < 0xA1 or b1 < 0xA1) return null;
        return jis.decode0208(b0 - 0x80, b1 - 0x80);
    }
};
