const encoding = @import("../encoding.zig");

pub const Iso88599Encoding = struct {
    pub fn name(_: Iso88599Encoding) []const u8 {
        return "ISO-8859-9";
    }

    pub fn nextCodepoint(_: Iso88599Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = decodeByte(b) };
    }

    pub fn nextChar(_: Iso88599Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Iso88599Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Iso88599Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Iso88599Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Iso88599Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Iso88599Encoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Iso88599Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Iso88599Encoding, codepoint: u32, out: *[4]u8) ?usize {
        const b = encodeCodepoint(codepoint) orelse return null;
        out[0] = b;
        return 1;
    }

    pub fn toUnicodeCodepoint(_: Iso88599Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return decodeByte(bytes[0]);
    }

    fn decodeByte(b: u8) u32 {
        return switch (b) {
            0xD0 => 0x011E,
            0xDD => 0x0130,
            0xDE => 0x015E,
            0xF0 => 0x011F,
            0xFD => 0x0131,
            0xFE => 0x015F,
            else => b,
        };
    }

    fn encodeCodepoint(codepoint: u32) ?u8 {
        return switch (codepoint) {
            0x011E => 0xD0,
            0x0130 => 0xDD,
            0x015E => 0xDE,
            0x011F => 0xF0,
            0x0131 => 0xFD,
            0x015F => 0xFE,
            else => if (codepoint <= 0xFF) @intCast(codepoint) else null,
        };
    }
};
