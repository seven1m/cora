const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "block break - basic with value" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break 42 if x == 2
        \\  x
        \\end
        \\result
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "block break - without value returns nil" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break if x == 1
        \\end
        \\result
    );
    try std.testing.expect(result.data == .nil);
}

test "block break - stops execution immediately" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\end
        \\
        \\each_test do |x|
        \\  break if x == 2
        \\  puts x
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - method doesn't continue after yield" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def test_method
        \\  puts 1
        \\  yield
        \\  puts 2
        \\  yield
        \\  puts 3
        \\end
        \\
        \\test_method do
        \\  break
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    // Should only print 1, not 2 or 3
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - nested blocks use innermost" {
    const result = try evalCode(
        \\def outer
        \\  yield
        \\  99
        \\end
        \\
        \\def inner
        \\  yield
        \\  88
        \\end
        \\
        \\result = outer do
        \\  inner do
        \\    break 42
        \\  end
        \\end
        \\result
    );
    // Break from inner block should return 42 from inner, not outer
    // Outer continues and returns 99
    try std.testing.expectEqual(@as(i64, 99), result.data.integer);
}

test "block break - different from loop break" {
    const result = try evalCode(
        \\def test
        \\  yield
        \\  77
        \\end
        \\
        \\result = test do
        \\  x = 0
        \\  while x == 0
        \\    x = 1
        \\    break
        \\  end
        \\  55
        \\end
        \\result
    );
    // Loop break exits loop, block continues and returns 55 to yield,
    // but the method continues and returns 77
    try std.testing.expectEqual(@as(i64, 77), result.data.integer);
}
