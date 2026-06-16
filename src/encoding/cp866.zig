const encoding = @import("../encoding.zig");

pub const Cp866Encoding = struct {
    pub fn name(_: Cp866Encoding) []const u8 {
        return "IBM866";
    }

    pub fn nextCodepoint(_: Cp866Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = b };
    }

    pub fn nextChar(_: Cp866Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Cp866Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Cp866Encoding, _: []const u8) bool {
        return true;
    }

    pub fn isAsciiCompatible(_: Cp866Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Cp866Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Cp866Encoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Cp866Encoding) bool {
        return true;
    }

    pub fn fromUnicodeCodepoint(_: Cp866Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0xFF) return null;
        out[0] = @intCast(codepoint);
        return 1;
    }

    pub fn toUnicodeCodepoint(_: Cp866Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        return bytes[0];
    }
};
