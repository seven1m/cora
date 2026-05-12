const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const warning_obj = Value.fromObject(&vm.warning_module.object);
    const warning_singleton = try vm.getOrCreateSingletonClass(warning_obj);

    const warn_sym = try vm.intern("warn");
    try warning_singleton.module.methods.put(warn_sym, value.MethodEntry.builtin(&builtinWarningWarn, .{ .exact = 1 }));

    const get_sym = try vm.intern("[]");
    try warning_singleton.module.methods.put(get_sym, value.MethodEntry.builtin(&builtinWarningGet, .{ .exact = 1 }));

    const set_sym = try vm.intern("[]=");
    try warning_singleton.module.methods.put(set_sym, value.MethodEntry.builtin(&builtinWarningSet, .{ .exact = 2 }));
}

pub fn builtinWarningGet(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (isDeprecatedCategory(args[0])) {
        return Value.boolean(vm.warning_deprecated_enabled);
    }
    return Value.nil();
}

pub fn builtinWarningSet(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (isDeprecatedCategory(args[0])) {
        vm.warning_deprecated_enabled = args[1].is_truthy();
    }
    return args[1];
}

pub fn builtinWarningWarn(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    var category: ?Value = null;
    try vm.consumeKeywordArgs(.{"category"}, .{&category});
    try vm.validateKeywordArgsConsumed();

    const message = try args[0].coerceToStr(vm, "no implicit conversion into String");
    try writeWarning(vm, message);
    return Value.nil();
}

pub fn writeWarning(vm: *VM, message: []const u8) VMError!void {
    const stderr_target = vm.globals.get("$stderr") orelse return;
    const warning_val = try vm.newString(message, false);
    var args = [_]Value{warning_val};
    _ = try vm.callMethodByName(stderr_target, "write", args[0..], null);
    _ = try vm.callMethodByName(stderr_target, "flush", &.{}, null);
}

pub fn warnBlockUnused(vm: *VM) VMError!void {
    const frame = vm.currentFrame();
    const source_file = frame.chunk.source_file orelse "(eval)";
    const ip = if (frame.ip == 0) 0 else frame.ip - 1;
    const line = if (frame.chunk.line_info.items.len == 0)
        @as(u32, 1)
    else blk: {
        const chunk_line = frame.chunk.getLine(ip);
        break :blk if (chunk_line == 0) @as(u32, 1) else chunk_line;
    };
    const warning = std.fmt.allocPrint(vm.allocator, "{s}:{d}: warning: given block not used\n", .{ source_file, line }) catch return error.Fatal;
    defer vm.allocator.free(warning);
    try writeWarning(vm, warning);
}

fn isDeprecatedCategory(category: Value) bool {
    if (!category.isSymbol()) return false;
    return std.mem.eql(u8, category.toSymbolObject().name, "deprecated");
}
