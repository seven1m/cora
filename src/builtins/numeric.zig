const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const comparable_sym = try vm.intern("Comparable");
    if (vm.object_class.module.constants.get(comparable_sym)) |comparable_val| {
        try vm.includeModule(&vm.numeric_class.module, comparable_val.value.toModuleObject());
    }

    const zero_q_sym = try vm.intern("zero?");
    try vm.numeric_class.module.methods.put(zero_q_sym, value.MethodEntry.builtin(&builtinNumericZero, .{ .exact = 0 }));

    const nonzero_sym = try vm.intern("nonzero?");
    try vm.numeric_class.module.methods.put(nonzero_sym, value.MethodEntry.builtin(&builtinNumericNonzero, .{ .exact = 0 }));

    const positive_q_sym = try vm.intern("positive?");
    try vm.numeric_class.module.methods.put(positive_q_sym, value.MethodEntry.builtin(&builtinNumericPositiveQ, .{ .exact = 0 }));

    const negative_q_sym = try vm.intern("negative?");
    try vm.numeric_class.module.methods.put(negative_q_sym, value.MethodEntry.builtin(&builtinNumericNegativeQ, .{ .exact = 0 }));

    const imag_sym = try vm.intern("imag");
    try vm.numeric_class.module.methods.put(imag_sym, value.MethodEntry.builtin(&builtinNumericImag, .{ .exact = 0 }));

    const imaginary_sym = try vm.intern("imaginary");
    try vm.numeric_class.module.methods.put(imaginary_sym, value.MethodEntry.builtin(&builtinNumericImag, .{ .exact = 0 }));

    const integer_q_sym = try vm.intern("integer?");
    try vm.numeric_class.module.methods.put(integer_q_sym, value.MethodEntry.builtin(&builtinNumericIntegerQ, .{ .exact = 0 }));
}

pub fn builtinNumericIntegerQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.isInteger());
}

pub fn builtinNumericZero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const zero_result = try vm.callMethodByName(receiver, "==", compare_args[0..], null);
    return Value.boolean(zero_result.isTruthy());
}

pub fn builtinNumericNonzero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const zero_result = try vm.callMethodByName(receiver, "zero?", &[_]Value{}, null);
    if (zero_result.isTruthy()) return Value.nil();
    return receiver;
}

pub fn builtinNumericPositiveQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const result = try vm.callMethodByName(receiver, ">", compare_args[0..], null);
    return Value.boolean(result.isTruthy());
}

pub fn builtinNumericNegativeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const result = try vm.callMethodByName(receiver, "<", compare_args[0..], null);
    return Value.boolean(result.isTruthy());
}

pub fn builtinNumericImag(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(0);
}
