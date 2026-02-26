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
