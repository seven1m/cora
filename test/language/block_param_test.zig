const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "numbered parameters bind through the highest referenced number" {
    const result = try evalCode(
        \\values = [10, 20, 30]
        \\block_result = values.then { [_1, _3] }
        \\numbered_lambda = -> { _2 }
        \\[block_result, numbered_lambda.arity, numbered_lambda.call(1, 2)]
    );
    const values = result.toArrayObject().elements.items;
    const block_result = values[0].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 10), block_result[0].toInteger());
    try std.testing.expectEqual(@as(i64, 30), block_result[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[2].toInteger());
}

test "block parameter receives Proc when block passed" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\foo { puts "hello" }
    );
    try std.testing.expect(result.isProc());
}

test "block argument calls balance stack depth across conditional branches" {
    const result = try evalCode(
        \\def fetch_value(values, key, &block)
        \\  key = key.to_s
        \\  if block
        \\    values.fetch(key, &block)
        \\  else
        \\    values[key]
        \\  end
        \\end
        \\[fetch_value({ "name" => "Cora" }, :name), fetch_value({}, :name) { "missing" }]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("Cora", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("missing", values[1].toStringObject().str);
}

test "block parameter receives nil when no block" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\foo
    );
    try std.testing.expect(result.isNil());
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
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "block parameter with required positional params" {
    const result = try evalCode(
        \\def foo(a, b, &block)
        \\  a + b + block.call
        \\end
        \\foo(1, 2) { 3 }
    );
    try std.testing.expectEqual(@as(i64, 6), result.toInteger());
}

test "block parameter with optional params" {
    const result = try evalCode(
        \\def foo(a = 10, &block)
        \\  a + (block ? block.call : 0)
        \\end
        \\foo(5) { 20 }
    );
    try std.testing.expectEqual(@as(i64, 25), result.toInteger());
}

test "block parameter with rest parameter" {
    const result = try evalCode(
        \\def foo(*args, &block)
        \\  args.length + block.call
        \\end
        \\foo(1, 2, 3) { 99 }
    );
    try std.testing.expectEqual(@as(i64, 102), result.toInteger());
}

test "block parameter with keyword params" {
    const result = try evalCode(
        \\def foo(a:, b: 5, &block)
        \\  a + b + block.call
        \\end
        \\foo(a: 10) { 30 }
    );
    try std.testing.expectEqual(@as(i64, 45), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "block parameter is a Proc not lambda" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block.lambda?
        \\end
        \\foo { puts "hi" }
    );
    try std.testing.expect(result.isBool());
    try std.testing.expect(!result.toBool());
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
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "block parameter with arguments" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block.call(10, 20)
        \\end
        \\foo { |a, b| a + b }
    );
    try std.testing.expectEqual(@as(i64, 30), result.toInteger());
}

test "block destructuring parameters bind inner locals" {
    const result = try evalCode(
        \\value = nil
        \\[[3, 9]].each do |(s, _)|
        \\  value = s
        \\end
        \\value
    );
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "block parameter can be stored and called later" {
    const result = try evalCode(
        \\def foo(&block)
        \\  block
        \\end
        \\stored = foo { 42 }
        \\stored.call
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 52), result.toInteger());
}

test "forwarded block yield uses enclosing block rather than itself" {
    const result = try evalCode(
        \\def inner
        \\  yield 1
        \\  nil
        \\end
        \\def outer(&block)
        \\  inner(&block)
        \\  nil
        \\end
        \\def middle
        \\  block_given = block_given?
        \\  outer do |k|
        \\    return block_given ? yield(k) : k
        \\  end
        \\  nil
        \\end
        \\def top
        \\  middle { |x| x }
        \\  99
        \\end
        \\top
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "__send__ forwarded block preserves yielded array on non-local return" {
    const result = try evalCode(
        \\class L
        \\  def search(*)
        \\    yield [1, 2]
        \\  end
        \\end
        \\def visit(id, *args, &block)
        \\  L.new.__send__(id, *args, &block)
        \\  nil
        \\end
        \\def search2
        \\  visit(:search) do |k|
        \\    return k
        \\  end
        \\end
        \\search2
    );
    try std.testing.expect(result.isArray());
    const array = result.toArrayObject();
    try std.testing.expectEqual(@as(usize, 2), array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), array.elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), array.elements.items[1].toInteger());
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
    try std.testing.expectEqualStrings("no block", result.toStringObject().str);
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
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
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
    try std.testing.expect(result.isBool());
    try std.testing.expect(!result.toBool());
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
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 45), result.toInteger());
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
    try std.testing.expectEqual(@as(i64, 13), result.toInteger());
}

test "&:symbol converts symbol to block via to_proc" {
    const result = try evalCode(
        \\['tim'].map(&:upcase)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 1), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isString());
    try std.testing.expectEqualStrings("TIM", result.toArrayObject().elements.items[0].toStringObject().str);
}

test "&:symbol forwards arguments to method call" {
    const result = try evalCode(
        \\[1, 2].map(&:to_s)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isString());
    try std.testing.expectEqualStrings("1", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expect(result.toArrayObject().elements.items[1].isString());
    try std.testing.expectEqualStrings("2", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "&argument calls to_proc when present" {
    const result = try evalCode(
        \\class M
        \\  def to_proc
        \\    proc { |x| x.to_s }
        \\  end
        \\end
        \\[1, 2].map(&M.new)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isString());
    try std.testing.expectEqualStrings("1", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expect(result.toArrayObject().elements.items[1].isString());
    try std.testing.expectEqualStrings("2", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "&argument honors respond_to_missing? when coercing to_proc" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.respond_to_missing?(name, include_private = false)
        \\  name == :to_proc || super
        \\end
        \\def obj.method_missing(name, *args, &block)
        \\  return proc { |x| x * 3 } if name == :to_proc
        \\  super
        \\end
        \\[1, 2].map(&obj)
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 6), result.toArrayObject().elements.items[1].toInteger());
}

test "&argument to_proc returning non-Proc raises TypeError" {
    try std.testing.expectError(error.UnhandledException, evalCode(
        \\class M
        \\  def to_proc
        \\    123
        \\  end
        \\end
        \\[1].map(&M.new)
    ));
}

test "anonymous block parameter forwards to another method" {
    const result = try evalCode(
        \\def bar(x, &b)
        \\  b.call(x * 2)
        \\end
        \\def foo(x, &)
        \\  bar(x, &)
        \\end
        \\foo(21) { |n| n + 1 }
    );
    try std.testing.expectEqual(@as(i64, 43), result.toInteger());
}

test "anonymous block parameter forwards nil when no block given" {
    const result = try evalCode(
        \\def bar(&b)
        \\  b.nil?
        \\end
        \\def foo(&)
        \\  bar(&)
        \\end
        \\foo
    );
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.toBool());
}

test "anonymous block parameter defined via module_eval forwards" {
    const result = try evalCode(
        \\class W
        \\  def initialize(v)
        \\    @value = v
        \\  end
        \\  def value
        \\    @value
        \\  end
        \\end
        \\W.class_eval("def doubled(&); (@value * 2) + (block_given? ? yield : 0); end")
        \\W.class_eval("def via_anon(&); doubled(&); end")
        \\W.new(21).via_anon { 1 }
    );
    try std.testing.expectEqual(@as(i64, 43), result.toInteger());
}
