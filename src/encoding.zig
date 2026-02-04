const Utf8Encoding = @import("encoding/utf8.zig").Utf8Encoding;
const Ascii8BitEncoding = @import("encoding/ascii_8bit.zig").Ascii8BitEncoding;
const UsAsciiEncoding = @import("encoding/us_ascii.zig").UsAsciiEncoding;

pub const CharResult = struct {
    valid: bool,
    len: usize,
};

pub const ValidityState = enum(u2) {
    unknown,
    valid,
    invalid,
};

pub const Encoding = union(enum) {
    utf8: Utf8Encoding,
    ascii_8bit: Ascii8BitEncoding,
    us_ascii: UsAsciiEncoding,

    // Delegate to active variant using inline else
    pub fn name(self: Encoding) []const u8 {
        return switch (self) {
            inline else => |enc| enc.name(),
        };
    }

    pub fn nextChar(self: Encoding, bytes: []const u8, index: *usize) CharResult {
        return switch (self) {
            inline else => |enc| enc.nextChar(bytes, index),
        };
    }

    pub fn isValid(self: Encoding, bytes: []const u8) bool {
        return switch (self) {
            inline else => |enc| enc.isValid(bytes),
        };
    }

    pub fn isAsciiCompatible(self: Encoding) bool {
        return switch (self) {
            inline else => |enc| enc.isAsciiCompatible(),
        };
    }

    pub fn isSingleByte(self: Encoding) bool {
        return switch (self) {
            inline else => |enc| enc.isSingleByte(),
        };
    }

    pub fn eql(self: Encoding, other: Encoding) bool {
        const self_tag = @as(std.meta.Tag(Encoding), self);
        const other_tag = @as(std.meta.Tag(Encoding), other);
        return self_tag == other_tag;
    }
};

/// Encoding negotiation for string operations.
/// Returns the result encoding for combining two strings, or null if incompatible.
pub fn negotiate(enc1: Encoding, str1: []const u8, enc2: Encoding, str2: []const u8) ?Encoding {
    // Same encoding - always compatible
    if (enc1.eql(enc2)) {
        return enc1;
    }

    // ASCII-8BIT (binary) with ASCII-only content is compatible with ASCII-compatible encodings
    const enc1_is_binary = (enc1 == .ascii_8bit);
    const enc2_is_binary = (enc2 == .ascii_8bit);

    if (enc1_is_binary and enc2.isAsciiCompatible() and isAsciiOnly(str1)) {
        return enc2;
    }

    if (enc2_is_binary and enc1.isAsciiCompatible() and isAsciiOnly(str2)) {
        return enc1;
    }

    // US-ASCII is compatible with UTF-8 (US-ASCII is a subset)
    const enc1_is_ascii = (enc1 == .us_ascii);
    const enc2_is_ascii = (enc2 == .us_ascii);
    const enc1_is_utf8 = (enc1 == .utf8);
    const enc2_is_utf8 = (enc2 == .utf8);

    if (enc1_is_ascii and enc2_is_utf8) {
        return enc2; // UTF-8
    }

    if (enc2_is_ascii and enc1_is_utf8) {
        return enc1; // UTF-8
    }

    // If both strings are ASCII-only, they're compatible regardless of encoding
    if (isAsciiOnly(str1) and isAsciiOnly(str2)) {
        // Prefer the non-ASCII encoding, or the first one
        if (enc1_is_ascii) return enc2;
        if (enc2_is_ascii) return enc1;
        return enc1;
    }

    // Incompatible encodings
    return null;
}

/// Helper used by multiple encodings - checks if all bytes are ASCII (0-127)
pub fn isAsciiOnly(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b > 127) return false;
    }
    return true;
}

const std = @import("std");
