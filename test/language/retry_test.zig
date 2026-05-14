const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Retry basic - retry until counter reaches target" {
    const result = try evalCode(
        \\count = 0
        \\begin
        \\  count = count + 1
        \\  if count == 3
        \\    10
        \\  else
        \\    raise "error"
        \\  end
        \\rescue
        \\  retry
        \\end
    );
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "Retry with ensure clause" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\count = 0
        \\begin
        \\  count = count + 1
        \\  if count == 2
        \\    42
        \\  else
        \\    raise "retry"
        \\  end
        \\rescue
        \\  retry
        \\ensure
        \\  puts "cleanup"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 42), result.value.toInteger());

    // Ensure should run only once (after successful completion)
    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Retry outside rescue errors at compile/eval" {
    try std.testing.expectError(error.RetryOutsideRescue, evalCode("retry"));
    try std.testing.expectError(error.RetryOutsideRescue, evalCode(
        \\begin
        \\  retry
        \\end
    ));
}

test "Retry targets innermost rescue" {
    const result = try evalCode(
        \\outer = 0
        \\inner = 0
        \\begin
        \\  outer = outer + 1
        \\  raise "outer" if outer == 1
        \\rescue
        \\  begin
        \\    inner = inner + 1
        \\    raise "inner" if inner == 1
        \\  rescue
        \\    retry
        \\  end
        \\end
        \\outer * 10 + inner
    );
    try std.testing.expectEqual(@as(i64, 12), result.toInteger());
}

test "Retry runs intervening ensure before restarting protected body" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\count = 0
        \\begin
        \\  raise "outer"
        \\rescue
        \\  begin
        \\    count = count + 1
        \\    puts count
        \\    retry if count < 2
        \\  ensure
        \\    puts "inner_ensure"
        \\  end
        \\end
        \\count
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 2), result.value.toInteger());
    try std.testing.expectEqualSlices(u8, "1\ninner_ensure\n2\ninner_ensure\n", result.stdout);
}

test "Retry in method called from rescue errors instead of retrying caller rescue" {
    try std.testing.expectError(error.RetryOutsideRescue, evalCode(
        \\def inner
        \\  retry
        \\end
        \\begin
        \\  raise "boom"
        \\rescue
        \\  inner
        \\end
    ));
}

test "Retry in proc called from rescue matches MRI invalid retry behavior" {
    try std.testing.expectError(error.RetryOutsideRescue, evalCode(
        \\begin
        \\  raise "boom"
        \\rescue
        \\  Proc.new { retry }.call
        \\end
    ));
}
