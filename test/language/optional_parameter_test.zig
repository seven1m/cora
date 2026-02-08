const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "method with one optional parameter - provided" {
    const result = try evalCode("def foo(a, b=10); a + b; end; foo(5, 3)");
    try std.testing.expectEqual(@as(i64, 8), result.data.integer);
}

test "method with one optional parameter - default used" {
    const result = try evalCode("def foo(a, b=10); a + b; end; foo(5)");
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "method with multiple optional parameters - all provided" {
    const result = try evalCode("def foo(a, b=10, c=20); a + b + c; end; foo(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 6), result.data.integer);
}

test "method with multiple optional parameters - partial defaults" {
    const result = try evalCode("def foo(a, b=10, c=20); a + b + c; end; foo(1, 2)");
    try std.testing.expectEqual(@as(i64, 23), result.data.integer);
}

test "method with multiple optional parameters - all defaults" {
    const result = try evalCode("def foo(a, b=10, c=20); a + b + c; end; foo(1)");
    try std.testing.expectEqual(@as(i64, 31), result.data.integer);
}

test "optional parameter with expression default" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(x=[])
        \\  x << 1
        \\  x.length
        \\end
        \\puts foo()
        \\puts foo()
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n1\n", result.stdout);
}

test "optional parameter referencing earlier parameter" {
    const result = try evalCode("def foo(x, y=x+1); x + y; end; foo(5)");
    try std.testing.expectEqual(@as(i64, 11), result.data.integer);
}

test "optional parameter referencing earlier optional with default" {
    const result = try evalCode("def foo(x=42, y=x); x == y; end; foo()");
    try std.testing.expect(result.data == .boolean and result.data.boolean == true);
}

test "required, optional, and rest parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, b=10, *rest)
        \\  puts a
        \\  puts b
        \\  puts rest.length
        \\end
        \\foo(1, 2, 3, 4)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n2\n", result.stdout);
}

test "required, optional, rest, and post parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, b=10, *rest, z)
        \\  puts a
        \\  puts b
        \\  puts rest.length
        \\  puts z
        \\end
        \\foo(1, 2, 3, 4)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n1\n4\n", result.stdout);
}

test "lambda with optional parameter strict arity - default used" {
    const result = try evalCode("l = ->(a, b=10) { a + b }; l.call(5)");
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "lambda with optional parameter strict arity - provided" {
    const result = try evalCode("l = ->(a, b=10) { a + b }; l.call(5, 3)");
    try std.testing.expectEqual(@as(i64, 8), result.data.integer);
}

test "lambda with optional parameter too many args raises error" {
    try std.testing.expectError(
        error.UnhandledException,
        evalCode("l = ->(a, b=10) { a + b }; l.call(5, 3, 7)"),
    );
}

test "proc with optional parameter lenient arity" {
    const result = try evalCode("p = proc { |a, b=10| a + b }; p.call(5)");
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "block with optional parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo
        \\  yield 5
        \\end
        \\foo { |a, b=10| puts a + b }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("15\n", result.stdout);
}

test "optional parameter minimum args" {
    const result = try evalCode("def foo(a, b=10, c=20); a; end; foo(5)");
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "optional parameter with rest - defaults used" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, b=10, *rest)
        \\  puts a
        \\  puts b
        \\  puts rest.length
        \\end
        \\foo(1)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n10\n0\n", result.stdout);
}

test "only optional parameters" {
    const result = try evalCode("def foo(a=5, b=10); a + b; end; foo()");
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "only optional parameters - one provided" {
    const result = try evalCode("def foo(a=5, b=10); a + b; end; foo(3)");
    try std.testing.expectEqual(@as(i64, 13), result.data.integer);
}

test "default expression side-effect locals visible in method body" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def bar
        \\  42
        \\end
        \\def foo(a=(x=23), b=bar)
        \\  p [a, x, b]
        \\end
        \\foo
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("[23, 23, 42]\n", result.stdout);
}

test "default expression side-effect locals are nil when default not used" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a=(x=23))
        \\  p [a, x]
        \\end
        \\foo(5)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("[5, nil]\n", result.stdout);
}
