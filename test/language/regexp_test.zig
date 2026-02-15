const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Regexp inspect" {
    const result = try evalCode("/hello/.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("/hello/", result.data.string.str);
}

test "Regexp with flags" {
    const result = try evalCode("/hello/i.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("/hello/i", result.data.string.str);
}

test "Regexp source" {
    const result = try evalCode("/hello/.source");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("hello", result.data.string.str);
}

test "Regexp options" {
    const result = try evalCode("/hello/i.options");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(1, result.data.integer);
}

test "Regexp options with multiple flags" {
    const result = try evalCode("/hello/im.options");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(5, result.data.integer);
}

test "Regexp casefold? true" {
    const result = try evalCode("/hello/i.casefold?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Regexp casefold? false" {
    const result = try evalCode("/hello/.casefold?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Regexp equality" {
    const result = try evalCode("/hello/ == /hello/");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Regexp inequality different pattern" {
    const result = try evalCode("/hello/ == /world/");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Regexp inequality different flags" {
    const result = try evalCode("/hello/ == /hello/i");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
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
        try std.testing.expect(result.value.data == .string);
    }
}

test "Regexp to_s" {
    const result = try evalCode("/hello/.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("(?-imx:hello)", result.data.string.str);
}

test "Regexp to_s with ignorecase flag" {
    const result = try evalCode("/hello/i.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("(?i-mx:hello)", result.data.string.str);
}

test "Regexp =~ returns match index" {
    const result = try evalCode("/a/ =~ \"cat\"");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Regexp =~ coerces Symbol argument" {
    const result = try evalCode("/a/ =~ :cat");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "Regexp =~ clears backref globals on no match" {
    const result = try evalCode(
        \\ /a/ =~ "cat"
        \\ /z/ =~ "cat"
        \\ $~
    );
    try std.testing.expect(result.data == .nil);
}

test "String =~ Regexp returns match index" {
    const result = try evalCode("\"cat\" =~ /a/");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "String =~ String raises TypeError" {
    const result = try evalCode(
        \\ begin
        \\   "cat" =~ "a"
        \\ rescue => e
        \\   e.instance_of?(TypeError)
        \\ end
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Regexp =~ sets backref globals and MatchData methods" {
    const result = try evalCode(
        \\ /(a)(b)?/ =~ "cabt"
        \\ [
        \\   $~.instance_of?(MatchData),
        \\   Regexp.last_match(0),
        \\   Regexp.last_match(1),
        \\   $~.captures,
        \\   $~.to_a,
        \\   $~.length,
        \\   $~.pre_match,
        \\   $~.post_match
        \\ ]
    );
    try std.testing.expect(result.data == .array);
    const items = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 8), items.len);
    try std.testing.expect(items[0].data == .boolean and items[0].data.boolean);
    try std.testing.expect(items[1].data == .string);
    try std.testing.expectEqualStrings("ab", items[1].data.string.str);
    try std.testing.expect(items[2].data == .string);
    try std.testing.expectEqualStrings("a", items[2].data.string.str);
    try std.testing.expect(items[3].data == .array);
    try std.testing.expect(items[4].data == .array);
    try std.testing.expect(items[5].data == .integer);
    try std.testing.expectEqual(@as(i64, 3), items[5].data.integer);
    try std.testing.expect(items[6].data == .string);
    try std.testing.expectEqualStrings("c", items[6].data.string.str);
    try std.testing.expect(items[7].data == .string);
    try std.testing.expectEqualStrings("t", items[7].data.string.str);
}
