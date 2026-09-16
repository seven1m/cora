const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const BigInt = std.math.big.int.Managed;

extern "c" fn erf(x: f64) f64;
extern "c" fn erfc(x: f64) f64;

pub fn register(vm: *VM) !void {
    const i_sym = try vm.intern("I");
    try vm.complex_class.module.constants.put(i_sym, .{ .value = try vm.newComplex(Value.integer(0), Value.integer(1)) });

    const real_sym = try vm.intern("real");
    try vm.complex_class.module.methods.put(real_sym, value.MethodEntry.builtin(&builtinComplexReal, .{ .exact = 0 }));

    const real_q_sym = try vm.intern("real?");
    try vm.complex_class.module.methods.put(real_q_sym, value.MethodEntry.builtin(&builtinComplexRealQ, .{ .exact = 0 }));

    const imaginary_entry = value.MethodEntry.builtin(&builtinComplexImaginary, .{ .exact = 0 });
    const imaginary_sym = try vm.intern("imaginary");
    try vm.complex_class.module.methods.put(imaginary_sym, imaginary_entry);
    const imag_sym = try vm.intern("imag");
    try vm.complex_class.module.methods.put(imag_sym, imaginary_entry);

    const finite_q_sym = try vm.intern("finite?");
    try vm.complex_class.module.methods.put(finite_q_sym, value.MethodEntry.builtin(&builtinComplexFinite, .{ .exact = 0 }));

    const infinite_q_sym = try vm.intern("infinite?");
    try vm.complex_class.module.methods.put(infinite_q_sym, value.MethodEntry.builtin(&builtinComplexInfinite, .{ .exact = 0 }));

    const hash_sym = try vm.intern("hash");
    try vm.complex_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinComplexHash, .{ .exact = 0 }));

    const marshal_dump_sym = try vm.intern("marshal_dump");
    try vm.complex_class.module.methods.put(marshal_dump_sym, value.MethodEntry.builtinWithVisibility(&builtinComplexMarshalDump, .{ .exact = 0 }, .private));

    const to_c_sym = try vm.intern("to_c");
    try vm.complex_class.module.methods.put(to_c_sym, value.MethodEntry.builtin(&builtinComplexToC, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.complex_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinComplexToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.complex_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinComplexInspect, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.complex_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinComplexToF, .{ .exact = 0 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.complex_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinComplexToI, .{ .exact = 0 }));

    const to_r_sym = try vm.intern("to_r");
    try vm.complex_class.module.methods.put(to_r_sym, value.MethodEntry.builtin(&builtinComplexToR, .{ .exact = 0 }));

    const rationalize_sym = try vm.intern("rationalize");
    try vm.complex_class.module.methods.put(rationalize_sym, value.MethodEntry.builtin(&builtinComplexRationalize, .{ .variadic = 0 }));

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

    const abs_entry = value.MethodEntry.builtin(&builtinComplexAbs, .{ .exact = 0 });
    const abs_sym = try vm.intern("abs");
    try vm.complex_class.module.methods.put(abs_sym, abs_entry);
    const magnitude_sym = try vm.intern("magnitude");
    try vm.complex_class.module.methods.put(magnitude_sym, abs_entry);

    const arg_entry = value.MethodEntry.builtin(&builtinComplexArg, .{ .exact = 0 });
    const arg_sym = try vm.intern("arg");
    try vm.complex_class.module.methods.put(arg_sym, arg_entry);
    const angle_sym = try vm.intern("angle");
    try vm.complex_class.module.methods.put(angle_sym, arg_entry);
    const phase_sym = try vm.intern("phase");
    try vm.complex_class.module.methods.put(phase_sym, arg_entry);

    const minus_sym = try vm.intern("-");
    try vm.complex_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinComplexMinus, .{ .exact = 1 }));

    const plus_sym = try vm.intern("+");
    try vm.complex_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinComplexPlus, .{ .exact = 1 }));

    const multiply_sym = try vm.intern("*");
    try vm.complex_class.module.methods.put(multiply_sym, value.MethodEntry.builtin(&builtinComplexMultiply, .{ .exact = 1 }));

    const uminus_sym = try vm.intern("-@");
    try vm.complex_class.module.methods.put(uminus_sym, value.MethodEntry.builtin(&builtinComplexUminus, .{ .exact = 0 }));

    const denominator_sym = try vm.intern("denominator");
    try vm.complex_class.module.methods.put(denominator_sym, value.MethodEntry.builtin(&builtinComplexDenominator, .{ .exact = 0 }));

    const numerator_sym = try vm.intern("numerator");
    try vm.complex_class.module.methods.put(numerator_sym, value.MethodEntry.builtin(&builtinComplexNumerator, .{ .exact = 0 }));

    const compare_sym = try vm.intern("<=>");
    try vm.complex_class.module.methods.put(compare_sym, value.MethodEntry.builtin(&builtinComplexCompare, .{ .exact = 1 }));

    const coerce_sym = try vm.intern("coerce");
    try vm.complex_class.module.methods.put(coerce_sym, value.MethodEntry.builtin(&builtinComplexCoerce, .{ .exact = 1 }));

    const fdiv_sym = try vm.intern("fdiv");
    try vm.complex_class.module.methods.put(fdiv_sym, value.MethodEntry.builtin(&builtinComplexFdiv, .{ .exact = 1 }));

    const rectangular_entry = value.MethodEntry.builtin(&builtinComplexRectangular, .{ .exact = 0 });
    const rectangular_sym = try vm.intern("rectangular");
    try vm.complex_class.module.methods.put(rectangular_sym, rectangular_entry);
    const rect_sym = try vm.intern("rect");
    try vm.complex_class.module.methods.put(rect_sym, rectangular_entry);

    const complex_singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.complex_class.module.object));
    const singleton_rectangular_entry = value.MethodEntry.builtin(&builtinComplexRectangularSingleton, .{ .variadic = 0 });
    try complex_singleton.module.methods.put(rectangular_sym, singleton_rectangular_entry);
    try complex_singleton.module.methods.put(rect_sym, singleton_rectangular_entry);

    // MRI undefines Numeric#positive? on Complex; it raises NoMethodError.
    const positive_q_sym = try vm.intern("positive?");
    try vm.complex_class.module.methods.put(positive_q_sym, .{ .method = .{ .undefined = {} } });

    // MRI undefines Numeric#negative? on Complex; it raises NoMethodError.
    const negative_q_sym = try vm.intern("negative?");
    try vm.complex_class.module.methods.put(negative_q_sym, .{ .method = .{ .undefined = {} } });

    // Math.sqrt / Math::PI are required by Complex expectations (and ruby/spec
    // uses them directly); Math has no dedicated builtins file yet so register
    // them here.
    const math_sym = try vm.intern("Math");
    if (vm.object_class.module.constants.get(math_sym)) |math_entry| {
        const math_singleton = try vm.getOrCreateSingletonClass(math_entry.value);
        const sqrt_sym = try vm.intern("sqrt");
        try math_singleton.module.methods.put(sqrt_sym, value.MethodEntry.builtin(&builtinMathSqrt, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(sqrt_sym, value.MethodEntry.builtinWithVisibility(&builtinMathSqrt, .{ .exact = 1 }, .private));
        const cbrt_sym = try vm.intern("cbrt");
        try math_singleton.module.methods.put(cbrt_sym, value.MethodEntry.builtin(&builtinMathCbrt, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(cbrt_sym, value.MethodEntry.builtinWithVisibility(&builtinMathCbrt, .{ .exact = 1 }, .private));
        const exp_sym = try vm.intern("exp");
        try math_singleton.module.methods.put(exp_sym, value.MethodEntry.builtin(&builtinMathExp, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(exp_sym, value.MethodEntry.builtinWithVisibility(&builtinMathExp, .{ .exact = 1 }, .private));
        const sinh_sym = try vm.intern("sinh");
        try math_singleton.module.methods.put(sinh_sym, value.MethodEntry.builtin(&builtinMathSinh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(sinh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathSinh, .{ .exact = 1 }, .private));
        const tanh_sym = try vm.intern("tanh");
        try math_singleton.module.methods.put(tanh_sym, value.MethodEntry.builtin(&builtinMathTanh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(tanh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathTanh, .{ .exact = 1 }, .private));
        const tan_sym = try vm.intern("tan");
        try math_singleton.module.methods.put(tan_sym, value.MethodEntry.builtin(&builtinMathTan, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(tan_sym, value.MethodEntry.builtinWithVisibility(&builtinMathTan, .{ .exact = 1 }, .private));
        const sin_sym = try vm.intern("sin");
        try math_singleton.module.methods.put(sin_sym, value.MethodEntry.builtin(&builtinMathSin, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(sin_sym, value.MethodEntry.builtinWithVisibility(&builtinMathSin, .{ .exact = 1 }, .private));
        const atan_sym = try vm.intern("atan");
        try math_singleton.module.methods.put(atan_sym, value.MethodEntry.builtin(&builtinMathAtan, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(atan_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAtan, .{ .exact = 1 }, .private));
        const acos_sym = try vm.intern("acos");
        try math_singleton.module.methods.put(acos_sym, value.MethodEntry.builtin(&builtinMathAcos, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(acos_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAcos, .{ .exact = 1 }, .private));
        const asin_sym = try vm.intern("asin");
        try math_singleton.module.methods.put(asin_sym, value.MethodEntry.builtin(&builtinMathAsin, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(asin_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAsin, .{ .exact = 1 }, .private));
        const cosh_sym = try vm.intern("cosh");
        try math_singleton.module.methods.put(cosh_sym, value.MethodEntry.builtin(&builtinMathCosh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(cosh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathCosh, .{ .exact = 1 }, .private));
        const cos_sym = try vm.intern("cos");
        try math_singleton.module.methods.put(cos_sym, value.MethodEntry.builtin(&builtinMathCos, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(cos_sym, value.MethodEntry.builtinWithVisibility(&builtinMathCos, .{ .exact = 1 }, .private));
        const acosh_sym = try vm.intern("acosh");
        try math_singleton.module.methods.put(acosh_sym, value.MethodEntry.builtin(&builtinMathAcosh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(acosh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAcosh, .{ .exact = 1 }, .private));
        const asinh_sym = try vm.intern("asinh");
        try math_singleton.module.methods.put(asinh_sym, value.MethodEntry.builtin(&builtinMathAsinh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(asinh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAsinh, .{ .exact = 1 }, .private));
        const atan2_sym = try vm.intern("atan2");
        try math_singleton.module.methods.put(atan2_sym, value.MethodEntry.builtin(&builtinMathAtan2, .{ .exact = 2 }));
        try math_entry.value.toModuleObject().methods.put(atan2_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAtan2, .{ .exact = 2 }, .private));
        const atanh_sym = try vm.intern("atanh");
        try math_singleton.module.methods.put(atanh_sym, value.MethodEntry.builtin(&builtinMathAtanh, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(atanh_sym, value.MethodEntry.builtinWithVisibility(&builtinMathAtanh, .{ .exact = 1 }, .private));
        const hypot_sym = try vm.intern("hypot");
        try math_singleton.module.methods.put(hypot_sym, value.MethodEntry.builtin(&builtinMathHypot, .{ .exact = 2 }));
        try math_entry.value.toModuleObject().methods.put(hypot_sym, value.MethodEntry.builtinWithVisibility(&builtinMathHypot, .{ .exact = 2 }, .private));
        const log10_sym = try vm.intern("log10");
        try math_singleton.module.methods.put(log10_sym, value.MethodEntry.builtin(&builtinMathLog10, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(log10_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLog10, .{ .exact = 1 }, .private));
        const log2_sym = try vm.intern("log2");
        try math_singleton.module.methods.put(log2_sym, value.MethodEntry.builtin(&builtinMathLog2, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(log2_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLog2, .{ .exact = 1 }, .private));
        const log_sym = try vm.intern("log");
        try math_singleton.module.methods.put(log_sym, value.MethodEntry.builtin(&builtinMathLog, .{ .variadic = 1 }));
        try math_entry.value.toModuleObject().methods.put(log_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLog, .{ .variadic = 1 }, .private));
        const frexp_sym = try vm.intern("frexp");
        try math_singleton.module.methods.put(frexp_sym, value.MethodEntry.builtin(&builtinMathFrexp, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(frexp_sym, value.MethodEntry.builtinWithVisibility(&builtinMathFrexp, .{ .exact = 1 }, .private));
        const expm1_sym = try vm.intern("expm1");
        try math_singleton.module.methods.put(expm1_sym, value.MethodEntry.builtin(&builtinMathExpm1, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(expm1_sym, value.MethodEntry.builtinWithVisibility(&builtinMathExpm1, .{ .exact = 1 }, .private));
        const gamma_sym = try vm.intern("gamma");
        try math_singleton.module.methods.put(gamma_sym, value.MethodEntry.builtin(&builtinMathGamma, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(gamma_sym, value.MethodEntry.builtinWithVisibility(&builtinMathGamma, .{ .exact = 1 }, .private));
        const log1p_sym = try vm.intern("log1p");
        try math_singleton.module.methods.put(log1p_sym, value.MethodEntry.builtin(&builtinMathLog1p, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(log1p_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLog1p, .{ .exact = 1 }, .private));
        const ldexp_sym = try vm.intern("ldexp");
        try math_singleton.module.methods.put(ldexp_sym, value.MethodEntry.builtin(&builtinMathLdexp, .{ .exact = 2 }));
        try math_entry.value.toModuleObject().methods.put(ldexp_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLdexp, .{ .exact = 2 }, .private));
        const lgamma_sym = try vm.intern("lgamma");
        try math_singleton.module.methods.put(lgamma_sym, value.MethodEntry.builtin(&builtinMathLgamma, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(lgamma_sym, value.MethodEntry.builtinWithVisibility(&builtinMathLgamma, .{ .exact = 1 }, .private));
        const erf_sym = try vm.intern("erf");
        try math_singleton.module.methods.put(erf_sym, value.MethodEntry.builtin(&builtinMathErf, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(erf_sym, value.MethodEntry.builtinWithVisibility(&builtinMathErf, .{ .exact = 1 }, .private));
        const erfc_sym = try vm.intern("erfc");
        try math_singleton.module.methods.put(erfc_sym, value.MethodEntry.builtin(&builtinMathErfc, .{ .exact = 1 }));
        try math_entry.value.toModuleObject().methods.put(erfc_sym, value.MethodEntry.builtinWithVisibility(&builtinMathErfc, .{ .exact = 1 }, .private));
        const pi_sym = try vm.intern("PI");
        try math_entry.value.toModuleObject().constants.put(pi_sym, .{ .value = try vm.newFloat(std.math.pi) });
        const e_sym = try vm.intern("E");
        try math_entry.value.toModuleObject().constants.put(e_sym, .{ .value = try vm.newFloat(std.math.e) });
    }
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

fn builtinComplexToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_str_val = try vm.callMethodByName(complex.real, "to_s", &.{}, null);
    if (!real_str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const imag_str_val = try vm.callMethodByName(complex.imaginary, "to_s", &.{}, null);
    if (!imag_str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }
    const real_obj = real_str_val.toStringObject();
    const imag_obj = imag_str_val.toStringObject();
    // A non-finite Float imaginary part renders with a '*' (e.g. "1+Infinity*i").
    const imag_nonfinite = complex.imaginary.isFloat() and
        !std.math.isFinite(complex.imaginary.toFloatObject().val);

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    buf.writer.writeAll(real_obj.str) catch return error.Fatal;
    // A leading '-' on the imaginary string (e.g. "-3.2", "-0.0") already
    // carries the sign; note -0.0 is not `< 0` so the string must be checked.
    if (imag_obj.str.len == 0 or imag_obj.str[0] != '-') {
        buf.writer.writeByte('+') catch return error.Fatal;
    }
    buf.writer.writeAll(imag_obj.str) catch return error.Fatal;
    if (imag_nonfinite) {
        buf.writer.writeByte('*') catch return error.Fatal;
    }
    buf.writer.writeByte('i') catch return error.Fatal;

    var output_encoding = real_obj.encoding;
    output_encoding = enc.negotiate(output_encoding, buf.written(), imag_obj.encoding, imag_obj.str) orelse {
        return vm.raiseEncodingCompatibilityError(output_encoding, imag_obj.encoding);
    };
    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, output_encoding);
}

fn builtinComplexInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_str_val = try vm.callMethodByName(complex.real, "inspect", &.{}, null);
    if (!real_str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "inspect did not return String", .{});
    }
    const imag_str_val = try vm.callMethodByName(complex.imaginary, "inspect", &.{}, null);
    if (!imag_str_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "inspect did not return String", .{});
    }
    const real_obj = real_str_val.toStringObject();
    const imag_obj = imag_str_val.toStringObject();
    // The sign is determined by `#<` so mocked numerics observe the call;
    // a non-negative imaginary part (including -0.0) renders with a '+'.
    var zero_arg = [_]Value{Value.integer(0)};
    const negative = try vm.callMethodByName(complex.imaginary, "<", zero_arg[0..], null);

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    buf.writer.writeByte('(') catch return error.Fatal;
    buf.writer.writeAll(real_obj.str) catch return error.Fatal;
    if (!negative.isTruthy()) {
        buf.writer.writeByte('+') catch return error.Fatal;
    }
    buf.writer.writeAll(imag_obj.str) catch return error.Fatal;
    // An imaginary part whose inspect form does not end in a digit (e.g.
    // "Infinity", "NaN", "(2)") needs a '*' before the trailing 'i'.
    if (imag_obj.str.len == 0 or !std.ascii.isDigit(imag_obj.str[imag_obj.str.len - 1])) {
        buf.writer.writeByte('*') catch return error.Fatal;
    }
    buf.writer.writeAll("i)") catch return error.Fatal;

    var output_encoding = real_obj.encoding;
    output_encoding = enc.negotiate(output_encoding, buf.written(), imag_obj.encoding, imag_obj.str) orelse {
        return vm.raiseEncodingCompatibilityError(output_encoding, imag_obj.encoding);
    };
    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, output_encoding);
}

fn builtinComplexToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const imaginary = complex.imaginary;
    // A Float imaginary part (even 0.0) is not an exact zero, so conversion
    // always fails per ruby/spec.
    if (imaginary.isFloat()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Float", .{});
    }
    var zero_arg = [_]Value{Value.integer(0)};
    const is_zero = try vm.callMethodByName(imaginary, "==", zero_arg[0..], null);
    if (is_zero.isTruthy()) {
        return vm.callMethodByName(complex.real, "to_f", &.{}, null);
    }
    return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Float", .{});
}

fn builtinComplexToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const imaginary = complex.imaginary;
    // A Float imaginary part (even 0.0) is not an exact zero, so conversion
    // always fails per ruby/spec.
    if (imaginary.isFloat()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Integer", .{});
    }
    var zero_arg = [_]Value{Value.integer(0)};
    const is_zero = try vm.callMethodByName(imaginary, "==", zero_arg[0..], null);
    if (is_zero.isTruthy()) {
        return vm.callMethodByName(complex.real, "to_i", &.{}, null);
    }
    return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Integer", .{});
}

fn builtinComplexToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    // Since Ruby 3.4 an inexact zero imaginary part (e.g. Float 0.0) is
    // accepted, so any imaginary part equal to 0 converts via the real part.
    var zero_arg = [_]Value{Value.integer(0)};
    const is_zero = try vm.callMethodByName(complex.imaginary, "==", zero_arg[0..], null);
    if (is_zero.isTruthy()) {
        return vm.callMethodByName(complex.real, "to_r", &.{}, null);
    }
    return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Rational", .{});
}

fn builtinComplexRationalize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const complex = receiver.toComplexObject();
    const imaginary = complex.imaginary;
    // Only an exact zero imaginary part converts; a Float imaginary part
    // (even 0.0) is inexact, so conversion always fails per ruby/spec.
    if (!imaginary.isFloat()) {
        var zero_arg = [_]Value{Value.integer(0)};
        const is_zero = try vm.callMethodByName(imaginary, "==", zero_arg[0..], null);
        if (is_zero.isTruthy()) {
            return vm.callMethodByName(complex.real, "rationalize", args, null);
        }
    }
    return vm.raiseExceptionFmt(vm.range_error_class, "can't convert Complex into Rational", .{});
}

fn builtinComplexConjugate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const neg_imaginary = try vm.callMethodByName(complex.imaginary, "-@", &.{}, null);
    return vm.newComplex(complex.real, neg_imaginary);
}

fn builtinComplexUminus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const neg_real = try vm.callMethodByName(complex.real, "-@", &.{}, null);
    const neg_imaginary = try vm.callMethodByName(complex.imaginary, "-@", &.{}, null);
    return vm.newComplex(neg_real, neg_imaginary);
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

fn builtinComplexMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        var real_arg = [_]Value{rhs.real};
        const real_diff = try vm.callMethodByName(lhs.real, "-", real_arg[0..], null);
        var imag_arg = [_]Value{rhs.imaginary};
        const imag_diff = try vm.callMethodByName(lhs.imaginary, "-", imag_arg[0..], null);
        return vm.newComplex(real_diff, imag_diff);
    }

    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            var real_arg = [_]Value{other};
            const real_diff = try vm.callMethodByName(lhs.real, "-", real_arg[0..], null);
            return vm.newComplex(real_diff, lhs.imaginary);
        }
    }

    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(other, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Complex", .{vm.className(other)});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    var op_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], "-", op_args[0..], null);
}

fn builtinComplexPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        var real_arg = [_]Value{rhs.real};
        const real_sum = try vm.callMethodByName(lhs.real, "+", real_arg[0..], null);
        var imag_arg = [_]Value{rhs.imaginary};
        const imag_sum = try vm.callMethodByName(lhs.imaginary, "+", imag_arg[0..], null);
        return vm.newComplex(real_sum, imag_sum);
    }

    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            var real_arg = [_]Value{other};
            const real_sum = try vm.callMethodByName(lhs.real, "+", real_arg[0..], null);
            return vm.newComplex(real_sum, lhs.imaginary);
        }
    }

    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(other, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Complex", .{vm.className(other)});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    var op_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], "+", op_args[0..], null);
}

fn builtinComplexMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        var ac_arg = [_]Value{rhs.real};
        const ac = try vm.callMethodByName(lhs.real, "*", ac_arg[0..], null);
        var bd_arg = [_]Value{rhs.imaginary};
        const bd = try vm.callMethodByName(lhs.imaginary, "*", bd_arg[0..], null);
        var real_arg = [_]Value{bd};
        const real_part = try vm.callMethodByName(ac, "-", real_arg[0..], null);
        var ad_arg = [_]Value{rhs.imaginary};
        const ad = try vm.callMethodByName(lhs.real, "*", ad_arg[0..], null);
        var bc_arg = [_]Value{rhs.real};
        const bc = try vm.callMethodByName(lhs.imaginary, "*", bc_arg[0..], null);
        var imag_arg = [_]Value{bc};
        const imag_part = try vm.callMethodByName(ad, "+", imag_arg[0..], null);
        return vm.newComplex(real_part, imag_part);
    }

    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            var real_arg = [_]Value{other};
            const real_part = try vm.callMethodByName(lhs.real, "*", real_arg[0..], null);
            var imag_arg = [_]Value{other};
            const imag_part = try vm.callMethodByName(lhs.imaginary, "*", imag_arg[0..], null);
            return vm.newComplex(real_part, imag_part);
        }
    }

    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(other, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Complex", .{vm.className(other)});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    var op_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], "*", op_args[0..], null);
}

fn builtinComplexAbs(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    var real_arg = [_]Value{complex.real};
    const real_sq = try vm.callMethodByName(complex.real, "*", real_arg[0..], null);
    var imag_arg = [_]Value{complex.imaginary};
    const imag_sq = try vm.callMethodByName(complex.imaginary, "*", imag_arg[0..], null);
    var sum_arg = [_]Value{imag_sq};
    const abs2 = try vm.callMethodByName(real_sq, "+", sum_arg[0..], null);
    const abs2_float = try vm.callMethodByName(abs2, "to_f", &.{}, null);
    return vm.newFloat(std.math.sqrt(abs2_float.toFloatObject().val));
}

fn builtinComplexArg(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_float = try vm.callMethodByName(complex.real, "to_f", &.{}, null);
    const imaginary_float = try vm.callMethodByName(complex.imaginary, "to_f", &.{}, null);
    return vm.newFloat(std.math.atan2(imaginary_float.toFloatObject().val, real_float.toFloatObject().val));
}

fn builtinMathSqrt(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    }
    else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < 0.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"sqrt\"", .{});
    return vm.newFloat(std.math.sqrt(f));
}

fn builtinMathCbrt(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.cbrt(f));
}

fn builtinMathExp(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.exp(f));
}

fn builtinMathSinh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.sinh(f));
}

fn builtinMathTanh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.tanh(f));
}

fn builtinMathTan(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    }     else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.tan(f));
}

fn builtinMathSin(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.sin(f));
}

fn builtinMathAtan(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.atan(f));
}

fn builtinMathAcos(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < -1.0 or f > 1.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"acos\"", .{});
    return vm.newFloat(std.math.acos(f));
}

fn builtinMathAsin(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < -1.0 or f > 1.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"asin\"", .{});
    return vm.newFloat(std.math.asin(f));
}

fn builtinMathCosh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.cosh(f));
}

fn builtinMathCos(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.cos(f));
}

fn builtinMathAcosh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < 1.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"acosh\"", .{});
    return vm.newFloat(std.math.acosh(f));
}

fn builtinMathAsinh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.asinh(f));
}

fn builtinMathAtan2(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    var fs: [2]f64 = undefined;
    for (args[0..2], 0..) |arg, i| {
        fs[i] = if (arg.isFloat())
            arg.toFloatObject().val
        else if (arg.isInteger() or arg.isBigInteger())
            arg.integerToF64()
        else if (arg.isRational())
            arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
        else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
            // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
            const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
            if (!float_val.isFloat()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
            }
            break :blk float_val.toFloatObject().val;
        } else
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    }
    return vm.newFloat(std.math.atan2(fs[0], fs[1]));
}

fn builtinMathAtanh(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (@abs(f) > 1.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"atanh\"", .{});
    return vm.newFloat(std.math.atanh(f));
}

fn builtinMathHypot(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    var fs: [2]f64 = undefined;
    for (args[0..2], 0..) |arg, i| {
        fs[i] = if (arg.isFloat())
            arg.toFloatObject().val
        else if (arg.isInteger() or arg.isBigInteger())
            arg.integerToF64()
        else if (arg.isRational())
            arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
        else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
            // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
            const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
            if (!float_val.isFloat()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
            }
            break :blk float_val.toFloatObject().val;
        } else
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    }
    return vm.newFloat(std.math.hypot(fs[0], fs[1]));
}

fn builtinMathLog10(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < 0.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"log10\"", .{});
    return vm.newFloat(std.math.log10(f));
}

fn builtinMathLog2(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < 0.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"log2\"", .{});
    if (std.math.isInf(f) and (arg.isInteger() or arg.isBigInteger())) {
        // Huge integers overflow to infinity via integerToF64, but MRI still
        // computes an exact log2 by decomposing the bignum: split off the top
        // 53 bits (exactly representable as f64) and add back the shift.
        var big = try arg.integerToManaged(vm);
        defer big.deinit();
        const bits = big.bitCountAbs();
        if (bits > 53) {
            const shift: usize = bits - 53;
            var top = BigInt.init(vm.allocator) catch return error.Fatal;
            defer top.deinit();
            top.shiftRight(&big, shift) catch return error.Fatal;
            const top_f: f64 = top.toFloat(f64, .nearest_even)[0];
            return vm.newFloat(@as(f64, @floatFromInt(shift)) + std.math.log2(top_f));
        }
    }
    return vm.newFloat(std.math.log2(f));
}

fn builtinMathLog(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    var fs: [2]f64 = undefined;
    for (args, 0..) |arg, i| {
        fs[i] = if (arg.isFloat())
            arg.toFloatObject().val
        else if (arg.isInteger() or arg.isBigInteger())
            arg.integerToF64()
        else if (arg.isRational())
            arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
        else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
            // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
            const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
            if (!float_val.isFloat()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
            }
            break :blk float_val.toFloatObject().val;
        } else
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    }
    if (fs[0] < 0.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"log\"", .{});
    const result = std.math.log(f64, std.math.e, fs[0]);
    if (args.len == 2) return vm.newFloat(result / std.math.log(f64, std.math.e, fs[1]));
    return vm.newFloat(result);
}

fn builtinMathFrexp(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    const parts = std.math.frexp(f);
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, try vm.newFloat(parts.significand)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(@as(i64, parts.exponent))) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

fn builtinMathExpm1(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(std.math.expm1(f));
}

fn builtinMathGamma(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    // Gamma has poles at negative integers (and -infinity compares equal to
    // its own truncation); MRI raises DomainError instead of returning NaN.
    if (f < 0.0 and f == @trunc(f))
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - \"gamma\"", .{});
    // gamma(n) is exactly (n-1)!; 22! is the largest factorial exactly
    // representable as f64, so compute small integer arguments with integer
    // arithmetic instead of the Lanczos approximation.
    if (f == @trunc(f) and f >= 1.0 and f <= 23.0) {
        const n: u128 = @intFromFloat(f);
        var fact: u128 = 1;
        var i: u128 = 1;
        while (i < n) : (i += 1) fact *= i;
        return vm.newFloat(@floatFromInt(fact));
    }
    return vm.newFloat(std.math.gamma(f64, f));
}

fn builtinMathLog1p(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    if (f < -1.0)
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - log1p", .{});
    return vm.newFloat(std.math.log1p(f));
}

fn builtinMathLdexp(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    // The exponent follows Integer() semantics: Float truncates via to_int
    // (NaN/Infinity raise RangeError there), other objects convert via to_int.
    const exp_val = try args[1].coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "can't convert into Integer",
    );
    const exp_i64: i64 = if (exp_val.isInteger())
        exp_val.toInteger()
    else
        try exp_val.integerToI64(vm, "bignum too big to convert into `long`");
    // Zero and non-finite inputs are exact regardless of exponent; this also
    // avoids overflow quirks in std.math.ldexp for extreme exponents.
    if (f == 0.0 or !std.math.isFinite(f)) return vm.newFloat(f);
    const exp_i32: i32 = @intCast(std.math.clamp(exp_i64, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32))));
    return vm.newFloat(std.math.ldexp(f, exp_i32));
}

fn builtinMathLgamma(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    // MRI raises DomainError for -Infinity; +Infinity and NaN pass through
    // with a sign of 1.
    if (std.math.isNegativeInf(f))
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "Numerical argument is out of domain - lgamma", .{});
    if (std.math.isPositiveInf(f) or std.math.isNan(f)) {
        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, try vm.newFloat(f)) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, Value.integer(1)) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    // Poles at zero and negative integers yield +Infinity; the sign is 1
    // except for -0.0, matching MRI's lgamma_r behavior.
    var sign: i64 = 1;
    var val: f64 = undefined;
    if (f == 0.0) {
        val = std.math.inf(f64);
        if (std.math.signbit(f)) sign = -1;
    } else if (f < 0.0 and f == @trunc(f)) {
        val = std.math.inf(f64);
    } else {
        val = std.math.lgamma(f64, f);
        if (f < 0.0) {
            // Gamma alternates sign between poles: negative on (-1, 0),
            // positive on (-2, -1), and so on.
            const k: i64 = @intFromFloat(@floor(-f));
            if (@mod(k, 2) == 0) sign = -1;
        }
    }
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, try vm.newFloat(val)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(sign)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

fn builtinMathErf(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(erf(f));
}

fn builtinMathErfc(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isNil())
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Float", .{});
    const f: f64 = if (arg.isFloat())
        arg.toFloatObject().val
    else if (arg.isInteger() or arg.isBigInteger())
        arg.integerToF64()
    else if (arg.isRational())
        arg.toRationalObject().numerator.integerToF64() / arg.toRationalObject().denominator.integerToF64()
    else if (vm.isClassOrSubclassOf(vm.getClass(arg), vm.numeric_class)) blk: {
        // Mirrors MRI's rb_num_to_dbl: non-core Numerics convert via to_f.
        const float_val = try vm.callMethodByName(arg, "to_f", &.{}, null);
        if (!float_val.isFloat()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
        }
        break :blk float_val.toFloatObject().val;
    } else
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    return vm.newFloat(erfc(f));
}

fn builtinComplexDenominator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_denom = try vm.callMethodByName(complex.real, "denominator", &.{}, null);
    const imag_denom = try vm.callMethodByName(complex.imaginary, "denominator", &.{}, null);
    var lcm_arg = [_]Value{imag_denom};
    return vm.callMethodByName(real_denom, "lcm", lcm_arg[0..], null);
}

fn builtinComplexNumerator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_num = try vm.callMethodByName(complex.real, "numerator", &.{}, null);
    const real_denom = try vm.callMethodByName(complex.real, "denominator", &.{}, null);
    const imag_num = try vm.callMethodByName(complex.imaginary, "numerator", &.{}, null);
    const imag_denom = try vm.callMethodByName(complex.imaginary, "denominator", &.{}, null);
    var lcm_arg = [_]Value{imag_denom};
    const common_denom = try vm.callMethodByName(real_denom, "lcm", lcm_arg[0..], null);
    var div_arg = [_]Value{real_denom};
    const real_factor = try vm.callMethodByName(common_denom, "/", div_arg[0..], null);
    var mul_arg = [_]Value{real_factor};
    const scaled_real = try vm.callMethodByName(real_num, "*", mul_arg[0..], null);
    div_arg[0] = imag_denom;
    const imag_factor = try vm.callMethodByName(common_denom, "/", div_arg[0..], null);
    mul_arg[0] = imag_factor;
    const scaled_imag = try vm.callMethodByName(imag_num, "*", mul_arg[0..], null);
    return vm.newComplex(scaled_real, scaled_imag);
}

fn builtinComplexCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];

    var other_real: Value = undefined;
    var other_imaginary: Value = undefined;
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        other_real = rhs.real;
        other_imaginary = rhs.imaginary;
    } else if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isFalsey()) return Value.nil();
        other_real = other;
        other_imaginary = Value.integer(0);
    } else {
        return Value.nil();
    }

    var zero_arg = [_]Value{Value.integer(0)};
    const self_imaginary_zero = try vm.callMethodByName(lhs.imaginary, "==", zero_arg[0..], null);
    if (self_imaginary_zero.isFalsey()) return Value.nil();
    const other_imaginary_zero = try vm.callMethodByName(other_imaginary, "==", zero_arg[0..], null);
    if (other_imaginary_zero.isFalsey()) return Value.nil();

    var compare_args = [_]Value{other_real};
    return vm.callMethodByName(lhs.real, "<=>", compare_args[0..], null);
}

fn builtinComplexCoerce(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    const result = try vm.createArray();
    if (other.isComplex()) {
        result.elements.append(vm.gc_allocator, other) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            result.elements.append(vm.gc_allocator, try vm.newComplex(other, Value.integer(0))) catch return error.Fatal;
            result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
            return Value.fromObject(&result.object);
        }
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Complex", .{vm.className(other)});
}

fn complexPartToF64(vm: *VM, part: Value) VMError!f64 {
    if (part.isFloat()) return part.toFloatObject().val;
    if (part.isInteger() or part.isBigInteger()) return part.integerToF64();
    if (part.isRational()) {
        const rational = part.toRationalObject();
        return rational.numerator.integerToF64() / rational.denominator.integerToF64();
    }
    const float_part = try vm.callMethodByName(part, "to_f", &.{}, null);
    return float_part.toFloatObject().val;
}

fn builtinComplexFdiv(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toComplexObject();
    const other = args[0];
    if (other.isComplex()) {
        const rhs = other.toComplexObject();
        const a = try complexPartToF64(vm, lhs.real);
        const b = try complexPartToF64(vm, lhs.imaginary);
        const c = try complexPartToF64(vm, rhs.real);
        const d = try complexPartToF64(vm, rhs.imaginary);
        const denominator = c * c + d * d;
        return vm.newComplex(
            try vm.newFloat((a * c + b * d) / denominator),
            try vm.newFloat((b * c - a * d) / denominator),
        );
    }

    if (vm.isClassOrSubclassOf(vm.getClass(other), vm.numeric_class)) {
        const real = try vm.callMethodByName(other, "real?", &.{}, null);
        if (real.isTruthy()) {
            var real_arg = [_]Value{other};
            const real_quotient = try vm.callMethodByName(lhs.real, "fdiv", real_arg[0..], null);
            var imag_arg = [_]Value{other};
            const imag_quotient = try vm.callMethodByName(lhs.imaginary, "fdiv", imag_arg[0..], null);
            return vm.newComplex(real_quotient, imag_quotient);
        }
    }

    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(other, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Complex", .{vm.className(other)});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }
    var op_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], "fdiv", op_args[0..], null);
}

fn builtinComplexHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@bitCast(receiver.hash()));
}

fn builtinComplexMarshalDump(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, complex.real) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, complex.imaginary) catch return error.Fatal;
    return Value.fromObject(&result.object);
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

fn builtinComplexFinite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_finite = try vm.callMethodByName(complex.real, "finite?", &.{}, null);
    if (real_finite.isFalsey()) return Value.boolean(false);
    const imaginary_finite = try vm.callMethodByName(complex.imaginary, "finite?", &.{}, null);
    return Value.boolean(imaginary_finite.isTruthy());
}

fn builtinComplexInfinite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const real_infinite = try vm.callMethodByName(complex.real, "infinite?", &.{}, null);
    if (real_infinite.isTruthy()) return Value.integer(1);
    const imaginary_infinite = try vm.callMethodByName(complex.imaginary, "infinite?", &.{}, null);
    if (imaginary_infinite.isTruthy()) return Value.integer(1);
    return Value.nil();
}

fn builtinComplexRectangular(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const complex = receiver.toComplexObject();
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, complex.real) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, complex.imaginary) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

fn builtinComplexRectangularSingleton(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const real = args[0];
    const imaginary = if (args.len == 2) args[1] else Value.integer(0);
    if (!vm.isClassOrSubclassOf(vm.getClass(real), vm.numeric_class) or real.isComplex() or
        !vm.isClassOrSubclassOf(vm.getClass(imaginary), vm.numeric_class) or imaginary.isComplex())
    {
        return vm.raiseExceptionFmt(vm.type_error_class, "not a real", .{});
    }
    return vm.newComplex(real, imaginary);
}
