const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Method with block and yield" {
    const result = try evalCode(
        \\def twice
        \\  yield 1
        \\  yield 2
        \\end
        \\
        \\twice { |x| x + 10 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "ArgumentError raised for no block given" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\foo
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "no block given") != null);
}

test "yield arity: block is lenient, lambda is strict" {
    const block_result = try evalCode(
        \\def foo
        \\  yield 1
        \\end
        \\foo { |a, b| [a, b] }
    );
    try std.testing.expect(block_result.data == .array);
    try std.testing.expectEqual(@as(i64, 1), block_result.data.array.elements.items[0].data.integer);
    try std.testing.expect(block_result.data.array.elements.items[1].data == .nil);

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const lambda_result = evalCodeWithOutput(
        \\def foo
        \\  yield 1
        \\end
        \\l = ->(a, b) { a + b }
        \\foo(&l)
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, lambda_result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, lambda_result.stderr, "ArgumentError") != null);
}

test "yield splat expands array arguments" {
    const result = try evalCode(
        \\def emit
        \\  yield *[1, 2, 3]
        \\end
        \\emit { |a, b, c| [a, b, c] }
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Block with multiple parameters" {
    const result = try evalCode(
        \\def add_them
        \\  yield 5, 7
        \\end
        \\
        \\add_them { |a, b| a + b }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.integer);
}

test "Block with no parameters" {
    const result = try evalCode(
        \\def call_block
        \\  yield
        \\end
        \\
        \\call_block { 42 }
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "Closure: read captured variable" {
    const result = try evalCode(
        \\def test_closure
        \\  yield
        \\end
        \\
        \\x = 5
        \\result = 0
        \\test_closure do
        \\  result = x
        \\end
        \\result
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "Closure: write captured variable" {
    const result = try evalCode(
        \\def test_closure
        \\  yield
        \\end
        \\
        \\x = 1
        \\test_closure do
        \\  x = 10
        \\end
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);
}

test "Closure: update captured variable multiple times" {
    const result = try evalCode(
        \\def test_closure
        \\  yield
        \\  yield
        \\  yield
        \\end
        \\
        \\x = 1
        \\test_closure do
        \\  x = x + 1
        \\end
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 4), result.data.integer);
}

test "Closure: multiple captured variables" {
    const result = try evalCode(
        \\def test_closure
        \\  yield
        \\end
        \\
        \\x = 1
        \\y = 2
        \\z = 3
        \\test_closure do
        \\  x = x + 10
        \\  y = y + 20
        \\  z = z + 30
        \\end
        \\x + y + z
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 66), result.data.integer); // 11 + 22 + 33
}

test "Closure: nested blocks update same variable" {
    const result = try evalCode(
        \\def outer
        \\  yield
        \\end
        \\
        \\def inner
        \\  yield
        \\end
        \\
        \\x = 1
        \\outer do
        \\  x = x + 10
        \\  inner do
        \\    x = x + 100
        \\  end
        \\end
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 111), result.data.integer);
}

test "Closure: deep nesting (3 levels)" {
    const result = try evalCode(
        \\def level1
        \\  yield
        \\end
        \\
        \\def level2
        \\  yield
        \\end
        \\
        \\def level3
        \\  yield
        \\end
        \\
        \\x = 0
        \\level1 do
        \\  x = x + 1
        \\  level2 do
        \\    x = x + 10
        \\    level3 do
        \\      x = x + 100
        \\    end
        \\  end
        \\end
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 111), result.data.integer);
}

test "Closure: shadowing with block parameter" {
    const result = try evalCode(
        \\def test_closure
        \\  yield 99
        \\end
        \\
        \\x = 5
        \\result = 0
        \\test_closure do |x|
        \\  result = x
        \\end
        \\result
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 99), result.data.integer); // Block param shadows outer x
}

test "Closure: outer variable unchanged when shadowed" {
    const result = try evalCode(
        \\def test_closure
        \\  yield 99
        \\end
        \\
        \\x = 5
        \\test_closure do |x|
        \\  x = x + 1
        \\end
        \\x
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 5), result.data.integer); // Outer x should be unchanged
}

test "Closure: capture and modify in nested blocks" {
    const result = try evalCode(
        \\def outer
        \\  yield
        \\end
        \\
        \\def inner
        \\  yield
        \\end
        \\
        \\a = 1
        \\b = 2
        \\outer do
        \\  a = a + 10
        \\  c = 100
        \\  inner do
        \\    b = b + 20
        \\    c = c + 200
        \\  end
        \\  a = a + c
        \\end
        \\a + b
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 333), result.data.integer); // a=11+300=311, b=22, total=333
}

test "Closure: RHS block sees assignment target as predeclared local" {
    const result = try evalCode(
        \\x = [1].map { x }
        \\[x.length, x[0].nil?]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(true, result.data.array.elements.items[1].data.boolean);
}
