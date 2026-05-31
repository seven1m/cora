const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const rational_builtin = @import("rational.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

extern fn dtoa(
    dd: f64,
    mode: c_int,
    ndigits: c_int,
    decpt: *c_int,
    sign: *c_int,
    rve: *?[*]u8,
) [*:0]u8;
extern fn freedtoa(s: [*]u8) void;
extern fn pow(x: f64, y: f64) f64;
extern fn nextafter(x: f64, y: f64) f64;

const max_fixed_decimal_digits: c_int = 15;

fn coerceNumericArg(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isFloat()) return arg.toFloatObject().val;
    if (arg.isInteger()) return @floatFromInt(arg.toInteger());
    if (arg.isBigInteger()) return arg.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
}

fn coercePrecisionArgToCInt(vm: *VM, arg: Value) VMError!c_int {
    const digits = try arg.integerToI64(vm, "invalid precision");
    if (digits < std.math.minInt(c_int)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer {d} too small to convert to 'int'", .{digits});
    }
    if (digits > std.math.maxInt(c_int)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer {d} too big to convert to 'int'", .{digits});
    }

    const coerced: c_int = @intCast(digits);
    if (coerced == std.math.minInt(c_int)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "exponent is too large", .{});
    }
    return coerced;
}

fn appendExponent(writer: anytype, exponent: c_int) VMError!void {
    writer.writeByte('e') catch return error.Fatal;
    if (exponent < 0) {
        writer.writeByte('-') catch return error.Fatal;
    } else {
        writer.writeByte('+') catch return error.Fatal;
    }

    const abs_exponent: c_int = @intCast(@abs(exponent));
    if (abs_exponent < 10) {
        writer.writeByte('0') catch return error.Fatal;
    }
    writer.print("{d}", .{abs_exponent}) catch return error.Fatal;
}

fn appendScientificMantissa(writer: anytype, digits: []const u8) VMError!void {
    if (digits.len > 1) {
        writer.writeByte(digits[0]) catch return error.Fatal;
        writer.writeByte('.') catch return error.Fatal;
        writer.writeAll(digits[1..]) catch return error.Fatal;
        return;
    }

    writer.writeAll(digits) catch return error.Fatal;
    writer.writeAll(".0") catch return error.Fatal;
}

pub fn register(vm: *VM) !void {
    const infinity_sym = try vm.intern("INFINITY");
    try vm.float_class.module.constants.put(infinity_sym, .{ .value = try vm.newFloat(std.math.inf(f64)) });

    const nan_const_sym = try vm.intern("NAN");
    try vm.float_class.module.constants.put(nan_const_sym, .{ .value = try vm.newFloat(std.math.nan(f64)) });

    const max_sym = try vm.intern("MAX");
    try vm.float_class.module.constants.put(max_sym, .{ .value = try vm.newFloat(std.math.floatMax(f64)) });

    const epsilon_sym = try vm.intern("EPSILON");
    try vm.float_class.module.constants.put(epsilon_sym, .{ .value = try vm.newFloat(std.math.floatEps(f64)) });

    const dig_sym = try vm.intern("DIG");
    try vm.float_class.module.constants.put(dig_sym, .{ .value = Value.integer(15) });

    const mant_dig_sym = try vm.intern("MANT_DIG");
    try vm.float_class.module.constants.put(mant_dig_sym, .{ .value = Value.integer(53) });

    const max_10_exp_sym = try vm.intern("MAX_10_EXP");
    try vm.float_class.module.constants.put(max_10_exp_sym, .{ .value = Value.integer(308) });

    const min_10_exp_sym = try vm.intern("MIN_10_EXP");
    try vm.float_class.module.constants.put(min_10_exp_sym, .{ .value = Value.integer(-307) });

    const max_exp_sym = try vm.intern("MAX_EXP");
    try vm.float_class.module.constants.put(max_exp_sym, .{ .value = Value.integer(1024) });

    const min_exp_sym = try vm.intern("MIN_EXP");
    try vm.float_class.module.constants.put(min_exp_sym, .{ .value = Value.integer(-1021) });

    const min_sym = try vm.intern("MIN");
    try vm.float_class.module.constants.put(min_sym, .{ .value = try vm.newFloat(std.math.floatMin(f64)) });

    const radix_sym = try vm.intern("RADIX");
    try vm.float_class.module.constants.put(radix_sym, .{ .value = Value.integer(2) });

    const plus_sym = try vm.intern("+");
    try vm.float_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinFloatPlus, .{ .exact = 1 }));

    const minus_sym = try vm.intern("-");
    try vm.float_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinFloatMinus, .{ .exact = 1 }));

    const unary_plus_sym = try vm.intern("+@");
    try vm.float_class.module.methods.put(unary_plus_sym, value.MethodEntry.builtin(&builtinFloatUnaryPlus, .{ .exact = 0 }));

    const unary_minus_sym = try vm.intern("-@");
    try vm.float_class.module.methods.put(unary_minus_sym, value.MethodEntry.builtin(&builtinFloatUnaryMinus, .{ .exact = 0 }));

    const multiply_sym = try vm.intern("*");
    try vm.float_class.module.methods.put(multiply_sym, value.MethodEntry.builtin(&builtinFloatMultiply, .{ .exact = 1 }));

    const exponent_sym = try vm.intern("**");
    try vm.float_class.module.methods.put(exponent_sym, value.MethodEntry.builtin(&builtinFloatExponent, .{ .exact = 1 }));

    const divide_sym = try vm.intern("/");
    try vm.float_class.module.methods.put(divide_sym, value.MethodEntry.builtin(&builtinFloatDivide, .{ .exact = 1 }));

    const compare_sym = try vm.intern("<=>");
    try vm.float_class.module.methods.put(compare_sym, value.MethodEntry.builtin(&builtinFloatCompare, .{ .exact = 1 }));

    const equal_sym = try vm.intern("==");
    try vm.float_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinFloatEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.float_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinFloatEql, .{ .exact = 1 }));

    const less_than_sym = try vm.intern("<");
    try vm.float_class.module.methods.put(less_than_sym, value.MethodEntry.builtin(&builtinFloatLessThan, .{ .exact = 1 }));

    const less_than_or_equal_sym = try vm.intern("<=");
    try vm.float_class.module.methods.put(less_than_or_equal_sym, value.MethodEntry.builtin(&builtinFloatLessThanOrEqual, .{ .exact = 1 }));

    const greater_than_sym = try vm.intern(">");
    try vm.float_class.module.methods.put(greater_than_sym, value.MethodEntry.builtin(&builtinFloatGreaterThan, .{ .exact = 1 }));

    const greater_than_or_equal_sym = try vm.intern(">=");
    try vm.float_class.module.methods.put(greater_than_or_equal_sym, value.MethodEntry.builtin(&builtinFloatGreaterThanOrEqual, .{ .exact = 1 }));

    const abs_sym = try vm.intern("abs");
    try vm.float_class.module.methods.put(abs_sym, value.MethodEntry.builtin(&builtinFloatAbs, .{ .exact = 0 }));

    const nan_sym = try vm.intern("nan?");
    try vm.float_class.module.methods.put(nan_sym, value.MethodEntry.builtin(&builtinFloatNan, .{ .exact = 0 }));

    const infinite_sym = try vm.intern("infinite?");
    try vm.float_class.module.methods.put(infinite_sym, value.MethodEntry.builtin(&builtinFloatInfinite, .{ .exact = 0 }));

    const negative_q_sym = try vm.intern("negative?");
    try vm.float_class.module.methods.put(negative_q_sym, value.MethodEntry.builtin(&builtinFloatNegative, .{ .exact = 0 }));

    const positive_q_sym = try vm.intern("positive?");
    try vm.float_class.module.methods.put(positive_q_sym, value.MethodEntry.builtin(&builtinFloatPositive, .{ .exact = 0 }));

    const to_int_sym = try vm.intern("to_int");
    try vm.float_class.module.methods.put(to_int_sym, value.MethodEntry.builtin(&builtinFloatToInt, .{ .exact = 0 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.float_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinFloatToInt, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.float_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinFloatToF, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.float_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinFloatToS, .{ .exact = 0 }));

    const to_r_sym = try vm.intern("to_r");
    try vm.float_class.module.methods.put(to_r_sym, value.MethodEntry.builtin(&builtinFloatToR, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.float_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinFloatInspect, .{ .exact = 0 }));

    const ceil_sym = try vm.intern("ceil");
    try vm.float_class.module.methods.put(ceil_sym, value.MethodEntry.builtin(&builtinFloatCeil, .{ .variadic = 0 }));

    const floor_sym = try vm.intern("floor");
    try vm.float_class.module.methods.put(floor_sym, value.MethodEntry.builtin(&builtinFloatFloor, .{ .variadic = 0 }));

    const round_sym = try vm.intern("round");
    try vm.float_class.module.methods.put(round_sym, value.MethodEntry.builtin(&builtinFloatRound, .{ .variadic = 0 }));

    const next_float_sym = try vm.intern("next_float");
    try vm.float_class.module.methods.put(next_float_sym, value.MethodEntry.builtin(&builtinFloatNextFloat, .{ .exact = 0 }));

    const prev_float_sym = try vm.intern("prev_float");
    try vm.float_class.module.methods.put(prev_float_sym, value.MethodEntry.builtin(&builtinFloatPrevFloat, .{ .exact = 0 }));
}

pub fn builtinFloatPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(lhs + rhs);
}

pub fn builtinFloatMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(lhs - rhs);
}

pub fn builtinFloatUnaryPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinFloatUnaryMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.newFloat(-receiver.toFloatObject().val);
}

pub fn builtinFloatMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(lhs * rhs);
}

pub fn builtinFloatExponent(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(pow(lhs, rhs));
}

pub fn builtinFloatDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(lhs / rhs);
}

pub fn builtinFloatEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    if (args[0].isFloat()) {
        return Value.boolean(lhs == args[0].toFloatObject().val);
    }
    if (args[0].isInteger()) {
        return Value.boolean(lhs == @as(f64, @floatFromInt(args[0].toInteger())));
    }

    var reverse_args = [_]Value{receiver};
    const result = try vm.callMethodByName(args[0], "==", reverse_args[0..], null);
    return Value.boolean(result.is_truthy());
}

pub fn builtinFloatCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs_f = try coerceNumericArg(vm, args[0]);

    if (std.math.isNan(lhs) or std.math.isNan(rhs_f)) return Value.nil();

    if (std.math.isInf(rhs_f) and args[0].isBigInteger()) {
        if (std.math.isInf(lhs)) {
            return if (lhs > 0) Value.integer(1) else Value.integer(-1);
        }
        return if (rhs_f > 0) Value.integer(-1) else Value.integer(1);
    }

    if (lhs < rhs_f) return Value.integer(-1);
    if (lhs > rhs_f) return Value.integer(1);
    return Value.integer(0);
}

pub fn builtinFloatEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isFloat()) return Value.boolean(false);
    const lhs = receiver.toFloatObject().val;
    return Value.boolean(lhs == args[0].toFloatObject().val);
}

pub fn builtinFloatLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return Value.boolean(lhs < rhs);
}

pub fn builtinFloatLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return Value.boolean(lhs <= rhs);
}

pub fn builtinFloatGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return Value.boolean(lhs > rhs);
}

pub fn builtinFloatGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return Value.boolean(lhs >= rhs);
}

pub fn builtinFloatAbs(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return vm.newFloat(@abs(f));
}

pub fn builtinFloatNan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return Value.boolean(std.math.isNan(f));
}

pub fn builtinFloatInfinite(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    if (std.math.isPositiveInf(f)) return Value.integer(1);
    if (std.math.isNegativeInf(f)) return Value.integer(-1);
    return Value.nil();
}

pub fn builtinFloatNegative(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toFloatObject().val < 0.0);
}

pub fn builtinFloatPositive(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toFloatObject().val > 0.0);
}

pub fn builtinFloatToInt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    if (std.math.isNan(f) or std.math.isInf(f)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "float out of range of integer", .{});
    }

    const bits: u64 = @bitCast(f);
    const sign = (bits >> 63) != 0;
    const exponent_bits: u16 = @intCast((bits >> 52) & 0x7ff);
    const fraction_bits = bits & 0x000f_ffff_ffff_ffff;

    if (exponent_bits == 0) {
        return Value.integer(0);
    }

    const exponent: i32 = @as(i32, exponent_bits) - 1023;
    if (exponent < 0) {
        return Value.integer(0);
    }

    const significand: u64 = fraction_bits | (@as(u64, 1) << 52);
    if (exponent <= 52) {
        const shift: u6 = @intCast(52 - exponent);
        const magnitude: i64 = @intCast(significand >> shift);
        return Value.integer(if (sign) -magnitude else magnitude);
    }

    var managed = std.math.big.int.Managed.initSet(vm.allocator, @as(i64, @intCast(significand))) catch return error.Fatal;
    defer managed.deinit();
    managed.shiftLeft(&managed, @intCast(exponent - 52)) catch return error.Fatal;
    if (sign) managed.negate();
    return vm.valueFromManagedInteger(&managed);
}

pub fn builtinFloatToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinFloatToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const parts = try rational_builtin.floatToRationalParts(vm, receiver.toFloatObject().val);
    return vm.newRationalValues(parts.numerator, parts.denominator);
}

fn floatToString(vm: *VM, value_f: f64) VMError!Value {
    if (std.math.isNan(value_f)) {
        return vm.newStringWithEncoding("NaN", false, .{ .us_ascii = .{} });
    }
    if (std.math.isPositiveInf(value_f)) {
        return vm.newStringWithEncoding("Infinity", false, .{ .us_ascii = .{} });
    }
    if (std.math.isNegativeInf(value_f)) {
        return vm.newStringWithEncoding("-Infinity", false, .{ .us_ascii = .{} });
    }

    var decpt: c_int = 0;
    var sign: c_int = 0;
    var end_ptr: ?[*]u8 = null;
    const dtoa_result = dtoa(value_f, 0, 0, &decpt, &sign, &end_ptr);
    defer freedtoa(@ptrCast(dtoa_result));

    const digits = std.mem.span(dtoa_result);

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;

    if (sign != 0) {
        writer.writeByte('-') catch return error.Fatal;
    }

    if (decpt > 0) {
        if (decpt < digits.len) {
            const split: usize = @intCast(decpt);
            writer.writeAll(digits[0..split]) catch return error.Fatal;
            writer.writeByte('.') catch return error.Fatal;
            writer.writeAll(digits[split..]) catch return error.Fatal;
        } else if (decpt <= max_fixed_decimal_digits) {
            writer.writeAll(digits) catch return error.Fatal;
            var i: usize = digits.len;
            const decpt_usize: usize = @intCast(decpt);
            while (i < decpt_usize) : (i += 1) {
                writer.writeByte('0') catch return error.Fatal;
            }
            writer.writeAll(".0") catch return error.Fatal;
        } else {
            try appendScientificMantissa(writer, digits);
            try appendExponent(writer, decpt - 1);
        }
    } else if (decpt > -4) {
        writer.writeAll("0.") catch return error.Fatal;
        var zero_count: c_int = -decpt;
        while (zero_count > 0) : (zero_count -= 1) {
            writer.writeByte('0') catch return error.Fatal;
        }
        writer.writeAll(digits) catch return error.Fatal;
    } else {
        try appendScientificMantissa(writer, digits);
        try appendExponent(writer, decpt - 1);
    }

    return vm.newStringWithEncoding(buf.written(), false, enc.Encoding{ .us_ascii = .{} });
}

pub fn builtinFloatToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return floatToString(vm, f);
}

pub fn builtinFloatInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinFloatToS(vm, receiver, args, null);
}

fn floatToIntegerValue(vm: *VM, f: f64) VMError!Value {
    if (std.math.isNan(f) or std.math.isInf(f)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "float out of range of integer", .{});
    }
    const max_exact_f64: f64 = 9007199254740992.0; // 2^53
    if (f >= -max_exact_f64 and f <= max_exact_f64) {
        return Value.integer(@as(i64, @intFromFloat(f)));
    }
    var managed = std.math.big.int.Managed.init(vm.gc_allocator) catch return error.Fatal;
    defer managed.deinit();
    managed.ensureCapacity(32) catch return error.Fatal;
    {
        var mut = managed.toMutable();
        _ = mut.setFloat(f, .nearest_even);
        managed.setMetadata(mut.positive, mut.len);
    }
    return vm.valueFromManagedInteger(&managed);
}

pub fn builtinFloatCeil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const f = receiver.toFloatObject().val;
    if (args.len == 0) {
        return floatToIntegerValue(vm, @ceil(f));
    }
    const digits = try coercePrecisionArgToCInt(vm, args[0]);
    if (digits > 0) {
        return try vm.newFloat(f);
    }
    if (digits == 0) {
        return floatToIntegerValue(vm, @ceil(f));
    }
    const factor = std.math.pow(f64, 10, @as(f64, @floatFromInt(-digits)));
    return floatToIntegerValue(vm, @ceil(f / factor) * factor);
}

pub fn builtinFloatFloor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const f = receiver.toFloatObject().val;
    if (args.len == 0) {
        return floatToIntegerValue(vm, @floor(f));
    }
    const digits = try coercePrecisionArgToCInt(vm, args[0]);
    if (digits > 0) {
        return try vm.newFloat(f);
    }
    if (digits == 0) {
        return floatToIntegerValue(vm, @floor(f));
    }
    const factor = std.math.pow(f64, 10, @as(f64, @floatFromInt(-digits)));
    return floatToIntegerValue(vm, @floor(f / factor) * factor);
}

pub fn builtinFloatRound(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const f = receiver.toFloatObject().val;
    if (args.len == 0) {
        return floatToIntegerValue(vm, @round(f));
    }
    const digits = try args[0].integerToI64(vm, "invalid precision");
    if (digits >= 0) {
        return try vm.newFloat(f);
    }
    const factor = std.math.pow(f64, 10, @as(f64, @floatFromInt(-digits)));
    return try vm.newFloat(@round(f / factor) * factor);
}

pub fn builtinFloatNextFloat(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return vm.newFloat(nextafter(f, std.math.inf(f64)));
}

pub fn builtinFloatPrevFloat(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return vm.newFloat(nextafter(f, -std.math.inf(f64)));
}
