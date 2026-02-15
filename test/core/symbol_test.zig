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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, ":foo", result.data.string.str);
}

test "Symbol#to_s" {
    const result = try evalCode(":foo.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "Symbol#to_sym returns self" {
    const result = try evalCode(":foo.to_sym.to_s");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "Symbol#== compares symbol identity/value" {
    var result = try evalCode(":foo == :foo");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode(":foo == :bar");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);

    result = try evalCode(":foo == 'foo'");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Symbol#to_proc creates callable proc" {
    const result = try evalCode(":upcase.to_proc.call('tim')");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "TIM", result.data.string.str);
}
