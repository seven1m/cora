const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "alias keyword in a class" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\end
        \\Foo.new.hi
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias keyword preserves original method" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\end
        \\Foo.new.greet
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias is independent of original method redefinition" {
    const result = try evalCode(
        \\class Foo
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias hi greet
        \\  def greet
        \\    "hey"
        \\  end
        \\end
        \\Foo.new.hi
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias at top-level" {
    const result = try evalCode(
        \\def greet
        \\  "hello"
        \\end
        \\alias hi greet
        \\hi
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias_method with symbol args" {
    const result = try evalCode(
        \\class Bar
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias_method :hi, :greet
        \\end
        \\Bar.new.hi
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias_method with string args" {
    const result = try evalCode(
        \\class Bar
        \\  def greet
        \\    "hello"
        \\  end
        \\  alias_method "hi", "greet"
        \\end
        \\Bar.new.hi
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "alias_method returns new name as symbol" {
    const result = try evalCode(
        \\class Baz
        \\  def greet
        \\    "hello"
        \\  end
        \\end
        \\Baz.alias_method(:hi, :greet)
    );
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "hi", result.data.symbol.name);
}

test "alias undefined method raises NameError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\  alias hi greet
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
}

test "alias_method undefined method raises NameError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\  alias_method :hi, :greet
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
}
