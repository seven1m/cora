const encoding = @import("../encoding.zig");

pub const Utf32Encoding = struct {
    pub fn name(_: Utf32Encoding) []const u8 {
        return "UTF-32";
    }

    pub fn nextCodepoint(_: Utf32Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = b };
    }

    pub fn nextChar(_: Utf32Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Utf32Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Utf32Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Utf32Encoding) bool {
        return false;
    }

    pub fn isDummy(_: Utf32Encoding) bool {
        return true;
    }

    pub fn isUnicode(_: Utf32Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Utf32Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Utf32Encoding, _: u32, _: *[4]u8) ?usize {
        return null;
    }

    pub fn toUnicodeCodepoint(_: Utf32Encoding, _: []const u8) ?u32 {
        return null;
    }
};
