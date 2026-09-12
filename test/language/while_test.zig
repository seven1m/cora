const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "while loop - basic execution" {
    const result = try evalCode(
        \\x = 3
        \\while x == 3
        \\  x = x + 1
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - condition false from start" {
    const result = try evalCode(
        \\x = 10
        \\while false
        \\  x = 999
        \\end
        \\x
    );
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "while loop - empty body" {
    const result = try evalCode(
        \\while false
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - modifier form" {
    const result = try evalCode(
        \\x = 5
        \\x = x - 1 while x == 5
        \\x
    );
    try std.testing.expectEqual(@as(i64, 4), result.toInteger());
}

test "while begin modifier executes body before first condition check" {
    const result = try evalCode(
        \\x = 0
        \\begin
        \\  x = x + 1
        \\end while false
        \\x
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "until begin modifier executes body before first condition check" {
    const result = try evalCode(
        \\x = 0
        \\begin
        \\  x = x + 1
        \\end until true
        \\x
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "until modifier - local assigned in body readable by first condition check" {
    const result = try evalCode(
        \\ok = 1 until ok
        \\ok
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "while modifier - local assigned in body readable by first condition check" {
    const result = try evalCode(
        \\ok = 1 while !ok
        \\ok
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "while modifier - false condition skips body" {
    const result = try evalCode(
        \\x = 0
        \\x = x + 1 while false
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "until modifier - true condition skips body" {
    const result = try evalCode(
        \\x = 0
        \\x = x + 1 until true
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "until modifier - loops until condition true" {
    const result = try evalCode(
        \\i = 0
        \\i = i + 1 until i == 3
        \\i
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "while modifier - loops while condition true" {
    const result = try evalCode(
        \\x = 5
        \\x = x - 1 while x > 0
        \\x
    );
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "if modifier - local assigned in body readable by condition" {
    const result = try evalCode(
        \\x = 1 if x
        \\x
    );
    try std.testing.expect(result.isNil());
}

test "while loop - break without value" {
    const result = try evalCode(
        \\i = 0
        \\while true
        \\  i = i + 1
        \\  break if i == 3
        \\end
    );
    try std.testing.expect(result.isNil());
}

test "while loop - break with value" {
    const result = try evalCode(
        \\i = 0
        \\while true
        \\  i = i + 1
        \\  break 42 if i == 3
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "while loop - break in nested loop" {
    const result = try evalCode(
        \\outer = 0
        \\while outer == 0
        \\  outer = outer + 1
        \\  inner = 0
        \\  while inner == 0
        \\    inner = inner + 1
        \\    break 99 if inner == 2
        \\  end
        \\end
        \\outer
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "while loop - break returns expression value" {
    const result = try evalCode(
        \\x = 10
        \\while true
        \\  break x + 5
        \\end
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "while loop - next skips to the next iteration" {
    const result = try evalCode(
        \\i = 0
        \\out = []
        \\while i < 4
        \\  i = i + 1
        \\  next if i == 2
        \\  out << i
        \\end
        \\out
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 4), values[2].toInteger());
}

test "next outside loop raises SyntaxError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\next
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Invalid next") != null);
}
