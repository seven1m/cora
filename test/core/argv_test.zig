const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const bdwgc = @import("bdwgc");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const getAllocator = test_helper.getAllocator;

test "ARGV constant exists and defaults to empty array" {
    const result = try evalCode("ARGV.length");
    try std.testing.expectEqual(@as(i64, 0), result.toInteger());
}

test "ARGV constant behaves like an array" {
    const result = try evalCode(
        \\ARGV << "first"
        \\ARGV[0]
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "first", result.toStringObject().str);
}

test "VM.setArgv sets ARGV constant to provided arguments" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    var parser = try prism.Parser.init(allocator, "", null);
    defer parser.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    try vm.prepare(&program);
    try vm.setArgv(&[_][]const u8{ "alpha", "beta", "gamma" });

    const argv_sym = try vm.intern("ARGV");
    const argv_val = vm.object_class.module.constants.get(argv_sym) orelse return error.TestExpectedEqual;

    try std.testing.expect(argv_val.isArray());
    const argv = argv_val.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), argv.len);
    try std.testing.expect(argv[0].isString());
    try std.testing.expect(argv[1].isString());
    try std.testing.expect(argv[2].isString());
    try std.testing.expectEqualSlices(u8, "alpha", argv[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "beta", argv[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "gamma", argv[2].toStringObject().str);
}

test "VM.setInputRecordSeparator updates $/ and $-0" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();
    var parser = try prism.Parser.init(allocator, "", null);
    defer parser.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    try vm.prepare(&program);
    try vm.setInputRecordSeparator(":", true);

    const input_record_separator = vm.globals.get("$/") orelse return error.TestExpectedEqual;
    const dash_zero = vm.globals.get("$-0") orelse return error.TestExpectedEqual;

    try std.testing.expect(input_record_separator.isString());
    try std.testing.expect(dash_zero.isString());
    try std.testing.expectEqualSlices(u8, ":", input_record_separator.toStringObject().str);
    try std.testing.expectEqualSlices(u8, ":", dash_zero.toStringObject().str);
    try std.testing.expect(input_record_separator.isFrozen());
    try std.testing.expect(dash_zero.isFrozen());
}
