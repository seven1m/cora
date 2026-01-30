const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "until loop - returns nil" {
    const result = try evalCode(
        \\result = until true
        \\  42
        \\end
        \\result
    );
    try std.testing.expect(result.data == .nil);
}

test "until loop - condition true from start" {
    const result = try evalCode(
        \\x = 10
        \\until true
        \\  x = 999
        \\end
        \\x
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "until loop - empty body" {
    const result = try evalCode(
        \\until true
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "until loop - modifier form" {
    const result = try evalCode(
        \\x = 0
        \\x = x + 1 until x == 3
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "until loop - executes at least once when condition false" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\x = 0
        \\until x == 1
        \\  puts x
        \\  x = x + 1
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    try std.testing.expect(eval_result.value.data == .nil);
    try std.testing.expectEqualStrings("0\n", eval_result.stdout);
}

