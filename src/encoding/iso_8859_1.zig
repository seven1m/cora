const encoding = @import("../encoding.zig");

pub const Iso88591Encoding = struct {
    pub fn name(_: Iso88591Encoding) []const u8 {
        return "ISO-8859-1";
    }

    pub fn nextCodepoint(_: Iso88591Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = b };
    }

    pub fn nextChar(_: Iso88591Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Iso88591Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Iso88591Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Iso88591Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Iso88591Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Iso88591Encoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Iso88591Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Iso88591Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0xFF) return null;
        out[0] = @intCast(codepoint);
        return 1;
    }

    pub fn toUnicodeCodepoint(_: Iso88591Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return bytes[0];
    }
};
