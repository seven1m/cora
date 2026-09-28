const encoding = @import("../encoding.zig");
const iconv = @import("iconv.zig");

pub const GbkEncoding = struct {
    pub fn name(_: GbkEncoding) []const u8 { return "GBK"; }

    pub fn nextCodepoint(_: GbkEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const first = bytes[index.*];
        index.* += 1;
        if (first <= 0x7f) return .{ .valid = true, .len = 1, .codepoint = first };
        if (first < 0x81 or first > 0xfe or index.* >= bytes.len) return .{ .valid = false, .len = 1, .codepoint = first };
        const second = bytes[index.*];
        index.* += 1;
        return .{ .valid = (second >= 0x40 and second <= 0x7e) or (second >= 0x80 and second <= 0xfe), .len = 2, .codepoint = 0 };
    }

    pub fn nextChar(self: GbkEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const result = self.nextCodepoint(bytes, index);
        return .{ .valid = result.valid, .len = result.len };
    }

    pub fn isValid(self: GbkEncoding, bytes: []const u8) bool {
        var index: usize = 0;
        while (index < bytes.len) if (!self.nextCodepoint(bytes, &index).valid) return false;
        return true;
    }

    pub fn isAsciiCompatible(_: GbkEncoding) bool { return true; }
    pub fn isDummy(_: GbkEncoding) bool { return false; }
    pub fn isUnicode(_: GbkEncoding) bool { return false; }
    pub fn isSingleByte(_: GbkEncoding) bool { return false; }
    pub fn fromUnicodeCodepoint(_: GbkEncoding, codepoint: u32, out: *[4]u8) ?usize {
        return iconv.encodeCodepoint("GBK", codepoint, out);
    }
    pub fn toUnicodeCodepoint(_: GbkEncoding, bytes: []const u8) ?u32 {
        const decoded = iconv.decodeFirst("GBK", bytes) orelse return null;
        if (decoded.consumed != bytes.len) return null;
        return decoded.codepoint;
    }
};
