const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const enumerable_sym = try vm.intern("Enumerable");
    const enumerable_val = vm.object_class.module.constants.get(enumerable_sym) orelse return error.Fatal;
    const entries_sym = try vm.intern("entries");
    try enumerable_val.toModuleObject().methods.put(entries_sym, .{ .method = .{ .builtin = &builtinEnumerableEntries } });
}

fn builtinEnumerableEntries(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.callMethodByName(receiver, "to_a", &.{}, null);
}
