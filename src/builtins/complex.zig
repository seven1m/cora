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

    const imaginary_entry = value.MethodEntry.builtin(&builtinComplexImaginary, .{ .exact = 0 });
    const imaginary_sym = try vm.intern("imaginary");
    try vm.complex_class.module.methods.put(imaginary_sym, imaginary_entry);
    const imag_sym = try vm.intern("imag");
    try vm.complex_class.module.methods.put(imag_sym, imaginary_entry);

    const hash_sym = try vm.intern("hash");
    try vm.complex_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinComplexHash, .{ .exact = 0 }));

    const to_c_sym = try vm.intern("to_c");
    try vm.complex_class.module.methods.put(to_c_sym, value.MethodEntry.builtin(&builtinComplexToC, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.complex_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinComplexEqual, .{ .exact = 1 }));
}

fn builtinComplexEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isComplex()) return Value.boolean(false);

    const lhs = receiver.toComplexObject();
    const rhs = args[0].toComplexObject();
    var equal_args = [_]Value{rhs.real};
    const real_equal = try vm.callMethodByName(lhs.real, "==", equal_args[0..], null);
    if (real_equal.isFalsey()) return Value.boolean(false);

    equal_args[0] = rhs.imaginary;
    const imaginary_equal = try vm.callMethodByName(lhs.imaginary, "==", equal_args[0..], null);
    return Value.boolean(imaginary_equal.isTruthy());
}

fn builtinComplexToC(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinComplexHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@bitCast(receiver.hash()));
}

fn builtinComplexRealQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(false);
}

fn builtinComplexReal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toComplexObject().real;
}

fn builtinComplexImaginary(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toComplexObject().imaginary;
}
