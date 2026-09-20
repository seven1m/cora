const encoding = @import("../encoding.zig");

pub const Windows1252Encoding = struct {
    const special = [_]u32{
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    };

    pub fn name(_: Windows1252Encoding) []const u8 {
        return "Windows-1252";
    }

    pub fn nextCodepoint(_: Windows1252Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const byte = bytes[index.*];
        index.* += 1;
        const codepoint = if (byte >= 0x80 and byte <= 0x9F) special[byte - 0x80] else byte;
        return .{ .valid = true, .len = 1, .codepoint = codepoint };
    }

    pub fn nextChar(_: Windows1252Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Windows1252Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Windows1252Encoding, _: []const u8) bool { return true; }
    pub fn isAsciiCompatible(_: Windows1252Encoding) bool { return true; }
    pub fn isDummy(_: Windows1252Encoding) bool { return false; }
    pub fn isUnicode(_: Windows1252Encoding) bool { return false; }
    pub fn isSingleByte(_: Windows1252Encoding) bool { return true; }

    pub fn fromUnicodeCodepoint(_: Windows1252Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F or (codepoint >= 0xA0 and codepoint <= 0xFF)) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        for (special, 0..) |candidate, index| {
            if (candidate == codepoint) {
                out[0] = @intCast(index + 0x80);
                return 1;
            }
        }
        return null;
    }

    pub fn toUnicodeCodepoint(_: Windows1252Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        const byte = bytes[0];
        return if (byte >= 0x80 and byte <= 0x9F) special[byte - 0x80] else byte;
    }
};
