const encoding = @import("../encoding.zig");

pub const Utf8Encoding = struct {
    pub fn name(_: Utf8Encoding) []const u8 {
        return "UTF-8";
    }

    pub fn nextChar(_: Utf8Encoding, bytes: []const u8, index: *usize) encoding.CharResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0 };
        const first = bytes[index.*];

        // Single byte (ASCII): 0xxxxxxx
        if (first < 0x80) {
            index.* += 1;
            return .{ .valid = true, .len = 1 };
        }

        // Invalid: continuation byte at start or invalid lead byte
        if (first < 0xC2 or first > 0xF4) {
            index.* += 1;
            return .{ .valid = false, .len = 1 };
        }

        // 2-byte sequence: 110xxxxx 10xxxxxx (C2-DF)
        if (first >= 0xC2 and first <= 0xDF) {
            if (index.* + 1 >= bytes.len) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }
            const second = bytes[index.* + 1];
            if ((second & 0xC0) != 0x80) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }
            index.* += 2;
            return .{ .valid = true, .len = 2 };
        }

        // 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx (E0-EF)
        if (first >= 0xE0 and first <= 0xEF) {
            if (index.* + 2 >= bytes.len) {
                const remaining = bytes.len - index.*;
                index.* += remaining;
                return .{ .valid = false, .len = remaining };
            }
            const second = bytes[index.* + 1];
            const third = bytes[index.* + 2];

            // Check continuation bytes
            if ((second & 0xC0) != 0x80 or (third & 0xC0) != 0x80) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }

            // Check for overlong encodings and surrogate pairs
            if (first == 0xE0 and second < 0xA0) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }
            if (first == 0xED and second >= 0xA0) {
                // Surrogate pairs (U+D800 to U+DFFF) are invalid
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }

            index.* += 3;
            return .{ .valid = true, .len = 3 };
        }

        // 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx (F0-F4)
        if (first >= 0xF0 and first <= 0xF4) {
            if (index.* + 3 >= bytes.len) {
                const remaining = bytes.len - index.*;
                index.* += remaining;
                return .{ .valid = false, .len = remaining };
            }
            const second = bytes[index.* + 1];
            const third = bytes[index.* + 2];
            const fourth = bytes[index.* + 3];

            // Check continuation bytes
            if ((second & 0xC0) != 0x80 or (third & 0xC0) != 0x80 or (fourth & 0xC0) != 0x80) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }

            // Check for overlong encodings and code points > U+10FFFF
            if (first == 0xF0 and second < 0x90) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }
            if (first == 0xF4 and second > 0x8F) {
                index.* += 1;
                return .{ .valid = false, .len = 1 };
            }

            index.* += 4;
            return .{ .valid = true, .len = 4 };
        }

        // Should not reach here, but handle gracefully
        index.* += 1;
        return .{ .valid = false, .len = 1 };
    }

    pub fn isValid(_: Utf8Encoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const result = (Utf8Encoding{}).nextChar(bytes, &i);
            if (!result.valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: Utf8Encoding) bool {
        return true;
    }

    pub fn isSingleByte(_: Utf8Encoding) bool {
        return false;
    }
};
