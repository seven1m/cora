const encoding = @import("../encoding.zig");

pub const Ascii8BitEncoding = struct {
    pub fn name(_: Ascii8BitEncoding) []const u8 {
        return "ASCII-8BIT";
    }

    pub fn nextChar(_: Ascii8BitEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0 };
        index.* += 1;
        return .{ .valid = true, .len = 1 }; // Every byte is valid
    }

    pub fn isValid(_: Ascii8BitEncoding, _: []const u8) bool {
        return true; // All byte sequences are valid in binary
    }

    pub fn isAsciiCompatible(_: Ascii8BitEncoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Ascii8BitEncoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Ascii8BitEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0xFF) return null;
        out[0] = @intCast(codepoint);
        return 1;
    }

    pub fn toUnicodeCodepoint(_: Ascii8BitEncoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return bytes[0];
    }
};
