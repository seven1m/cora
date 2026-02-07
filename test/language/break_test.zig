const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "break outside loop - should error" {
    const result = evalCode(
        \\break
    );
    try std.testing.expectError(error.BreakOutsideLoop, result);
}

test "break outside loop with value - should error" {
    const result = evalCode(
        \\x = 5
        \\break x
    );
    try std.testing.expectError(error.BreakOutsideLoop, result);
}
