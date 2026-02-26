const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const VM = cora.vm.VM;
const bdwgc = @import("bdwgc");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;
const getAllocator = test_helper.getAllocator;

test "Symbol interning - same address for identical symbols" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
    defer vm.deinit();

    const symbol1 = try vm.intern("foo");
    const symbol2 = try vm.intern("foo");
    const symbol3 = try vm.intern("bar");

    try std.testing.expectEqual(@intFromPtr(symbol1), @intFromPtr(symbol2));
    try std.testing.expect(@intFromPtr(symbol1) != @intFromPtr(symbol3));
}

test "Symbol#inspect" {
    const result = try evalCode(":foo.inspect");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, ":foo", result.toStringObject().str);
}

test "Symbol#to_s" {
    const result = try evalCode(":foo.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);
}

test "Symbol#encoding reflects symbol encoding" {
    var result = try evalCode(":foo.encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "US-ASCII", result.toStringObject().str);

    result = try evalCode("\"café\".to_sym.encoding.name");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "UTF-8", result.toStringObject().str);
}

test "Symbol#to_sym returns self" {
    const result = try evalCode(":foo.to_sym.to_s");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "foo", result.toStringObject().str);
}

test "Symbol#== compares symbol identity/value" {
    var result = try evalCode(":foo == :foo");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode(":foo == :bar");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());

    result = try evalCode(":foo == 'foo'");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Symbol#to_proc creates callable proc" {
    const result = try evalCode(":upcase.to_proc.call('tim')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "TIM", result.toStringObject().str);
}

test "String#to_sym canonicalizes ASCII-only symbols to US-ASCII" {
    const result = try evalCode("\"foo\".force_encoding(Encoding::UTF_8).to_sym.equal?(\"foo\".force_encoding(Encoding::US_ASCII).to_sym)");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "String#to_sym keeps non-ASCII symbols distinct by encoding" {
    const result = try evalCode("\"f\\xE9e\".force_encoding(Encoding::ISO_8859_1).to_sym == \"f\\xE9e\".force_encoding(Encoding::BINARY).to_sym");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "String#to_sym raises EncodingError for invalid bytes in UTF-8" {
    const result = try evalCode("begin; \"\\xC3\".force_encoding(Encoding::UTF_8).to_sym; rescue => e; [e.class == EncodingError, e.message]; end");
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expect(items[0].isBool());
    try std.testing.expectEqual(true, items[0].toBool());
    try std.testing.expect(items[1].isString());
    try std.testing.expectEqualSlices(u8, "invalid symbol in encoding UTF-8 :\"\\xC3\"", items[1].toStringObject().str);
}
