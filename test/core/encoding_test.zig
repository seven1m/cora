const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Encoding::UTF_8 exists" {
    const result = try evalCode("Encoding::UTF_8");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::ASCII_8BIT exists" {
    const result = try evalCode("Encoding::ASCII_8BIT");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::US_ASCII exists" {
    const result = try evalCode("Encoding::US_ASCII");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::SHIFT_JIS exists" {
    const result = try evalCode("Encoding::SHIFT_JIS");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::Windows_31J exists" {
    const result = try evalCode("Encoding::Windows_31J");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_7 exists" {
    const result = try evalCode("Encoding::UTF_7");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_16 exists" {
    const result = try evalCode("Encoding::UTF_16");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_32 exists" {
    const result = try evalCode("Encoding::UTF_32");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::ISO_8859_15 exists" {
    const result = try evalCode("Encoding::ISO_8859_15");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_16LE exists" {
    const result = try evalCode("Encoding::UTF_16LE");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_16BE exists" {
    const result = try evalCode("Encoding::UTF_16BE");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_32LE exists" {
    const result = try evalCode("Encoding::UTF_32LE");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::UTF_32BE exists" {
    const result = try evalCode("Encoding::UTF_32BE");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::BINARY is alias for ASCII_8BIT" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "puts Encoding::BINARY.name\nputs Encoding::ASCII_8BIT.name",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, null), result.err);
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT\nASCII-8BIT\n", result.stdout);
}

test "Encoding#name returns encoding name" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "puts Encoding::UTF_8.name",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, null), result.err);
    try std.testing.expectEqualSlices(u8, "UTF-8\n", result.stdout);
}

test "Encoding#to_s returns encoding name" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "puts Encoding::UTF_8.to_s",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, null), result.err);
    try std.testing.expectEqualSlices(u8, "UTF-8\n", result.stdout);
}

test "Encoding#inspect returns #<Encoding:name>" {
    const result = try evalCode("Encoding::UTF_8.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "#<Encoding:UTF-8>", result.toStringObject().str);
}

test "Encoding#ascii_compatible? returns true for UTF-8" {
    const result = try evalCode("Encoding::UTF_8.ascii_compatible?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "Encoding#ascii_compatible? returns true for ASCII-8BIT" {
    const result = try evalCode("Encoding::ASCII_8BIT.ascii_compatible?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "Encoding#ascii_compatible? returns true for US-ASCII" {
    const result = try evalCode("Encoding::US_ASCII.ascii_compatible?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "Encoding.find with string argument" {
    const result = try evalCode("Encoding.find('UTF-8').name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);
}

test "Encoding.find normalizes name" {
    const result = try evalCode("Encoding.find('utf-8').name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);
}

test "Encoding.find supports SHIFT_JIS aliases" {
    const result = try evalCode("Encoding.find('sjis').name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "Windows-31J", result.toStringObject().str);
}

test "Windows_31J is distinct from Shift_JIS" {
    const result = try evalCode("Encoding::Windows_31J == Encoding::Shift_JIS");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Windows_31J accepts CP932 extension bytes that Shift_JIS cannot transcode" {
    const result = try evalCode(
        \\[
        \\  "\x87]".dup.force_encoding(Encoding::Windows_31J).encode("UTF-8"),
        \\  begin
        \\    "\x87]".dup.force_encoding(Encoding::Shift_JIS).encode("UTF-8")
        \\  rescue Encoding::UndefinedConversionError
        \\    :undefined
        \\  end
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "Ⅹ", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expect(result.toArrayObject().elements.items[1].isSymbol());
    try std.testing.expectEqualSlices(u8, "undefined", result.toArrayObject().elements.items[1].toSymbolObject().name);
}

test "Encoding.find supports UTF-16/UTF-32 aliases" {
    const result_utf16 = try evalCode("Encoding.find('utf16').name");
    try std.testing.expect(result_utf16.isString());
    try std.testing.expectEqualSlices(u8, "UTF-16", result_utf16.toStringObject().str);

    const result_utf32 = try evalCode("Encoding.find('utf32').name");
    try std.testing.expect(result_utf32.isString());
    try std.testing.expectEqualSlices(u8, "UTF-32", result_utf32.toStringObject().str);
}

test "String#encode transcodes UTF-8 to UTF-32BE and preserves char count" {
    const result = try evalCode("'こにちわ'.encode(Encoding::UTF_32BE).length");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());
}

test "String#encode transcodes UTF-8 to SHIFT_JIS and preserves char count" {
    const result = try evalCode("'こにちわ'.encode(Encoding::SHIFT_JIS).length");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());
}

test "Encoding.find with symbol argument raises TypeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("Encoding.find(:binary)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
}

test "Encoding.find coerces to string via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.to_str
        \\  "utf-8"
        \\end
        \\Encoding.find(obj).name
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);
}

test "String#encoding returns encoding object" {
    const result = try evalCode("'hello'.encoding");
    try std.testing.expect(result.isEncoding());
}

test "String#force_encoding changes encoding" {
    const result = try evalCode("'hello'.force_encoding('ASCII-8BIT').encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toStringObject().str);
}

test "String#force_encoding accepts encoding object" {
    const result = try evalCode("'hello'.force_encoding(Encoding::US_ASCII).encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "US-ASCII", result.toStringObject().str);
}

test "String#force_encoding with symbol raises TypeError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("'hello'.force_encoding(:binary)", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
}

test "String#valid_encoding? returns true for valid UTF-8" {
    const result = try evalCode("'hello'.valid_encoding?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "String#valid_encoding? returns true for ASCII-8BIT (always valid)" {
    const result = try evalCode("'hello'.force_encoding('ASCII-8BIT').valid_encoding?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "String#valid_encoding? returns false for invalid UTF-8 bytes" {
    const result = try evalCode("\"\\xF0\\x9F\\x98\".force_encoding('UTF-8').valid_encoding?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == false);
}

test "String#chars splits truncated UTF-8 bytes one-by-one" {
    const result = try evalCode("\"\\xF0\\x9F\\x98\".force_encoding('UTF-8').chars.size");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "String#valid_encoding? accepts non-ASCII byte in ASCII-8BIT" {
    const result = try evalCode("\"\\xFF\".force_encoding('ASCII-8BIT').valid_encoding?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "String#valid_encoding? rejects non-ASCII byte in US-ASCII" {
    const result = try evalCode("\"\\xFF\".force_encoding('US-ASCII').valid_encoding?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == false);
}

test "String#ascii_only? returns true for ASCII string" {
    const result = try evalCode("'hello'.ascii_only?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool() == true);
}

test "String#b returns binary copy" {
    const result = try evalCode("'hello'.b.encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toStringObject().str);
}

test "String#b preserves content" {
    const result = try evalCode("'hello'.b");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}
