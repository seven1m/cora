const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const encoding_builtin = @import("encoding.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const BigInt = std.math.big.int.Managed;

const NumericArg = union(enum) {
    integer: Value,
    float: f64,
};

fn coerceNumericArg(vm: *VM, arg: Value) VMError!NumericArg {
    if (arg.isInteger() or arg.isBigInteger()) return .{ .integer = arg };
    if (arg.isFloat()) return .{ .float = arg.toFloatObject().val };
    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
}

fn coerceAndCallIntegerArithmetic(vm: *VM, receiver: Value, arg: Value, op_name: []const u8) VMError!Value {
    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(arg, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }

    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.type_error_class, "coerce must return [x, y]", .{});
    }

    var op_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], op_name, op_args[0..], null);
}

fn compareIntegerRelational(vm: *VM, receiver: Value, arg: Value, op_name: []const u8) VMError!Value {
    if (arg.isInteger() or arg.isBigInteger() or arg.isFloat()) {
        const rhs = try coerceNumericArg(vm, arg);
        return switch (rhs) {
            .integer => |i| {
                const ord = try compareIntegers(vm, receiver, i);
                if (std.mem.eql(u8, op_name, "<")) return Value.boolean(ord == .lt);
                if (std.mem.eql(u8, op_name, "<=")) return Value.boolean(ord == .lt or ord == .eq);
                if (std.mem.eql(u8, op_name, ">")) return Value.boolean(ord == .gt);
                if (std.mem.eql(u8, op_name, ">=")) return Value.boolean(ord == .gt or ord == .eq);
                unreachable;
            },
            .float => |f| {
                const lhs = receiver.integerToF64();
                if (std.mem.eql(u8, op_name, "<")) return Value.boolean(lhs < f);
                if (std.mem.eql(u8, op_name, "<=")) return Value.boolean(lhs <= f);
                if (std.mem.eql(u8, op_name, ">")) return Value.boolean(lhs > f);
                if (std.mem.eql(u8, op_name, ">=")) return Value.boolean(lhs >= f);
                unreachable;
            },
        };
    }

    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(arg, "coerce", false, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.argument_error_class, "comparison of Integer with {s} failed", .{vm.className(arg)});
    };
    if (!coerced.isArray()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "comparison of Integer with {s} failed", .{vm.className(arg)});
    }

    const coerced_items = coerced.toArrayObject().elements.items;
    if (coerced_items.len != 2) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "comparison of Integer with {s} failed", .{vm.className(arg)});
    }

    var compare_args = [_]Value{coerced_items[1]};
    return vm.callMethodByName(coerced_items[0], op_name, compare_args[0..], null);
}

inline fn addIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.add(i63, li, ri)) |sum| {
            return Value.integer(@as(i64, sum));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.add(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

inline fn subIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.sub(i63, li, ri)) |diff| {
            return Value.integer(@as(i64, diff));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.sub(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

inline fn mulIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.mul(i63, li, ri)) |prod| {
            return Value.integer(@as(i64, prod));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.mul(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

inline fn divFloorIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.divFloor(i63, li, ri)) |quot| {
            return Value.integer(@as(i64, quot));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();

    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();

    quot.divFloor(&rem, &a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&quot);
}

inline fn divTruncIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.divTrunc(i63, li, ri)) |quot| {
            return Value.integer(@as(i64, quot));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();

    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();

    quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&quot);
}

inline fn modIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li = lhs.toInteger();
        const ri = rhs.toInteger();
        const maybe_q = std.math.divFloor(i64, li, ri);
        if (maybe_q) |q| {
            const prod = std.math.mul(i64, q, ri) catch {
                return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
            };
            const result = std.math.sub(i64, li, prod) catch {
                return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
            };
            return Value.integer(result);
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();

    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();

    quot.divFloor(&rem, &a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&rem);
}

inline fn compareIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!std.math.Order {
    if (lhs.isInteger() and rhs.isInteger()) {
        return std.math.order(lhs.toInteger(), rhs.toInteger());
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    return BigInt.order(a, b);
}

pub fn uptoStopToI64(vm: *VM, stop: Value) VMError!i64 {
    if (stop.isInteger() or stop.isBigInteger()) {
        return stop.integerToI64(vm, "integer is too large to iterate");
    }
    if (stop.isFloat()) {
        const floored = @floor(stop.toFloatObject().val);
        if (std.math.isNan(floored) or std.math.isInf(floored)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
        }
        const max_i64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
        const min_i64 = @as(f64, @floatFromInt(std.math.minInt(i64)));
        if (floored > max_i64 or floored < min_i64) {
            return vm.raiseExceptionFmt(vm.range_error_class, "integer is too large to iterate", .{});
        }
        return @intFromFloat(floored);
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
}

pub fn downtoStopToI64(vm: *VM, stop: Value) VMError!i64 {
    if (stop.isInteger() or stop.isBigInteger()) {
        return stop.integerToI64(vm, "integer is too large to iterate");
    }
    if (stop.isFloat()) {
        const ceiled = @ceil(stop.toFloatObject().val);
        if (std.math.isNan(ceiled) or std.math.isInf(ceiled)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
        }
        const max_i64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
        const min_i64 = @as(f64, @floatFromInt(std.math.minInt(i64)));
        if (ceiled > max_i64 or ceiled < min_i64) {
            return vm.raiseExceptionFmt(vm.range_error_class, "integer is too large to iterate", .{});
        }
        return @intFromFloat(ceiled);
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
}

pub fn uptoEnumeratorSize(vm: *VM, receiver: Value, method_args: ?*value.ArrayObject) VMError!Value {
    const args = method_args orelse return Value.nil();
    if (args.elements.items.len != 1) return Value.nil();

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    const stop = try uptoStopToI64(vm, args.elements.items[0]);
    if (start > stop) return Value.integer(0);
    return Value.integer(stop - start + 1);
}

pub fn downtoEnumeratorSize(vm: *VM, receiver: Value, method_args: ?*value.ArrayObject) VMError!Value {
    const args = method_args orelse return Value.nil();
    if (args.elements.items.len != 1) return Value.nil();

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    const stop = try downtoStopToI64(vm, args.elements.items[0]);
    if (start < stop) return Value.integer(0);
    return Value.integer(start - stop + 1);
}

pub fn register(vm: *VM) !void {
    const integer_class_val = Value.fromObject(vm.integer_class);
    const integer_singleton = try vm.getOrCreateSingletonClass(integer_class_val);
    const try_convert_sym = try vm.intern("try_convert");
    try integer_singleton.module.methods.put(try_convert_sym, .{ .method = .{ .builtin = &builtinIntegerTryConvert } });

    const plus_sym = try vm.intern("+");
    try vm.integer_class.module.methods.put(plus_sym, .{ .method = .{ .builtin = &builtinIntegerPlus } });

    const unary_plus_sym = try vm.intern("+@");
    try vm.integer_class.module.methods.put(unary_plus_sym, .{ .method = .{ .builtin = &builtinIntegerUnaryPlus } });

    const minus_sym = try vm.intern("-");
    try vm.integer_class.module.methods.put(minus_sym, .{ .method = .{ .builtin = &builtinIntegerMinus } });

    const unary_minus_sym = try vm.intern("-@");
    try vm.integer_class.module.methods.put(unary_minus_sym, .{ .method = .{ .builtin = &builtinIntegerUnaryMinus } });

    const multiply_sym = try vm.intern("*");
    try vm.integer_class.module.methods.put(multiply_sym, .{ .method = .{ .builtin = &builtinIntegerMultiply } });

    const divide_sym = try vm.intern("/");
    try vm.integer_class.module.methods.put(divide_sym, .{ .method = .{ .builtin = &builtinIntegerDivide } });

    const modulo_sym = try vm.intern("%");
    try vm.integer_class.module.methods.put(modulo_sym, .{ .method = .{ .builtin = &builtinIntegerModulo } });

    const compare_sym = try vm.intern("<=>");
    try vm.integer_class.module.methods.put(compare_sym, .{ .method = .{ .builtin = &builtinIntegerCompare } });

    const left_shift_sym = try vm.intern("<<");
    try vm.integer_class.module.methods.put(left_shift_sym, .{ .method = .{ .builtin = &builtinIntegerLeftShift } });

    const power_sym = try vm.intern("**");
    try vm.integer_class.module.methods.put(power_sym, .{ .method = .{ .builtin = &builtinIntegerPower } });

    const equal_sym = try vm.intern("==");
    try vm.integer_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinIntegerEqual } });

    const eql_sym = try vm.intern("eql?");
    try vm.integer_class.module.methods.put(eql_sym, .{ .method = .{ .builtin = &builtinIntegerEql } });

    const not_equal_sym = try vm.intern("!=");
    try vm.integer_class.module.methods.put(not_equal_sym, .{ .method = .{ .builtin = &builtinIntegerNotEqual } });

    const less_than_sym = try vm.intern("<");
    try vm.integer_class.module.methods.put(less_than_sym, .{ .method = .{ .builtin = &builtinIntegerLessThan } });

    const less_than_or_equal_sym = try vm.intern("<=");
    try vm.integer_class.module.methods.put(less_than_or_equal_sym, .{ .method = .{ .builtin = &builtinIntegerLessThanOrEqual } });

    const greater_than_sym = try vm.intern(">");
    try vm.integer_class.module.methods.put(greater_than_sym, .{ .method = .{ .builtin = &builtinIntegerGreaterThan } });

    const greater_than_or_equal_sym = try vm.intern(">=");
    try vm.integer_class.module.methods.put(greater_than_or_equal_sym, .{ .method = .{ .builtin = &builtinIntegerGreaterThanOrEqual } });

    const to_s_sym = try vm.intern("to_s");
    try vm.integer_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinIntegerToS } });

    const to_i_sym = try vm.intern("to_i");
    try vm.integer_class.module.methods.put(to_i_sym, .{ .method = .{ .builtin = &builtinIntegerToI } });

    const to_int_sym = try vm.intern("to_int");
    try vm.integer_class.module.methods.put(to_int_sym, .{ .method = .{ .builtin = &builtinIntegerToI } });

    const to_f_sym = try vm.intern("to_f");
    try vm.integer_class.module.methods.put(to_f_sym, .{ .method = .{ .builtin = &builtinIntegerToF } });

    const ord_sym = try vm.intern("ord");
    try vm.integer_class.module.methods.put(ord_sym, .{ .method = .{ .builtin = &builtinIntegerOrd } });

    const denominator_sym = try vm.intern("denominator");
    try vm.integer_class.module.methods.put(denominator_sym, .{ .method = .{ .builtin = &builtinIntegerDenominator } });

    const size_sym = try vm.intern("size");
    try vm.integer_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinIntegerSize } });

    const truncate_sym = try vm.intern("truncate");
    try vm.integer_class.module.methods.put(truncate_sym, .{ .method = .{ .builtin = &builtinIntegerTruncate } });

    const inspect_sym = try vm.intern("inspect");
    try vm.integer_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinIntegerInspect } });

    const abs_sym = try vm.intern("abs");
    try vm.integer_class.module.methods.put(abs_sym, .{ .method = .{ .builtin = &builtinIntegerAbs } });

    const negative_sym = try vm.intern("negative?");
    try vm.integer_class.module.methods.put(negative_sym, .{ .method = .{ .builtin = &builtinIntegerNegative } });

    const zero_sym = try vm.intern("zero?");
    try vm.integer_class.module.methods.put(zero_sym, .{ .method = .{ .builtin = &builtinIntegerZero } });

    const even_sym = try vm.intern("even?");
    try vm.integer_class.module.methods.put(even_sym, .{ .method = .{ .builtin = &builtinIntegerEven } });

    const odd_sym = try vm.intern("odd?");
    try vm.integer_class.module.methods.put(odd_sym, .{ .method = .{ .builtin = &builtinIntegerOdd } });

    const next_sym = try vm.intern("next");
    try vm.integer_class.module.methods.put(next_sym, .{ .method = .{ .builtin = &builtinIntegerNext } });

    const succ_sym = try vm.intern("succ");
    try vm.integer_class.module.methods.put(succ_sym, .{ .method = .{ .builtin = &builtinIntegerNext } });

    const pred_sym = try vm.intern("pred");
    try vm.integer_class.module.methods.put(pred_sym, .{ .method = .{ .builtin = &builtinIntegerPred } });

    const times_sym = try vm.intern("times");
    try vm.integer_class.module.methods.put(times_sym, .{ .method = .{ .builtin = &builtinIntegerTimes } });

    const upto_sym = try vm.intern("upto");
    try vm.integer_class.module.methods.put(upto_sym, .{ .method = .{ .builtin = &builtinIntegerUpto } });

    const downto_sym = try vm.intern("downto");
    try vm.integer_class.module.methods.put(downto_sym, .{ .method = .{ .builtin = &builtinIntegerDownto } });

    const chr_sym = try vm.intern("chr");
    try vm.integer_class.module.methods.put(chr_sym, .{ .method = .{ .builtin = &builtinIntegerChr } });
}

pub fn builtinIntegerPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger() and !args[0].isFloat()) {
        return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "+");
    }
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try addIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() + f),
    };
}

pub fn builtinIntegerTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isInteger() or arg.isBigInteger()) return arg;

    const maybe_converted = try vm.checkCallMethodByName(arg, "to_int", false, &[_]Value{}, null);
    const converted = maybe_converted orelse return Value.nil();
    if (converted.isNil()) return Value.nil();
    if (converted.isInteger() or converted.isBigInteger()) return converted;

    return vm.raiseExceptionFmt(
        vm.type_error_class,
        "can't convert {s} to Integer ({s}#to_int gives {s})",
        .{ vm.className(arg), vm.className(arg), vm.className(converted) },
    );
}

pub fn builtinIntegerUnaryPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return receiver;
}

pub fn builtinIntegerMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try subIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() - f),
    };
}

pub fn builtinIntegerUnaryMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    if (receiver.isInteger()) {
        if (std.math.negate(receiver.toInteger())) |negated| {
            return Value.integer(negated);
        } else |_| {}
    }

    var value_managed = try receiver.integerToManaged(vm);
    defer value_managed.deinit();
    value_managed.negate();
    return vm.valueFromManagedInteger(&value_managed);
}

pub fn builtinIntegerMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try mulIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() * f),
    };
}

pub fn builtinIntegerLeftShift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const shift_count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    if (shift_count == 0) return receiver;

    var result = receiver;
    if (shift_count > 0) {
        var i: i64 = 0;
        while (i < shift_count) : (i += 1) {
            result = try mulIntegers(vm, result, Value.integer(2));
        }
        return result;
    }

    var i: i64 = 0;
    const right_shift_count = -shift_count;
    while (i < right_shift_count) : (i += 1) {
        result = try divFloorIntegers(vm, result, Value.integer(2));
    }
    return result;
}

pub fn builtinIntegerDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |divisor| blk: {
            const divisor_is_zero = if (divisor.isInteger())
                divisor.toInteger() == 0
            else if (divisor.isBigInteger())
                divisor.toBigIntegerObject().value.eqlZero()
            else
                unreachable;
            if (divisor_is_zero) {
                return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
            }
            break :blk try divFloorIntegers(vm, receiver, divisor);
        },
        .float => |divisor| try vm.newFloat(receiver.integerToF64() / divisor),
    };
}

pub fn builtinIntegerModulo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    try args[0].ensureInteger(vm);

    const divisor_is_zero = if (args[0].isInteger())
        args[0].toInteger() == 0
    else if (args[0].isBigInteger())
        args[0].toBigIntegerObject().value.eqlZero()
    else
        unreachable;
    if (divisor_is_zero) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }

    return modIntegers(vm, receiver, args[0]);
}

pub fn builtinIntegerCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = args[0];

    if (rhs.isFloat()) {
        const lhs_f = receiver.integerToF64();
        const rhs_f = rhs.toFloatObject().val;
        if (lhs_f < rhs_f) return Value.integer(-1);
        if (lhs_f > rhs_f) return Value.integer(1);
        return Value.integer(0);
    }

    if (!rhs.isInteger() and !rhs.isBigInteger()) return Value.nil();
    const order = try compareIntegers(vm, receiver, rhs);
    return switch (order) {
        .lt => Value.integer(-1),
        .eq => Value.integer(0),
        .gt => Value.integer(1),
    };
}

pub fn builtinIntegerPower(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    try args[0].ensureInteger(vm);

    const exponent_i64 = try args[0].integerToI64(vm, "exponent is too large");
    if (exponent_i64 < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative exponent not supported", .{});
    }
    if (exponent_i64 > std.math.maxInt(u32)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "exponent is too large", .{});
    }

    const exponent_u32: u32 = @intCast(exponent_i64);

    if (receiver.isInteger()) {
        var result: i64 = 1;
        var base = receiver.toInteger();
        var exp: u64 = exponent_u32;
        var overflowed = false;

        while (exp > 0) : (exp >>= 1) {
            if ((exp & 1) == 1) {
                result = std.math.mul(i64, result, base) catch {
                    overflowed = true;
                    break;
                };
            }
            if (exp > 1) {
                base = std.math.mul(i64, base, base) catch {
                    overflowed = true;
                    break;
                };
            }
        }

        if (!overflowed) {
            return Value.integer(result);
        }
    }

    var a = try receiver.integerToManaged(vm);
    defer a.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.pow(&a, exponent_u32) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

pub fn builtinIntegerEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    if (args[0].isFloat()) {
        return Value.boolean(receiver.integerToF64() == args[0].toFloatObject().val);
    }
    if (args[0].isInteger() or args[0].isBigInteger()) {
        return Value.boolean((try compareIntegers(vm, receiver, args[0])) == .eq);
    }

    var reverse_args = [_]Value{receiver};
    const result = try vm.callMethodByName(args[0], "==", reverse_args[0..], null);
    return Value.boolean(result.is_truthy());
}

pub fn builtinIntegerEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger()) return Value.boolean(false);
    return Value.boolean((try compareIntegers(vm, receiver, args[0])) == .eq);
}

pub fn builtinIntegerNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const equal = try builtinIntegerEqual(vm, receiver, args, null);
    return Value.boolean(!equal.is_truthy());
}

pub fn builtinIntegerLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    return compareIntegerRelational(vm, receiver, args[0], "<");
}

pub fn builtinIntegerLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    return compareIntegerRelational(vm, receiver, args[0], "<=");
}

pub fn builtinIntegerGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    return compareIntegerRelational(vm, receiver, args[0], ">");
}

pub fn builtinIntegerGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    return compareIntegerRelational(vm, receiver, args[0], ">=");
}

pub fn builtinIntegerToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    var base: u8 = 10;
    if (args.len == 1) {
        const base_i64 = try args[0].integerArgToI64(vm, "argument is not an Integer", "base is too large");
        if (base_i64 < 2 or base_i64 > 36) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid radix {d}", .{base_i64});
        }
        base = @intCast(base_i64);
    }

    if (receiver.isInteger()) {
        var buf: [65]u8 = undefined;
        const str = integerToBaseString(receiver.toInteger(), base, &buf);
        return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
    } else if (receiver.isBigInteger()) {
        const b = receiver.toBigIntegerObject();
        const decimal = b.value.toString(vm.allocator, 10, .lower) catch return error.Fatal;
        defer vm.allocator.free(decimal);

        const str = if (base == 10)
            decimal
        else
            decimalStringToBaseString(vm.allocator, decimal, base) catch return error.Fatal;
        defer if (base != 10) vm.allocator.free(str);

        return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
    } else unreachable;
}

pub fn builtinIntegerToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return receiver;
}

pub fn builtinIntegerToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return vm.newFloat(receiver.integerToF64());
}

pub fn builtinIntegerOrd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return receiver;
}

pub fn builtinIntegerDenominator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return Value.integer(1);
}

pub fn builtinIntegerSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);

    if (receiver.isInteger()) {
        return Value.integer(@sizeOf(c_long));
    }

    const bit_count = receiver.toBigIntegerObject().value.bitCountAbs();
    const byte_count = if (bit_count == 0) 1 else @divFloor(bit_count + 7, 8);
    return Value.integer(@intCast(byte_count));
}

pub fn builtinIntegerTruncate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (args.len == 0) return receiver;

    const ndigits = try args[0].integerArgToI64(vm, "argument is not an Integer", "ndigits is too large");
    if (ndigits >= 0) return receiver;

    const abs_ndigits: u64 = @intCast(-ndigits);
    var factor = Value.integer(1);
    var i: u64 = 0;
    while (i < abs_ndigits) : (i += 1) {
        factor = try mulIntegers(vm, factor, Value.integer(10));
    }

    const quotient = try divTruncIntegers(vm, receiver, factor);
    return mulIntegers(vm, quotient, factor);
}

pub fn builtinIntegerInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinIntegerToS(vm, receiver, args, null);
}

pub fn builtinIntegerAbs(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);

    if (receiver.isInteger()) {
        const val = receiver.toInteger();
        if (val >= 0) return Value.integer(val);
        if (std.math.negate(val)) |abs_val| {
            return Value.integer(abs_val);
        } else |_| {
            return vm.newBigIntegerFromDecimalString("9223372036854775808");
        }
    } else if (receiver.isBigInteger()) {
        const b = receiver.toBigIntegerObject();
        if (b.value.isPositive()) return receiver;
        var temp = b.value.cloneWithDifferentAllocator(vm.allocator) catch return error.Fatal;
        defer temp.deinit();
        temp.abs();
        return vm.valueFromManagedInteger(&temp);
    } else unreachable;
}

pub fn builtinIntegerNegative(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    if (receiver.isInteger()) return Value.boolean(receiver.toInteger() < 0);
    if (receiver.isBigInteger()) {
        const b = receiver.toBigIntegerObject();
        return Value.boolean(!b.value.isPositive() and !b.value.eqlZero());
    }
    unreachable;
}

pub fn builtinIntegerZero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    if (receiver.isInteger()) return Value.boolean(receiver.toInteger() == 0);
    if (receiver.isBigInteger()) return Value.boolean(receiver.toBigIntegerObject().value.eqlZero());
    unreachable;
}

pub fn builtinIntegerEven(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    if (receiver.isInteger()) return Value.boolean(@mod(receiver.toInteger(), 2) == 0);
    if (receiver.isBigInteger()) {
        const remainder = try modIntegers(vm, receiver, Value.integer(2));
        if (remainder.isInteger()) return Value.boolean(remainder.toInteger() == 0);
        return Value.boolean(remainder.toBigIntegerObject().value.eqlZero());
    }
    unreachable;
}

pub fn builtinIntegerOdd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    if (receiver.isInteger()) return Value.boolean(@mod(receiver.toInteger(), 2) != 0);
    if (receiver.isBigInteger()) {
        const remainder = try modIntegers(vm, receiver, Value.integer(2));
        if (remainder.isInteger()) return Value.boolean(remainder.toInteger() != 0);
        return Value.boolean(!remainder.toBigIntegerObject().value.eqlZero());
    }
    unreachable;
}

pub fn builtinIntegerNext(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return addIntegers(vm, receiver, Value.integer(1));
}

pub fn builtinIntegerPred(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return subIntegers(vm, receiver, Value.integer(1));
}

pub fn builtinIntegerTimes(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("times"), &.{}, receiver);
    };

    const count = try receiver.integerToI64(vm, "integer is too large to iterate");
    if (count <= 0) {
        return receiver;
    }

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        const yield_args = [_]Value{Value.integer(i)};
        const yield_result = try vm.yieldToBlock(blk, &yield_args);
        if (yield_result.break_occurred) {
            return yield_result.value;
        }
    }

    return receiver;
}

pub fn builtinIntegerUpto(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSizeFn(receiver, try vm.intern("upto"), args, &uptoEnumeratorSize);
    };

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    const stop = try uptoStopToI64(vm, args[0]);
    if (start > stop) {
        return receiver;
    }

    var i = start;
    while (i <= stop) : (i += 1) {
        const yield_args = [_]Value{Value.integer(i)};
        const yield_result = try vm.yieldToBlock(blk, &yield_args);
        if (yield_result.break_occurred) {
            return yield_result.value;
        }
    }

    return receiver;
}

pub fn builtinIntegerDownto(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSizeFn(receiver, try vm.intern("downto"), args, &downtoEnumeratorSize);
    };

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    const stop = try downtoStopToI64(vm, args[0]);
    if (start < stop) {
        return receiver;
    }

    var i = start;
    while (i >= stop) : (i -= 1) {
        const yield_args = [_]Value{Value.integer(i)};
        const yield_result = try vm.yieldToBlock(blk, &yield_args);
        if (yield_result.break_occurred) {
            return yield_result.value;
        }
    }

    return receiver;
}

pub fn builtinIntegerChr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    const codepoint: i64 = if (receiver.isInteger())
        receiver.toInteger()
    else
        receiver.toBigIntegerObject().value.toInt(i64) catch
            return vm.raiseExceptionFmt(vm.range_error_class, "bignum out of char range", .{});
    if (codepoint < 0) {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint});
    }

    const target_encoding: enc.Encoding = if (args.len == 0)
        if (codepoint <= 127)
            .{ .us_ascii = .{} }
        else if (codepoint <= 255)
            .{ .ascii_8bit = .{} }
        else if (vm.default_internal_encoding) |internal|
            internal.encoding
        else
            return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint})
    else if (args[0].isEncoding())
        args[0].toEncodingObject().encoding
    else blk: {
        const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
        break :blk result.toEncodingObject().encoding;
    };

    const cp: u32 = @intCast(codepoint);
    var buf: [8]u8 = undefined;
    const encoded_len = encodeIntegerChrBytes(target_encoding, cp, &buf) orelse {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint});
    };
    const bytes = buf[0..encoded_len];

    return try vm.newStringWithEncoding(bytes, false, target_encoding);
}

fn encodeIntegerChrBytes(target_encoding: enc.Encoding, codepoint: u32, out: *[8]u8) ?usize {
    switch (target_encoding) {
        .cesu8 => return encodeCesu8Codepoint(codepoint, out),
        .shift_jis, .windows_31j, .euc_jp, .iso_2022_jp => return encodeEncodedCharValue(target_encoding, codepoint, out),
        else => {
            var narrow: [4]u8 = undefined;
            const len = target_encoding.fromUnicodeCodepoint(codepoint, &narrow) orelse return null;
            @memcpy(out[0..len], narrow[0..len]);
            return len;
        },
    }
}

fn encodeEncodedCharValue(target_encoding: enc.Encoding, codepoint: u32, out: *[8]u8) ?usize {
    if (codepoint == 0) {
        out[0] = 0;
        return 1;
    }

    var tmp: [4]u8 = undefined;
    var tmp_len: usize = 0;
    var value_left = codepoint;
    while (value_left > 0) : (value_left >>= 8) {
        if (tmp_len >= tmp.len) return null;
        tmp[tmp_len] = @intCast(value_left & 0xFF);
        tmp_len += 1;
    }

    var i: usize = 0;
    while (i < tmp_len) : (i += 1) {
        out[i] = tmp[tmp_len - 1 - i];
    }

    var index: usize = 0;
    const parsed = target_encoding.nextChar(out[0..tmp_len], &index);
    if (!parsed.valid or parsed.len != tmp_len or index != tmp_len) return null;
    return tmp_len;
}

fn encodeCesu8Codepoint(codepoint: u32, out: *[8]u8) ?usize {
    var utf8_buf: [4]u8 = undefined;
    if (codepoint <= 0xFFFF) {
        const len = (enc.Encoding{ .utf8 = .{} }).fromUnicodeCodepoint(codepoint, &utf8_buf) orelse return null;
        @memcpy(out[0..len], utf8_buf[0..len]);
        return len;
    }
    if (codepoint > 0x10FFFF) return null;

    const n = codepoint - 0x10000;
    const high = 0xD800 + ((n >> 10) & 0x3FF);
    const low = 0xDC00 + (n & 0x3FF);

    encodeUtf8ThreeByteUnit(@intCast(high), out[0..3]);
    encodeUtf8ThreeByteUnit(@intCast(low), out[3..6]);
    return 6;
}

fn encodeUtf8ThreeByteUnit(unit: u16, out: []u8) void {
    out[0] = 0xE0 | @as(u8, @intCast(unit >> 12));
    out[1] = 0x80 | @as(u8, @intCast((unit >> 6) & 0x3F));
    out[2] = 0x80 | @as(u8, @intCast(unit & 0x3F));
}

fn integerToBaseString(number: i64, base: u8, out: *[65]u8) []const u8 {
    var i: usize = out.len;
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";

    const negative = number < 0;
    var magnitude: u64 = if (negative)
        (~@as(u64, @bitCast(number))) + 1
    else
        @intCast(number);

    if (magnitude == 0) {
        i -= 1;
        out[i] = '0';
    } else {
        while (magnitude > 0) {
            const digit: usize = @intCast(magnitude % base);
            i -= 1;
            out[i] = digits[digit];
            magnitude /= base;
        }
    }

    if (negative) {
        i -= 1;
        out[i] = '-';
    }

    return out[i..];
}

fn decimalStringToBaseString(allocator: std.mem.Allocator, decimal: []const u8, base: u8) ![]const u8 {
    const digits_table = "0123456789abcdefghijklmnopqrstuvwxyz";
    const negative = decimal.len > 0 and decimal[0] == '-';
    var source = if (negative) decimal[1..] else decimal;

    while (source.len > 1 and source[0] == '0') {
        source = source[1..];
    }
    if (source.len == 0) source = "0";

    if (std.mem.eql(u8, source, "0")) {
        return allocator.dupe(u8, "0");
    }

    var work = try allocator.dupe(u8, source);
    defer allocator.free(work);

    var reversed: std.ArrayList(u8) = .empty;
    defer reversed.deinit(allocator);

    while (!(work.len == 1 and work[0] == '0')) {
        var quotient: std.ArrayList(u8) = .empty;
        defer quotient.deinit(allocator);

        var carry: u16 = 0;
        var started = false;
        for (work) |ch| {
            const decimal_digit = ch - '0';
            const acc: u16 = carry * 10 + decimal_digit;
            const q_digit: u8 = @intCast(acc / base);
            carry = acc % base;

            if (q_digit != 0 or started) {
                try quotient.append(allocator, '0' + q_digit);
                started = true;
            }
        }

        try reversed.append(allocator, digits_table[carry]);

        allocator.free(work);
        if (quotient.items.len == 0) {
            work = try allocator.dupe(u8, "0");
        } else {
            work = try quotient.toOwnedSlice(allocator);
        }
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, reversed.items.len + @as(usize, if (negative) 1 else 0));

    if (negative) {
        try out.append(allocator, '-');
    }

    var idx = reversed.items.len;
    while (idx > 0) {
        idx -= 1;
        try out.append(allocator, reversed.items[idx]);
    }

    return out.toOwnedSlice(allocator);
}
