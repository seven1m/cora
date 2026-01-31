const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Proc.call with parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\pr = Proc.new { |x| p x }
        \\pr.call(99)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqualSlices(u8, "99\n", result.stdout);
}

test "Proc.call captures variables from defining scope" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\x = 10
        \\pr = Proc.new { p x }
        \\pr.call
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqualSlices(u8, "10\n", result.stdout);
}

test "Proc closure: modifying captured variable in proc affects outer scope" {
    const result = try evalCode(
        \\def test_proc
        \\  yield
        \\end
        \\
        \\x = 5
        \\pr = Proc.new do
        \\  x = 10
        \\end
        \\pr.call
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}
