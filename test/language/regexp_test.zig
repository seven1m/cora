const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

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
