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

test "C extension numeric st tables support insert lookup iteration and deletion" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.st_table
    );
    const items = result.toArrayObject().elements.items;
    const expected = [_]i64{ 7, 1, 4, 1, 1, 0 };
    for (items, expected) |item, value| {
        try std.testing.expectEqual(value, item.toInteger());
    }
}

test "C extension Check_Type accepts arrays and raises for other types" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\begin
        \\  CoraCExt.check_array_type(42)
        \\rescue TypeError => error
        \\  [CoraCExt.check_array_type([]), error.message]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].toBool());
    try std.testing.expectEqualStrings("wrong argument type Integer (expected Array)", values[1].toStringObject().str);
}

test "C extension rb_raise formats varargs messages" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\begin
        \\  CoraCExt.raise_formatted
        \\rescue RuntimeError => error
        \\  error.message
        \\end
    );
    try std.testing.expectEqualStrings("alias value bad 3 4 text %", result.toStringObject().str);
}

test "C extension percent V formats an object's string value" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.format_class([])
    );
    try std.testing.expectEqualStrings("class Array", result.toStringObject().str);
}

test "C extension defines constants on modules" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt::FIXTURE_VALUE
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "C extension method works on arbitrary receiver" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\"hello".cora_cext_test
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "C extension CLASS_OF returns singleton class without changing rb_obj_class" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\klass = Class.new
        \\[
        \\  CoraCExt.class_of(klass).equal?(klass.singleton_class),
        \\  CoraCExt.obj_class(klass).equal?(Class),
        \\]
    );
    for (result.toArrayObject().elements.items) |element| {
        try std.testing.expect(element.toBool());
    }
}

test "C extension accesses and detects instance variables" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.ivar_access(Object.new)
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 42), values[0].toInteger());
    try std.testing.expect(values[1].toBool());
    try std.testing.expect(!values[2].toBool());
}

test "C extension deletes and stores array elements" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.array_mutation
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    const array = values[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), array.len);
    try std.testing.expectEqual(@as(i64, 2), array[0].toInteger());
    try std.testing.expect(array[1].isNil());
    try std.testing.expectEqual(@as(i64, 4), array[2].toInteger());
}

test "C extension extracts array subsequences" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\array = [1, 2, 3, 4, 5]
        \\[
        \\  CoraCExt.array_subseq(array, 1, 3) == [2, 3, 4],
        \\  CoraCExt.array_subseq(array, 1, 0) == [],
        \\  CoraCExt.array_subseq(array, 6, 3).nil?,
        \\  CoraCExt.array_subseq(array, 4, 3) == [5],
        \\  CoraCExt.array_subseq(array, 1, -1).nil?,
        \\  CoraCExt.array_subseq(array, -2, 2) == [4, 5]
        \\]
    );
    for (result.toArrayObject().elements.items) |element| {
        try std.testing.expect(element.toBool());
    }
}

test "C extension pops array elements" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\array = [1, 2, 3]
        \\[CoraCExt.array_pop(array), array, CoraCExt.array_pop([])]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 3), values[0].toInteger());
    try std.testing.expectEqual(@as(usize, 2), values[1].toArrayObject().elements.items.len);
    try std.testing.expect(values[2].isNil());
}

test "C extension reads interned ID names" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\[CoraCExt.id2name(:test_symbol), CoraCExt.id2name_zero]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("test_symbol", values[0].toStringObject().str);
    try std.testing.expect(values[1].isNil());
}

test "C extension calls Ruby iterators with a C block" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.block_call_collect([1, 2, 3])
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), values.len);
    for (values, 1..) |item, expected| try std.testing.expectEqual(@as(i64, @intCast(expected)), item.toInteger());
}

test "C extension breaks Ruby iteration from a C block" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.block_call_break([1, 2, 3])
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isNil());
    const collected = values[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), collected.len);
    try std.testing.expectEqual(@as(i64, 1), collected[0].toInteger());
}

test "C extension forwards an existing Ruby block" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\mapped = CoraCExt.block_call_forward([1, 2, 3]) { |value| value * 2 }
        \\unmapped = CoraCExt.block_call_forward([1, 2, 3])
        \\[mapped, unmapped.is_a?(Enumerator)]
    );
    const values = result.toArrayObject().elements.items;
    const mapped = values[0].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), mapped.len);
    for (mapped, 1..) |item, expected| try std.testing.expectEqual(@as(i64, @intCast(expected * 2)), item.toInteger());
    try std.testing.expect(values[1].toBool());
}

test "C extension catch receives returns and Ruby throws" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.catch_control_flow(42)
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 42), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 42), values[1].toInteger());
}

test "C extension call and block helpers invoke Ruby code" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.call_helpers(5) { |value| value * 2 }
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 24), values[0].toInteger());
    try std.testing.expectEqualStrings("Integer!", values[1].toStringObject().str);
}

test "C extension creates exceptions from C strings" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.exception_message
    );
    try std.testing.expectEqualStrings("from C", result.toStringObject().str);
}

test "C extension updates exception messages through the mesg ivar" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.exception_ivar_message.message
    );
    try std.testing.expectEqualStrings("updated", result.toStringObject().str);
}

test "C extension path to class raises for missing and nonclass constants" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraPathValue = 42
        \\found = CoraCExt.path_to_class("String") == String
        \\missing = begin; CoraCExt.path_to_class("CoraMissingPath"); rescue ArgumentError => error; error.message; end
        \\wrong = begin; CoraCExt.path_to_class("CoraPathValue"); rescue TypeError => error; error.message; end
        \\[found, missing, wrong]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expectEqualStrings("undefined class/module CoraMissingPath", values[1].toStringObject().str);
    try std.testing.expectEqualStrings("CoraPathValue does not refer to class/module", values[2].toStringObject().str);
}

test "C extension associates string encodings by index" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\bytes = "text".encode("UTF-16LE").force_encoding(Encoding::BINARY)
        \\encoded = CoraCExt.associate_utf16le(bytes)
        \\[encoded.equal?(bytes), encoded.encoding.name, encoded.codepoints]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expectEqualStrings("UTF-16LE", values[1].toStringObject().str);
    const codepoints = values[2].toArrayObject().elements.items;
    const expected = [_]i64{ 't', 'e', 'x', 't' };
    for (codepoints, expected) |actual, codepoint| try std.testing.expectEqual(codepoint, actual.toInteger());
}

test "C extension appends raw bytes without changing string encoding" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\string = "a".encode("UTF-16LE")
        \\result = CoraCExt.append_raw_utf16(string)
        \\[result.equal?(string), result.encoding.name, result.codepoints]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expectEqualStrings("UTF-16LE", values[1].toStringObject().str);
    const codepoints = values[2].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), codepoints.len);
    try std.testing.expectEqual(@as(i64, 'a'), codepoints[0].toInteger());
    try std.testing.expectEqual(@as(i64, 0), codepoints[1].toInteger());
}

test "C extension exports strings to the default internal encoding" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\Encoding.default_internal = "EUC-JP"
        \\encoded = CoraCExt.export_to_internal("plain")
        \\[encoded.encoding.name, encoded]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("EUC-JP", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("plain", values[1].toStringObject().str);
}

test "C extension packs signed 64-bit integers" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\[
        \\  CoraCExt.integer_pack(2 ** 63 - 1),
        \\  CoraCExt.integer_pack(-(2 ** 63)),
        \\  CoraCExt.integer_pack(2 ** 63),
        \\  CoraCExt.integer_pack(-(2 ** 63) - 1),
        \\]
    );
    const rows = result.toArrayObject().elements.items;
    const expected_statuses = [_]i64{ 1, -1, 2, -2 };
    for (rows, expected_statuses) |row, status| {
        try std.testing.expectEqual(status, row.toArrayObject().elements.items[0].toInteger());
    }
    try std.testing.expectEqualStrings("9223372036854775807", rows[0].toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualStrings("-9223372036854775808", rows[1].toArrayObject().elements.items[1].toStringObject().str);
}

test "C extension identifies large integers as bignums" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\[CoraCExt.integer_type(42), CoraCExt.integer_type(2 ** 63),
        \\ CoraCExt.long_roundtrip(2 ** 63 - 1).to_s,
        \\ CoraCExt.long_roundtrip(-(2 ** 63)).to_s]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0x15), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 0x0a), values[1].toInteger());
    try std.testing.expectEqualStrings("9223372036854775807", values[2].toStringObject().str);
    try std.testing.expectEqualStrings("-9223372036854775808", values[3].toStringObject().str);
}

test "C extension concatenates and encodes strings" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_encoding_helpers
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("leftright", values[0].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 0), values[1].toInteger());
}

test "C extension creates strings and copies their encoding" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_encoding_creation.map { |string| [string.bytes, string.encoding] }
    );
    for (result.toArrayObject().elements.items) |entry| {
        const values = entry.toArrayObject().elements.items;
        try std.testing.expectEqual(@as(i64, 128), values[0].toArrayObject().elements.items[0].toInteger());
        try std.testing.expect(values[1].toEncodingObject().encoding.eql(.{ .ascii_8bit = .{} }));
    }
}

test "C extension string constructors assign MRI encodings" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_constructor_encodings.map { |string| string.encoding.name }
    );
    const names = result.toArrayObject().elements.items;
    const expected = [_][]const u8{ "ASCII-8BIT", "ASCII-8BIT", "UTF-8", "UTF-8", "US-ASCII" };
    for (names, expected) |name, encoding_name| {
        try std.testing.expectEqualStrings(encoding_name, name.toStringObject().str);
    }
}

test "C extension StringValue accepts embedded null bytes" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_value([97, 0, 98].pack("C*")).bytes
    );
    const bytes = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), bytes.len);
    try std.testing.expectEqual(@as(i64, 0), bytes[1].toInteger());
}

test "C extension StringValue uses to_str and rejects nil" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\string_like = Object.new
        \\def string_like.to_str; "converted"; end
        \\def string_like.to_s; "wrong"; end
        \\converted = CoraCExt.string_value(string_like)
        \\error = begin; CoraCExt.string_value(nil); rescue TypeError => e; e.message; end
        \\[converted, error]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("converted", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("no implicit conversion of nil into String", values[1].toStringObject().str);
}

test "C extension can undefine new on one class singleton" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\klass = Class.new
        \\CoraCExt.undef_class_new(klass)
        \\[
        \\  klass.respond_to?(:new),
        \\  Class.respond_to?(:new),
        \\  Object.new.class.equal?(Object),
        \\]
    );
    const elements = result.toArrayObject().elements.items;
    try std.testing.expect(!elements[0].toBool());
    try std.testing.expect(elements[1].toBool());
    try std.testing.expect(elements[2].toBool());
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

test "C extension rb_str_new rejects negative lengths" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\begin
        \\  CoraCExt.str_new_length(-1)
        \\rescue => error
        \\  [error.class == ArgumentError, error.message]
        \\end
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].toBool());
    try std.testing.expectEqualStrings("negative string size (or size too big)", elems[1].toStringObject().str);
}

test "C extension rb_intern2 honors the explicit length" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.intern_length
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("abc", result.toSymbolObject().name);
}

test "C extension rb_str_new_static honors the explicit length" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.static_string
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("abc", result.toStringObject().str);
}

test "C extension NUM2LONG rejects out-of-range integers" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\begin
        \\  CoraCExt.str_new_length(2 ** 100)
        \\rescue => error
        \\  [error.class == RangeError, error.message]
        \\end
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].toBool());
    try std.testing.expectEqualStrings("bignum too big to convert into 'long'", elems[1].toStringObject().str);
}

test "C extension FIX2LONG preserves negative fixnums" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\[-10, -1, 0, 1, 10].map { |value| CoraCExt.fixnum_to_long(value) }
    );
    const values = result.toArrayObject().elements.items;
    const expected = [_]i64{ -10, -1, 0, 1, 10 };
    for (values, expected) |value, number| {
        try std.testing.expectEqual(number, value.toInteger());
    }
}

test "C extension typed data preserves type and payload" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.typed_data_round_trip
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0x0c), values[0].toInteger());
    try std.testing.expectEqual(@as(i64, 42), values[1].toInteger());
}

test "C extension typed data can assign payload after allocation" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.typed_data_assign_after_alloc
    );
    try std.testing.expectEqual(@as(i64, 73), result.toInteger());
}

test "C extension appends encoded bytes to an external string" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\str = CoraCExt.encoded_string_append
        \\str == "caf\u{e9}" && str.encoding.name == "UTF-8"
    );
    try std.testing.expect(result.toBool());
}

test "C extension converts an Encoding object to an encoding pointer" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.to_encoding(Encoding::UTF_8) == Encoding::UTF_8
    );
    try std.testing.expect(result.toBool());
}

test "C extension string splitting uses Ruby semantics" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.split_string(" a  b ") == ["a", "b"]
    );
    try std.testing.expect(result.toBool());
}

test "C extension block requirement raises when no block is given" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.needs_block { } && begin
        \\  CoraCExt.needs_block
        \\  false
        \\rescue LocalJumpError => e
        \\  e.message == "no block given"
        \\end
    );
    try std.testing.expect(result.toBool());
}

test "C extension method calls its superclass method" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\class CoraCExt::SuperBase
        \\  def greeting(name); "hello " + name; end
        \\end
        \\CoraCExt::SuperChild.new.greeting("Cora")
    );
    try std.testing.expectEqualStrings("hello Cora", result.toStringObject().str);
}

test "C extension object initialization forwards arguments and block" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\class CoraCExt::InitTarget
        \\  attr_reader :value
        \\  def initialize(x); @value = yield(x); end
        \\end
        \\CoraCExt.alloc_and_init(CoraCExt::InitTarget, 2) { |x| x + 3 }.value
    );
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "C extension registers protected methods" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\class CoraCExt::SuperChild
        \\  def read_value(other); other.protected_value; end
        \\end
        \\one = CoraCExt::SuperChild.new
        \\two = CoraCExt::SuperChild.new
        \\one.read_value(two) == 7 && CoraCExt::SuperChild.protected_instance_methods(false).include?(:protected_value)
    );
    try std.testing.expect(result.toBool());
}

test "C extension reports object class and pointer identity" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\name, pointer = CoraCExt.object_identity("hello")
        \\name == "String" && pointer.is_a?(Integer) && pointer > 0
    );
    try std.testing.expect(result.toBool());
}

test "C extension normalizes range bounds for slicing" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.range_bounds(1..3, 5) == [true, 1, 3] &&
        \\CoraCExt.range_bounds(-3...-1, 5) == [true, 2, 2] &&
        \\CoraCExt.range_bounds(5..9, 5) == [true, 5, 0] &&
        \\CoraCExt.range_bounds(6..9, 5)[0].nil? &&
        \\CoraCExt.range_bounds(2, 5)[0] == false
    );
    try std.testing.expect(result.toBool());
}

test "C extension converts encoded strings and integer values" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\str = CoraCExt.converted_string
        \\str.encoding.name == "ISO-8859-1" && str.bytes == [99, 97, 102, 233] && CoraCExt.integer("12") == 12
    );
    try std.testing.expect(result.toBool());
}

test "C extension keeps values at registered external addresses alive" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.register_external_root("rooted-" + ("x" * 1024))
        \\10.times { 1000.times { "garbage" * 128 }; GC.start }
        \\survived = CoraCExt.read_external_root == "rooted-" + ("x" * 1024)
        \\CoraCExt.unregister_external_root
        \\survived
    );
    try std.testing.expect(result.toBool());
}

test "C extension converts objects to strings and clears arrays" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\ary = [1, 2]
        \\CoraCExt.string_and_clear(:symbol, ary) == ["symbol", []] && ary.empty?
    );
    try std.testing.expect(result.toBool());
}

test "C extension typed data keeps referenced Ruby objects alive" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\value = "retained-value-" + ("x" * 1024)
        \\holder = CoraCExt.typed_data_retain(value)
        \\value = nil
        \\10.times do
        \\  1000.times { "garbage" * 128 }
        \\  GC.start
        \\end
        \\CoraCExt.typed_data_retained(holder) == "retained-value-" + ("x" * 1024)
    );
    try std.testing.expect(result.toBool());
}

test "C extension StringValueCStr provides a trailing null byte" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_value_cstr_length("hello")
    );
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "C extension StringValueCStr uses to_str and rejects unrelated objects" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\string_like = Object.new
        \\def string_like.to_str; "hello"; end
        \\length = CoraCExt.string_value_cstr_length(string_like)
        \\raised_type_error = begin
        \\  CoraCExt.string_value_cstr_length(Object.new)
        \\rescue => error
        \\  error.is_a?(TypeError)
        \\end
        \\[length, raised_type_error]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 5), values[0].toInteger());
    try std.testing.expect(values[1].toBool());
}

test "C extension variadic methods receive keyword arguments through rb_scan_args" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\a = CoraCExt.scan_keywords("one", exception: false)
        \\b = CoraCExt.scan_keywords("one", 2, exception: true)
        \\[a[0], a[1], a[2], a[3][:exception], b[0], b[2], b[3][:exception]]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), values[0].toInteger());
    try std.testing.expectEqualStrings("one", values[1].toStringObject().str);
    try std.testing.expect(values[2].isNil());
    try std.testing.expect(!values[3].toBool());
    try std.testing.expectEqual(@as(i64, 2), values[4].toInteger());
    try std.testing.expectEqual(@as(i64, 2), values[5].toInteger());
    try std.testing.expect(values[6].toBool());
}

test "C extension rb_scan_args collects remaining positional arguments" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\a = CoraCExt.scan_rest
        \\b = CoraCExt.scan_rest(1, 2, 3)
        \\c = CoraCExt.scan_required_rest("first", "second", "third")
        \\[a, b, c]
    );
    const groups = result.toArrayObject().elements.items;
    const empty = groups[0].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), empty[0].toInteger());
    try std.testing.expectEqual(@as(usize, 0), empty[1].toArrayObject().elements.items.len);

    const all = groups[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 3), all[0].toInteger());
    const all_rest = all[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), all_rest.len);
    try std.testing.expectEqual(@as(i64, 1), all_rest[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), all_rest[2].toInteger());

    const required = groups[2].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 3), required[0].toInteger());
    try std.testing.expectEqualStrings("first", required[1].toStringObject().str);
    try std.testing.expectEqualStrings("second", required[2].toStringObject().str);
    const required_rest = required[3].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 1), required_rest.len);
    try std.testing.expectEqualStrings("third", required_rest[0].toStringObject().str);
}

test "C extension rb_str_buf_new starts empty and can be appended" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.string_buffer
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("", values[0].toStringObject().str);
    try std.testing.expectEqualStrings("content", values[1].toStringObject().str);
}

test "C extension rb_ary_entry returns nil outside array bounds" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\CoraCExt.array_entries
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isNil());
    try std.testing.expect(values[1].isNil());
    try std.testing.expect(values[2].isNil());
    try std.testing.expectEqual(@as(i64, 9), values[3].toInteger());
}
