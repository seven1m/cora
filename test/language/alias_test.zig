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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "alias at top-level" {
    const result = try evalCode(
        \\def greet
        \\  "hello"
        \\end
        \\alias hi greet
        \\hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "hi", result.toSymbolObject().name);
}

test "alias_method coerces names via to_str" {
    const result = try evalCode(
        \\class Baz
        \\  def greet
        \\    "hello"
        \\  end
        \\end
        \\new_name = Object.new
        \\old_name = Object.new
        \\def new_name.to_str
        \\  "hi"
        \\end
        \\def old_name.to_str
        \\  "greet"
        \\end
        \\Baz.alias_method(new_name, old_name)
        \\Baz.new.hi
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
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

test "alias can target inherited private methods in class_eval" {
    const result = try evalCode(
        \\kernel = Kernel.dup
        \\kernel.class_eval do
        \\  alias __raise__ raise
        \\end
        \\kernel.instance_methods(false).include?(:__raise__)
    );
    try std.testing.expect(result.isTrue());
}
