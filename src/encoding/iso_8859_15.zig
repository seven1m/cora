const encoding = @import("../encoding.zig");

pub const Iso885915Encoding = struct {
    pub fn name(_: Iso885915Encoding) []const u8 {
        return "ISO-8859-15";
    }

    pub fn nextCodepoint(_: Iso885915Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = decodeByte(b) };
    }

    pub fn nextChar(_: Iso885915Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Iso885915Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Iso885915Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Iso885915Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Iso885915Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Iso885915Encoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Iso885915Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Iso885915Encoding, codepoint: u32, out: *[4]u8) ?usize {
        const b = encodeCodepoint(codepoint) orelse return null;
        out[0] = b;
        return 1;
    }

    pub fn toUnicodeCodepoint(_: Iso885915Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return decodeByte(bytes[0]);
    }

    fn decodeByte(b: u8) u32 {
        return switch (b) {
            0xA4 => 0x20AC,
            0xA6 => 0x0160,
            0xA8 => 0x0161,
            0xB4 => 0x017D,
            0xB8 => 0x017E,
            0xBC => 0x0152,
            0xBD => 0x0153,
            0xBE => 0x0178,
            else => b,
        };
    }

    fn encodeCodepoint(codepoint: u32) ?u8 {
        return switch (codepoint) {
            0x20AC => 0xA4,
            0x0160 => 0xA6,
            0x0161 => 0xA8,
            0x017D => 0xB4,
            0x017E => 0xB8,
            0x0152 => 0xBC,
            0x0153 => 0xBD,
            0x0178 => 0xBE,
            else => if (codepoint <= 0xFF) @intCast(codepoint) else null,
        };
    }
};
