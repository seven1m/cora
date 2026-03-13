const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const warning_obj = Value.fromObject(vm.warning_module);
    const warning_singleton = try vm.getOrCreateSingletonClass(warning_obj);

    const get_sym = try vm.intern("[]");
    try warning_singleton.module.methods.put(get_sym, .{ .method = .{ .builtin = &builtinWarningGet } });

    const set_sym = try vm.intern("[]=");
    try warning_singleton.module.methods.put(set_sym, .{ .method = .{ .builtin = &builtinWarningSet } });
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

pub fn writeWarning(vm: *VM, message: []const u8) VMError!void {
    const stderr_target = vm.globals.get("$stderr") orelse return;
    const warning_val = try vm.newString(message, false);
    var args = [_]Value{warning_val};
    _ = try vm.callMethodByName(stderr_target, "write", args[0..], null);
}

pub fn warnBlockUnused(vm: *VM) VMError!void {
    try writeWarning(vm, "warning: given block not used\n");
}

fn isDeprecatedCategory(category: Value) bool {
    if (!category.isSymbol()) return false;
    return std.mem.eql(u8, category.toSymbolObject().name, "deprecated");
}
