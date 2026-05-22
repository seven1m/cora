const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const nonzero_sym = try vm.intern("nonzero?");
    try vm.numeric_class.module.methods.put(nonzero_sym, value.MethodEntry.builtin(&builtinNumericNonzero, .{ .exact = 0 }));
}

pub fn builtinNumericNonzero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const zero_result = try vm.callMethodByName(receiver, "zero?", &[_]Value{}, null);
    if (zero_result.is_truthy()) return Value.nil();
    return receiver;
}
