const encoding = @import("../encoding.zig");

pub const Iso2022JpEncoding = struct {
    pub fn name(_: Iso2022JpEncoding) []const u8 {
        return "ISO-2022-JP";
    }

    pub fn nextCodepoint(_: Iso2022JpEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        var mode: enum { ascii, jis } = .ascii;
        var i: usize = 0;
        while (i < index.* and i < bytes.len) {
            if (isEsc(bytes, i, "$B")) {
                mode = .jis;
                i += 3;
                continue;
            }
            if (isEsc(bytes, i, "(B")) {
                mode = .ascii;
                i += 3;
                continue;
            }
            i += if (mode == .ascii) 1 else 2;
        }

        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        if (isEsc(bytes, index.*, "$B")) {
            index.* += 3;
            return nextCodepoint(.{}, bytes, index);
        }
        if (isEsc(bytes, index.*, "(B")) {
            index.* += 3;
            return nextCodepoint(.{}, bytes, index);
        }

        if (mode == .ascii) {
            const b = bytes[index.*];
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = b };
        }

        if (bytes.len - index.* < 2) {
            index.* = bytes.len;
            return .{ .valid = false, .len = 1, .codepoint = 0 };
        }
        const b0 = bytes[index.*];
        const b1 = bytes[index.* + 1];
        index.* += 2;
        const cp = decodeJisPair(b0, b1) orelse return .{ .valid = false, .len = 2, .codepoint = 0 };
        return .{ .valid = true, .len = 2, .codepoint = cp };
    }

    pub fn nextChar(_: Iso2022JpEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Iso2022JpEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Iso2022JpEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (Iso2022JpEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Iso2022JpEncoding) bool {
        return true;
    }

    pub fn isDummy(_: Iso2022JpEncoding) bool {
        return true;
    }

    pub fn isUnicode(_: Iso2022JpEncoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Iso2022JpEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Iso2022JpEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        if (codepoint >= 0x3041 and codepoint <= 0x3093) {
            out[0] = 0x24;
            out[1] = @intCast(0x21 + (codepoint - 0x3041));
            return 2;
        }
        return null;
    }

    pub fn toUnicodeCodepoint(_: Iso2022JpEncoding, bytes: []const u8) ?u32 {
        if (bytes.len == 1) {
            if (bytes[0] <= 0x7F) return bytes[0];
            return null;
        }
        if (bytes.len != 2) return null;
        return decodeJisPair(bytes[0], bytes[1]);
    }

    fn decodeJisPair(b0: u8, b1: u8) ?u32 {
        if (b0 == 0x24 and b1 >= 0x21 and b1 <= 0x73) {
            return 0x3041 + @as(u32, b1 - 0x21);
        }
        return null;
    }

    fn isEsc(bytes: []const u8, idx: usize, seq: []const u8) bool {
        if (idx + 3 > bytes.len) return false;
        return bytes[idx] == 0x1B and bytes[idx + 1] == seq[0] and bytes[idx + 2] == seq[1];
    }
};
