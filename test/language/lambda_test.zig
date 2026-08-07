const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "lambda: stabby syntax creates lambda" {
    const result = try evalCode("l = -> { 42 }; l.call");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "lambda: lambda method creates lambda" {
    const result = try evalCode("l = lambda { 42 }; l.call");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "lambda: lambda? returns true for lambda" {
    const result = try evalCode("l = lambda { 42 }; l.lambda?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
}

test "lambda: lambda? returns false for proc" {
    const result = try evalCode("p = proc { 42 }; p.lambda?");
    try std.testing.expect(result.isBool());
    try std.testing.expect(!result.toBool());
}

test "lambda: strict arity - exact match succeeds" {
    const result = try evalCode("l = lambda { |x, y| x + y }; l.call(3, 5)");
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "lambda: strict arity - too few arguments raises ArgumentError" {
    try std.testing.expectError(error.UnhandledException, evalCode("l = lambda { |x, y| x + y }; l.call(3)"));
}

test "lambda: strict arity - too many arguments raises ArgumentError" {
    try std.testing.expectError(error.UnhandledException, evalCode("l = lambda { |x, y| x + y }; l.call(3, 5, 7)"));
}

test "proc: lenient arity - too few arguments fills with nil" {
    const result = try evalCode("p = proc { |x, y| x }; p.call(5)");
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "proc: lenient arity - too many arguments ignored" {
    const result = try evalCode("p = proc { |x| x }; p.call(5, 10)");
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "lambda: return exits lambda only" {
    const result = try evalCode(
        \\def foo
        \\  l = lambda { return 10 }
        \\  l.call
        \\  return 20
        \\end
        \\foo
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "lambda: break exits lambda only" {
    const result = try evalCode(
        \\def foo
        \\  l = lambda { break 10 }
        \\  l.call
        \\  20
        \\end
        \\foo
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "proc: return exits enclosing method" {
    const result = try evalCode(
        \\def foo
        \\  p = proc { return 10 }
        \\  p.call
        \\  return 20
        \\end
        \\foo
    );
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "proc: return exits the lambda where it was defined" {
    const result = try evalCode(
        \\def foo
        \\  l = lambda do
        \\    proc { return 10 }.call
        \\    20
        \\  end
        \\  [l.call, 30]
        \\end
        \\foo
    );
    try std.testing.expect(result.isArray());
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 10), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 30), values[1].toInteger());
}

test "proc: break after enclosing method returned raises LocalJumpError" {
    try std.testing.expectError(error.UnhandledException, evalCode(
        \\def make_proc
        \\  proc { break 10 }
        \\end
        \\make_proc.call
    ));
}

test "lambda: parameters work correctly" {
    const result = try evalCode("l = lambda { |x| x + 2 }; l.call(5)");
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "lambda: multiple parameters work" {
    const result = try evalCode("l = lambda { |x, y, z| x + y + z }; l.call(1, 2, 3)");
    try std.testing.expectEqual(@as(i64, 6), result.toInteger());
}

test "lambda: closures capture variables" {
    const result = try evalCode(
        \\def make_adder(n)
        \\  lambda { |x| x + n }
        \\end
        \\add5 = make_adder(5)
        \\add5.call(10)
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "proc: closures capture variables" {
    const result = try evalCode(
        \\def make_adder(n)
        \\  proc { |x| x + n }
        \\end
        \\add5 = make_adder(5)
        \\add5.call(10)
    );
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "lambda: nested lambda with proc" {
    const result = try evalCode(
        \\def foo
        \\  p = proc {
        \\    l = lambda { return 10 }
        \\    l.call
        \\    return 20
        \\  }
        \\  p.call
        \\  return 30
        \\end
        \\foo
    );
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "lambda: zero parameters" {
    const result = try evalCode("l = lambda { 42 }; l.call");
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "lambda: zero parameters with arguments raises error" {
    try std.testing.expectError(error.UnhandledException, evalCode("l = lambda { 42 }; l.call(1)"));
}

test "lambda: can be assigned to variable" {
    const result = try evalCode("l = lambda { |x| x + 2 }; m = l; m.call(3)");
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "proc: different return behavior than lambda" {
    const result = try evalCode(
        \\def test_lambda
        \\  l = lambda { return 1 }
        \\  l.call
        \\  2
        \\end
        \\
        \\def test_proc
        \\  p = proc { return 1 }
        \\  p.call
        \\  2
        \\end
        \\
        \\test_lambda + test_proc
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger()); // 2 + 1
}

test "lambda: stabby lambda with parameters" {
    const result = try evalCode("l = ->(x, y) { x - y }; l.call(10, 3)");
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "lambda: body can have multiple statements" {
    const result = try evalCode(
        \\l = lambda { |x|
        \\  y = x + 1
        \\  z = y + 2
        \\  z
        \\}
        \\l.call(5)
    );
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "lambda: return value is last expression" {
    const result = try evalCode("l = lambda { 1; 2; 3 }; l.call");
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "proc: return value is last expression" {
    const result = try evalCode("p = proc { 1; 2; 3 }; p.call");
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}
