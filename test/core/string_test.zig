const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "String#inspect basic" {
    const result = try evalCode("\"hello\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"hello\"", result.toStringObject().str);
}

test "String#inspect with quotes" {
    const result = try evalCode("\"say \\\"hi\\\"\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"say \\\"hi\\\"\"", result.toStringObject().str);
}

test "String#inspect with newline" {
    const result = try evalCode("\"hello\\nworld\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"hello\\nworld\"", result.toStringObject().str);
}

test "String#inspect with tab" {
    const result = try evalCode("\"hello\\tworld\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"hello\\tworld\"", result.toStringObject().str);
}

test "String#inspect with backslash" {
    const result = try evalCode("\"path\\\\to\\\\file\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"path\\\\to\\\\file\"", result.toStringObject().str);
}

test "String#inspect empty string" {
    const result = try evalCode("\"\".inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\"\"", result.toStringObject().str);
}

test "String#to_s" {
    const result = try evalCode("'hello'.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "String#to_str" {
    const result = try evalCode("'hello'.to_str");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "String#initialize_copy is private and String#dup dispatches through method_missing after undef_method" {
    var result = try evalCode("\"x\".respond_to?(:initialize_copy, true)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("\"x\".send(:initialize_copy, \"y\") == \"y\"");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode(
        \\class InitCopyMissingString < String
        \\  undef_method :initialize_copy
        \\
        \\  def respond_to_missing?(name, include_private = false)
        \\    name == :initialize_copy
        \\  end
        \\
        \\  def method_missing(name, *args)
        \\    replace("mm")
        \\  end
        \\end
        \\
        \\source = InitCopyMissingString.new("x")
        \\duped = source.dup
        \\[duped == "mm", duped.class == InitCopyMissingString]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
}

test "String#<=> inverse fallback recursion is pair-specific" {
    const result = try evalCode(
        \\$other = Object.new
        \\def $other.<=>(_x)
        \\  1
        \\end
        \\
        \\obj = Object.new
        \\def obj.<=>(x)
        \\  $nested_result = ("b" <=> $other)
        \\  x <=> self
        \\end
        \\
        \\("a" <=> obj).nil? && $nested_result == -1
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "String#+ concatenates two strings" {
    const result = try evalCode("\"Hello, \" + \"world!\"");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "Hello, world!", result.toStringObject().str);
}

test "String#+ concatenates multiple strings" {
    const result = try evalCode("\"a\" + \"b\" + \"c\"");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "abc", result.toStringObject().str);
}

test "String#+ TypeError for non-string receiver" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "1 + \"hello\"",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
}

test "String#+ TypeError for non-string argument" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "\"hello\" + 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
}

test "String#+ coerces argument via to_str" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.to_str
        \\  " world"
        \\end
        \\"hello" + obj
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello world", result.toStringObject().str);
}

test "String#+ raises TypeError when to_str returns non-string" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\obj = Object.new
        \\def obj.to_str
        \\  123
        \\end
        \\"hello" + obj
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
}

test "String#length and String#size" {
    var result = try evalCode("'hello'.length");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());

    result = try evalCode("'hello'.size");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "String#unicode_normalize accepts standard forms and returns a copy" {
    const result = try evalCode(
        \\s = "Cafe"
        \\t = s.unicode_normalize(:nfc)
        \\[t, t == s, t.equal?(s), s.unicode_normalize("nfkc")]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, "Cafe", items[0].toStringObject().str);
    try std.testing.expectEqual(true, items[1].toBool());
    try std.testing.expectEqual(false, items[2].toBool());
    try std.testing.expectEqualSlices(u8, "Cafe", items[3].toStringObject().str);
}

test "String#unicode_normalize rejects invalid form" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "\"x\".unicode_normalize(:bogus)",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "String#count" {
    var result = try evalCode("'hello'.count('lo')");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());

    result = try evalCode("'hello'.count('lo', '^o')");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "String#[] with integer index" {
    var result = try evalCode("'hello'[0]");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "h", result.toStringObject().str);

    result = try evalCode("'hello'[-1]");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "o", result.toStringObject().str);

    result = try evalCode("'hello'[99]");
    try std.testing.expect(result.isNil());
}

test "String#[] with range slice" {
    var result = try evalCode("'hello world'[0...5]");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);

    result = try evalCode("'hello world'[6..-1]");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "world", result.toStringObject().str);

    result = try evalCode("'hello'[20..25]");
    try std.testing.expect(result.isNil());
}

test "String#<< appends string and codepoint" {
    var result = try evalCode("s = 'ab'; s << 'cd'; s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "abcd", result.toStringObject().str);

    result = try evalCode("s = 'A'; s << 66; s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "AB", result.toStringObject().str);
}

test "String#start_with? and #end_with?" {
    var result = try evalCode("'|abc'.start_with?('|')");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("\"line\\n\".end_with?(\"\\n\")");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("'hello'.start_with?('x')");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "String#prepend" {
    var result = try evalCode("s = 'world'; s.prepend('hello '); s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello world", result.toStringObject().str);

    result = try evalCode("s = 'world'; s.prepend('he', '', 'llo '); s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello world", result.toStringObject().str);
}

test "String#upcase" {
    var result = try evalCode("'hello'.upcase");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "HELLO", result.toStringObject().str);

    result = try evalCode("'a1b!'.upcase");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "A1B!", result.toStringObject().str);
}

test "String#to_i" {
    var result = try evalCode("'123abc'.to_i");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 123), result.toInteger());

    result = try evalCode("'  -10x'.to_i");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, -10), result.toInteger());

    result = try evalCode("'ff'.to_i(16)");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 255), result.toInteger());

    result = try evalCode("'18446744073709551616'.to_i");
    try std.testing.expect(result.isBigInteger());

    result = try evalCode("'1_2_3_4'.to_i");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 1234), result.toInteger());
}

test "String#to_sym" {
    const result = try evalCode("'hello'.to_sym.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "String#chomp removes default line endings and explicit separator" {
    var result = try evalCode("\"a\\n\".chomp");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "a", result.toStringObject().str);

    result = try evalCode("\"a\\r\\n\".chomp");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "a", result.toStringObject().str);

    result = try evalCode("\"a/\".chomp(?/)");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "a", result.toStringObject().str);
}

test "String#chars propagates break value" {
    var result = try evalCode("'abc'.chars { |c| break :done if c == 'b' }");
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "done", result.toSymbolObject().name);

    result = try evalCode("'abc'.chars { break }");
    try std.testing.expect(result.isNil());
}

test "String#unpack integer and float directives" {
    var result = try evalCode("\"\\x01\\x02\".b.unpack('C2').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2]", result.toStringObject().str);

    result = try evalCode("\"\".b.unpack('C2').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[nil, nil]", result.toStringObject().str);

    result = try evalCode("[1.5].pack('d').unpack('d')[0]");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.toFloatObject().val, 0.0000001);
}

test "String#unpack string directives" {
    var result = try evalCode("\"A \\x00\".b.unpack('A3').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[\"A\"]", result.toStringObject().str);

    result = try evalCode("\"abc\\x00xyz\".b.unpack('Z*').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[\"abc\"]", result.toStringObject().str);
}

test "String.new accepts encoding and capacity keywords" {
    var result = try evalCode("String.new.encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ASCII-8BIT", result.toStringObject().str);

    result = try evalCode("String.new(\"abc\", encoding: \"US-ASCII\", capacity: 100_000).encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "US-ASCII", result.toStringObject().str);
}

test "Builtin methods reject keywords unless consumed" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "String.new('', encoding: 'UTF-8', nope: 1)",
        &stdout_buf,
        &stderr_buf,
    );
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown keyword: nope") != null);
}
