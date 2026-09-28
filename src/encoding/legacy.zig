const encoding = @import("../encoding.zig");
const iconv = @import("iconv.zig");

pub const Id = enum {
    iso_8859_2,
    iso_8859_3,
    iso_8859_4,
    iso_8859_5,
    iso_8859_6,
    iso_8859_7,
    iso_8859_8,
    iso_8859_10,
    iso_8859_11,
    iso_8859_13,
    iso_8859_14,
    iso_8859_16,
    koi8_r,
    koi8_u,
    ibm737,
    ibm775,
    cp850,
    ibm852,
    ibm855,
    ibm857,
    ibm860,
    ibm861,
    ibm862,
    ibm863,
    ibm864,
    ibm865,
    ibm869,
    windows_874,
    windows_1250,
    windows_1251,
    windows_1253,
    windows_1254,
    windows_1255,
    windows_1256,
    windows_1257,
    windows_1258,
    mac_centro_euro,
    mac_croatian,
    mac_cyrillic,
    mac_greek,
    mac_iceland,
    mac_roman,
    mac_romania,
    mac_thai,
    mac_turkish,
    mac_ukraine,
    euc_kr,
};

pub const count = @typeInfo(Id).@"enum".fields.len;

pub const LegacyEncoding = struct {
    id: Id,

    pub fn name(self: LegacyEncoding) []const u8 {
        return switch (self.id) {
            .ibm737 => "IBM737",
            .windows_874 => "Windows-874",
            .windows_1250 => "Windows-1250",
            .windows_1251 => "Windows-1251",
            .windows_1253 => "Windows-1253",
            .windows_1254 => "Windows-1254",
            .windows_1255 => "Windows-1255",
            .windows_1256 => "Windows-1256",
            .windows_1257 => "Windows-1257",
            .windows_1258 => "Windows-1258",
            .mac_centro_euro => "macCentEuro",
            .mac_croatian => "macCroatian",
            .mac_cyrillic => "macCyrillic",
            .mac_greek => "macGreek",
            .mac_iceland => "macIceland",
            .mac_roman => "macRoman",
            .mac_romania => "macRomania",
            .mac_thai => "macThai",
            .mac_turkish => "macTurkish",
            .mac_ukraine => "macUkraine",
            else => self.iconvName(),
        };
    }

    pub fn iconvName(self: LegacyEncoding) [:0]const u8 {
        return switch (self.id) {
            .iso_8859_2 => "ISO-8859-2",
            .iso_8859_3 => "ISO-8859-3",
            .iso_8859_4 => "ISO-8859-4",
            .iso_8859_5 => "ISO-8859-5",
            .iso_8859_6 => "ISO-8859-6",
            .iso_8859_7 => "ISO-8859-7",
            .iso_8859_8 => "ISO-8859-8",
            .iso_8859_10 => "ISO-8859-10",
            .iso_8859_11 => "ISO-8859-11",
            .iso_8859_13 => "ISO-8859-13",
            .iso_8859_14 => "ISO-8859-14",
            .iso_8859_16 => "ISO-8859-16",
            .koi8_r => "KOI8-R",
            .koi8_u => "KOI8-U",
            .ibm737 => "CP737",
            .ibm775 => "IBM775",
            .cp850 => "CP850",
            .ibm852 => "IBM852",
            .ibm855 => "IBM855",
            .ibm857 => "IBM857",
            .ibm860 => "IBM860",
            .ibm861 => "IBM861",
            .ibm862 => "IBM862",
            .ibm863 => "IBM863",
            .ibm864 => "IBM864",
            .ibm865 => "IBM865",
            .ibm869 => "IBM869",
            .windows_874 => "WINDOWS-874",
            .windows_1250 => "WINDOWS-1250",
            .windows_1251 => "WINDOWS-1251",
            .windows_1253 => "WINDOWS-1253",
            .windows_1254 => "WINDOWS-1254",
            .windows_1255 => "WINDOWS-1255",
            .windows_1256 => "WINDOWS-1256",
            .windows_1257 => "WINDOWS-1257",
            .windows_1258 => "WINDOWS-1258",
            .mac_centro_euro => "MAC-CENTRALEUROPE",
            .mac_croatian => "MAC-CROATIAN",
            .mac_cyrillic => "MAC-CYRILLIC",
            .mac_greek => "MAC-GREEK",
            .mac_iceland => "MAC-IS",
            .mac_roman => "MACINTOSH",
            .mac_romania => "MAC-ROMANIA",
            .mac_thai => "MAC-THAI",
            .mac_turkish => "MAC-TURKISH",
            .mac_ukraine => "MAC-UKRAINE",
            .euc_kr => "EUC-KR",
        };
    }

    pub fn constantName(self: LegacyEncoding) [:0]const u8 {
        return switch (self.id) {
            .iso_8859_2 => "ISO_8859_2",
            .iso_8859_3 => "ISO_8859_3",
            .iso_8859_4 => "ISO_8859_4",
            .iso_8859_5 => "ISO_8859_5",
            .iso_8859_6 => "ISO_8859_6",
            .iso_8859_7 => "ISO_8859_7",
            .iso_8859_8 => "ISO_8859_8",
            .iso_8859_10 => "ISO_8859_10",
            .iso_8859_11 => "ISO_8859_11",
            .iso_8859_13 => "ISO_8859_13",
            .iso_8859_14 => "ISO_8859_14",
            .iso_8859_16 => "ISO_8859_16",
            .koi8_r => "KOI8_R",
            .koi8_u => "KOI8_U",
            .ibm737 => "IBM737",
            .ibm775 => "IBM775",
            .cp850 => "CP850",
            .ibm852 => "IBM852",
            .ibm855 => "IBM855",
            .ibm857 => "IBM857",
            .ibm860 => "IBM860",
            .ibm861 => "IBM861",
            .ibm862 => "IBM862",
            .ibm863 => "IBM863",
            .ibm864 => "IBM864",
            .ibm865 => "IBM865",
            .ibm869 => "IBM869",
            .windows_874 => "Windows_874",
            .windows_1250 => "Windows_1250",
            .windows_1251 => "Windows_1251",
            .windows_1253 => "Windows_1253",
            .windows_1254 => "Windows_1254",
            .windows_1255 => "Windows_1255",
            .windows_1256 => "Windows_1256",
            .windows_1257 => "Windows_1257",
            .windows_1258 => "Windows_1258",
            .mac_centro_euro => "MacCentEuro",
            .mac_croatian => "MacCroatian",
            .mac_cyrillic => "MacCyrillic",
            .mac_greek => "MacGreek",
            .mac_iceland => "MacIceland",
            .mac_roman => "MacRoman",
            .mac_romania => "MacRomania",
            .mac_thai => "MacThai",
            .mac_turkish => "MacTurkish",
            .mac_ukraine => "MacUkraine",
            .euc_kr => "EUC_KR",
        };
    }

    pub fn nextCodepoint(self: LegacyEncoding, bytes: []const u8, index: *usize) encoding.CodepointResult {
        if (index.* >= bytes.len) return .{ .valid = true, .len = 0, .codepoint = 0 };
        const decoded = iconv.decodeFirst(self.iconvName(), bytes[index.*..]) orelse {
            if (self.isSingleByte()) {
                const byte = bytes[index.*];
                index.* += 1;
                return .{ .valid = true, .len = 1, .codepoint = byte };
            }
            index.* += 1;
            return .{ .valid = false, .len = 1, .codepoint = bytes[index.* - 1] };
        };
        index.* += decoded.consumed;
        return .{ .valid = true, .len = decoded.consumed, .codepoint = decoded.codepoint };
    }

    pub fn nextChar(self: LegacyEncoding, bytes: []const u8, index: *usize) encoding.CharResult {
        const result = self.nextCodepoint(bytes, index);
        return .{ .valid = result.valid, .len = result.len };
    }

    pub fn isValid(self: LegacyEncoding, bytes: []const u8) bool {
        var index: usize = 0;
        while (index < bytes.len) {
            if (!self.nextCodepoint(bytes, &index).valid) return false;
        }
        return true;
    }

    pub fn isAsciiCompatible(_: LegacyEncoding) bool {
        return true;
    }

    pub fn isDummy(_: LegacyEncoding) bool {
        return false;
    }

    pub fn isUnicode(_: LegacyEncoding) bool {
        return false;
    }

    pub fn isSingleByte(self: LegacyEncoding) bool {
        return switch (self.id) {
            .euc_kr => false,
            else => true,
        };
    }

    pub fn fromUnicodeCodepoint(self: LegacyEncoding, codepoint: u32, out: *[4]u8) ?usize {
        if (codepoint <= 0x7F) {
            out[0] = @intCast(codepoint);
            return 1;
        }
        return iconv.encodeCodepoint(self.iconvName(), codepoint, out);
    }

    pub fn toUnicodeCodepoint(self: LegacyEncoding, bytes: []const u8) ?u32 {
        if (bytes.len == 1 and bytes[0] <= 0x7F) return bytes[0];
        const decoded = iconv.decodeFirst(self.iconvName(), bytes) orelse return null;
        if (decoded.consumed != bytes.len) return null;
        return decoded.codepoint;
    }
};
