const std = @import("std");
const enc = @import("encoding.zig");

fn appendHexByte(writer: anytype, b: u8) !void {
    try std.fmt.format(writer, "\\x{X:0>2}", .{b});
}

fn appendUnicodeEscape(writer: anytype, codepoint: u32) !void {
    if (codepoint <= 0xFFFF) {
        try std.fmt.format(writer, "\\u{X:0>4}", .{codepoint});
    } else {
        try std.fmt.format(writer, "\\u{{{X}}}", .{codepoint});
    }
}

fn appendEscapedCodepoint(writer: anytype, codepoint: u32, unicode_encoding: bool) !void {
    if (unicode_encoding) {
        try appendUnicodeEscape(writer, codepoint);
        return;
    }

    if (codepoint <= 0xFF) {
        try std.fmt.format(writer, "\\x{X:0>2}", .{codepoint});
    } else {
        try std.fmt.format(writer, "\\x{{{X}}}", .{codepoint});
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
        0x7F => "\\c?",
        else => null,
    };
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
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
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

    return buf.toOwnedSlice(allocator);
}

pub fn inspectStringBytes(
    allocator: std.mem.Allocator,
    input: []const u8,
    input_encoding: enc.Encoding,
    result_encoding: enc.Encoding,
) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    const unicode_encoding = input_encoding.isUnicode();
    const use_hex_braces_for_non_ascii = input_encoding.isAsciiCompatible() and !input_encoding.eql(result_encoding);

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
                        try std.fmt.format(writer, "{X:0>2}", .{b});
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

    return buf.toOwnedSlice(allocator);
}
