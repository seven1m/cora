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

    const eql_sym = try vm.intern("eql?");
    try vm.complex_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinComplexEql, .{ .exact = 1 }));

    const conjugate_entry = value.MethodEntry.builtin(&builtinComplexConjugate, .{ .exact = 0 });
    const conjugate_sym = try vm.intern("conjugate");
    try vm.complex_class.module.methods.put(conjugate_sym, conjugate_entry);
    const conj_sym = try vm.intern("conj");
    try vm.complex_class.module.methods.put(conj_sym, conjugate_entry);

    const abs2_sym = try vm.intern("abs2");
    try vm.complex_class.module.methods.put(abs2_sym, value.MethodEntry.builtin(&builtinComplexAbs2, .{ .exact = 0 }));
}

fn builtinComplexEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isComplex()) return Value.boolean(false);

    const lhs = receiver.toComplexObject();
    const rhs = args[0].toComplexObject();
    if (vm.getClass(lhs.real) != vm.getClass(rhs.real) or
        vm.getClass(lhs.imaginary) != vm.getClass(rhs.imaginary))
    {
        return Value.boolean(false);
    }
    return builtinComplexEqual(vm, receiver, args, null);
}

fn builtinComplexEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        var equal_args = [_]Value{rhs.real};
        const real_equal = try vm.callMethodByName(lhs.real, "==", equal_args[0..], null);
        if (real_equal.isFalsey()) return Value.boolean(false);

        equal_args[0] = rhs.imaginary;
        const imaginary_equal = try vm.callMethodByName(lhs.imaginary, "==", equal_args[0..], null);
        return Value.boolean(imaginary_equal.isTruthy());
    }

    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            var equal_args = [_]Value{Value.integer(0)};
            const imaginary_zero = try vm.callMethodByName(lhs.imaginary, "==", equal_args[0..], null);
            if (imaginary_zero.isFalsey()) return Value.boolean(false);
            equal_args[0] = other;
            const real_equal = try vm.callMethodByName(lhs.real, "==", equal_args[0..], null);
            return Value.boolean(real_equal.isTruthy());
        }
    }

    var reverse_args = [_]Value{receiver};
    const reverse_equal = try vm.callMethodByName(other, "==", reverse_args[0..], null);
    return Value.boolean(reverse_equal.isTruthy());
}

fn builtinComplexToC(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinComplexConjugate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const neg_imaginary = try vm.callMethodByName(complex.imaginary, "-@", &.{}, null);
    return vm.newComplex(complex.real, neg_imaginary);
}

fn builtinComplexAbs2(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    var real_arg = [_]Value{complex.real};
    const real_sq = try vm.callMethodByName(complex.real, "*", real_arg[0..], null);
    var imag_arg = [_]Value{complex.imaginary};
    const imag_sq = try vm.callMethodByName(complex.imaginary, "*", imag_arg[0..], null);
    var sum_arg = [_]Value{imag_sq};
    return vm.callMethodByName(real_sq, "+", sum_arg[0..], null);
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
