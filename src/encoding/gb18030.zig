const encoding = @import("../encoding.zig");

/// GB18030 (GB18030-2005) is a real variable-length encoding, not an alias:
/// 1-byte ASCII, 2-byte sequences compatible with GBK, and 4-byte sequences
/// covering the rest of Unicode.
///
/// The 2-byte table (~24k entries) is not implemented here: 2-byte sequences
/// are validated structurally and report `valid`, but `toUnicodeCodepoint`
/// returns null for them so transcoding raises `UndefinedConversion` (or
/// substitutes when `undef: :replace` is given), instead of silently
/// producing wrong characters.
///
/// The 4-byte mapping is algorithmic and implemented exactly. Verified
/// exhaustively against CPython's GB18030-2005 tables:
/// - pointer = (b1-0x81)*12600 + (b2-0x30)*1260 + (b3-0x81)*10 + (b4-0x30)
/// - pointer <= 0x23: codepoint = pointer + 0x80 (U+0080..U+00A3)
/// - pointer 0x99E2..0x99FB: codepoint = pointer + 0x6604 (U+FFE6..U+FFFF)
/// - pointer >= 0x2E248: codepoint = pointer - 0x1E248 (U+10000..U+10FFFF)
/// - pointers 0x99FC..0x2E247 and above 0x12E247 are unassigned (invalid).
pub const Gb18030Encoding = struct {
    pub fn name(_: Gb18030Encoding) []const u8 {
        return "GB18030";
    }

    pub fn nextCodepoint(_: Gb18030Encoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        const b0 = bytes[i];

        if (b0 <= 0x7F) {
            index.* += 1;
            return .{ .valid = true, .len = 1, .codepoint = b0 };
        }

        if (b0 < 0x81 or b0 > 0xFE) {
            index.* += 1;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }

        // b0 in 0x81..0xFE: could lead a 2-byte or 4-byte sequence.
        // A 0x30..0x39 second byte only occurs in 4-byte sequences.
        if (i + 1 < bytes.len and bytes[i + 1] >= 0x30 and bytes[i + 1] <= 0x39) {
            if (bytes.len - i < 4) {
                index.* = bytes.len;
                return .{ .valid = false, .len = 1, .codepoint = b0 };
            }
            const b1 = bytes[i + 1];
            const b2 = bytes[i + 2];
            const b3 = bytes[i + 3];
            if (b2 < 0x81 or b2 > 0xFE or b3 < 0x30 or b3 > 0x39) {
                index.* += 2;
                return .{ .valid = false, .len = 2, .codepoint = b0 };
            }
            const ptr = fourBytePointer(b0, b1, b2, b3);
            index.* += 4;
            if (pointerToCodepoint(ptr)) |cp| {
                return .{ .valid = true, .len = 4, .codepoint = cp };
            }
            if (isUnassignedPointer(ptr)) {
                return .{ .valid = false, .len = 4, .codepoint = 0 };
            }
            // Assigned 4-byte sequence outside the algorithmic ranges
            // (BMP zone covered by the 2-byte table area): structurally
            // valid, but not mappable without the table.
            return .{ .valid = true, .len = 4, .codepoint = 0 };
        }

        if (bytes.len - i < 2) {
            index.* = bytes.len;
            return .{ .valid = false, .len = 1, .codepoint = b0 };
        }

        const b1 = bytes[i + 1];
        index.* += 2;
        if ((b1 >= 0x40 and b1 <= 0x7E) or (b1 >= 0x80 and b1 <= 0xFE)) {
            // 2-byte sequence: structurally valid, mapping needs the table.
            return .{ .valid = true, .len = 2, .codepoint = 0 };
        }
        return .{ .valid = false, .len = 2, .codepoint = b0 };
    }

    pub fn nextChar(_: Gb18030Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Gb18030Encoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Gb18030Encoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (Gb18030Encoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Gb18030Encoding) bool {
        return true;
    }

    pub fn isDummy(_: Gb18030Encoding) bool {
        return false;
    }

    pub fn isUnicode(_: Gb18030Encoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Gb18030Encoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Gb18030Encoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }

        const ptr: u32 = if (codepoint >= 0x80 and codepoint <= 0xA3)
            codepoint - 0x80
        else if (codepoint >= 0xFFE6 and codepoint <= 0xFFFF)
            codepoint - 0x6604
        else if (codepoint >= 0x10000 and codepoint <= 0x10FFFF)
            codepoint + 0x1E248
        else
            return null;

        out[3] = 0x30 + @as(u8, @intCast(ptr % 10));
        out[2] = 0x81 + @as(u8, @intCast((ptr / 10) % 126));
        out[1] = 0x30 + @as(u8, @intCast((ptr / 1260) % 10));
        out[0] = 0x81 + @as(u8, @intCast(ptr / 12600));
        return 4;
    }

    pub fn toUnicodeCodepoint(_: Gb18030Encoding, bytes: []const u8) ?u32 {
        if (bytes.len == 1) {
            if (bytes[0] <= 0x7F) return bytes[0];
            return null;
        }
        if (bytes.len != 4) return null;
        if (bytes[1] < 0x30 or bytes[1] > 0x39) return null;
        if (bytes[2] < 0x81 or bytes[2] > 0xFE) return null;
        if (bytes[3] < 0x30 or bytes[3] > 0x39) return null;
        return pointerToCodepoint(fourBytePointer(bytes[0], bytes[1], bytes[2], bytes[3]));
    }

    fn fourBytePointer(b0: u8, b1: u8, b2: u8, b3: u8) u32 {
        return (@as(u32, b0 - 0x81)) * 12600 +
            (@as(u32, b1 - 0x30)) * 1260 +
            (@as(u32, b2 - 0x81)) * 10 +
            @as(u32, b3 - 0x30);
    }

    fn isUnassignedPointer(ptr: u32) bool {
        return (ptr >= 0x99FC and ptr <= 0x2E247) or ptr > 0x12E247;
    }

    fn pointerToCodepoint(ptr: u32) ?u32 {
        if (ptr <= 0x23) return ptr + 0x80;
        if (ptr >= 0x99E2 and ptr <= 0x99FB) return ptr + 0x6604;
        if (ptr >= 0x2E248 and ptr <= 0x12E247) return ptr - 0x1E248;
        return null;
    }
};
