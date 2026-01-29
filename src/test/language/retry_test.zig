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
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
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
    try std.testing.expectEqual(@as(i64, 42), result.value.data.integer);

    // Ensure should run only once (after successful completion)
    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}
