const encoding = @import("../encoding.zig");

pub const Cp437Encoding = struct {
    pub fn name(_: Cp437Encoding) []const u8 {
        return "IBM437";
    }

    pub fn nextCodepoint(_: Cp437Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = decodeByte(b) };
    }

    pub fn nextChar(_: Cp437Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Cp437Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Cp437Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Cp437Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Cp437Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Cp437Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        if (codepoint == 0x03C0) {
            out[0] = 0xE3;
            return 1;
        }
        if (codepoint == 0x00FC) {
            out[0] = 0x81;
            return 1;
        }
        if (codepoint == 0x00E9) {
            out[0] = 0x82;
            return 1;
        }
        return null;
    }

    pub fn toUnicodeCodepoint(_: Cp437Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return decodeByte(bytes[0]);
    }

    fn decodeByte(b: u8) u32 {
        return switch (b) {
            0xE3 => 0x03C0, // π
            0x81 => 0x00FC, // ü
            0x82 => 0x00E9, // é
            else => b,
        };
    }
};
