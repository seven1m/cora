const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "block parameter receives Proc when block passed" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\foo { puts "hello" }
    );
    try std.testing.expect(result.data == .proc);
}

test "block parameter receives nil when no block" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\foo
    );
    try std.testing.expect(result.data == .nil);
}

test "calling block.call executes the block" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block.call if block
        \\end
        \\x = 1
        \\foo { x = 42 }
        \\x
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "block parameter with yield both work" {
    const result = try evalCode(
        \\def foo(&block)
        \\  yield(1)
        \\  block.call(2)
        \\end
        \\x = 0
        \\foo { |n| x = x + n }
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "block parameter with required positional params" {
    const result = try evalCode(
        \\def foo(a, b, &block)
        \\  a + b + block.call
        \\end
        \\foo(1, 2) { 3 }
    );
    try std.testing.expectEqual(@as(i64, 6), result.data.integer);
}

test "block parameter with optional params" {
    const result = try evalCode(
        \\def foo(a = 10, &block)
        \\  a + (block ? block.call : 0)
        \\end
        \\foo(5) { 20 }
    );
    try std.testing.expectEqual(@as(i64, 25), result.data.integer);
}

test "block parameter with rest parameter" {
    const result = try evalCode(
        \\def foo(*args, &block)
        \\  args.length + block.call
        \\end
        \\foo(1, 2, 3) { 99 }
    );
    try std.testing.expectEqual(@as(i64, 102), result.data.integer);
}

test "block parameter with keyword params" {
    const result = try evalCode(
        \\def foo(a:, b: 5, &block)
        \\  a + b + block.call
        \\end
        \\foo(a: 10) { 30 }
    );
    try std.testing.expectEqual(@as(i64, 45), result.data.integer);
}

test "passing block parameter to another method via call" {
    const result = try evalCode(
        \\def bar(pr)
        \\  pr.call
        \\end
        \\def foo(&block)
        \\  bar(block)
        \\end
        \\foo { 100 }
    );
    try std.testing.expectEqual(@as(i64, 100), result.data.integer);
}

test "block parameter is a Proc not lambda" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block.lambda?
        \\end
        \\foo { puts "hi" }
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expect(!result.data.boolean);
}

test "block parameter captures closure" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\x = 5
        \\b = foo { x = x + 1 }
        \\b.call
        \\b.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "block parameter with arguments" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block.call(10, 20)
        \\end
        \\foo { |a, b| a + b }
    );
    try std.testing.expectEqual(@as(i64, 30), result.data.integer);
}

test "block parameter can be stored and called later" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\stored = foo { 42 }
        \\stored.call
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "pass block using &variable syntax" {
    const result = try evalCode(
        \\def bar(&block)
        \\  yield + 10
        \\end
        \\def foo(&block)
        \\  bar(&block)
        \\end
        \\foo { 42 }
    );
    try std.testing.expectEqual(@as(i64, 52), result.data.integer);
}

test "pass &nil disables block" {
    const result = try evalCode(
        \\def bar(&block)
        \\  if block
        \\    block.call
        \\  else
        \\    "no block"
        \\  end
        \\end
        \\def foo
        \\  bar(&nil)
        \\end
        \\foo
    );
    try std.testing.expectEqualStrings("no block", result.data.string.str);
}

test "lambda flag preserved when passing" {
    const result = try evalCode(
        \\def bar(&block)
        \\  block.lambda?
        \\end
        \\def foo
        \\  b = lambda { 1 }
        \\  bar(&b)
        \\end
        \\foo
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expect(result.data.boolean);
}

test "proc flag preserved when passing" {
    const result = try evalCode(
        \\def bar(&block)
        \\  block.lambda?
        \\end
        \\def foo
        \\  b = proc { 1 }
        \\  bar(&b)
        \\end
        \\foo
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expect(!result.data.boolean);
}

test "passing invalid type raises TypeError" {
    try std.testing.expectError(error.UnhandledException, evalCode(
        \\def bar(&block)
        \\  block.call
        \\end
        \\def foo
        \\  bar(&42)
        \\end
        \\foo
    ));
}

test "multiple method hops with &variable" {
    const result = try evalCode(
        \\def baz
        \\  yield * 2
        \\end
        \\def bar(&block)
        \\  baz(&block)
        \\end
        \\def foo(&block)
        \\  bar(&block)
        \\end
        \\foo { 21 }
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "closure preserved across multiple hops" {
    const result = try evalCode(
        \\def bar(&block)
        \\  block
        \\end
        \\def foo
        \\  y = 10
        \\  bar { y + 5 }
        \\end
        \\b = foo
        \\b.call
    );
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "&variable with block arguments" {
    const result = try evalCode(
        \\def bar(a, &block)
        \\  block.call(a)
        \\end
        \\def foo(&block)
        \\  bar(5, &block)
        \\end
        \\foo { |n| n * 2 }
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "&variable with keyword args and block" {
    const result = try evalCode(
        \\def bar(a:, b: 10, &block)
        \\  block.call(a + b)
        \\end
        \\def foo(&block)
        \\  bar(a: 5, &block)
        \\end
        \\foo { |n| n * 3 }
    );
    try std.testing.expectEqual(@as(i64, 45), result.data.integer);
}

test "&variable with rest params and block" {
    const result = try evalCode(
        \\def bar(*args, &block)
        \\  block.call(args.length)
        \\end
        \\def foo(&block)
        \\  bar(1, 2, 3, &block)
        \\end
        \\foo { |n| n + 10 }
    );
    try std.testing.expectEqual(@as(i64, 13), result.data.integer);
}
