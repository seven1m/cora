const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

fn coerceNumericArg(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isFloat()) return arg.toFloatObject().val;
    if (arg.isInteger()) return @floatFromInt(arg.toInteger());
    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
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

    const divide_sym = try vm.intern("/");
    try vm.float_class.module.methods.put(divide_sym, .{ .method = .{ .builtin = &builtinFloatDivide } });

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

pub fn builtinFloatDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = try coerceNumericArg(vm, args[0]);
    return vm.newFloat(lhs / rhs);
}

pub fn builtinFloatEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toFloatObject().val;
    const rhs = coerceNumericArg(vm, args[0]) catch return Value.boolean(false);
    return Value.boolean(lhs == rhs);
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

    const truncated = @trunc(f);
    const max_i64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
    const min_i64 = @as(f64, @floatFromInt(std.math.minInt(i64)));
    if (truncated > max_i64 or truncated < min_i64) {
        return vm.raiseExceptionFmt(vm.range_error_class, "float out of range of integer", .{});
    }

    return Value.integer(@intFromFloat(truncated));
}

fn floatToString(vm: *VM, value_f: f64) VMError!Value {
    if (std.math.isNan(value_f)) {
        return vm.newString("NaN", false);
    }
    if (std.math.isPositiveInf(value_f)) {
        return vm.newString("Infinity", false);
    }
    if (std.math.isNegativeInf(value_f)) {
        return vm.newString("-Infinity", false);
    }

    const str = std.fmt.allocPrint(vm.gc_allocator, "{d}", .{value_f}) catch return error.Fatal;
    return vm.newString(str, false);
}

pub fn builtinFloatToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const f = receiver.toFloatObject().val;
    return floatToString(vm, f);
}

pub fn builtinFloatInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinFloatToS(vm, receiver, args, null);
}
