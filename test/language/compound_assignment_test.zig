const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "local ||= initializes undefined local" {
    const result = try evalCode(
        \\a ||= 1
        \\a
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "local &&= on undefined local returns nil and keeps nil" {
    const result = try evalCode(
        \\a &&= 1
        \\a
    );
    try std.testing.expect(result.data == .nil);
}

test "local compound assignment short-circuits rhs" {
    var result = try evalCode(
        \\x = nil
        \\y = 0
        \\x &&= (y = 1)
        \\y
    );
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);

    result = try evalCode(
        \\x = false
        \\y = 0
        \\x ||= (y = 1)
        \\y
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "local compound assignment updates outer scope locals" {
    var result = try evalCode(
        \\x = 1
        \\f = -> { x &&= 2 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);

    result = try evalCode(
        \\x = nil
        \\f = -> { x ||= 3 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "local operator assignment updates local variable" {
    const result = try evalCode(
        \\x = 1
        \\x += 2
        \\x
    );
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "local operator assignment updates captured outer local" {
    const result = try evalCode(
        \\x = 10
        \\f = -> { x += 5 }
        \\f.call
        \\x
    );
    try std.testing.expectEqual(@as(i64, 15), result.data.integer);
}

test "index operator assignment updates array element and returns assigned value" {
    const result = try evalCode(
        \\a = [10, 20, 30]
        \\x = (a[1] += 5)
        \\[x, a[1]]
    );

    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 25), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 25), result.data.array.elements.items[1].data.integer);
}

test "index operator assignment evaluates index expression once" {
    const result = try evalCode(
        \\a = [1, 2, 3]
        \\i = 0
        \\a[(i = i + 1)] += 10
        \\i
    );

    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "index operator assignment evaluates receiver expression once" {
    const result = try evalCode(
        \\$counter = 0
        \\def make_array
        \\  $counter = $counter + 1
        \\  [1, 2, 3]
        \\end
        \\make_array[0] += 7
        \\$counter
    );

    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "index operator assignment supports splatted index arguments" {
    const result = try evalCode(
        \\a = [10, 20, 30]
        \\idx = [1]
        \\a[*idx] += 7
        \\a[1]
    );
    try std.testing.expectEqual(@as(i64, 27), result.data.integer);
}

test "global compound assignment" {
    var result = try evalCode(
        \\$g = nil
        \\$g ||= 9
        \\$g
    );
    try std.testing.expectEqual(@as(i64, 9), result.data.integer);

    result = try evalCode(
        \\$h = false
        \\$h &&= 7
        \\$h
    );
    try std.testing.expect(result.data == .boolean and !result.data.boolean);
}

test "instance variable compound assignment" {
    var result = try evalCode(
        \\class Foo
        \\  def run
        \\    @x ||= 10
        \\  end
        \\end
        \\Foo.new.run
    );
    try std.testing.expectEqual(@as(i64, 10), result.data.integer);

    result = try evalCode(
        \\class Bar
        \\  def run
        \\    @y = nil
        \\    @y &&= 5
        \\  end
        \\end
        \\Bar.new.run
    );
    try std.testing.expect(result.data == .nil);
}

test "constant ||= initializes when missing" {
    const result = try evalCode(
        \\X ||= 1
        \\X
    );
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "constant ||= assigns when existing constant is falsey" {
    const result = try evalCode(
        \\Y = false
        \\Y ||= 2
        \\Y
    );
    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "constant &&= raises NameError when constant is missing" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "Z &&= 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, error.UnhandledException), result.err);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "uninitialized constant Z") != null);
}
