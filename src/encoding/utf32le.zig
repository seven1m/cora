const encoding = @import("../encoding.zig");

pub const Utf32LeEncoding = struct {
    pub fn name(_: Utf32LeEncoding) []const u8 {
        return "UTF-32LE";
    }

    pub fn nextCodepoint(_: Utf32LeEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        if (bytes.len - i < 4) {
            const remaining = bytes.len - i;
            index.* = bytes.len;
            return .{ .valid = false, .len = remaining, .codepoint = 0 };
        }

        const cp = readLe32(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
        index.* += 4;
        if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) {
            return .{ .valid = false, .len = 4, .codepoint = cp };
        }
        return .{ .valid = true, .len = 4, .codepoint = cp };
    }

    pub fn nextChar(_: Utf32LeEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Utf32LeEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Utf32LeEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (Utf32LeEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Utf32LeEncoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Utf32LeEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Utf32LeEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0x10FFFF) return null;
        if (codepoint >= 0xD800 and codepoint <= 0xDFFF) return null;
        out[0] = @intCast(codepoint & 0xFF);
        out[1] = @intCast((codepoint >> 8) & 0xFF);
        out[2] = @intCast((codepoint >> 16) & 0xFF);
        out[3] = @intCast((codepoint >> 24) & 0xFF);
        return 4;
    }

    pub fn toUnicodeCodepoint(_: Utf32LeEncoding, bytes: []const u8) ?u32 {
        if (bytes.len != 4) return null;
        var i: usize = 0;
        const parsed = (Utf32LeEncoding{}).nextCodepoint(bytes, &i);
        if (!parsed.valid or parsed.len != 4 or i != 4) return null;
        return parsed.codepoint;
    }

    fn readLe32(b0: u8, b1: u8, b2: u8, b3: u8) u32 {
        return (@as(u32, b3) << 24) | (@as(u32, b2) << 16) | (@as(u32, b1) << 8) | b0;
    }
};
