const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

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

const max_fixed_decimal_digits: c_int = 15;

fn coerceNumericArg(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isFloat()) return arg.toFloatObject().val;
    if (arg.isInteger()) return @floatFromInt(arg.toInteger());
    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
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
    const plus_sym = try vm.intern("+");
    try vm.float_class.module.methods.put(plus_sym, .{ .method = .{ .builtin = &builtinFloatPlus } });

    const minus_sym = try vm.intern("-");
    try vm.float_class.module.methods.put(minus_sym, .{ .method = .{ .builtin = &builtinFloatMinus } });

    const unary_plus_sym = try vm.intern("+@");
    try vm.float_class.module.methods.put(unary_plus_sym, .{ .method = .{ .builtin = &builtinFloatUnaryPlus } });

    const unary_minus_sym = try vm.intern("-@");
    try vm.float_class.module.methods.put(unary_minus_sym, .{ .method = .{ .builtin = &builtinFloatUnaryMinus } });

    const multiply_sym = try vm.intern("*");
    try vm.float_class.module.methods.put(multiply_sym, .{ .method = .{ .builtin = &builtinFloatMultiply } });

    const exponent_sym = try vm.intern("**");
    try vm.float_class.module.methods.put(exponent_sym, .{ .method = .{ .builtin = &builtinFloatExponent } });

    const divide_sym = try vm.intern("/");
    try vm.float_class.module.methods.put(divide_sym, .{ .method = .{ .builtin = &builtinFloatDivide } });

    const compare_sym = try vm.intern("<=>");
    try vm.float_class.module.methods.put(compare_sym, .{ .method = .{ .builtin = &builtinFloatCompare } });

    const equal_sym = try vm.intern("==");
    try vm.float_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinFloatEqual } });

    const eql_sym = try vm.intern("eql?");
    try vm.float_class.module.methods.put(eql_sym, .{ .method = .{ .builtin = &builtinFloatEql } });

    const less_than_sym = try vm.intern("<");
    try vm.float_class.module.methods.put(less_than_sym, .{ .method = .{ .builtin = &builtinFloatLessThan } });

    const less_than_or_equal_sym = try vm.intern("<=");
    try vm.float_class.module.methods.put(less_than_or_equal_sym, .{ .method = .{ .builtin = &builtinFloatLessThanOrEqual } });

    const greater_than_sym = try vm.intern(">");
    try vm.float_class.module.methods.put(greater_than_sym, .{ .method = .{ .builtin = &builtinFloatGreaterThan } });

    const greater_than_or_equal_sym = try vm.intern(">=");
    try vm.float_class.module.methods.put(greater_than_or_equal_sym, .{ .method = .{ .builtin = &builtinFloatGreaterThanOrEqual } });

    const abs_sym = try vm.intern("abs");
    try vm.float_class.module.methods.put(abs_sym, .{ .method = .{ .builtin = &builtinFloatAbs } });

    const nan_sym = try vm.intern("nan?");
    try vm.float_class.module.methods.put(nan_sym, .{ .method = .{ .builtin = &builtinFloatNan } });

    const infinite_sym = try vm.intern("infinite?");
    try vm.float_class.module.methods.put(infinite_sym, .{ .method = .{ .builtin = &builtinFloatInfinite } });

    const to_int_sym = try vm.intern("to_int");
    try vm.float_class.module.methods.put(to_int_sym, .{ .method = .{ .builtin = &builtinFloatToInt } });

    const to_i_sym = try vm.intern("to_i");
    try vm.float_class.module.methods.put(to_i_sym, .{ .method = .{ .builtin = &builtinFloatToInt } });

    const to_s_sym = try vm.intern("to_s");
    try vm.float_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinFloatToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.float_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinFloatInspect } });
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
    const rhs = coerceNumericArg(vm, args[0]) catch |err| {
        if (err == error.Unwind) {
            vm.pending_exception = null;
            return Value.boolean(false);
        }
        return err;
    };
    return Value.boolean(lhs == rhs);
}

pub fn builtinFloatCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs_f = try coerceNumericArg(vm, args[0]);

    if (std.math.isNan(lhs) or std.math.isNan(rhs_f)) return Value.nil();
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

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    const writer = buf.writer(vm.allocator);

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

    return vm.newStringWithEncoding(buf.items, false, enc.Encoding{ .us_ascii = .{} });
}

pub fn builtinFloatToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return floatToString(vm, f);
}

pub fn builtinFloatInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinFloatToS(vm, receiver, args, null);
}
