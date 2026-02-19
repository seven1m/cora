const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Empty array" {
    const result = try evalCode("[]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 0), result.data.array.elements.items.len);
}

test "Array with integers" {
    const result = try evalCode("[1, 2, 3]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Array with mixed types" {
    const result = try evalCode("[1, true, nil]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expect(result.data.array.elements.items[0].data == .integer);
    try std.testing.expect(result.data.array.elements.items[1].data == .boolean);
    try std.testing.expect(result.data.array.elements.items[2].data == .nil);
}

test "Array << append" {
    const result = try evalCode(
        \\[1, 2] << 3
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Array << chaining" {
    const result = try evalCode(
        \\[1] << 2 << 3
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
}

test "Nested arrays" {
    const result = try evalCode("[[1, 2], [3, 4]]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);

    const first_array = result.data.array.elements.items[0];
    try std.testing.expect(first_array.data == .array);
    try std.testing.expectEqual(@as(usize, 2), first_array.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), first_array.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), first_array.data.array.elements.items[1].data.integer);

    const second_array = result.data.array.elements.items[1];
    try std.testing.expect(second_array.data == .array);
    try std.testing.expectEqual(@as(usize, 2), second_array.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 3), second_array.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 4), second_array.data.array.elements.items[1].data.integer);
}

test "Array#inspect with integers" {
    const result = try evalCode("[1, 2, 3].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.data.string.str);
}

test "Array#inspect with strings" {
    const result = try evalCode("[\"a\", \"b\"].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[\"a\", \"b\"]", result.data.string.str);
}

test "Array#inspect mixed types" {
    const result = try evalCode("[1, \"hi\", :foo, nil].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, \"hi\", :foo, nil]", result.data.string.str);
}

test "Array#inspect empty" {
    const result = try evalCode("[].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[]", result.data.string.str);
}

test "Array#inspect nested" {
    const result = try evalCode("[[1, 2], [3, 4]].inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[[1, 2], [3, 4]]", result.data.string.str);
}

test "Array#to_s" {
    const result = try evalCode("[1, 2, 3].to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, 2, 3]", result.data.string.str);
}

test "Array#size" {
    const result = try evalCode("[1, 2, 3].size");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "Array#map" {
    const result = try evalCode("[1, 2, 3].map { |x| x * 2 }");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 4), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 6), result.data.array.elements.items[2].data.integer);
}

test "Array#each propagates break value" {
    var result = try evalCode("a = [1, 2, 3]; a.each { |x| break :done if x == 2 }");
    try std.testing.expect(result.data == .symbol);
    try std.testing.expectEqualSlices(u8, "done", result.data.symbol.name);

    result = try evalCode("a = [1, 2, 3]; a.each { break }");
    try std.testing.expect(result.data == .nil);
}

test "Array#any?" {
    var result = try evalCode("[nil, false, 1].any?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("[nil, false].any?");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);

    result = try evalCode("[1, 2, 3].any? { |x| x > 2 }");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Array#include?" {
    var result = try evalCode("[1, 2, 3].include?(2)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("[1, 2, 3].include?(9)");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Array#join" {
    var result = try evalCode("[1, 2, 3].join");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "123", result.data.string.str);

    result = try evalCode("[1, 2, 3].join('-')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "1-2-3", result.data.string.str);
}

test "Array#first and Array#last" {
    var result = try evalCode("[1, 2, 3].first");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("[1, 2, 3].last");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.integer);

    result = try evalCode("[].first");
    try std.testing.expect(result.data == .nil);

    result = try evalCode("[].last");
    try std.testing.expect(result.data == .nil);
}

test "Array#[]= set and extend" {
    var result = try evalCode("a = [1, 2, 3]; a[1] = 9; a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 9), result.data.array.elements.items[1].data.integer);

    result = try evalCode("a = [1]; a[3] = 5; a.inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[1, nil, nil, 5]", result.data.string.str);

    result = try evalCode("a = [1, 2, 3]; a[-1] = 7; a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 7), result.data.array.elements.items[2].data.integer);
}

test "Array#map! mutates in place" {
    const result = try evalCode("a = [1, 2, 3]; a.map! { |x| x + 10 }; a");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 11), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 12), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 13), result.data.array.elements.items[2].data.integer);
}

test "Array#& intersection" {
    const result = try evalCode("[1, 2, 2, 3] & [2, 3, 4]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[1].data.integer);
}

test "Array#| union" {
    const result = try evalCode("[1, 2, 2] | [2, 3, 1, 4]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 4), result.data.array.elements.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 3), result.data.array.elements.items[2].data.integer);
    try std.testing.expectEqual(@as(i64, 4), result.data.array.elements.items[3].data.integer);
}

test "Array#pack integer directives" {
    var result = try evalCode("[1, 2, 255].pack('C*')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\x01\x02\xff", result.data.string.str);

    result = try evalCode("[0x1234].pack('n').unpack('C*').inspect");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "[18, 52]", result.data.string.str);
}

test "Array#pack string directives" {
    var result = try evalCode("['ab'].pack('A4')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "ab  ", result.data.string.str);

    result = try evalCode("['ab'].pack('a4')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.data.string.str);

    result = try evalCode("['ab'].pack('Z4')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "ab\x00\x00", result.data.string.str);
}

test "Array#pack cursor directives" {
    var result = try evalCode("[1, 2].pack('CXC')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\x02", result.data.string.str);

    result = try evalCode("[1, 2].pack('C@3C')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "\x01\x00\x00\x02", result.data.string.str);
}
