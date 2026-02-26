const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "case expression with predicate chooses matching when" {
    const result = try evalCode(
        \\case 2
        \\when 1
        \\  10
        \\when 2
        \\  20
        \\else
        \\  30
        \\end
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "case expression without predicate uses truthiness" {
    const result = try evalCode(
        \\case
        \\when false
        \\  10
        \\when 7
        \\  20
        \\else
        \\  30
        \\end
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "case returns nil when nothing matches and no else" {
    const result = try evalCode(
        \\case 5
        \\when 1
        \\  10
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "case supports comma-separated when conditions" {
    const result = try evalCode(
        \\case 3
        \\when 1, 2
        \\  10
        \\when 3, 4
        \\  20
        \\else
        \\  30
        \\end
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "case evaluates predicate once" {
    const result = try evalCode(
        \\x = 0
        \\case (x = x + 1)
        \\when 1
        \\  x
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "case evaluates predicate once and when conditions left-to-right" {
    const result = try evalCode(
        \\x = 0
        \\y = (x = x + 1)
        \\case 3
        \\when (x = x + 1), (x = x + 1), (x = x + 1)
        \\  x
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "case when and else empty bodies return nil" {
    var result = try evalCode(
        \\case 1
        \\when 1 then
        \\else
        \\  9
        \\end
    );
    try std.testing.expect(result.isNil());

    result = try evalCode(
        \\case 2
        \\when 1
        \\  9
        \\else
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "case matching works with Module#=== Class/Range/Regexp" {
    var result = try evalCode(
        \\case "hello"
        \\when String
        \\  1
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());

    result = try evalCode(
        \\case 4
        \\when 1..5
        \\  1
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());

    result = try evalCode(
        \\case "abc"
        \\when /b/
        \\  1
        \\else
        \\  0
        \\end
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}
