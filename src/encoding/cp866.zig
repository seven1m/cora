const encoding = @import("../encoding.zig");

const high_codepoints = [_]u16{
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
    0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
    0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
    0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
    0x0401, 0x0451, 0x0404, 0x0454, 0x0407, 0x0457, 0x040E, 0x045E,
    0x00B0, 0x2219, 0x00B7, 0x221A, 0x2116, 0x00A4, 0x25A0, 0x00A0,
};

pub const Cp866Encoding = struct {
    pub fn name(_: Cp866Encoding) []const u8 {
        return "IBM866";
    }

    pub fn nextCodepoint(_: Cp866Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const b = bytes[index.*];
        index.* += 1;
        return .{ .valid = true, .len = 1, .codepoint = if (b < 0x80) b else high_codepoints[b - 0x80] };
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
        if (codepoint < 0x80) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        for (high_codepoints, 0..) |mapped, index| {
            if (mapped == codepoint) {
                out[0] = @intCast(index + 0x80);
                return 1;
            }
        }
        return null;
    }

    pub fn toUnicodeCodepoint(_: Cp866Encoding, bytes: []const u8) ?u32 {
        if (bytes.len != 1) return null;
        const b = bytes[0];
        return if (b < 0x80) b else high_codepoints[b - 0x80];
    }
};
