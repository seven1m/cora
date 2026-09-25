const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Proc.call with parameters" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\pr = Proc.new { |x| p x }
        \\pr.call(99)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqualSlices(u8, "99\n", result.stdout);
}

test "Proc.call and lambda call bind passed blocks" {
    const result = try evalCode(
        \\proc_receiver = proc { |&block| block.call(2) }
        \\lambda_receiver = ->(&block) { block.call(3) }
        \\[proc_receiver.call { |value| value * 4 }, lambda_receiver.call { |value| value * 5 }]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 8), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 15), values[1].toInteger());
}

test "Proc.call captures variables from defining scope" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\x = 10
        \\pr = Proc.new { p x }
        \\pr.call
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqualSlices(u8, "10\n", result.stdout);
}

test "Proc.binding retains defining scope after its frame returns" {
    const result = try evalCode(
        \\def make_proc
        \\  value = 10
        \\  proc { value }
        \\end
        \\captured = make_proc
        \\captured.binding.eval("value += 5")
        \\[captured.call, captured.binding.receiver.equal?(self)]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 15), values[0].toInteger());
    try std.testing.expect(values[1].isTruthy());
}

test "Binding local_variable_defined? checks captured and eval locals" {
    const result = try evalCode(
        \\def captured_binding
        \\  count = 2
        \\  binding
        \\end
        \\b = captured_binding
        \\first = [b.local_variable_defined?(:count), b.local_variable_defined?("missing")]
        \\b.eval("added = 3")
        \\first << b.local_variable_defined?(:added)
        \\first
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expect(values[1].isFalse());
    try std.testing.expect(values[2].isTrue());
}

test "Binding local_variable_set updates existing locals and adds locals to copies" {
    const result = try evalCode(
        \\def make_binding
        \\  count = 2
        \\  binding
        \\end
        \\captured = make_binding
        \\captured.local_variable_set(:count, 7)
        \\copy = TOPLEVEL_BINDING.dup
        \\copy.local_variable_set(:added, 12)
        \\copy.eval("earlier = 4")
        \\copy.local_variable_set(:later, 21)
        \\[captured.eval("count"), copy.eval("added"), copy.eval("later"), TOPLEVEL_BINDING.local_variable_defined?(:added)]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 7), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 12), values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 21), values[2].toInteger());
    try std.testing.expect(values[3].isFalse());
}

test "Binding local_variable_get reads locals and names missing locals" {
    const result = try evalCode(
        \\b = TOPLEVEL_BINDING.dup
        \\b.local_variable_set(:value, 8)
        \\begin
        \\  b.local_variable_get(:missing)
        \\rescue NameError => error
        \\  [b.local_variable_get("value"), error.name]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 8), values[0].toInteger());
    try std.testing.expectEqualStrings("missing", values[1].toSymbolObject().name);
}

test "Proc.call uses defining self" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.make_proc
        \\  @foo = 42
        \\  Proc.new { [@foo, self] }
        \\end
        \\pr = obj.make_proc
        \\res = pr.call
        \\[res[0], res[1].object_id, obj.object_id]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elems.len);
    try std.testing.expect(elems[0].isInteger());
    try std.testing.expect(elems[1].isInteger());
    try std.testing.expect(elems[2].isInteger());
    try std.testing.expectEqual(@as(i64, 42), elems[0].toInteger());
    try std.testing.expectEqual(elems[1].toInteger(), elems[2].toInteger());
}

test "Proc closure: modifying captured variable in proc affects outer scope" {
    const result = try evalCode(
        \\def test_proc
        \\  yield
        \\end
        \\
        \\x = 5
        \\pr = Proc.new do
        \\  x = 10
        \\end
        \\pr.call
        \\x
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "Kernel#proc creates a Proc" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\pr = proc { |x| p x }
        \\pr.call(99)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqualSlices(u8, "99\n", result.stdout);
}

test "Proc implicit return: returns last expression, method continues" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new { 10 }
        \\  p.call
        \\  20
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 20), result.toInteger());
}

test "Proc explicit return: exits enclosing method" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new { return 10 }
        \\  p.call
        \\  20
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "Proc implicit return with value: returns value from proc, method continues" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new { |x| x + 5 }
        \\  result = p.call(3)
        \\  result + 10
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 18), result.toInteger()); // (3 + 5) + 10
}

test "Proc explicit return with value: exits method with that value" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new { |x| return x + 5 }
        \\  result = p.call(3)
        \\  result + 10
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toInteger()); // 3 + 5, method exits
}

test "proc keyword: implicit return behaves correctly" {
    const result = try evalCode(
        \\def foo
        \\  p = proc { 15 }
        \\  p.call
        \\  25
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 25), result.toInteger());
}

test "proc keyword: explicit return exits method" {
    const result = try evalCode(
        \\def foo
        \\  p = proc { return 15 }
        \\  p.call
        \\  25
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 15), result.toInteger());
}

test "Proc implicit return: multiple statements, returns last" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new {
        \\    x = 5
        \\    y = 10
        \\    x + y
        \\  }
        \\  p.call
        \\  30
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 30), result.toInteger());
}

test "Proc explicit return: early exit from proc body" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new {
        \\    return 100
        \\    200
        \\  }
        \\  p.call
        \\  300
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 100), result.toInteger());
}

test "Proc#to_proc returns self" {
    const result = try evalCode(
        \\pr = proc { |x| x + 1 }
        \\[pr.to_proc.call(4), pr.object_id == pr.to_proc.object_id]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 5), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
}

test "Proc#inspect and to_s include source location and lambda status" {
    const result = try evalCode(
        \\pr = eval("proc {}", binding, "proc_source.rb", 12)
        \\lambda_proc = eval("-> {}", binding, "lambda_source.rb", 34)
        \\[
        \\  pr.inspect.match?(/#<Proc:0x[0-9a-f]+ proc_source\.rb:12>/),
        \\  pr.to_s == pr.inspect,
        \\  lambda_proc.inspect.match?(/#<Proc:0x[0-9a-f]+ lambda_source\.rb:34 \(lambda\)>/),
        \\]
    );

    for (result.toArrayObject().elements.items) |value| {
        try std.testing.expect(value.isTrue());
    }
}

test "Nested procs: outer explicit return exits method" {
    const result = try evalCode(
        \\def foo
        \\  outer = Proc.new {
        \\    inner = Proc.new { 5 }
        \\    inner.call
        \\    return 10
        \\  }
        \\  outer.call
        \\  20
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 10), result.toInteger());
}

test "Nested procs: inner explicit return exits method from inside" {
    const result = try evalCode(
        \\def foo
        \\  outer = Proc.new {
        \\    inner = Proc.new { return 5 }
        \\    inner.call
        \\    10
        \\  }
        \\  outer.call
        \\  20
        \\end
        \\foo
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "Proc.new block keeps enclosing method yield when called later" {
    const result = try evalCode(
        \\def foo
        \\  p = Proc.new { yield 1 }
        \\  p.call
        \\end
        \\foo { |x| x + 1 }
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "Proc explicit return raises LocalJumpError after enclosing method has returned" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def make_proc
        \\  Proc.new { return :late }
        \\end
        \\
        \\p = make_proc
        \\p.call
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "LocalJumpError") != null);
}

test "deep recursive Proc#call (stack depth stress test)" {
    const result = try evalCode(
        \\f = proc { |n| n > 0 ? f.call(n - 1) : 0 }
        \\f.call(1000)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "deep recursive lambda call (stack depth stress test)" {
    const result = try evalCode(
        \\f = lambda { |n| n > 0 ? f.call(n - 1) : 0 }
        \\f.call(1000)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}
