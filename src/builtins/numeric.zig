const std = @import("std");
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

    const real_sym = try vm.intern("real");
    try vm.numeric_class.module.methods.put(real_sym, value.MethodEntry.builtin(&builtinNumericReal, .{ .exact = 0 }));

    const to_int_sym = try vm.intern("to_int");
    try vm.numeric_class.module.methods.put(to_int_sym, value.MethodEntry.builtin(&builtinNumericToInt, .{ .exact = 0 }));

    const real_q_sym = try vm.intern("real?");
    try vm.numeric_class.module.methods.put(real_q_sym, value.MethodEntry.builtin(&builtinNumericRealQ, .{ .exact = 0 }));

    const uplus_sym = try vm.intern("+@");
    try vm.numeric_class.module.methods.put(uplus_sym, value.MethodEntry.builtin(&builtinNumericUplus, .{ .exact = 0 }));

    const abs_sym = try vm.intern("abs");
    try vm.numeric_class.module.methods.put(abs_sym, value.MethodEntry.builtin(&builtinNumericAbs, .{ .exact = 0 }));

    const magnitude_sym = try vm.intern("magnitude");
    try vm.numeric_class.module.methods.put(magnitude_sym, value.MethodEntry.builtin(&builtinNumericAbs, .{ .exact = 0 }));

    const finite_q_sym = try vm.intern("finite?");
    try vm.numeric_class.module.methods.put(finite_q_sym, value.MethodEntry.builtin(&builtinNumericFinite, .{ .exact = 0 }));

    const infinite_q_sym = try vm.intern("infinite?");
    try vm.numeric_class.module.methods.put(infinite_q_sym, value.MethodEntry.builtin(&builtinNumericInfinite, .{ .exact = 0 }));

    const abs2_sym = try vm.intern("abs2");
    try vm.numeric_class.module.methods.put(abs2_sym, value.MethodEntry.builtin(&builtinNumericAbs2, .{ .exact = 0 }));

    const conj_sym = try vm.intern("conj");
    try vm.numeric_class.module.methods.put(conj_sym, value.MethodEntry.builtin(&builtinNumericConj, .{ .exact = 0 }));

    const conjugate_sym = try vm.intern("conjugate");
    try vm.numeric_class.module.methods.put(conjugate_sym, value.MethodEntry.builtin(&builtinNumericConj, .{ .exact = 0 }));

    const denominator_sym = try vm.intern("denominator");
    try vm.numeric_class.module.methods.put(denominator_sym, value.MethodEntry.builtin(&builtinNumericDenominator, .{ .exact = 0 }));

    const numerator_sym = try vm.intern("numerator");
    try vm.numeric_class.module.methods.put(numerator_sym, value.MethodEntry.builtin(&builtinNumericNumerator, .{ .exact = 0 }));

    const rectangular_entry = value.MethodEntry.builtin(&builtinNumericRectangular, .{ .exact = 0 });
    const rectangular_sym = try vm.intern("rectangular");
    try vm.numeric_class.module.methods.put(rectangular_sym, rectangular_entry);
    const rect_sym = try vm.intern("rect");
    try vm.numeric_class.module.methods.put(rect_sym, rectangular_entry);

    const coerce_sym = try vm.intern("coerce");
    try vm.numeric_class.module.methods.put(coerce_sym, value.MethodEntry.builtin(&builtinNumericCoerce, .{ .exact = 1 }));

    const dup_sym = try vm.intern("dup");
    try vm.numeric_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinNumericDup, .{ .exact = 0 }));

    const clone_sym = try vm.intern("clone");
    try vm.numeric_class.module.methods.put(clone_sym, value.MethodEntry.builtin(&builtinNumericClone, .{ .variadic = 0 }));

    const arg_entry = value.MethodEntry.builtin(&builtinNumericArg, .{ .exact = 0 });
    const arg_sym = try vm.intern("arg");
    try vm.numeric_class.module.methods.put(arg_sym, arg_entry);
    const angle_sym = try vm.intern("angle");
    try vm.numeric_class.module.methods.put(angle_sym, arg_entry);
    const phase_sym = try vm.intern("phase");
    try vm.numeric_class.module.methods.put(phase_sym, arg_entry);

    const ceil_sym = try vm.intern("ceil");
    try vm.numeric_class.module.methods.put(ceil_sym, value.MethodEntry.builtin(&builtinNumericCeil, .{ .variadic = 0 }));

    const floor_sym = try vm.intern("floor");
    try vm.numeric_class.module.methods.put(floor_sym, value.MethodEntry.builtin(&builtinNumericFloor, .{ .variadic = 0 }));
}

pub fn builtinNumericCoerce(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    var lhs = args[0];
    var rhs = receiver;
    if (vm.getClass(lhs) != vm.getClass(rhs)) {
        var float_args = [_]Value{lhs};
        lhs = try vm.callMethodByName(receiver, "Float", float_args[0..], null);
        float_args[0] = rhs;
        rhs = try vm.callMethodByName(receiver, "Float", float_args[0..], null);
    }

    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, lhs) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, rhs) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinNumericDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinNumericClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const freeze = try vm.consumeCloneFreezeOpt();
    if (freeze.isFalse()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "can't unfreeze {s}", .{vm.className(receiver)});
    }
    return receiver;
}

pub fn builtinNumericIntegerQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.isInteger() or receiver.isBigInteger());
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

pub fn builtinNumericReal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinNumericToInt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.callMethodByName(receiver, "to_i", &.{}, null);
}

pub fn builtinNumericRealQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(true);
}

pub fn builtinNumericUplus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinNumericAbs(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const less_than_zero = try vm.callMethodByName(receiver, "<", compare_args[0..], null);
    if (less_than_zero.isTruthy()) {
        return vm.callMethodByName(receiver, "-@", &.{}, null);
    }
    return receiver;
}

pub fn builtinNumericFinite(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(true);
}

pub fn builtinNumericInfinite(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.nil();
}

pub fn builtinNumericAbs2(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var mul_args = [_]Value{receiver};
    return vm.callMethodByName(receiver, "*", &mul_args, null);
}

pub fn builtinNumericConj(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinNumericDenominator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const to_r_result = try vm.callMethodByName(receiver, "to_r", &.{}, null);
    return vm.callMethodByName(to_r_result, "denominator", &.{}, null);
}

pub fn builtinNumericNumerator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const to_r_result = try vm.callMethodByName(receiver, "to_r", &.{}, null);
    return vm.callMethodByName(to_r_result, "numerator", &.{}, null);
}

pub fn builtinNumericRectangular(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(0)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinNumericArg(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var compare_args = [_]Value{Value.integer(0)};
    const less_than_zero = try vm.callMethodByName(receiver, "<", compare_args[0..], null);
    if (less_than_zero.isTruthy()) {
        return vm.newFloat(std.math.pi);
    }
    return Value.integer(0);
}

pub fn builtinNumericCeil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const float_value = try vm.callMethodByName(receiver, "to_f", &.{}, null);
    return vm.callMethodByName(float_value, "ceil", args, null);
}

pub fn builtinNumericFloor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const float_value = try vm.callMethodByName(receiver, "to_f", &.{}, null);
    return vm.callMethodByName(float_value, "floor", args, null);
}
