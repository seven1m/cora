const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Empty array" {
    const result = try evalCode("[]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 0), result.toArrayObject().elements.items.len);
}

test "Array with integers" {
    const result = try evalCode("[1, 2, 3]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Array with mixed types" {
    const result = try evalCode("[1, true, nil]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expect(result.toArrayObject().elements.items[0].isInteger());
    try std.testing.expect(result.toArrayObject().elements.items[1].isBool());
    try std.testing.expect(result.toArrayObject().elements.items[2].isNil());
}

test "Array << append" {
    const result = try evalCode(
        \\[1, 2] << 3
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Array << chaining" {
    const result = try evalCode(
        \\[1] << 2 << 3
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
}

test "Nested arrays" {
    const result = try evalCode("[[1, 2], [3, 4]]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);

    const first_array = result.toArrayObject().elements.items[0];
    try std.testing.expect(first_array.isArray());
    try std.testing.expectEqual(@as(usize, 2), first_array.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), first_array.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), first_array.toArrayObject().elements.items[1].toInteger());

    const second_array = result.toArrayObject().elements.items[1];
    try std.testing.expect(second_array.isArray());
    try std.testing.expectEqual(@as(usize, 2), second_array.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), second_array.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), second_array.toArrayObject().elements.items[1].toInteger());
}

test "Array#inspect with integers" {
    const result = try evalCode("[1, 2, 3].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array#inspect with strings" {
    const result = try evalCode("[\"a\", \"b\"].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[\"a\", \"b\"]", result.toStringObject().str);
}

test "Array#inspect mixed types" {
    const result = try evalCode("[1, \"hi\", :foo, nil].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, \"hi\", :foo, nil]", result.toStringObject().str);
}

test "Array#inspect empty" {
    const result = try evalCode("[].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[]", result.toStringObject().str);
}

test "Array#inspect nested" {
    const result = try evalCode("[[1, 2], [3, 4]].inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[[1, 2], [3, 4]]", result.toStringObject().str);
}

test "Array#inspect recursive" {
    const result = try evalCode(
        \\a = [1, 2, 3]
        \\a << a
        \\a.inspect
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3, [...]]", result.toStringObject().str);
}

test "Array#to_s" {
    const result = try evalCode("[1, 2, 3].to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.toStringObject().str);
}

test "Array#size" {
    const result = try evalCode("[1, 2, 3].size");
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "Array#map" {
    const result = try evalCode("[1, 2, 3].map { |x| x * 2 }");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 6), result.toArrayObject().elements.items[2].toInteger());
}

test "Array#each propagates break value" {
    var result = try evalCode("a = [1, 2, 3]; a.each { |x| break :done if x == 2 }");
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "done", result.toSymbolObject().name);

    result = try evalCode("a = [1, 2, 3]; a.each { break }");
    try std.testing.expect(result.isNil());
}

test "Array#any?" {
    var result = try evalCode("[nil, false, 1].any?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("[nil, false].any?");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());

    result = try evalCode("[1, 2, 3].any? { |x| x > 2 }");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Array#include?" {
    var result = try evalCode("[1, 2, 3].include?(2)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("[1, 2, 3].include?(9)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Array#[]= set and extend" {
    var result = try evalCode("a = [1, 2, 3]; a[1] = 9; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[1].toInteger());

    result = try evalCode("a = [1]; a[3] = 5; a.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[1, nil, nil, 5]", result.toStringObject().str);

    result = try evalCode("a = [1, 2, 3]; a[-1] = 7; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[2].toInteger());
}

test "Array#map! mutates in place" {
    const result = try evalCode("a = [1, 2, 3]; a.map! { |x| x + 10 }; a");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 11), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 12), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 13), result.toArrayObject().elements.items[2].toInteger());
}

test "Array#& intersection" {
    const result = try evalCode("[1, 2, 2, 3] & [2, 3, 4]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[1].toInteger());
}

test "Array#| union" {
    const result = try evalCode("[1, 2, 2] | [2, 3, 1, 4]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 4), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[3].toInteger());
}

test "Array#pack integer directives" {
    var result = try evalCode("[1, 2, 255].pack('C*')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x01\x02\xff", result.toStringObject().str);

    result = try evalCode("[0x1234].pack('n').unpack('C*').inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "[18, 52]", result.toStringObject().str);
}

test "Array#pack float directives honor respond_to_missing? for to_f" {
    const result = try evalCode(
        \\obj = Object.new
        \\def obj.respond_to_missing?(name, include_private = false)
        \\  name == :to_f || super
        \\end
        \\def obj.method_missing(name, *args, &block)
        \\  return 3.5 if name == :to_f
        \\  super
        \\end
        \\[obj].pack('G').bytesize
    );
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Array#dup dispatches initialize_dup and initialize_copy overrides" {
    var result = try evalCode(
        \\class ArrayDupHookSpec < Array
        \\  def initialize_dup(other)
        \\    @hook = :dup
        \\    super
        \\  end
        \\
        \\  def initialize_copy(other)
        \\    @copy = other[0]
        \\    super
        \\  end
        \\end
        \\
        \\source = ArrayDupHookSpec[7]
        \\source.instance_variable_set(:@kept, 9)
        \\duped = source.dup
        \\[duped.instance_variable_get(:@hook), duped.instance_variable_get(:@copy), duped.instance_variable_get(:@kept), duped[0], duped.class == ArrayDupHookSpec]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "dup", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[3].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[4].toBool());
}

test "Array#dup can reach method_missing for initialize_copy after undef_method" {
    const result = try evalCode(
        \\class ArrayDupMissingSpec < Array
        \\  undef_method :initialize_copy
        \\
        \\  def respond_to_missing?(name, include_private = false)
        \\    name == :initialize_copy
        \\  end
        \\
        \\  def method_missing(name, *args)
        \\    replace([:mm])
        \\    self
        \\  end
        \\end
        \\
        \\ArrayDupMissingSpec[1, 2].dup == [:mm]
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Array#clone dispatches initialize_clone, preserves frozen state, and copies singleton methods" {
    const result = try evalCode(
        \\class ArrayCloneHookSpec < Array
        \\  def initialize_clone(other)
        \\    @hook = :clone
        \\    super
        \\  end
        \\end
        \\
        \\source = ArrayCloneHookSpec[7]
        \\source.instance_variable_set(:@kept, 9)
        \\def source.special
        \\  :singleton
        \\end
        \\source.freeze
        \\cloned = source.clone
        \\[
        \\  cloned.instance_variable_get(:@hook),
        \\  cloned.instance_variable_get(:@kept),
        \\  cloned[0],
        \\  cloned.class == ArrayCloneHookSpec,
        \\  cloned.frozen?,
        \\  cloned.special
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "clone", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 9), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 7), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[3].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[4].toBool());
    try std.testing.expectEqualSlices(u8, "singleton", result.toArrayObject().elements.items[5].toSymbolObject().name);
}

test "Array#pack string directives" {
    var result = try evalCode("['ab'].pack('A4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab  ", result.toStringObject().str);

    result = try evalCode("['ab'].pack('a4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.toStringObject().str);

    result = try evalCode("['ab'].pack('Z4')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.toStringObject().str);
}

test "Array#pack cursor directives" {
    var result = try evalCode("[1, 2].pack('CXC')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x02", result.toStringObject().str);

    result = try evalCode("[1, 2].pack('C@3C')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "\x01\x00\x00\x02", result.toStringObject().str);
}
