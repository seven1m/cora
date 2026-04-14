const std = @import("std");
const onigmo = @import("onigmo.zig");
const Utf8Encoding = @import("encoding/utf8.zig").Utf8Encoding;
const Cesu8Encoding = @import("encoding/cesu8.zig").Cesu8Encoding;
const Ascii8BitEncoding = @import("encoding/ascii_8bit.zig").Ascii8BitEncoding;
const UsAsciiEncoding = @import("encoding/us_ascii.zig").UsAsciiEncoding;
const ShiftJisEncoding = @import("encoding/shift_jis.zig").ShiftJisEncoding;
const Windows31JEncoding = @import("encoding/windows_31j.zig").Windows31JEncoding;
const EucJpEncoding = @import("encoding/euc_jp.zig").EucJpEncoding;
const Cp437Encoding = @import("encoding/cp437.zig").Cp437Encoding;
const Iso2022JpEncoding = @import("encoding/iso_2022_jp.zig").Iso2022JpEncoding;
const Iso88599Encoding = @import("encoding/iso_8859_9.zig").Iso88599Encoding;
const Iso885915Encoding = @import("encoding/iso_8859_15.zig").Iso885915Encoding;
const Utf7Encoding = @import("encoding/utf7.zig").Utf7Encoding;
const Utf16Encoding = @import("encoding/utf16.zig").Utf16Encoding;
const Utf32Encoding = @import("encoding/utf32.zig").Utf32Encoding;
const Utf16LeEncoding = @import("encoding/utf16le.zig").Utf16LeEncoding;
const Utf16BeEncoding = @import("encoding/utf16be.zig").Utf16BeEncoding;
const Utf32LeEncoding = @import("encoding/utf32le.zig").Utf32LeEncoding;
const Utf32BeEncoding = @import("encoding/utf32be.zig").Utf32BeEncoding;

pub const CharResult = struct {
    valid: bool,
    len: usize,
};

pub const CodepointResult = struct {
    valid: bool,
    len: usize,
    codepoint: u32,
};

pub const ValidityState = enum(u2) {
    unknown,
    valid,
    invalid,
};

pub const Encoding = union(enum) {
    utf8: Utf8Encoding,
    cesu8: Cesu8Encoding,
    ascii_8bit: Ascii8BitEncoding,
    us_ascii: UsAsciiEncoding,
    shift_jis: ShiftJisEncoding,
    windows_31j: Windows31JEncoding,
    euc_jp: EucJpEncoding,
    cp437: Cp437Encoding,
    iso_2022_jp: Iso2022JpEncoding,
    iso_8859_9: Iso88599Encoding,
    iso_8859_15: Iso885915Encoding,
    utf7: Utf7Encoding,
    utf16: Utf16Encoding,
    utf32: Utf32Encoding,
    utf16le: Utf16LeEncoding,
    utf16be: Utf16BeEncoding,
    utf32le: Utf32LeEncoding,
    utf32be: Utf32BeEncoding,

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

    pub fn nextCodepoint(self: Encoding, bytes: []const u8, index: *usize) CodepointResult {
        return switch (self) {
            inline else => |enc| enc.nextCodepoint(bytes, index),
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

    pub fn isDummy(self: Encoding) bool {
        return switch (self) {
            inline else => |enc| enc.isDummy(),
        };
    }

    pub fn isUnicode(self: Encoding) bool {
        return switch (self) {
            inline else => |enc| enc.isUnicode(),
        };
    }

    pub fn isAsciiOnlyString(self: Encoding, bytes: []const u8) bool {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = self.nextCodepoint(bytes, &i);
            if (parsed.len == 0 or !parsed.valid) return false;
            if (parsed.codepoint > 0x7F) return false;
        }
        return true;
    }

    pub fn isSingleByte(self: Encoding) bool {
        return switch (self) {
            inline else => |enc| enc.isSingleByte(),
        };
    }

    pub fn fromUnicodeCodepoint(self: Encoding, codepoint: u32, out: *[4]u8) ?usize {
        return switch (self) {
            inline else => |enc| enc.fromUnicodeCodepoint(codepoint, out),
        };
    }

    pub fn toUnicodeCodepoint(self: Encoding, bytes: []const u8) ?u32 {
        return switch (self) {
            inline else => |enc| enc.toUnicodeCodepoint(bytes),
        };
    }

    pub fn charCount(self: Encoding, bytes: []const u8) usize {
        var i: usize = 0;
        var count: usize = 0;
        while (i < bytes.len) {
            const r = self.nextChar(bytes, &i);
            if (r.len == 0) break;
            count += 1;
        }
        return count;
    }

    pub fn byteOffsetForCharIndex(self: Encoding, bytes: []const u8, char_index: usize) ?usize {
        var i: usize = 0;
        var count: usize = 0;
        while (i < bytes.len and count < char_index) : (count += 1) {
            const r = self.nextChar(bytes, &i);
            if (r.len == 0) return null;
        }
        if (count == char_index) return i;
        return null;
    }

    pub fn isCharBoundary(self: Encoding, bytes: []const u8, offset: usize) bool {
        if (offset == 0 or offset == bytes.len) return true;
        if (offset > bytes.len) return false;

        var i: usize = 0;
        while (i < bytes.len) {
            if (i == offset) return true;
            const r = self.nextChar(bytes, &i);
            if (r.len == 0) break;
        }
        return i == offset;
    }

    pub fn normalizeCharIndex(self: Encoding, bytes: []const u8, idx: i64) ?usize {
        const len_i64: i64 = @intCast(self.charCount(bytes));
        var actual = idx;
        if (actual < 0) actual += len_i64;
        if (actual < 0 or actual >= len_i64) return null;
        return @intCast(actual);
    }

    pub fn charSliceAtIndex(self: Encoding, bytes: []const u8, idx: i64) ?[]const u8 {
        const char_idx = self.normalizeCharIndex(bytes, idx) orelse return null;
        const start = self.byteOffsetForCharIndex(bytes, char_idx) orelse return null;
        const end = self.byteOffsetForCharIndex(bytes, char_idx + 1) orelse bytes.len;
        return bytes[start..end];
    }

    pub fn eql(self: Encoding, other: Encoding) bool {
        const self_tag = @as(std.meta.Tag(Encoding), self);
        const other_tag = @as(std.meta.Tag(Encoding), other);
        return self_tag == other_tag;
    }
};

pub const TranscodeError = error{
    OutOfMemory,
    InvalidByteSequence,
    UndefinedConversion,
};

pub const ConverterAvailability = enum {
    available,
    ascii_only_passthrough,
    unavailable,
};

pub const CaseMapMode = enum {
    upcase,
    downcase,
};

pub const CaseMapOptions = struct {
    ascii_only: bool = false,
    turkic: bool = false,
    lithuanian: bool = false,
    fold: bool = false,
};

pub const CaseMapError = error{
    OutOfMemory,
    InvalidByteSequence,
};

pub const CaseMapResult = struct {
    bytes: []const u8,
    modified: bool,
    encoding: Encoding,
};

pub fn effectiveTranscodeTargetEncoding(target: Encoding) Encoding {
    return switch (target) {
        .utf16 => .{ .utf16be = .{} },
        .utf32 => .{ .utf32be = .{} },
        else => target,
    };
}

pub fn converterAvailability(from: Encoding, to: Encoding) ConverterAvailability {
    const effective_target = effectiveTranscodeTargetEncoding(to);
    if (from.eql(effective_target)) return .available;

    if (from == .ascii_8bit and (effective_target == .shift_jis or effective_target == .windows_31j)) {
        return .ascii_only_passthrough;
    }

    if ((from == .shift_jis or from == .windows_31j) and effective_target == .ascii_8bit) {
        return .unavailable;
    }

    return .available;
}

pub fn transcode(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    source: Encoding,
    target: Encoding,
) TranscodeError![]u8 {
    const effective_target = effectiveTranscodeTargetEncoding(target);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const parsed = source.nextChar(bytes, &i);
        if (parsed.len == 0) break;
        if (!parsed.valid) return error.InvalidByteSequence;
        const codepoint = source.toUnicodeCodepoint(bytes[start .. start + parsed.len]) orelse {
            return error.UndefinedConversion;
        };

        var encoded: [4]u8 = undefined;
        const encoded_len = effective_target.fromUnicodeCodepoint(codepoint, &encoded) orelse {
            return error.UndefinedConversion;
        };
        out.appendSlice(allocator, encoded[0..encoded_len]) catch return error.OutOfMemory;
    }

    return out.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn caseMap(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    source_encoding: Encoding,
    mode: CaseMapMode,
    options: CaseMapOptions,
) CaseMapError!CaseMapResult {
    var out_bytes = try allocator.dupe(u8, bytes);
    var modified = false;
    errdefer allocator.free(out_bytes);
    var out_encoding = source_encoding;

    if (mode != .upcase and mode != .downcase) return .{ .bytes = out_bytes, .modified = false, .encoding = out_encoding };

    const effective_source_encoding: Encoding = if (source_encoding == .us_ascii and !options.ascii_only and (options.turkic or options.lithuanian))
        .{ .utf8 = .{} }
    else
        source_encoding;
    if (!effective_source_encoding.eql(source_encoding)) {
        out_encoding = effective_source_encoding;
    }

    const onig_encoding = mapOnigEncoding(effective_source_encoding);
    if (onig_encoding) |oe| {
        var flags: onigmo.OnigCaseFoldType = switch (mode) {
            .upcase => onigmo.CASE_UPCASE,
            .downcase => onigmo.CASE_DOWNCASE,
        };
        if (options.ascii_only) flags |= onigmo.CASE_ASCII_ONLY;
        if (options.turkic) flags |= onigmo.CASE_FOLD_TURKISH_AZERI;
        if (options.lithuanian) flags |= onigmo.CASE_FOLD_LITHUANIAN;
        if (options.fold) flags |= onigmo.CASE_FOLD;

        const mapped = onigmo.caseMap(allocator, bytes, oe, flags) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidByteSequence => return error.InvalidByteSequence,
            error.UnsupportedEncoding => unreachable,
        };
        allocator.free(out_bytes);
        out_bytes = mapped.bytes;
        modified = (mapped.flags & onigmo.CASE_MODIFIED) != 0;
        return .{ .bytes = out_bytes, .modified = modified, .encoding = out_encoding };
    }

    for (out_bytes) |*b| {
        switch (mode) {
            .upcase => {
                if (b.* >= 'a' and b.* <= 'z') {
                    b.* -= 32;
                    modified = true;
                }
            },
            .downcase => {
                if (b.* >= 'A' and b.* <= 'Z') {
                    b.* += 32;
                    modified = true;
                }
            },
        }
    }
    return .{ .bytes = out_bytes, .modified = modified, .encoding = out_encoding };
}

/// Encoding negotiation for string operations.
/// Returns the result encoding for combining two strings, or null if incompatible.
pub fn negotiate(enc1: Encoding, str1: []const u8, enc2: Encoding, str2: []const u8) ?Encoding {
    // Same encoding - always compatible
    if (enc1.eql(enc2)) {
        return enc1;
    }

    // Dummy encodings do not implicitly negotiate with different encodings.
    if (enc1.isDummy() or enc2.isDummy()) {
        return null;
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

    // US-ASCII is compatible with any ASCII-compatible encoding because its
    // contents are necessarily ASCII-only.
    const enc1_is_ascii = (enc1 == .us_ascii);
    const enc2_is_ascii = (enc2 == .us_ascii);

    if (enc1_is_ascii and enc2.isAsciiCompatible()) {
        return enc2;
    }

    if (enc2_is_ascii and enc1.isAsciiCompatible()) {
        return enc1;
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

fn mapOnigEncoding(source_encoding: Encoding) ?onigmo.OnigEncoding {
    return switch (source_encoding) {
        .utf8 => onigmo.ENCODING_UTF_8,
        .ascii_8bit => onigmo.ENCODING_ASCII,
        .us_ascii => onigmo.ENCODING_ASCII,
        .shift_jis => onigmo.ENCODING_SHIFT_JIS,
        .windows_31j => onigmo.ENCODING_WINDOWS_31J,
        .euc_jp => onigmo.ENCODING_EUC_JP,
        .iso_8859_9 => onigmo.ENCODING_ISO_8859_9,
        .iso_8859_15 => onigmo.ENCODING_ISO_8859_15,
        .utf16le => onigmo.ENCODING_UTF_16LE,
        .utf16be => onigmo.ENCODING_UTF_16BE,
        .utf32le => onigmo.ENCODING_UTF_32LE,
        .utf32be => onigmo.ENCODING_UTF_32BE,
        else => null,
    };
}

/// Helper used by multiple encodings - checks if all bytes are ASCII (0-127)
pub fn isAsciiOnly(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b > 127) return false;
    }
    return true;
}
