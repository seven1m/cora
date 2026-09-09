const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const real_sym = try vm.intern("real");
    try vm.complex_class.module.methods.put(real_sym, value.MethodEntry.builtin(&builtinComplexReal, .{ .exact = 0 }));

    const real_q_sym = try vm.intern("real?");
    try vm.complex_class.module.methods.put(real_q_sym, value.MethodEntry.builtin(&builtinComplexRealQ, .{ .exact = 0 }));
}

fn builtinComplexRealQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(false);
}

fn builtinComplexReal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toComplexObject().real;
}
