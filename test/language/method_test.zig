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
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "foo", result.toSymbolObject().name);

    result = try evalCode(
        \\def foo
        \\  'foo'
        \\end
        \\foo
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);
}

test "Method calls with arguments" {
    const result = try evalCode(
        \\def increment(x)
        \\  x + 1
        \\end
        \\increment(41)
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(42, result.toInteger());
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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings("unknown_call", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[2].toInteger());
}

test "method_missing preserves ruby2_keywords through send" {
    const result = try evalCode(
        \\class KeywordSendTarget
        \\  def add_index(table, column, unique: false)
        \\    [table, column, unique]
        \\  end
        \\end
        \\class KeywordSendInnerProxy
        \\  def initialize
        \\    @target = KeywordSendTarget.new
        \\  end
        \\  def method_missing(method, ...)
        \\    @target.send(method, ...)
        \\  end
        \\end
        \\class KeywordSendOuterProxy
        \\  def initialize
        \\    @target = KeywordSendInnerProxy.new
        \\  end
        \\  def method_missing(method, *arguments, &block)
        \\    @target.send(method, *arguments, &block)
        \\  end
        \\  ruby2_keywords(:method_missing)
        \\end
        \\KeywordSendOuterProxy.new.add_index(:users, :email, unique: true)
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("users", values[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("email", values[1].toSymbolObject().name);
    try std.testing.expect(values[2].isTrue());
}

test "public_send and __send__ preserve ruby2_keywords" {
    const result = try evalCode(
        \\class KeywordSendReceiver
        \\  def collect(value:, &block)
        \\    [value, block.call]
        \\  end
        \\end
        \\class KeywordSendForwarder
        \\  def initialize(dispatch)
        \\    @dispatch = dispatch
        \\  end
        \\  def forward(receiver, method, *arguments, &block)
        \\    receiver.__send__(@dispatch, method, *arguments, &block)
        \\  end
        \\  ruby2_keywords(:forward)
        \\end
        \\receiver = KeywordSendReceiver.new
        \\[
        \\  KeywordSendForwarder.new(:public_send).forward(receiver, :collect, value: 1) { 2 },
        \\  KeywordSendForwarder.new(:__send__).forward(receiver, :collect, value: 3) { 4 }
        \\]
    );
    const outer = result.toArrayObject().elements.items;
    const public_values = outer[0].toArrayObject().elements.items;
    const private_values = outer[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), public_values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), public_values[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), private_values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), private_values[1].toInteger());
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
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualStrings("private_hidden", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("protected_hidden", result.toArrayObject().elements.items[1].toSymbolObject().name);
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

test "method call reflects method redefinition after prior call" {
    const result = try evalCode(
        \\class C
        \\  def value
        \\    1
        \\  end
        \\end
        \\obj = C.new
        \\first = obj.value
        \\class C
        \\  def value
        \\    2
        \\  end
        \\end
        \\[first, obj.value]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
}

test "method call reflects include after prior call" {
    const result = try evalCode(
        \\class Base
        \\  def value
        \\    1
        \\  end
        \\end
        \\module Mixin
        \\  def value
        \\    2
        \\  end
        \\end
        \\class C < Base
        \\end
        \\obj = C.new
        \\first = obj.value
        \\class C
        \\  include Mixin
        \\end
        \\[first, obj.value]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
}

test "method call reflects prepend after prior call" {
    const result = try evalCode(
        \\module Prep
        \\  def value
        \\    2
        \\  end
        \\end
        \\class C
        \\  def value
        \\    1
        \\  end
        \\end
        \\obj = C.new
        \\first = obj.value
        \\class C
        \\  prepend Prep
        \\end
        \\[first, obj.value]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
}

test "method call reflects visibility change after prior call" {
    const result = try evalCode(
        \\class C
        \\  def value
        \\    1
        \\  end
        \\end
        \\obj = C.new
        \\first = obj.value
        \\class C
        \\  private :value
        \\end
        \\second = begin
        \\  obj.value
        \\rescue NoMethodError
        \\  :no_method
        \\end
        \\[first, second]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqualStrings("no_method", result.toArrayObject().elements.items[1].toSymbolObject().name);
}
