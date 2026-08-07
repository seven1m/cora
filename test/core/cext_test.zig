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

test "C extension rb_funcall stops C execution when Ruby raises" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\begin
        \\  CoraCExt.funcall_then_value(proc { raise "from callback" })
        \\rescue => error
        \\  error.message
        \\end
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("from callback", result.toStringObject().str);
}

test "C extension rb_funcall stops C execution for Ruby throw" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\catch(:done) do
        \\  CoraCExt.funcall_then_value(proc { throw :done, 73 })
        \\end
    );
    try std.testing.expectEqual(@as(i64, 73), result.toInteger());
}

test "C extension calls continue inside an active ensure unwind" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def cext_ensure_return(trace)
        \\  begin
        \\    return :done
        \\  ensure
        \\    trace << CoraCExt.funcall_then_value(proc { :callback })
        \\    trace << :after
        \\  end
        \\end
        \\trace = []
        \\[cext_ensure_return(trace), trace]
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("done", elems[0].toSymbolObject().name);
    const trace = elems[1].toArrayObject().elements.items;
    try std.testing.expectEqualStrings("continued", trace[0].toStringObject().str);
    try std.testing.expectEqualStrings("after", trace[1].toSymbolObject().name);
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

test "C extension rb_yield `next` does not leak as non-local return" {
    // A block doing `next` should return the next's value to the C extension
    // and must not be misinterpreted as a non-local return. After the yield,
    // the C code does another rb_funcall to confirm the boundary state is
    // clean.
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.yield_next_then_value(123) { |marker| next marker }
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("123", result.toStringObject().str);
}

test "C extension rb_yield `break` returns the break value to C" {
    // Returning rb_yield directly makes the break value observable at the
    // Ruby call site, but does not by itself prove whether the C frame unwound.
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.yield_break(7) { |marker| break marker + 100 }
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 107), result.toInteger());
}

test "C extension rb_yield `break` unwinds past code after the yield" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.yield_break_then_value(7) { |marker| break marker + 100 }
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 107), result.toInteger());
}

test "C extension `next` in callback does not pollute later C calls" {
    // Direct repro for the JSON.parse-style bug: a `next` in a callback must
    // not cause a later C extension call (within or across frames) to see a
    // stale scalar from the previous non-local return path. The C code does
    // an rb_funcall on the value returned from rb_yield, which depends on
    // the boundary state being clean.
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.yield_next_then_call_to_s(:first) { |m| next m; :unreachable }
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("first", result.toStringObject().str);
}

test "C extension real non-local `return` still crosses C boundary" {
    // Sanity check: even after the refactor, a real `return` from a block
    // invoked via rb_yield must still escape the surrounding method.
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def outer
        \\  CoraCExt.yield_break(:ignored) { |_| return 999 }
        \\  :after
        \\end
        \\outer
    );
    try std.testing.expectEqual(@as(i64, 999), result.toInteger());
}

test "C extension real non-local `return` through rb_funcall still works" {
    // Sanity check: a `return` from a proc called via rb_funcall still
    // escapes the surrounding method.
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\def outer
        \\  callback = proc { return 314 }
        \\  CoraCExt.funcall_nlr(callback)
        \\  :after
        \\end
        \\outer
    );
    try std.testing.expectEqual(@as(i64, 314), result.toInteger());
}
