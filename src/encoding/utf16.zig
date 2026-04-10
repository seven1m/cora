const encoding = @import("../encoding.zig");

pub const Utf16Encoding = struct {
    pub fn name(_: Utf16Encoding) []const u8 {
        return "UTF-16";
    }

    pub fn nextCodepoint(_: Utf16Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = b };
    }

    pub fn nextChar(_: Utf16Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Utf16Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Utf16Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Utf16Encoding) bool {
        return false;
    }

    pub fn isDummy(_: Utf16Encoding) bool {
        return true;
    }

    pub fn isUnicode(_: Utf16Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Utf16Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Utf16Encoding, _: u32, _: *[4]u8) ?usize {
        return null;
    }

    pub fn toUnicodeCodepoint(_: Utf16Encoding, _: []const u8) ?u32 {
        return null;
    }
};
