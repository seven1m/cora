const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "instance variable basic assignment and read" {
    const result = try evalCode(
        \\class Foo
        \\  def set_x(val)
        \\    @x = val
        \\  end
        \\  def get_x
        \\    @x
        \\  end
        \\end
        \\f = Foo.new
        \\f.set_x(42)
        \\f.get_x
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "instance variable uninitialized returns nil" {
    const result = try evalCode(
        \\class Bar
        \\  def get_undefined
        \\    @undefined
        \\  end
        \\end
        \\Bar.new.get_undefined
    );
    try std.testing.expect(result.data == .nil);
}

test "instance_variable_set returns the value" {
    const result = try evalCode(
        \\class Foo
        \\  def test_ivar
        \\    instance_variable_set(:@a, 123)
        \\  end
        \\end
        \\Foo.new.test_ivar
    );
    try std.testing.expectEqual(@as(i64, 123), result.data.integer);
}

test "instance_variable_set rejects symbol without @ prefix" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\class Foo
        \\  def test_ivar
        \\    instance_variable_set(:foo, 123)
        \\  end
        \\end
        \\Foo.new.test_ivar
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError: 'foo' is not allowed as an instance variable name") != null);
}

test "instance_variable_set rejects string without @ prefix" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\class Foo
        \\  def test_ivar
        \\    instance_variable_set("foo", 123)
        \\  end
        \\end
        \\Foo.new.test_ivar
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError: 'foo' is not allowed as an instance variable name") != null);
}

test "instance_variable_set rejects string with only '@'" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\class Foo
        \\  def test_ivar
        \\    instance_variable_set('@', 123)
        \\  end
        \\end
        \\Foo.new.test_ivar
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError: '@' is not allowed as an instance variable name") != null);
}
