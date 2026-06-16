const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const argf_obj = try vm.newInstance(vm.object_class);
    const argf_singleton = try vm.getOrCreateSingletonClass(argf_obj);

    const enumerable_sym = try vm.intern("Enumerable");
    const enumerable_entry = vm.object_class.module.constants.get(enumerable_sym) orelse return error.Fatal;
    try vm.includeModule(&argf_singleton.module, enumerable_entry.value.toModuleObject());

    const argf_sym = try vm.intern("ARGF");
    vm.object_class.module.constants.put(argf_sym, .{ .value = argf_obj }) catch return error.Fatal;
}
