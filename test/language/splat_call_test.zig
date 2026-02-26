const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

fn expectIntArray(val: @import("cora").value.Value, expected: []const i64) !void {
    try std.testing.expect(val.isArray());
    try std.testing.expectEqual(expected.len, val.toArrayObject().elements.items.len);
    for (expected, 0..) |want, i| {
        const got = val.toArrayObject().elements.items[i];
        try std.testing.expect(got.isInteger());
        try std.testing.expectEqual(want, got.toInteger());
    }
}

test "splat call basic expansion" {
    const result = try evalCode(
        \\def f(*a); a; end
        \\f(*[1, 2, 3])
    );
    try expectIntArray(result, &.{ 1, 2, 3 });
}

test "splat call mixed fixed and splat args" {
    const result = try evalCode(
        \\def f(a, b, c); [a, b, c]; end
        \\f(0, *[1, 2])
    );
    try expectIntArray(result, &.{ 0, 1, 2 });
}

test "splat call supports multiple splats" {
    const result = try evalCode(
        \\def f(*a); a; end
        \\f(*[1], *[2, 3])
    );
    try expectIntArray(result, &.{ 1, 2, 3 });
}

test "splat call empty array" {
    const result = try evalCode(
        \\def f(*a); a; end
        \\f(*[])
    );
    try expectIntArray(result, &.{});
}

test "splat call with keywords via CALL_KW" {
    var result = try evalCode(
        \\def f(*a, b:); [a, b]; end
        \\f(*[1, 2], b: 3)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expect(result.toArrayObject().elements.items[0].isArray());
    try expectIntArray(result.toArrayObject().elements.items[0], &.{ 1, 2 });
    try std.testing.expect(result.toArrayObject().elements.items[1].isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[1].toInteger());

    result = try evalCode(
        \\def g(a, b:, c:); [a, b, c]; end
        \\g(*[1], b: 2, c: 3)
    );
    try expectIntArray(result, &.{ 1, 2, 3 });
}

test "super with splat forwards args" {
    const result = try evalCode(
        \\class A
        \\  def foo(*args)
        \\    args
        \\  end
        \\end
        \\class B < A
        \\  def foo(arr)
        \\    super(*arr)
        \\  end
        \\end
        \\B.new.foo([1, 2, 3])
    );
    try expectIntArray(result, &.{ 1, 2, 3 });
}

test "splat argument must be Array" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def f(*a); a; end
        \\f(*1)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(@as(?anyerror, error.UnhandledException), result.err);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "TypeError") != null);
}
