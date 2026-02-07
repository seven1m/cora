const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "method with only rest parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(*args)
        \\  puts args.length
        \\end
        \\foo(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("3\n", result.stdout);
}

test "method with required and rest parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, *rest)
        \\  puts a
        \\  puts rest.length
        \\end
        \\foo(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n", result.stdout);
}

test "method with rest and post-required parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(*rest, b)
        \\  puts rest.length
        \\  puts b
        \\end
        \\foo(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("2\n3\n", result.stdout);
}

test "method with pre, rest, and post parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, *rest, b)
        \\  puts a
        \\  puts rest.length
        \\  puts b
        \\end
        \\foo(1, 2, 3, 4)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n4\n", result.stdout);
}

test "method with anonymous rest parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, *, b)
        \\  puts a
        \\  puts b
        \\end
        \\foo(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n3\n", result.stdout);
}

test "method with empty rest array" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, *rest, b)
        \\  puts rest.length
        \\end
        \\foo(1, 2)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("0\n", result.stdout);
}

test "block with only rest parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo
        \\  yield 1, 2, 3
        \\end
        \\foo { |*args| puts args.length }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("3\n", result.stdout);
}

test "block with required and rest parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo
        \\  yield 1, 2, 3
        \\end
        \\foo { |a, *rest| puts a; puts rest.length }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n", result.stdout);
}

test "block with rest and post-required parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo
        \\  yield 1, 2, 3
        \\end
        \\foo { |*rest, b| puts rest.length; puts b }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("2\n3\n", result.stdout);
}

test "block with anonymous rest parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo
        \\  yield 1, 2, 3
        \\end
        \\foo { |*| puts "ok" }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("ok\n", result.stdout);
}

test "lambda with rest parameter strict arity" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\l = ->(a, *rest, b) { puts a; puts rest.length; puts b }
        \\l.call(1, 2, 3, 4)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n4\n", result.stdout);
}

test "lambda with rest parameter minimum args" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\l = ->(a, *rest, b) { puts a; puts rest.length; puts b }
        \\l.call(1, 2)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n0\n2\n", result.stdout);
}

test "proc with rest parameter lenient arity" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\p = proc { |a, *rest, b| puts a; puts rest.length; puts b }
        \\p.call(1)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n0\n\n", result.stdout);
}

test "rest parameter captures correct elements" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(a, *rest, b)
        \\  rest.each { |x| puts x }
        \\end
        \\foo(1, 2, 3, 4)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("2\n3\n", result.stdout);
}

test "multiple rest parameters in different scopes" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def outer(*args1)
        \\  def inner(*args2)
        \\    puts args2.length
        \\  end
        \\  puts args1.length
        \\  inner(4, 5, 6)
        \\end
        \\outer(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("3\n3\n", result.stdout);
}

test "rest parameter with array iteration" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\def foo(*args)
        \\  args.each { |x| puts x }
        \\end
        \\foo(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "Proc.new with rest parameter" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\p = Proc.new { |a, *rest| puts a; puts rest.length }
        \\p.call(1, 2, 3)
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n2\n", result.stdout);
}

test "rest parameter in block passed to method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const code =
        \\[1, 2, 3].each { |*args| puts args.length }
    ;

    const result = evalCodeWithOutput(code, &stdout_buf, &stderr_buf);
    try std.testing.expectEqualStrings("1\n1\n1\n", result.stdout);
}
