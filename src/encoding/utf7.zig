const encoding = @import("../encoding.zig");

pub const Utf7Encoding = struct {
    pub fn name(_: Utf7Encoding) []const u8 {
        return "UTF-7";
    }

    pub fn nextCodepoint(_: Utf7Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = b };
    }

    pub fn nextChar(_: Utf7Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Utf7Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Utf7Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Utf7Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Utf7Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Utf7Encoding, _: u32, _: *[4]u8) ?usize {
        return null;
    }

    pub fn toUnicodeCodepoint(_: Utf7Encoding, _: []const u8) ?u32 {
        return null;
    }
};
