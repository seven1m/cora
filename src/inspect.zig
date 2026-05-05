const std = @import("std");
const enc = @import("encoding.zig");
const value = @import("value.zig");

fn appendHexByte(writer: anytype, b: u8) !void {
    try writer.print("\\x{X:0>2}", .{b});
}

fn appendUnicodeEscape(writer: anytype, codepoint: u32) !void {
    if (codepoint <= 0xFFFF) {
        try writer.print("\\u{X:0>4}", .{codepoint});
    } else {
        try writer.print("\\u{{{X}}}", .{codepoint});
    }
}

fn appendEscapedCodepoint(writer: anytype, codepoint: u32, unicode_encoding: bool) !void {
    if (unicode_encoding) {
        try appendUnicodeEscape(writer, codepoint);
        return;
    }

    if (codepoint <= 0xFF) {
        try writer.print("\\x{X:0>2}", .{codepoint});
    } else {
        try writer.print("\\x{{{X}}}", .{codepoint});
    }
}

fn appendUtf8Codepoint(writer: anytype, codepoint: u32) !void {
    if (codepoint > std.math.maxInt(u21)) return error.InvalidCodePoint;
    var utf8_buf: [4]u8 = undefined;
    const encoded_len = try std.unicode.utf8Encode(@intCast(codepoint), &utf8_buf);
    try writer.writeAll(utf8_buf[0..encoded_len]);
}

fn escapedControl(codepoint: u32) ?[]const u8 {
    return switch (codepoint) {
        0 => "\\0",
        0x07 => "\\a",
        0x08 => "\\b",
        0x09 => "\\t",
        0x0A => "\\n",
        0x0B => "\\v",
        0x0C => "\\f",
        0x0D => "\\r",
        0x1B => "\\e",
        0x7F => "\\c?",
        else => null,
    };
}

fn escapedInspectControl(codepoint: u32) ?[]const u8 {
    return switch (codepoint) {
        0x07 => "\\a",
        0x08 => "\\b",
        0x09 => "\\t",
        0x0A => "\\n",
        0x0B => "\\v",
        0x0C => "\\f",
        0x0D => "\\r",
        0x1B => "\\e",
        else => null,
    };
}

fn appendDumpEscapedByte(writer: anytype, b: u8, next_byte: u8) !void {
    switch (b) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '#' => {
            if (next_byte == '$' or next_byte == '@' or next_byte == '{') {
                try writer.writeAll("\\#");
            } else {
                try writer.writeByte('#');
            }
        },
        0x07 => try writer.writeAll("\\a"),
        0x08 => try writer.writeAll("\\b"),
        0x09 => try writer.writeAll("\\t"),
        0x0A => try writer.writeAll("\\n"),
        0x0B => try writer.writeAll("\\v"),
        0x0C => try writer.writeAll("\\f"),
        0x0D => try writer.writeAll("\\r"),
        0x1B => try writer.writeAll("\\e"),
        else => {
            if ((b < 0x20) or (b >= 0x7F)) {
                try appendHexByte(writer, b);
            } else {
                try writer.writeByte(b);
            }
        },
    }
}

fn isIdentifierStart(codepoint: u32) bool {
    return codepoint == '_' or (codepoint <= 0x7F and std.ascii.isAlphabetic(@intCast(codepoint))) or codepoint > 0x7F;
}

fn isIdentifierPart(codepoint: u32) bool {
    return isIdentifierStart(codepoint) or (codepoint <= 0x7F and std.ascii.isDigit(@intCast(codepoint)));
}

fn isIdentifierLike(bytes: []const u8, encoding: enc.Encoding, allow_suffix: bool) bool {
    if (bytes.len == 0) return false;

    var i: usize = 0;
    const first = encoding.nextCodepoint(bytes, &i);
    if (first.len == 0 or !first.valid or !isIdentifierStart(first.codepoint)) return false;

    while (i < bytes.len) {
        const parsed = encoding.nextCodepoint(bytes, &i);
        if (parsed.len == 0 or !parsed.valid) return false;
        if (allow_suffix and i == bytes.len and (parsed.codepoint == '!' or parsed.codepoint == '?')) {
            return true;
        }
        if (!isIdentifierPart(parsed.codepoint)) return false;
    }

    return true;
}

fn isBareGlobalSymbolName(bytes: []const u8, encoding: enc.Encoding) bool {
    if (bytes.len < 2 or bytes[0] != '$') return false;

    if (bytes.len == 2) {
        return switch (bytes[1]) {
            '+', '~', ':', '?', '<', '_', '/', '\'', '"', '$', '.', ',', '`', '!', ';', '\\', '=', '*', '>', '&', '@' => true,
            else => false,
        };
    }

    if (bytes[1] == '-') {
        if (bytes.len != 3) return false;
        const option = bytes[2];
        return std.ascii.isAlphabetic(option) or option == '_' or std.ascii.isDigit(option);
    }

    if (std.ascii.isDigit(bytes[1])) {
        for (bytes[1..]) |b| {
            if (!std.ascii.isDigit(b)) return false;
        }
        return true;
    }

    return isIdentifierLike(bytes[1..], encoding, false);
}

fn isBareInstanceOrClassVariableSymbolName(bytes: []const u8, encoding: enc.Encoding) bool {
    if (bytes.len < 2 or bytes[0] != '@') return false;
    if (bytes[1] == '@') {
        if (bytes.len < 3) return false;
        return isIdentifierLike(bytes[2..], encoding, false);
    }
    return isIdentifierLike(bytes[1..], encoding, false);
}

fn isBareOperatorSymbolName(bytes: []const u8) bool {
    const operators = [_][]const u8{
        "-@", "+@", "!", "!=", "!~", "%", "&", "*", "**", "/", "<", "<=", "<=>",
        "==", "===", "=~", ">", ">=", ">>", "[]", "[]=", "<<", "^", "`", "~", "|",
    };

    for (operators) |operator| {
        if (std.mem.eql(u8, bytes, operator)) return true;
    }
    return false;
}

pub fn isBareInspectableSymbolName(bytes: []const u8, encoding: enc.Encoding) bool {
    return isIdentifierLike(bytes, encoding, true);
}

pub fn isBareHashKeySymbol(sym: *value.SymbolObject, target_encoding: enc.Encoding) bool {
    if (!sym.encoding.isAsciiCompatible() or sym.encoding.isDummy()) return false;
    if (!isBareInspectableSymbolName(sym.name, sym.encoding)) return false;
    return sym.encoding.isAsciiOnlyString(sym.name) or sym.encoding.eql(target_encoding);
}

pub fn isBareInspectableSymbol(sym: *value.SymbolObject, target_encoding: enc.Encoding) bool {
    if (!sym.encoding.isAsciiCompatible() or sym.encoding.isDummy()) return false;
    if (!(sym.encoding.isAsciiOnlyString(sym.name) or sym.encoding.eql(target_encoding))) return false;

    return isBareInspectableSymbolName(sym.name, sym.encoding) or
        isBareGlobalSymbolName(sym.name, sym.encoding) or
        isBareInstanceOrClassVariableSymbolName(sym.name, sym.encoding) or
        isBareOperatorSymbolName(sym.name);
}

pub fn targetEncoding(default_internal: ?enc.Encoding, default_external: enc.Encoding) enc.Encoding {
    const selected = default_internal orelse default_external;
    if (!selected.isAsciiCompatible()) return .{ .us_ascii = .{} };
    return selected;
}

pub fn escapeStringBytes(
    allocator: std.mem.Allocator,
    input: []const u8,
    input_encoding: enc.Encoding,
) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    const unicode_encoding = input_encoding.isUnicode();

    var i: usize = 0;
    while (i < input.len) {
        const start = i;
        const parsed = input_encoding.nextCodepoint(input, &i);
        if (parsed.len == 0) break;

        const char_bytes = input[start .. start + parsed.len];
        if (!parsed.valid) {
            for (char_bytes) |b| {
                try appendHexByte(writer, b);
            }
            continue;
        }

        const codepoint = parsed.codepoint;
        if (escapedControl(codepoint)) |escaped| {
            try writer.writeAll(escaped);
            continue;
        }

        if (codepoint <= 0x7F and std.ascii.isPrint(@intCast(codepoint))) {
            try writer.writeByte(@intCast(codepoint));
            continue;
        }

        try appendEscapedCodepoint(writer, codepoint, unicode_encoding);
    }

    return buf.toOwnedSlice();
}

pub fn inspectStringBytes(
    allocator: std.mem.Allocator,
    input: []const u8,
    input_encoding: enc.Encoding,
    result_encoding: enc.Encoding,
) ![]u8 {
    if (input_encoding == .ascii_8bit) {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        const writer = &buf.writer;
        try writer.writeAll("\"");

        for (input, 0..) |b, idx| {
            switch (b) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '#' => {
                    const next_byte = if (idx + 1 < input.len) input[idx + 1] else 0;
                    if (next_byte == '$' or next_byte == '@' or next_byte == '{') {
                        try writer.writeAll("\\#");
                    } else {
                        try writer.writeByte('#');
                    }
                },
                0x07 => try writer.writeAll("\\a"),
                0x08 => try writer.writeAll("\\b"),
                0x09 => try writer.writeAll("\\t"),
                0x0A => try writer.writeAll("\\n"),
                0x0B => try writer.writeAll("\\v"),
                0x0C => try writer.writeAll("\\f"),
                0x0D => try writer.writeAll("\\r"),
                0x1B => try writer.writeAll("\\e"),
                else => {
                    if ((b < 0x20) or (b >= 0x7F)) {
                        try appendHexByte(writer, b);
                    } else {
                        try writer.writeByte(b);
                    }
                },
            }
        }

        try writer.writeAll("\"");
        return buf.toOwnedSlice();
    }

    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    const writer = &buf.writer;

    const unicode_encoding = input_encoding.isUnicode();
    const use_hex_braces_for_non_ascii = input_encoding.isAsciiCompatible() and !unicode_encoding and !input_encoding.eql(result_encoding);

    try writer.writeAll("\"");
    var i: usize = 0;
    while (i < input.len) {
        const start = i;
        const parsed = input_encoding.nextCodepoint(input, &i);
        if (parsed.len == 0) break;

        const char_bytes = input[start .. start + parsed.len];
        if (!parsed.valid) {
            for (char_bytes) |b| {
                try appendHexByte(writer, b);
            }
            continue;
        }

        const codepoint = parsed.codepoint;
        const next_byte = if (i < input.len) input[i] else 0;

        switch (codepoint) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '#' => {
                if (next_byte == '$' or next_byte == '@' or next_byte == '{') {
                    try writer.writeAll("\\#");
                } else {
                    try writer.writeByte('#');
                }
            },
            else => {
                if (escapedInspectControl(codepoint)) |escaped| {
                    try writer.writeAll(escaped);
                    continue;
                }

                if (codepoint < 0x20 or (codepoint >= 0x7F and codepoint <= 0x9F)) {
                    try appendEscapedCodepoint(writer, codepoint, unicode_encoding);
                    continue;
                }

                if (codepoint > 0x7F and use_hex_braces_for_non_ascii) {
                    try writer.writeAll("\\x{");
                    for (char_bytes) |b| {
                        try writer.print("{X:0>2}", .{b});
                    }
                    try writer.writeAll("}");
                    continue;
                }

                if (codepoint <= 0x7F) {
                    try writer.writeByte(@intCast(codepoint));
                    continue;
                }

                if (!input_encoding.isAsciiCompatible()) {
                    try appendUnicodeEscape(writer, codepoint);
                    continue;
                }

                if (!input_encoding.eql(result_encoding)) {
                    try appendUnicodeEscape(writer, codepoint);
                    continue;
                }

                if (unicode_encoding) {
                    try appendUtf8Codepoint(writer, codepoint);
                    continue;
                }

                for (char_bytes) |b| {
                    try appendHexByte(writer, b);
                }
            },
        }
    }
    try writer.writeAll("\"");

    return buf.toOwnedSlice();
}

pub fn dumpStringBytes(
    allocator: std.mem.Allocator,
    input: []const u8,
    input_encoding: enc.Encoding,
) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    const writer = &buf.writer;

    try writer.writeAll("\"");

    if (!input_encoding.isAsciiCompatible()) {
        for (input, 0..) |b, idx| {
            const next_byte = if (idx + 1 < input.len) input[idx + 1] else 0;
            try appendDumpEscapedByte(writer, b, next_byte);
        }

        try writer.writeAll("\"");
        try writer.print(".force_encoding(\"{s}\")", .{input_encoding.name()});
        return buf.toOwnedSlice();
    }

    const unicode_encoding = input_encoding.isUnicode();
    var i: usize = 0;
    while (i < input.len) {
        const start = i;
        const parsed = input_encoding.nextCodepoint(input, &i);
        if (parsed.len == 0) break;

        const char_bytes = input[start .. start + parsed.len];
        if (!parsed.valid) {
            for (char_bytes) |b| {
                try appendHexByte(writer, b);
            }
            continue;
        }

        const codepoint = parsed.codepoint;
        const next_byte = if (i < input.len) input[i] else 0;

        if (codepoint <= 0x7F) {
            try appendDumpEscapedByte(writer, @intCast(codepoint), next_byte);
            continue;
        }

        if (unicode_encoding) {
            try appendUnicodeEscape(writer, codepoint);
            continue;
        }

        for (char_bytes) |b| {
            try appendHexByte(writer, b);
        }
    }

    try writer.writeAll("\"");
    return buf.toOwnedSlice();
}

pub fn inspectSymbolBytes(
    allocator: std.mem.Allocator,
    input: []const u8,
    input_encoding: enc.Encoding,
    result_encoding: enc.Encoding,
) ![]u8 {
    if (input_encoding.isDummy()) {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        const writer = &buf.writer;
        try writer.writeAll("\"");
        for (input) |b| {
            try appendHexByte(writer, b);
        }
        try writer.writeAll("\"");
        return buf.toOwnedSlice();
    }

    if (input_encoding == .ascii_8bit) {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        const writer = &buf.writer;
        try writer.writeAll("\"");

        for (input, 0..) |b, idx| {
            switch (b) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '#' => {
                    const next_byte = if (idx + 1 < input.len) input[idx + 1] else 0;
                    if (next_byte == '$' or next_byte == '@' or next_byte == '{') {
                        try writer.writeAll("\\#");
                    } else {
                        try writer.writeByte('#');
                    }
                },
                0x07 => try writer.writeAll("\\a"),
                0x08 => try writer.writeAll("\\b"),
                0x09 => try writer.writeAll("\\t"),
                0x0A => try writer.writeAll("\\n"),
                0x0B => try writer.writeAll("\\v"),
                0x0C => try writer.writeAll("\\f"),
                0x0D => try writer.writeAll("\\r"),
                0x1B => try writer.writeAll("\\e"),
                else => {
                    if ((b < 0x20) or (b >= 0x7F)) {
                        try appendHexByte(writer, b);
                    } else {
                        try writer.writeByte(b);
                    }
                },
            }
        }

        try writer.writeAll("\"");
        return buf.toOwnedSlice();
    }

    return inspectStringBytes(allocator, input, input_encoding, result_encoding);
}
