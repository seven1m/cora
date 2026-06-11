const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "C extension fixture loads and defines method" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\"".cora_cext_test
    );
    try std.testing.expect(result.isTruthy());
    try std.testing.expectEqual(true, result.toBool());
}

test "C extension method works on arbitrary receiver" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\"hello".cora_cext_test
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "C extension rb_funcall without block" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.call_to_s(42)
    );
    try std.testing.expectEqual(true, result.isString());
    try std.testing.expectEqualStrings("42", result.toStringObject().str);
}

test "C extension rb_yield basic (no NLR)" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def test_method
        \\  CoraCExt.simple_yield(99) { |x| 77 }
        \\end
        \\test_method
    );
    try std.testing.expectEqual(@as(i64, 77), result.toInteger());
}

test "C extension rb_yield NLR (return from block)" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def test_method
        \\  CoraCExt.yield_nlr(42) { |x| return x }
        \\  "should-not-return-this"
        \\end
        \\test_method
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "C extension rb_funcall NLR from proc call" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def test_method
        \\  callback = proc { return 55 }
        \\  CoraCExt.funcall_nlr(callback)
        \\  "should-not-return-this"
        \\end
        \\test_method
    );
    try std.testing.expectEqual(@as(i64, 55), result.toInteger());
}

test "C extension nested rb_funcall NLR unwinds through multiple C frames" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\class CExtDeepHelper
        \\  def initialize(callback)
        \\    @callback = callback
        \\  end
        \\
        \\  def run
        \\    CoraCExt.funcall_nlr(@callback)
        \\    "should-not-return-inner"
        \\  end
        \\end
        \\
        \\def test_method
        \\  callback = proc { return 88 }
        \\  CoraCExt.deep_nlr(CExtDeepHelper.new(callback))
        \\  "should-not-return-outer"
        \\end
        \\test_method
    );
    try std.testing.expectEqual(@as(i64, 88), result.toInteger());
}
