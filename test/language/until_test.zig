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

test "until loop - break without value" {
    const result = try evalCode(
        \\i = 0
        \\until false
        \\  i = i + 1
        \\  break if i == 3
        \\end
    );
    try std.testing.expect(result.data == .nil);
}

test "until loop - break with value" {
    const result = try evalCode(
        \\i = 0
        \\until false
        \\  i = i + 1
        \\  break 42 if i == 3
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "until loop - break in nested loop" {
    const result = try evalCode(
        \\outer = 0
        \\until outer == 5
        \\  outer = outer + 1
        \\  inner = 0
        \\  until inner == 5
        \\    inner = inner + 1
        \\    break 99 if inner == 2
        \\  end
        \\end
        \\outer
    );
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "until loop - break returns expression value" {
    const result = try evalCode(
        \\x = 10
        \\until false
        \\  break x + 5
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}
