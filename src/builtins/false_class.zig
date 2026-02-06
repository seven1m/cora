const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.false_class.module.methods.put(to_s_sym, .{ .builtin = &builtinFalseClassToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.false_class.module.methods.put(inspect_sym, .{ .builtin = &builtinFalseClassInspect });
}

pub fn builtinFalseClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return vm.newString("false", false);
}

pub fn builtinFalseClassInspect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinFalseClassToS(vm, receiver, args, block);
}
