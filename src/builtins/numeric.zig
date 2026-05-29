const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const zero_q_sym = try vm.intern("zero?");
    try vm.numeric_class.module.methods.put(zero_q_sym, value.MethodEntry.builtin(&builtinNumericZero, .{ .exact = 0 }));

    const nonzero_sym = try vm.intern("nonzero?");
    try vm.numeric_class.module.methods.put(nonzero_sym, value.MethodEntry.builtin(&builtinNumericNonzero, .{ .exact = 0 }));

    const positive_q_sym = try vm.intern("positive?");
    try vm.numeric_class.module.methods.put(positive_q_sym, value.MethodEntry.builtin(&builtinNumericPositiveQ, .{ .exact = 0 }));

    const negative_q_sym = try vm.intern("negative?");
    try vm.numeric_class.module.methods.put(negative_q_sym, value.MethodEntry.builtin(&builtinNumericNegativeQ, .{ .exact = 0 }));
}

pub fn builtinNumericZero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const zero_result = try vm.callMethodByName(receiver, "==", compare_args[0..], null);
    return Value.boolean(zero_result.is_truthy());
}

pub fn builtinNumericNonzero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const zero_result = try vm.callMethodByName(receiver, "zero?", &[_]Value{}, null);
    if (zero_result.is_truthy()) return Value.nil();
    return receiver;
}

pub fn builtinNumericPositiveQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const result = try vm.callMethodByName(receiver, ">", compare_args[0..], null);
    return Value.boolean(result.is_truthy());
}

pub fn builtinNumericNegativeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const result = try vm.callMethodByName(receiver, "<", compare_args[0..], null);
    return Value.boolean(result.is_truthy());
}
