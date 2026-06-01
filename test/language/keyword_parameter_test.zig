const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Required keyword argument" {
    const result = try evalCode("def foo(x:); x * 2; end\nfoo(x: 21)");
    try std.testing.expectEqual(42, result.toInteger());
}

test "Required keyword missing raises error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("def foo(x:); x; end\nfoo()", &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "missing") != null and
        std.mem.indexOf(u8, result.stderr, "keyword") != null);
}

test "Optional keyword with default" {
    const result = try evalCode("def bar(y: 100); y; end\nbar()");
    try std.testing.expectEqual(100, result.toInteger());
}

test "Optional keyword overridden" {
    const result = try evalCode("def bar(y: 100); y; end\nbar(y: 5)");
    try std.testing.expectEqual(5, result.toInteger());
}

test "Mixed positional and keyword args" {
    const result = try evalCode(
        \\def qux(a, b:, c: 3); [a, b, c]; end
        \\qux(10, b: 20)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(10, result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(20, result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(3, result.toArrayObject().elements.items[2].toInteger());
}

test "Keyword rest collects extra keywords" {
    const result = try evalCode(
        \\def baz(**opts); opts; end
        \\baz(a: 1, b: 2)
    );
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);
}

test "No keywords parameter rejects keywords" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\def bar(**nil); 42; end
        \\bar(x: 1)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "does not accept keyword") != null);
}

test "Unknown keyword without rest raises error" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\def foo(a:); a; end
        \\foo(a: 1, b: 2)
    , &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown keyword") != null);
}

test "Keywords matched by name not position" {
    const result = try evalCode(
        \\def foo(a:, b:); [a, b]; end
        \\foo(b: 2, a: 1)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(1, result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(2, result.toArrayObject().elements.items[1].toInteger());
}

test "Keyword with positional arguments" {
    const result = try evalCode(
        \\def foo(x, y:); x + y; end
        \\foo(10, y: 32)
    );
    try std.testing.expectEqual(42, result.toInteger());
}

test "Keyword argument omission uses local variable value" {
    const result = try evalCode(
        \\def foo(token:); token; end
        \\token = 42
        \\foo(token:)
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Multiple optional keywords" {
    const result = try evalCode(
        \\def foo(a: 1, b: 2, c: 3); a + b + c; end
        \\foo(b: 10)
    );
    try std.testing.expectEqual(14, result.toInteger());
}

test "Empty keyword rest hash" {
    const result = try evalCode(
        \\def foo(a:, **opts); opts; end
        \\foo(a: 1)
    );
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(0, result.toHashObject().entries.items.len);
}

test "define_method block with keyword rest receives empty hash when no kwargs passed" {
    const result = try evalCode(
        \\klass = Class.new
        \\klass.define_method(:greet) {|*messages, **kw| kw }
        \\klass.new.greet("hello")
    );
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(0, result.toHashObject().entries.items.len);
}

test "Multiple optional keywords called with no arguments" {
    const result = try evalCode(
        \\def foo(a: 10, b: 20, c: 30); a + b + c; end
        \\foo()
    );
    try std.testing.expectEqual(60, result.toInteger());
}

test "non-local return in optional keyword default targets enclosing method" {
    const result = try evalCode(
        \\def foo(value: (proc { return 42 }.call))
        \\  99
        \\end
        \\foo
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "non-local return in optional keyword default does not corrupt caller locals" {
    const result = try evalCode(
        \\def foo(value: (proc { return 42 }.call), **kw)
        \\  99
        \\end
        \\def bar
        \\  a = 1
        \\  b = 2
        \\  foo()
        \\  a + b
        \\end
        \\bar()
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "Keyword syntax becomes positional hash when method has no keyword params" {
    var result = try evalCode(
        \\def foo(opts); opts; end
        \\foo(a: 1, b: 2)
    );
    try std.testing.expect(result.isHash());
    try std.testing.expectEqual(2, result.toHashObject().entries.items.len);

    result = try evalCode(
        \\def bar(*args); args; end
        \\bar(a: 1)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 1), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isHash());
    try std.testing.expectEqual(@as(usize, 1), result.toArrayObject().elements.items[0].toHashObject().entries.items.len);
}
