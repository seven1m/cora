const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Encoding.compatible? chooses a common encoding" {
    const result = try evalCode(
        \\utf8 = Encoding::UTF_8
        \\sjis = Encoding::SHIFT_JIS
        \\ascii = Encoding::US_ASCII
        \\binary = Encoding::ASCII_8BIT
        \\[Encoding.compatible?("abc", "def"),
        \\ Encoding.compatible?("abc".force_encoding(sjis), "def"),
        \\ Encoding.compatible?("def", "abc".force_encoding(sjis)),
        \\ Encoding.compatible?(utf8, ascii),
        \\ Encoding.compatible?(utf8, binary),
        \\ Encoding.compatible?("", "abc".force_encoding(sjis)),
        \\ Encoding.compatible?(nil, "abc")]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 7), items.len);
    try std.testing.expectEqualStrings("UTF-8", items[0].toEncodingObject().encoding.name());
    try std.testing.expectEqualStrings("Shift_JIS", items[1].toEncodingObject().encoding.name());
    try std.testing.expectEqualStrings("UTF-8", items[2].toEncodingObject().encoding.name());
    try std.testing.expectEqualStrings("UTF-8", items[3].toEncodingObject().encoding.name());
    try std.testing.expect(items[4].isNil());
    try std.testing.expectEqualStrings("Shift_JIS", items[5].toEncodingObject().encoding.name());
    try std.testing.expect(items[6].isNil());
}

test "Encoding::UTF_8 exists" {
    const result = try evalCode("Encoding::UTF_8");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::CESU_8 exists" {
    const result = try evalCode("Encoding::CESU_8");
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

test "Encoding#inspect returns #<Encoding:name> for non-dummy encodings" {
    const result = try evalCode("Encoding::UTF_8.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "#<Encoding:UTF-8>", result.toStringObject().str);
}

test "Encoding#inspect returns BINARY alias for ASCII-8BIT" {
    const result = try evalCode("Encoding::ASCII_8BIT.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "#<Encoding:BINARY (ASCII-8BIT)>", result.toStringObject().str);
}

test "Encoding#inspect marks dummy encodings" {
    const result = try evalCode("Encoding::UTF_7.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "#<Encoding:UTF-7 (dummy)>", result.toStringObject().str);
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

test "Encoding::Converter.new succeeds for supported conversions" {
    const result = try evalCode("Encoding::Converter.new(Encoding::EUC_JP, Encoding::UTF_8)");
    try std.testing.expect(result.isObject());
}

test "Encoding::Converter.new raises for missing converter paths" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        "Encoding::Converter.new(Encoding::Windows_31J, Encoding::BINARY)",
        &stdout_buf,
        &stderr_buf,
    );
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ConverterNotFoundError") != null);
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

test "Japanese encodings use JIS mappings for kanji punctuation and accented letters" {
    const result = try evalCode(
        \\[
        \\  "壁鍵猫！".encode("EUC-JP").bytes == [0xCA, 0xC9, 0xB8, 0xB0, 0xC7, 0xAD, 0xA1, 0xAA],
        \\  "壁鍵猫！".encode("Shift_JIS").bytes == [0x95, 0xC7, 0x8C, 0xAE, 0x94, 0x4C, 0x81, 0x49],
        \\  "üé".encode("EUC-JP").bytes == [0x8F, 0xAB, 0xE4, 0x8F, 0xAB, 0xB1],
        \\  "壁鍵猫！üé".encode("EUC-JP").encode("UTF-8") == "壁鍵猫！üé",
        \\  "壁鍵猫！".encode("Shift_JIS").encode("UTF-8") == "壁鍵猫！"
        \\]
    );
    for (result.toArrayObject().elements.items) |item| try std.testing.expect(item.isTruthy());
}

test "String#encode decodes ISO-2022-JP katakana" {
    const result = try evalCode(
        \\[27, 36, 66, 37, 34, 37, 106, 37, 57, 27, 40, 66].pack("C*").force_encoding("ISO-2022-JP").encode("UTF-8")
    );
    try std.testing.expectEqualStrings("アリス", result.toStringObject().str);
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

test "ASCII-8BIT(non-ASCII) compatible with UTF-8(ASCII-only) via negotiate" {
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').include?('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').start_with?('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').end_with?('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').index('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').rindex('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').delete_prefix('#')");
    _ = try evalCode("\"\\x80\".force_encoding('ASCII-8BIT').delete_suffix('#')");
}

test "ASCII-8BIT(non-ASCII) incompatible with UTF-8(non-ASCII) via negotiate" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    {
        const result = evalCodeWithOutput(
            "\"\\x80\".force_encoding('ASCII-8BIT').include?(\"\\xC3\\xA9\")",
            &stdout_buf,
            &stderr_buf,
        );
        try std.testing.expectEqual(error.UnhandledException, result.err.?);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "CompatibilityError") != null);
    }
    {
        const result = evalCodeWithOutput(
            "\"\\x80\".force_encoding('ASCII-8BIT').start_with?(\"\\xC3\\xA9\")",
            &stdout_buf,
            &stderr_buf,
        );
        try std.testing.expectEqual(error.UnhandledException, result.err.?);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "CompatibilityError") != null);
    }
    {
        const result = evalCodeWithOutput(
            "\"\\x80\".force_encoding('ASCII-8BIT').end_with?(\"\\xC3\\xA9\")",
            &stdout_buf,
            &stderr_buf,
        );
        try std.testing.expectEqual(error.UnhandledException, result.err.?);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "CompatibilityError") != null);
    }
    {
        const result = evalCodeWithOutput(
            "\"\\x80\".force_encoding('ASCII-8BIT').index(\"\\xC3\\xA9\")",
            &stdout_buf,
            &stderr_buf,
        );
        try std.testing.expectEqual(error.UnhandledException, result.err.?);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "CompatibilityError") != null);
    }
}

test "ASCII-8BIT encoding compatibility for concat" {
    // ASCII-8BIT(non-ASCII) + UTF-8(ASCII-only) should be ASCII-8BIT.
    const result = try evalCode(
        "(\"\\x80\".force_encoding('ASCII-8BIT') + '#').encoding.name",
    );
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toStringObject().str);

    // ASCII-8BIT(non-ASCII) + UTF-8(non-ASCII) should raise.
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const err_result = evalCodeWithOutput(
        "\"\\x80\".force_encoding('ASCII-8BIT') + \"\\xC3\\xA9\"",
        &stdout_buf,
        &stderr_buf,
    );
    try std.testing.expectEqual(error.UnhandledException, err_result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, err_result.stderr, "CompatibilityError") != null);
}

test "Encoding::GB18030 exists" {
    const result = try evalCode("Encoding::GB18030");
    try std.testing.expect(result.isEncoding());
}

test "Encoding::GB18030 is distinct from Shift_JIS" {
    const result = try evalCode("Encoding::GB18030 == Encoding::Shift_JIS");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "GBK and Big5 have distinct canonical encodings" {
    const result = try evalCode(
        \\[Encoding.find("GBK").name, Encoding.find("Big5").name,
        \\ Encoding.find("GBK") == Encoding::Shift_JIS,
        \\ Encoding.find("Big5") == Encoding::Shift_JIS]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("GBK", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("Big5", values[1].toStringObject().str);
    try std.testing.expect(values[2].isFalse());
    try std.testing.expect(values[3].isFalse());
}

test "Encoding.find resolves GB18030" {
    const result = try evalCode("Encoding.find('GB18030').name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "GB18030", result.toStringObject().str);
}

test "GB18030 roundtrips astral plane through 4-byte sequences" {
    const result = try evalCode(
        \\[0x80, 0xA3, 0xFFE6, 0xFFFF, 0x10000, 0x20BB7, 0x10FFFF].map do |cp|
        \\  cp.chr(Encoding::UTF_8).encode(Encoding::GB18030).force_encoding(Encoding::GB18030).encode(Encoding::UTF_8).ord
        \\end
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    const expected = [_]i64{ 0x80, 0xA3, 0xFFE6, 0xFFFF, 0x10000, 0x20BB7, 0x10FFFF };
    try std.testing.expectEqual(expected.len, items.len);
    for (expected, items) |want, got| {
        try std.testing.expectEqual(want, got.toInteger());
    }
}

test "GB18030 rejects unassigned 4-byte sequences" {
    const result = try evalCode(
        \\["\x84\x31\xA5\x30", "\xE3\x32\x9A\x36"].map do |s|
        \\  s.dup.force_encoding(Encoding::GB18030).valid_encoding?
        \\end
    );
    try std.testing.expect(result.isArray());
    for (result.toArrayObject().elements.items) |item| {
        try std.testing.expectEqual(false, item.toBool());
    }
}

test "GB18030 2-byte sequences are structurally valid but need the table to transcode" {
    const result = try evalCode(
        \\[
        \\  "\xD6\xD0".dup.force_encoding(Encoding::GB18030).valid_encoding?,
        \\  begin
        \\    "\xD6\xD0".dup.force_encoding(Encoding::GB18030).encode(Encoding::UTF_8)
        \\  rescue Encoding::UndefinedConversionError
        \\    :undefined
        \\  end
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(true, items[0].toBool());
    try std.testing.expect(items[1].isSymbol());
    try std.testing.expectEqualSlices(u8, "undefined", items[1].toSymbolObject().name);
}

test "ASCII-8BIT encoding compatibility raises before length check" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    // start_with? should raise even when needle is longer than receiver.
    const result = evalCodeWithOutput(
        "\"\\x80\".force_encoding('ASCII-8BIT').start_with?(\"\\xC3\\xA9\\xC3\\xA9\")",
        &stdout_buf,
        &stderr_buf,
    );
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "CompatibilityError") != null);
}
