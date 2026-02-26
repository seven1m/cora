const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "global variable basic assignment and read" {
    const result = try evalCode("$foo = 42; $foo");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "global variable initial value is nil" {
    const result = try evalCode("$undefined_var");
    try std.testing.expect(result.isNil());
}

test "global variables accessible across scopes" {
    const result = try evalCode(
        \\$global = 100
        \\def foo
        \\  $global = $global + 1
        \\end
        \\foo
        \\$global
    );
    try std.testing.expectEqual(@as(i64, 101), result.toInteger());
}
