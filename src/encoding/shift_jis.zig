const encoding = @import("../encoding.zig");
const jis = @import("jis.zig");

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

        if (jis.encode0208(codepoint)) |pair| {
            const row: u8 = @truncate(pair >> 8);
            const col: u8 = @truncate(pair);
            const lead = @as(u8, 0x81) + (row - 0x21) / 2;
            out[0] = if (lead > 0x9F) lead + 0x40 else lead;
            out[1] = if (row & 1 == 0) col + 0x7E else col + (if (col < 0x60) @as(u8, 0x1F) else 0x20);
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
        if (!isLeadByte(b0) or !isTrailByte(b1)) return null;
        const lead = b0 - (if (b0 <= 0x9F) @as(u8, 0x81) else 0xC1);
        const row = 0x21 + lead * 2 + @as(u8, if (b1 >= 0x9F) 1 else 0);
        const col = if (b1 >= 0x9F) b1 - 0x7E else b1 - (if (b1 < 0x7F) @as(u8, 0x1F) else 0x20);
        return jis.decode0208(row, col);
    }
};
