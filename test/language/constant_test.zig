const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Constants can be set and read" {
    const result = try evalCode(
        \\FOO = 42
        \\FOO
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Constant path: simple module constant" {
    const result = try evalCode(
        \\module A
        \\  X = 42
        \\end
        \\A::X
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Constant path: nested modules" {
    const result = try evalCode(
        \\module A
        \\  module B
        \\    Y = 99
        \\  end
        \\end
        \\A::B::Y
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Constant path: class constant" {
    const result = try evalCode(
        \\class C
        \\  Z = 123
        \\end
        \\C::Z
    );
    try std.testing.expectEqual(@as(i64, 123), result.toInteger());
}

test "Lexical scope: nested module constants" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\X = 999
        \\module A
        \\  X = 42
        \\  puts X
        \\end
        \\puts X
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqualSlices(u8, "42\n999\n", result.stdout);
}

test "Lexical scope: class with method finding outer constant" {
    const result = try evalCode(
        \\Y = 999
        \\class C
        \\  Y = 42
        \\  def get_y
        \\    Y
        \\  end
        \\end
        \\C.new.get_y
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Lexical scope: top-level fallback" {
    const result = try evalCode(
        \\X = 100
        \\class A
        \\  def get_x
        \\    X
        \\  end
        \\end
        \\A.new.get_x
    );
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "Unknown constant raises NameError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "UnknownConstant",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, error.UnhandledException), result.err);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "uninitialized constant UnknownConstant") != null);
}
