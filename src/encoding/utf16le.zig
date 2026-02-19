const encoding = @import("../encoding.zig");

pub const Utf16LeEncoding = struct {
    pub fn name(_: Utf16LeEncoding) []const u8 {
        return "UTF-16LE";
    }

    pub fn nextCodepoint(_: Utf16LeEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };

        const i = index.*;
        if (bytes.len - i < 2) {
            const remaining = bytes.len - i;
            index.* = bytes.len;
            return .{ .valid = false, .len = remaining, .codepoint = 0 };
        }

        const unit1 = readLe16(bytes[i], bytes[i + 1]);
        if (unit1 >= 0xD800 and unit1 <= 0xDBFF) {
            if (bytes.len - i < 4) {
                index.* += 2;
                return .{ .valid = false, .len = 2, .codepoint = unit1 };
            }
            const unit2 = readLe16(bytes[i + 2], bytes[i + 3]);
            if (!(unit2 >= 0xDC00 and unit2 <= 0xDFFF)) {
                index.* += 2;
                return .{ .valid = false, .len = 2, .codepoint = unit1 };
            }

            const high = @as(u32, unit1 - 0xD800);
            const low = @as(u32, unit2 - 0xDC00);
            const cp = 0x10000 + ((high << 10) | low);
            index.* += 4;
            return .{ .valid = true, .len = 4, .codepoint = cp };
        }

        if (unit1 >= 0xDC00 and unit1 <= 0xDFFF) {
            index.* += 2;
            return .{ .valid = false, .len = 2, .codepoint = unit1 };
        }

        index.* += 2;
        return .{ .valid = true, .len = 2, .codepoint = unit1 };
    }

    pub fn nextChar(_: Utf16LeEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const parsed = (Utf16LeEncoding{}).nextCodepoint(bytes, index);
        return .{ .valid = parsed.valid, .len = parsed.len };
    }

    pub fn isValid(_: Utf16LeEncoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = (Utf16LeEncoding{}).nextCodepoint(bytes, &i);
            if (!parsed.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Utf16LeEncoding) bool {
        return false;
    }

    pub fn isSingleByte(_: Utf16LeEncoding) bool {
        return false;
    }

    pub fn fromUnicodeCodepoint(_: Utf16LeEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint > 0x10FFFF) return null;
        if (codepoint >= 0xD800 and codepoint <= 0xDFFF) return null;

        if (codepoint <= 0xFFFF) {
            writeLe16(@intCast(codepoint), out[0..2]);
            return 2;
        }

        const n = codepoint - 0x10000;
        const high: u16 = @intCast(0xD800 + ((n >> 10) & 0x3FF));
        const low: u16 = @intCast(0xDC00 + (n & 0x3FF));
        writeLe16(high, out[0..2]);
        writeLe16(low, out[2..4]);
        return 4;
    }

    pub fn toUnicodeCodepoint(_: Utf16LeEncoding, bytes: []const u8) ?u32 {
        if (!(bytes.len == 2 or bytes.len == 4)) return null;
        var i: usize = 0;
        const parsed = (Utf16LeEncoding{}).nextCodepoint(bytes, &i);
        if (!parsed.valid or parsed.len != bytes.len or i != bytes.len) return null;
        return parsed.codepoint;
    }

    fn readLe16(b0: u8, b1: u8) u16 {
        return (@as(u16, b1) << 8) | b0;
    }

    fn writeLe16(v: u16, out: []u8) void {
        out[0] = @intCast(v & 0x00FF);
        out[1] = @intCast((v >> 8) & 0x00FF);
    }
};
