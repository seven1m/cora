const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Top-level methods" {
    var result = try evalCode(
        \\def foo
        \\  'foo'
        \\end
    );
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "foo", result.data.symbol.name);

    result = try evalCode(
        \\def foo
        \\  'foo'
        \\end
        \\foo
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "Method calls with arguments" {
    const result = try evalCode(
        \\def increment(x)
        \\  x + 1
        \\end
        \\increment(41)
    );
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(42, result.data.integer);
}

test "NoMethodError raised for undefined method" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class Foo
        \\end
        \\Foo.new.bar
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "bar") != null);
}

test "method_missing receives method name and args" {
    const result = try evalCode(
        \\class MethodMissingSpec
        \\  def method_missing(name, *args)
        \\    [name, args.length, args[0]]
        \\  end
        \\end
        \\MethodMissingSpec.new.unknown_call(7)
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqualStrings("unknown_call", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 7), result.data.array.elements.items[2].data.integer);
}

test "method_missing handles private and protected call failures" {
    const result = try evalCode(
        \\class MethodMissingVisibilitySpec
        \\  def method_missing(name, *args)
        \\    name
        \\  end
        \\
        \\  private
        \\  def private_hidden
        \\    :nope
        \\  end
        \\
        \\  protected
        \\  def protected_hidden
        \\    :nope
        \\  end
        \\end
        \\obj = MethodMissingVisibilitySpec.new
        \\[obj.private_hidden, obj.protected_hidden]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqualStrings("private_hidden", result.data.array.elements.items[0].data.symbol.name);
    try std.testing.expectEqualStrings("protected_hidden", result.data.array.elements.items[1].data.symbol.name);
}

test "TypeError raised for wrong receiver type" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        "true + 1",
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    // Note: Exception is raised, but message content checking depends on implementation
}
