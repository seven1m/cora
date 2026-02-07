const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Exception#message returns message string" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError, "my message"
        \\rescue => e
        \\  e.message
        \\end
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "my message", result.data.string.str);
}
