const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Regexp match predicate preserves backreferences and supports capture-dependent patterns" {
    const result = try evalCode(
        \\/(saved)/.match("saved")
        \\previous = $~
        \\checks = [
        \\  /(a)\1/.match?("aa"),
        \\  !/(a)\1/.match?("ab"),
        \\  /(?<word>ab)\k<word>/.match?("abab"),
        \\  /(?<=a)b/.match?("ab"),
        \\  /(x)?y/.match?("y"),
        \\  "abab".match?(/(ab)\1/),
        \\  !/x/.match?(nil),
        \\  !/x/.match?("x", 2)
        \\]
        \\checks.all? && $~.equal?(previous) && $1 == "saved" && $& == "saved"
    );
    try std.testing.expect(result.isTrue());
}

test "Regexp match predicate handles character offsets and coerced sources" {
    const result = try evalCode(
        \\source = Object.new
        \\def source.to_str; "éab"; end
        \\position = Object.new
        \\def position.to_int; 1; end
        \\checks = [
        \\  /a/.match?(source, position),
        \\  /a/.match?("éab", -2),
        \\  !/a/.match?("éab", 2),
        \\  !/a/.match?("éab", -4),
        \\  /$/.match?("éab", 3),
        \\  !/$/.match?("éab", 4),
        \\  /ab/.match?(:abc),
        \\  /./.match?("\xE9".force_encoding("ISO-8859-1"))
        \\]
        \\checks.all?
    );
    try std.testing.expect(result.isTrue());
}

test "Regexp literals reuse identity per site while interpolation stays dynamic" {
    const result = try evalCode(
        \\def literal; /cache-me/i; end
        \\def other_literal; /cache-me/i; end
        \\def dynamic(text); /#{text}/; end
        \\first = literal
        \\300.times { |i| Regexp.new("unrelated-#{i}") }
        \\GC.start
        \\20.times do |i|
        \\  raise "stale eval literal" unless eval("/pattern-#{i}/").source == "pattern-#{i}"
        \\end
        \\first.equal?(literal) && first.frozen? && !first.equal?(other_literal) &&
        \\  first.match?("CACHE-ME") && !dynamic("x").equal?(dynamic("x")) &&
        \\  dynamic("x").source == "x" && dynamic("y").source == "y"
    );
    try std.testing.expect(result.isTrue());
}

test "Regexp matching preserves encoding and MatchData across cached variants" {
    const result = try evalCode(
        \\regexp = /./
        \\sources = ["é", "\xE9".force_encoding("ISO-8859-1"), "abc".b, "xyz".force_encoding("US-ASCII")]
        \\20.times do
        \\  sources.each do |source|
        \\    match = regexp.match(source)
        \\    raise "match identity" unless match.regexp.equal?(regexp)
        \\    raise "character boundary" unless match[0] == source[0]
        \\    raise "match encoding" unless match[0].encoding == source.encoding
        \\    raise "match predicate" unless regexp.match?(source)
        \\    raise "match operator" unless (regexp =~ source) == 0
        \\    raise "forward search" unless source.index(regexp) == 0
        \\    raise "reverse search" unless source.rindex(regexp) == source.length - 1
        \\    raise "scan" unless source.scan(regexp) == source.chars
        \\    raise "sub" unless source.sub(regexp, "_") == "_" + source[1..-1]
        \\    raise "gsub" unless source.gsub(regexp, "_") == "_" * source.length
        \\  end
        \\  GC.start
        \\end
        \\begin
        \\  regexp.match?("\xFF".force_encoding("UTF-8"))
        \\  raise "invalid encoding accepted"
        \\rescue ArgumentError
        \\end
        \\regexp.encoding == Encoding::US_ASCII && regexp.source == "." && regexp.options == 0
    );
    try std.testing.expect(result.isTrue());
}

test "MatchData integer_at handles named captures and conversion boundaries" {
    const result = try evalCode(
        \\m = /(?<number>12x)(?<missing>z)?/.match("12x")
        \\[m.integer_at(:number), m.integer_at("number", 16), m.integer_at(:missing),
        \\ m.integer_at(-1), m.integer_at(-2), m.integer_at(-3), m.integer_at(99, 1),
        \\ (begin m.integer_at(:absent); rescue IndexError; :missing_name; end),
        \\ (begin m.integer_at(0, 1); rescue ArgumentError; :invalid_base; end)]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 12), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 18), values[1].toInteger());
    try std.testing.expect(values[2].isNil());
    try std.testing.expect(values[3].isNil());
    try std.testing.expectEqual(@as(i64, 12), values[4].toInteger());
    try std.testing.expect(values[5].isNil());
    try std.testing.expect(values[6].isNil());
    try std.testing.expectEqualStrings("missing_name", values[7].toSymbolObject().name);
    try std.testing.expectEqualStrings("invalid_base", values[8].toSymbolObject().name);
}

test "$+ returns the last non-nil regexp capture during scan" {
    const result = try evalCode(
        \\captures = []
        \\"ab".scan(/(a)(b)?/) { captures << $+ }
        \\"a".scan(/(a)(b)?/) { captures << $+ }
        \\captures
    );
    const captures = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("b", captures[0].toStringObject().str);
    try std.testing.expectEqualStrings("a", captures[1].toStringObject().str);
}

test "MatchData keeps its source string after the original is mutated" {
    const result = try evalCode(
        \\source = "abc"
        \\match = /b/.match(source)
        \\source.replace("x")
        \\[match.string, match[0], match.pre_match, match.post_match, $~.string]
    );
    const values = result.toArrayObject().elements.items;
    const expected = [_][]const u8{ "abc", "b", "a", "c", "abc" };
    for (values, expected) |value_, string| {
        try std.testing.expectEqualStrings(string, value_.toStringObject().str);
    }
}

test "Regexp inspect" {
    const result = try evalCode("/hello/.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("/hello/", result.toStringObject().str);
}

test "Regexp with flags" {
    const result = try evalCode("/hello/i.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("/hello/i", result.toStringObject().str);
}

test "Regexp source" {
    const result = try evalCode("/hello/.source");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("hello", result.toStringObject().str);
}

test "Regexp options" {
    const result = try evalCode("/hello/i.options");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(1, result.toInteger());
}

test "Regexp options with multiple flags" {
    const result = try evalCode("/hello/im.options");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(5, result.toInteger());
}

test "Regexp casefold? true" {
    const result = try evalCode("/hello/i.casefold?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Regexp casefold? false" {
    const result = try evalCode("/hello/.casefold?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Regexp equality" {
    const result = try evalCode("/hello/ == /hello/");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Regexp inequality different pattern" {
    const result = try evalCode("/hello/ == /world/");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Regexp inequality different flags" {
    const result = try evalCode("/hello/ == /hello/i");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Invalid regexp raises RegexpError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  /(/
        \\rescue RegexpError => e
        \\  e.message
        \\end
    , &stdout_buf, &stderr_buf);

    if (result.err) |_| {
        // The error should have been caught by rescue
        try std.testing.expect(false);
    } else {
        try std.testing.expect(result.value.isString());
    }
}

test "Regexp to_s" {
    const result = try evalCode("/hello/.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("(?-mix:hello)", result.toStringObject().str);
}

test "Regexp to_s with ignorecase flag" {
    const result = try evalCode("/hello/i.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("(?i-mx:hello)", result.toStringObject().str);
}

test "Regexp =~ returns match index" {
    const result = try evalCode("/a/ =~ \"cat\"");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Regexp =~ with a named capture returns match index" {
    const result = try evalCode(
        \\result = /(?<word>bar)/ =~ "bar"
        \\[result, word]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), values[0].toInteger());
    try std.testing.expectEqualStrings("bar", values[1].toStringObject().str);
}

test "Regexp =~ assigns multiple named capture locals" {
    const result = try evalCode(
        \\/(?<matched>foo)(?<unmatched>bar)?/ =~ "foofoo"
        \\[matched, unmatched]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("foo", values[0].toStringObject().str);
    try std.testing.expect(values[1].isNil());
}

test "Regexp =~ coerces Symbol argument" {
    const result = try evalCode("/a/ =~ :cat");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Regexp =~ clears backref globals on no match" {
    const result = try evalCode(
        \\ /a/ =~ "cat"
        \\ /z/ =~ "cat"
        \\ [$~, $1]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expect(items[0].isNil());
    try std.testing.expect(items[1].isNil());
}

test "String =~ Regexp returns match index" {
    const result = try evalCode("\"cat\" =~ /a/");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "String =~ String raises TypeError" {
    const result = try evalCode(
        \\ begin
        \\   "cat" =~ "a"
        \\ rescue => e
        \\   e.instance_of?(TypeError)
        \\ end
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Regexp =~ sets backref globals and MatchData methods" {
    const result = try evalCode(
        \\ /(a)(b)?/ =~ "cabt"
        \\ [
        \\   $~.instance_of?(MatchData),
        \\   $1,
        \\   $2,
        \\   $3,
        \\   Regexp.last_match(0),
        \\   Regexp.last_match(1),
        \\   $~.captures,
        \\   $~.to_a,
        \\   $~.length,
        \\   $~.pre_match,
        \\   $~.post_match
        \\ ]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 11), items.len);
    try std.testing.expect(items[0].isBool() and items[0].toBool());
    try std.testing.expect(items[1].isString());
    try std.testing.expectEqualStrings("a", items[1].toStringObject().str);
    try std.testing.expect(items[2].isString());
    try std.testing.expectEqualStrings("b", items[2].toStringObject().str);
    try std.testing.expect(items[3].isNil());
    try std.testing.expect(items[4].isString());
    try std.testing.expectEqualStrings("ab", items[4].toStringObject().str);
    try std.testing.expect(items[5].isString());
    try std.testing.expectEqualStrings("a", items[5].toStringObject().str);
    try std.testing.expect(items[6].isArray());
    try std.testing.expect(items[7].isArray());
    try std.testing.expect(items[8].isInteger());
    try std.testing.expectEqual(@as(i64, 3), items[8].toInteger());
    try std.testing.expect(items[9].isString());
    try std.testing.expectEqualStrings("c", items[9].toStringObject().str);
    try std.testing.expect(items[10].isString());
    try std.testing.expectEqualStrings("t", items[10].toStringObject().str);
}

test "Regexp === updates match globals in case expressions" {
    const result = try evalCode(
        \\ case "mswin32"
        \\ when /(mswin\d+)(?:[_-](\d+))?/
        \\   [
        \\     $~.instance_of?(MatchData),
        \\     $1,
        \\     $2,
        \\     Regexp.last_match(0),
        \\     Regexp.last_match(1),
        \\     Regexp.last_match(2)
        \\   ]
        \\ else
        \\   :no_match
        \\ end
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 6), items.len);
    try std.testing.expect(items[0].isBool() and items[0].toBool());
    try std.testing.expect(items[1].isString());
    try std.testing.expectEqualStrings("mswin32", items[1].toStringObject().str);
    try std.testing.expect(items[2].isNil());
    try std.testing.expect(items[3].isString());
    try std.testing.expectEqualStrings("mswin32", items[3].toStringObject().str);
    try std.testing.expect(items[4].isString());
    try std.testing.expectEqualStrings("mswin32", items[4].toStringObject().str);
    try std.testing.expect(items[5].isNil());
}
