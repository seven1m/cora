const encoding = @import("../encoding.zig");

pub const Cesu8Encoding = struct {
    pub fn name(_: Cesu8Encoding) []const u8 {
        return "CESU-8";
    }

    pub fn nextCodepoint(_: Cesu8Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        return (encoding.Encoding{ .utf8 = .{} }).nextCodepoint(bytes, index);
    }

    pub fn nextChar(_: Cesu8Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        return (encoding.Encoding{ .utf8 = .{} }).nextChar(bytes, index);
    }

    pub fn isValid(_: Cesu8Encoding, bytes: []const u8) bool {
        return (encoding.Encoding{ .utf8 = .{} }).isValid(bytes);
    }

    pub fn isAsciiCompatible(_: Cesu8Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Cesu8Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Cesu8Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Cesu8Encoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Cesu8Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0xFFFF) return null;
        return (encoding.Encoding{ .utf8 = .{} }).fromUnicodeCodepoint(codepoint, out);
    }

    pub fn toUnicodeCodepoint(_: Cesu8Encoding, bytes: []const u8) ?u32 {
        return (encoding.Encoding{ .utf8 = .{} }).toUnicodeCodepoint(bytes);
    }
};
