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

const ShiftCount = union(enum) {
    finite: i64,
    positive_overflow,
    negative_overflow,
};

const max_shift_width: u64 = std.math.maxInt(u32) + 1;

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

fn coerceAndCallIntegerBitwise(vm: *VM, receiver: Value, arg: Value, op_name: []const u8) VMError!Value {
    if (arg.isFloat()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert Float into Integer", .{});
    }
    return coerceAndCallIntegerArithmetic(vm, receiver, arg, op_name);
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
                if (lhs != f) {
                    if (std.mem.eql(u8, op_name, "<")) return Value.boolean(lhs < f);
                    if (std.mem.eql(u8, op_name, "<=")) return Value.boolean(lhs <= f);
                    if (std.mem.eql(u8, op_name, ">")) return Value.boolean(lhs > f);
                    if (std.mem.eql(u8, op_name, ">=")) return Value.boolean(lhs >= f);
                    unreachable;
                }
                const float_as_int = try vm.callMethodByName(arg, "to_i", &.{}, null);
                const ord = try compareIntegers(vm, receiver, float_as_int);
                if (std.mem.eql(u8, op_name, "<")) return Value.boolean(ord == .lt);
                if (std.mem.eql(u8, op_name, "<=")) return Value.boolean(ord == .lt or ord == .eq);
                if (std.mem.eql(u8, op_name, ">")) return Value.boolean(ord == .gt);
                if (std.mem.eql(u8, op_name, ">=")) return Value.boolean(ord == .gt or ord == .eq);
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

inline fn divCeilIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        const li: i63 = @intCast(lhs.toInteger());
        const ri: i63 = @intCast(rhs.toInteger());
        if (std.math.divCeil(i63, li, ri)) |quot| {
            return Value.integer(@as(i64, quot));
        } else |_| {}
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();

    a.negate();

    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();

    quot.divFloor(&rem, &a, &b) catch return error.Fatal;
    quot.negate();
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

inline fn bitAndIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        return Value.integer(lhs.toInteger() & rhs.toInteger());
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.bitAnd(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

inline fn bitOrIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        return Value.integer(lhs.toInteger() | rhs.toInteger());
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.bitOr(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
}

inline fn bitXorIntegers(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    if (lhs.isInteger() and rhs.isInteger()) {
        return Value.integer(lhs.toInteger() ^ rhs.toInteger());
    }

    var a = try lhs.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var out = BigInt.init(vm.allocator) catch return error.Fatal;
    defer out.deinit();
    out.bitXor(&a, &b) catch return error.Fatal;
    return vm.valueFromManagedInteger(&out);
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

fn coerceShiftCount(vm: *VM, arg: Value) VMError!ShiftCount {
    const coerced = try arg.coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );
    if (coerced.isInteger()) return .{ .finite = coerced.toInteger() };

    const bigint = coerced.toBigIntegerObject().value;
    const shift_count = bigint.toInt(i64) catch {
        return if (bigint.isPositive()) .positive_overflow else .negative_overflow;
    };
    return .{ .finite = shift_count };
}

fn negateInteger(vm: *VM, value_: Value) VMError!Value {
    if (value_.isInteger()) {
        if (std.math.negate(value_.toInteger())) |negated| {
            return Value.integer(negated);
        } else |_| {}
    }

    var value_managed = try value_.integerToManaged(vm);
    defer value_managed.deinit();
    value_managed.negate();
    return vm.valueFromManagedInteger(&value_managed);
}

fn bitNotInteger(vm: *VM, value_: Value) VMError!Value {
    const incremented = try addIntegers(vm, value_, Value.integer(1));
    return negateInteger(vm, incremented);
}

fn integerIsZero(value_: Value) bool {
    return if (value_.isInteger())
        value_.toInteger() == 0
    else
        value_.toBigIntegerObject().value.eqlZero();
}

fn integerIsNegative(value_: Value) bool {
    return if (value_.isInteger())
        value_.toInteger() < 0
    else
        !value_.toBigIntegerObject().value.isPositive() and !value_.toBigIntegerObject().value.eqlZero();
}

fn integerDecimalFactor(vm: *VM, abs_ndigits: u64) VMError!Value {
    var factor = Value.integer(1);
    var i: u64 = 0;
    while (i < abs_ndigits) : (i += 1) {
        factor = try mulIntegers(vm, factor, Value.integer(10));
    }
    return factor;
}

fn shiftRightConvergedValue(receiver: Value) Value {
    return Value.integer(if (integerIsNegative(receiver)) -1 else 0);
}

fn raiseShiftWidthTooBig(vm: *VM) VMError!Value {
    return vm.raiseExceptionFmt(vm.range_error_class, "shift width too big", .{});
}

fn shiftWidthTooBig(shift: u64) bool {
    return shift >= max_shift_width;
}

fn shiftLeftInteger(vm: *VM, receiver: Value, shift: usize) VMError!Value {
    if (shift == 0 or integerIsZero(receiver)) return receiver;

    var managed = try receiver.integerToManaged(vm);
    defer managed.deinit();
    managed.shiftLeft(&managed, shift) catch return error.Fatal;
    return vm.valueFromManagedInteger(&managed);
}

fn shiftRightInteger(vm: *VM, receiver: Value, shift: usize) VMError!Value {
    if (shift == 0 or integerIsZero(receiver)) return receiver;

    var managed = try receiver.integerToManaged(vm);
    defer managed.deinit();
    managed.shiftRight(&managed, shift) catch return error.Fatal;
    return vm.valueFromManagedInteger(&managed);
}

pub fn uptoStopToI64(vm: *VM, stop: Value) VMError!i64 {
    if (stop.isInteger() or stop.isBigInteger()) {
        return stop.integerToI64(vm, "integer is too large to iterate");
    }
    if (stop.isFloat()) {
        const floored = @floor(stop.toFloatObject().val);
        if (std.math.isNan(floored)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
        }
        if (std.math.isPositiveInf(floored)) return std.math.maxInt(i64);
        if (std.math.isNegativeInf(floored)) return std.math.minInt(i64);
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
        if (std.math.isNan(ceiled)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "bad value for range", .{});
        }
        if (std.math.isPositiveInf(ceiled)) return std.math.maxInt(i64);
        if (std.math.isNegativeInf(ceiled)) return std.math.minInt(i64);
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
    if (args.elements.items[0].isFloat()) {
        const stop_float = args.elements.items[0].toFloatObject().val;
        if (std.math.isPositiveInf(stop_float)) return vm.newFloat(std.math.inf(f64));
        if (std.math.isNegativeInf(stop_float)) return Value.integer(0);
    }
    const stop = try uptoStopToI64(vm, args.elements.items[0]);
    if (start > stop) return Value.integer(0);
    return Value.integer(stop - start + 1);
}

pub fn downtoEnumeratorSize(vm: *VM, receiver: Value, method_args: ?*value.ArrayObject) VMError!Value {
    const args = method_args orelse return Value.nil();
    if (args.elements.items.len != 1) return Value.nil();

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    if (args.elements.items[0].isFloat()) {
        const stop_float = args.elements.items[0].toFloatObject().val;
        if (std.math.isNegativeInf(stop_float)) return vm.newFloat(std.math.inf(f64));
        if (std.math.isPositiveInf(stop_float)) return Value.integer(0);
    }
    const stop = try downtoStopToI64(vm, args.elements.items[0]);
    if (start < stop) return Value.integer(0);
    return Value.integer(start - stop + 1);
}

pub fn register(vm: *VM) !void {
    const integer_class_val = Value.fromObject(&vm.integer_class.module.object);
    const integer_singleton = try vm.getOrCreateSingletonClass(integer_class_val);
    const try_convert_sym = try vm.intern("try_convert");
    try integer_singleton.module.methods.put(try_convert_sym, value.MethodEntry.builtin(&builtinIntegerTryConvert, .{ .exact = 1 }));

    const sqrt_sym = try vm.intern("sqrt");
    try integer_singleton.module.methods.put(sqrt_sym, value.MethodEntry.builtin(&builtinIntegerSqrt, .{ .exact = 1 }));

    const plus_sym = try vm.intern("+");
    try vm.integer_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinIntegerPlus, .{ .exact = 1 }));

    const bit_and_sym = try vm.intern("&");
    try vm.integer_class.module.methods.put(bit_and_sym, value.MethodEntry.builtin(&builtinIntegerBitAnd, .{ .exact = 1 }));

    const bit_or_sym = try vm.intern("|");
    try vm.integer_class.module.methods.put(bit_or_sym, value.MethodEntry.builtin(&builtinIntegerBitOr, .{ .exact = 1 }));

    const bit_xor_sym = try vm.intern("^");
    try vm.integer_class.module.methods.put(bit_xor_sym, value.MethodEntry.builtin(&builtinIntegerBitXor, .{ .exact = 1 }));

    const allbits_sym = try vm.intern("allbits?");
    try vm.integer_class.module.methods.put(allbits_sym, value.MethodEntry.builtin(&builtinIntegerAllBits, .{ .exact = 1 }));

    const anybits_sym = try vm.intern("anybits?");
    try vm.integer_class.module.methods.put(anybits_sym, value.MethodEntry.builtin(&builtinIntegerAnyBits, .{ .exact = 1 }));

    const nobits_sym = try vm.intern("nobits?");
    try vm.integer_class.module.methods.put(nobits_sym, value.MethodEntry.builtin(&builtinIntegerNoBits, .{ .exact = 1 }));

    const bit_not_sym = try vm.intern("~");
    try vm.integer_class.module.methods.put(bit_not_sym, value.MethodEntry.builtin(&builtinIntegerBitNot, .{ .exact = 0 }));

    const bit_length_sym = try vm.intern("bit_length");
    try vm.integer_class.module.methods.put(bit_length_sym, value.MethodEntry.builtin(&builtinIntegerBitLength, .{ .exact = 0 }));

    const element_reference_sym = try vm.intern("[]");
    try vm.integer_class.module.methods.put(element_reference_sym, value.MethodEntry.builtin(&builtinIntegerElementReference, .{ .variadic = 0 }));

    const unary_plus_sym = try vm.intern("+@");
    try vm.integer_class.module.methods.put(unary_plus_sym, value.MethodEntry.builtin(&builtinIntegerUnaryPlus, .{ .exact = 0 }));

    const minus_sym = try vm.intern("-");
    try vm.integer_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinIntegerMinus, .{ .exact = 1 }));

    const unary_minus_sym = try vm.intern("-@");
    try vm.integer_class.module.methods.put(unary_minus_sym, value.MethodEntry.builtin(&builtinIntegerUnaryMinus, .{ .exact = 0 }));

    const multiply_sym = try vm.intern("*");
    try vm.integer_class.module.methods.put(multiply_sym, value.MethodEntry.builtin(&builtinIntegerMultiply, .{ .exact = 1 }));

    const divide_sym = try vm.intern("/");
    try vm.integer_class.module.methods.put(divide_sym, value.MethodEntry.builtin(&builtinIntegerDivide, .{ .exact = 1 }));

    const modulo_sym = try vm.intern("%");
    try vm.integer_class.module.methods.put(modulo_sym, value.MethodEntry.builtin(&builtinIntegerModulo, .{ .exact = 1 }));

    const modulo_method_sym = try vm.intern("modulo");
    try vm.integer_class.module.methods.put(modulo_method_sym, value.MethodEntry.builtin(&builtinIntegerModulo, .{ .exact = 1 }));

    const remainder_sym = try vm.intern("remainder");
    try vm.integer_class.module.methods.put(remainder_sym, value.MethodEntry.builtin(&builtinIntegerRemainder, .{ .exact = 1 }));

    const ceildiv_sym = try vm.intern("ceildiv");
    try vm.integer_class.module.methods.put(ceildiv_sym, value.MethodEntry.builtin(&builtinIntegerCeildiv, .{ .exact = 1 }));

    const compare_sym = try vm.intern("<=>");
    try vm.integer_class.module.methods.put(compare_sym, value.MethodEntry.builtin(&builtinIntegerCompare, .{ .exact = 1 }));

    const left_shift_sym = try vm.intern("<<");
    try vm.integer_class.module.methods.put(left_shift_sym, value.MethodEntry.builtin(&builtinIntegerLeftShift, .{ .exact = 1 }));

    const right_shift_sym = try vm.intern(">>");
    try vm.integer_class.module.methods.put(right_shift_sym, value.MethodEntry.builtin(&builtinIntegerRightShift, .{ .exact = 1 }));

    const power_sym = try vm.intern("**");
    try vm.integer_class.module.methods.put(power_sym, value.MethodEntry.builtin(&builtinIntegerPower, .{ .exact = 1 }));

    const pow_sym = try vm.intern("pow");
    try vm.integer_class.module.methods.put(pow_sym, value.MethodEntry.builtin(&builtinIntegerPow, .{ .variadic = 1 }));

    const equal_sym = try vm.intern("==");
    try vm.integer_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinIntegerEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.integer_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinIntegerEql, .{ .exact = 1 }));

    const not_equal_sym = try vm.intern("!=");
    try vm.integer_class.module.methods.put(not_equal_sym, value.MethodEntry.builtin(&builtinIntegerNotEqual, .{ .exact = 1 }));

    const less_than_sym = try vm.intern("<");
    try vm.integer_class.module.methods.put(less_than_sym, value.MethodEntry.builtin(&builtinIntegerLessThan, .{ .exact = 1 }));

    const less_than_or_equal_sym = try vm.intern("<=");
    try vm.integer_class.module.methods.put(less_than_or_equal_sym, value.MethodEntry.builtin(&builtinIntegerLessThanOrEqual, .{ .exact = 1 }));

    const greater_than_sym = try vm.intern(">");
    try vm.integer_class.module.methods.put(greater_than_sym, value.MethodEntry.builtin(&builtinIntegerGreaterThan, .{ .exact = 1 }));

    const greater_than_or_equal_sym = try vm.intern(">=");
    try vm.integer_class.module.methods.put(greater_than_or_equal_sym, value.MethodEntry.builtin(&builtinIntegerGreaterThanOrEqual, .{ .exact = 1 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.integer_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinIntegerToS, .{ .variadic = 0 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.integer_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinIntegerToI, .{ .exact = 0 }));

    const coerce_sym = try vm.intern("coerce");
    try vm.integer_class.module.methods.put(coerce_sym, value.MethodEntry.builtin(&builtinIntegerCoerce, .{ .exact = 1 }));

    const to_int_sym = try vm.intern("to_int");
    try vm.integer_class.module.methods.put(to_int_sym, value.MethodEntry.builtin(&builtinIntegerToI, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.integer_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinIntegerToF, .{ .exact = 0 }));

    const ord_sym = try vm.intern("ord");
    try vm.integer_class.module.methods.put(ord_sym, value.MethodEntry.builtin(&builtinIntegerOrd, .{ .exact = 0 }));

    const denominator_sym = try vm.intern("denominator");
    try vm.integer_class.module.methods.put(denominator_sym, value.MethodEntry.builtin(&builtinIntegerDenominator, .{ .exact = 0 }));

    const numerator_sym = try vm.intern("numerator");
    try vm.integer_class.module.methods.put(numerator_sym, value.MethodEntry.builtin(&builtinIntegerNumerator, .{ .exact = 0 }));

    const to_r_sym = try vm.intern("to_r");
    try vm.integer_class.module.methods.put(to_r_sym, value.MethodEntry.builtin(&builtinIntegerToR, .{ .exact = 0 }));

    const rationalize_sym = try vm.intern("rationalize");
    try vm.integer_class.module.methods.put(rationalize_sym, value.MethodEntry.builtin(&builtinIntegerRationalize, .{ .variadic = 0 }));

    const size_sym = try vm.intern("size");
    try vm.integer_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinIntegerSize, .{ .exact = 0 }));

    const truncate_sym = try vm.intern("truncate");
    try vm.integer_class.module.methods.put(truncate_sym, value.MethodEntry.builtin(&builtinIntegerTruncate, .{ .variadic = 0 }));

    const round_sym = try vm.intern("round");
    try vm.integer_class.module.methods.put(round_sym, value.MethodEntry.builtin(&builtinIntegerRound, .{ .variadic = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.integer_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinIntegerInspect, .{ .variadic = 0 }));

    const abs_sym = try vm.intern("abs");
    try vm.integer_class.module.methods.put(abs_sym, value.MethodEntry.builtin(&builtinIntegerAbs, .{ .exact = 0 }));

    const magnitude_sym = try vm.intern("magnitude");
    try vm.integer_class.module.methods.put(magnitude_sym, value.MethodEntry.builtin(&builtinIntegerAbs, .{ .exact = 0 }));

    const negative_sym = try vm.intern("negative?");
    try vm.integer_class.module.methods.put(negative_sym, value.MethodEntry.builtin(&builtinIntegerNegative, .{ .exact = 0 }));

    const zero_sym = try vm.intern("zero?");
    try vm.integer_class.module.methods.put(zero_sym, value.MethodEntry.builtin(&builtinIntegerZero, .{ .exact = 0 }));

    const even_sym = try vm.intern("even?");
    try vm.integer_class.module.methods.put(even_sym, value.MethodEntry.builtin(&builtinIntegerEven, .{ .exact = 0 }));

    const odd_sym = try vm.intern("odd?");
    try vm.integer_class.module.methods.put(odd_sym, value.MethodEntry.builtin(&builtinIntegerOdd, .{ .exact = 0 }));

    const next_sym = try vm.intern("next");
    try vm.integer_class.module.methods.put(next_sym, value.MethodEntry.builtin(&builtinIntegerNext, .{ .exact = 0 }));

    const succ_sym = try vm.intern("succ");
    try vm.integer_class.module.methods.put(succ_sym, value.MethodEntry.builtin(&builtinIntegerNext, .{ .exact = 0 }));

    const pred_sym = try vm.intern("pred");
    try vm.integer_class.module.methods.put(pred_sym, value.MethodEntry.builtin(&builtinIntegerPred, .{ .exact = 0 }));

    const times_sym = try vm.intern("times");
    try vm.integer_class.module.methods.put(times_sym, value.MethodEntry.builtin(&builtinIntegerTimes, .{ .exact = 0 }));

    const upto_sym = try vm.intern("upto");
    try vm.integer_class.module.methods.put(upto_sym, value.MethodEntry.builtin(&builtinIntegerUpto, .{ .exact = 1 }));

    const downto_sym = try vm.intern("downto");
    try vm.integer_class.module.methods.put(downto_sym, value.MethodEntry.builtin(&builtinIntegerDownto, .{ .exact = 1 }));

    const chr_sym = try vm.intern("chr");
    try vm.integer_class.module.methods.put(chr_sym, value.MethodEntry.builtin(&builtinIntegerChr, .{ .variadic = 0 }));

    const gcd_sym = try vm.intern("gcd");
    try vm.integer_class.module.methods.put(gcd_sym, value.MethodEntry.builtin(&builtinIntegerGcd, .{ .exact = 1 }));

    const lcm_sym = try vm.intern("lcm");
    try vm.integer_class.module.methods.put(lcm_sym, value.MethodEntry.builtin(&builtinIntegerLcm, .{ .exact = 1 }));

    const gcdlcm_sym = try vm.intern("gcdlcm");
    try vm.integer_class.module.methods.put(gcdlcm_sym, value.MethodEntry.builtin(&builtinIntegerGcdlcm, .{ .exact = 1 }));

    const digits_sym = try vm.intern("digits");
    try vm.integer_class.module.methods.put(digits_sym, value.MethodEntry.builtin(&builtinIntegerDigits, .{ .variadic = 0 }));

    const div_sym = try vm.intern("div");
    try vm.integer_class.module.methods.put(div_sym, value.MethodEntry.builtin(&builtinIntegerDiv, .{ .exact = 1 }));

    const divmod_sym = try vm.intern("divmod");
    try vm.integer_class.module.methods.put(divmod_sym, value.MethodEntry.builtin(&builtinIntegerDivmod, .{ .exact = 1 }));

    const fdiv_sym = try vm.intern("fdiv");
    try vm.integer_class.module.methods.put(fdiv_sym, value.MethodEntry.builtin(&builtinIntegerFdiv, .{ .exact = 1 }));

    const ceil_sym = try vm.intern("ceil");
    try integer_singleton.module.methods.put(ceil_sym, value.MethodEntry.builtin(&builtinIntegerCeil, .{ .variadic = 0 }));
    try vm.integer_class.module.methods.put(ceil_sym, value.MethodEntry.builtin(&builtinIntegerCeil, .{ .variadic = 0 }));

    const floor_sym = try vm.intern("floor");
    try integer_singleton.module.methods.put(floor_sym, value.MethodEntry.builtin(&builtinIntegerFloor, .{ .variadic = 0 }));
    try vm.integer_class.module.methods.put(floor_sym, value.MethodEntry.builtin(&builtinIntegerFloor, .{ .variadic = 0 }));

    const dup_sym = try vm.intern("dup");
    try vm.integer_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinIntegerDup, .{ .exact = 0 }));
}

pub fn builtinIntegerDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
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

pub fn builtinIntegerCoerce(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isInteger() or arg.isBigInteger()) {
        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    if (arg.isFloat()) {
        const self_float = try vm.newFloat(receiver.integerToF64());
        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, self_float) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    if (arg.isString()) {
        const str_obj = arg.toStringObject();
        const trimmed = std.mem.trim(u8, str_obj.str, " \t\n\r\x0B\x0C");
        const parsed = std.fmt.parseFloat(f64, trimmed) catch 0.0;
        if (parsed == 0.0 and !isZeroString(trimmed)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid value for Integer: \"{s}\"", .{str_obj.str});
        }
        const self_float = try vm.newFloat(receiver.integerToF64());
        const arg_float = try vm.newFloat(parsed);
        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, arg_float) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, self_float) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    if (arg.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "nil can't be coerced to Integer", .{});
    }

    const maybe_to_f = try vm.checkCallMethodByName(arg, "to_f", false, &[_]Value{}, null);
    if (maybe_to_f) |to_f_result| {
        if (to_f_result.isNil()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "nil can't be coerced to Integer", .{});
        }
        if (!to_f_result.isFloat() and !to_f_result.isInteger() and !to_f_result.isBigInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't coerce {s} to Integer", .{vm.className(to_f_result)});
        }
        const self_float = try vm.newFloat(receiver.integerToF64());
        const arg_float = if (to_f_result.isFloat())
            to_f_result
        else
            try vm.newFloat(to_f_result.integerToF64());
        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, arg_float) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, self_float) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "can't coerce {s} to Integer", .{vm.className(arg)});
}

fn isZeroString(s: []const u8) bool {
    if (s.len == 0) return false;
    var offset: usize = 0;
    if (s[0] == '-' or s[0] == '+') {
        offset = 1;
    }
    const trimmed = s[offset..];
    if (std.mem.eql(u8, trimmed, "0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0")) return true;
    if (std.mem.eql(u8, trimmed, "0e0")) return true;
    if (std.mem.eql(u8, trimmed, "0E0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0e0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0E0")) return true;
    if (std.mem.eql(u8, trimmed, "0e-0")) return true;
    if (std.mem.eql(u8, trimmed, "0E-0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0e-0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0E-0")) return true;
    if (std.mem.eql(u8, trimmed, "0e+0")) return true;
    if (std.mem.eql(u8, trimmed, "0E+0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0e+0")) return true;
    if (std.mem.eql(u8, trimmed, "0.0E+0")) return true;
    return false;
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

pub fn builtinIntegerSqrt(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isBigInteger()) {
        const big = arg.toBigIntegerObject().value;
        if (!big.isPositive() and !big.eqlZero()) {
            return vm.raiseExceptionFmt(vm.math_domain_error_class, "Integer.sqrt: domain error", .{});
        }
        var result = BigInt.init(vm.allocator) catch return error.Fatal;
        defer result.deinit();
        BigInt.sqrt(&result, &big) catch |e| switch (e) {
            error.OutOfMemory => return error.Fatal,
            error.SqrtOfNegativeNumber => unreachable,
        };
        return vm.valueFromManagedInteger(&result);
    }

    if (arg.isInteger()) {
        const n = arg.toInteger();
        if (n < 0) {
            return vm.raiseExceptionFmt(vm.math_domain_error_class, "Integer.sqrt: domain error", .{});
        }
        const sqrt_n = std.math.sqrt(@as(f64, @floatFromInt(n)));
        return Value.integer(@as(i64, @intFromFloat(sqrt_n)));
    }

    if (arg.isFloat()) {
        const f = arg.toFloatObject().val;
        if (f < 0) {
            return vm.raiseExceptionFmt(vm.math_domain_error_class, "Integer.sqrt: domain error", .{});
        }
        const n = @as(i64, @intFromFloat(@floor(f)));
        const sqrt_n = std.math.sqrt(@as(f64, @floatFromInt(n)));
        return Value.integer(@as(i64, @intFromFloat(sqrt_n)));
    }

    const maybe_converted = try vm.checkCallMethodByName(arg, "to_int", false, &[_]Value{}, null);
    const converted = maybe_converted orelse {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "no implicit conversion of {s} into Integer",
            .{vm.className(arg)},
        );
    };
    if (converted.isNil()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "no implicit conversion of {s} into Integer",
            .{vm.className(arg)},
        );
    }
    if (converted.isInteger()) {
        const n = converted.toInteger();
        if (n < 0) {
            return vm.raiseExceptionFmt(vm.range_error_class, "Integer.sqrt: domain error", .{});
        }
        const sqrt_n = std.math.sqrt(@as(f64, @floatFromInt(n)));
        return Value.integer(@as(i64, @intFromFloat(sqrt_n)));
    }
    if (converted.isBigInteger()) {
        const big = converted.toBigIntegerObject().value;
        if (!big.isPositive() and !big.eqlZero()) {
            return vm.raiseExceptionFmt(vm.range_error_class, "Integer.sqrt: domain error", .{});
        }
        var result = BigInt.init(vm.allocator) catch return error.Fatal;
        defer result.deinit();
        BigInt.sqrt(&result, &big) catch |e| switch (e) {
            error.OutOfMemory => return error.Fatal,
            error.SqrtOfNegativeNumber => unreachable,
        };
        return vm.valueFromManagedInteger(&result);
    }

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

pub fn builtinIntegerBitAnd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const rhs = args[0];
    if (rhs.isInteger() or rhs.isBigInteger()) {
        return bitAndIntegers(vm, receiver, rhs);
    }
    return coerceAndCallIntegerBitwise(vm, receiver, rhs, "&");
}

pub fn builtinIntegerBitOr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const rhs = args[0];
    if (rhs.isInteger() or rhs.isBigInteger()) {
        return bitOrIntegers(vm, receiver, rhs);
    }
    return coerceAndCallIntegerBitwise(vm, receiver, rhs, "|");
}

pub fn builtinIntegerBitXor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const rhs = args[0];
    if (rhs.isInteger() or rhs.isBigInteger()) {
        return bitXorIntegers(vm, receiver, rhs);
    }
    return coerceAndCallIntegerBitwise(vm, receiver, rhs, "^");
}

pub fn builtinIntegerAllBits(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const arg = try args[0].coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );
    const result = try bitAndIntegers(vm, receiver, arg);
    return Value.boolean(result.eql(arg));
}

pub fn builtinIntegerAnyBits(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const arg = try args[0].coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );
    const result = try bitAndIntegers(vm, receiver, arg);
    return Value.boolean(!result.isInteger() or result.toInteger() != 0);
}

pub fn builtinIntegerNoBits(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const arg = try args[0].coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );
    const result = try bitAndIntegers(vm, receiver, arg);
    return Value.boolean(result.isInteger() and result.toInteger() == 0);
}

pub fn builtinIntegerBitNot(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return bitNotInteger(vm, receiver);
}

pub fn builtinIntegerBitLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);

    if (receiver.isInteger()) {
        const val = receiver.toInteger();
        if (val == 0) return Value.integer(0);
        const abs_val: u64 = if (val < 0) @intCast(-(val + 1)) else @intCast(val);
        return Value.integer(@intCast(@bitSizeOf(u64) - @clz(abs_val)));
    }

    var managed = try receiver.integerToManaged(vm);
    defer managed.deinit();

    if (managed.isPositive() and managed.eqlZero()) {
        return Value.integer(0);
    }

    if (!managed.isPositive()) {
        managed.negate();
        var one = BigInt.init(vm.allocator) catch return error.Fatal;
        defer one.deinit();
        one.set(1) catch return error.Fatal;
        var out = BigInt.init(vm.allocator) catch return error.Fatal;
        defer out.deinit();
        out.sub(&managed, &one) catch return error.Fatal;
        return Value.integer(@intCast(out.bitCountAbs()));
    }

    return Value.integer(@intCast(managed.bitCountAbs()));
}

pub fn builtinIntegerMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger() and !args[0].isFloat()) {
        return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "-");
    }
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try subIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() - f),
    };
}

pub fn builtinIntegerUnaryMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return negateInteger(vm, receiver);
}

pub fn builtinIntegerMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger() and !args[0].isFloat()) {
        return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "*");
    }
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try mulIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() * f),
    };
}

pub fn builtinIntegerLeftShift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    return switch (try coerceShiftCount(vm, args[0])) {
        .finite => |shift_count| {
            if (shift_count == 0) return receiver;
            if (shift_count > 0) {
                if (shiftWidthTooBig(@intCast(shift_count)) and !integerIsZero(receiver)) {
                    return raiseShiftWidthTooBig(vm);
                }
                return shiftLeftInteger(vm, receiver, @intCast(shift_count));
            }
            if (shift_count == std.math.minInt(i64)) return shiftRightConvergedValue(receiver);
            return shiftRightInteger(vm, receiver, @intCast(-shift_count));
        },
        .positive_overflow => {
            if (integerIsZero(receiver)) return receiver;
            return raiseShiftWidthTooBig(vm);
        },
        .negative_overflow => return shiftRightConvergedValue(receiver),
    };
}

pub fn builtinIntegerRightShift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    return switch (try coerceShiftCount(vm, args[0])) {
        .finite => |shift_count| {
            if (shift_count == 0) return receiver;
            if (shift_count > 0) return shiftRightInteger(vm, receiver, @intCast(shift_count));
            if (shift_count == std.math.minInt(i64)) {
                if (integerIsZero(receiver)) return receiver;
                return raiseShiftWidthTooBig(vm);
            }
            if (shiftWidthTooBig(@intCast(-shift_count)) and !integerIsZero(receiver)) {
                return raiseShiftWidthTooBig(vm);
            }
            return shiftLeftInteger(vm, receiver, @intCast(-shift_count));
        },
        .positive_overflow => return shiftRightConvergedValue(receiver),
        .negative_overflow => {
            if (integerIsZero(receiver)) return receiver;
            return raiseShiftWidthTooBig(vm);
        },
    };
}

pub fn builtinIntegerDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger() and !args[0].isFloat() and !args[0].isRational()) {
        return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "/");
    }
    if (args[0].isRational()) {
        const rhs_rational = args[0].toRationalObject();
        const rhs_num = rhs_rational.numerator;
        if ((try vm.compareIntegerValues(rhs_num, Value.integer(0))) == .eq) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const numerator = try vm.mulIntegerValues(receiver, rhs_rational.denominator);
        return vm.newRationalValues(numerator, rhs_num);
    }
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

pub fn builtinIntegerDivmod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const arg = args[0];

    if (arg.isInteger() or arg.isBigInteger()) {
        const divisor_is_zero = if (arg.isInteger())
            arg.toInteger() == 0
        else if (arg.isBigInteger())
            arg.toBigIntegerObject().value.eqlZero()
        else
            unreachable;
        if (divisor_is_zero) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }

        const quot = try divFloorIntegers(vm, receiver, arg);
        const rem = try modIntegers(vm, receiver, arg);

        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, quot) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, rem) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    if (arg.isFloat()) {
        const arg_f = arg.toFloatObject().val;
        if (arg_f == 0.0) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        if (std.math.isNan(arg_f)) {
            return vm.raiseExceptionFmt(vm.float_domain_error_class, "Computation results to 'NaN'(Not a Number)", .{});
        }

        const receiver_f = receiver.integerToF64();
        const f = @floor(receiver_f / arg_f);
        const mod = receiver_f - f * arg_f;

        const i64_max_f = @as(f64, @floatFromInt(std.math.maxInt(i64)));
        const i64_min_f = @as(f64, @floatFromInt(std.math.minInt(i64)));

        const quot = if (f >= i64_min_f and f < i64_max_f) blk: {
            const i = @as(i64, @intFromFloat(f));
            if (i >= -4611686018427387904 and i <= 4611686018427387903) {
                break :blk Value.integer(i);
            }
            var managed = BigInt.init(vm.allocator) catch return error.Fatal;
            defer managed.deinit();
            managed.set(i) catch return error.Fatal;
            break :blk try vm.valueFromManagedInteger(&managed);
        } else blk: {
            var managed = BigInt.init(vm.allocator) catch return error.Fatal;
            defer managed.deinit();
            managed.set(@as(i64, @intFromFloat(f))) catch return error.Fatal;
            break :blk try vm.valueFromManagedInteger(&managed);
        };

        const result = try vm.createArray();
        result.elements.append(vm.gc_allocator, quot) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, try vm.newFloat(mod)) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
}

fn getIntegerAbsManaged(vm: *VM, val: Value) !BigInt {
    var result = BigInt.init(vm.allocator) catch return error.Fatal;
    if (val.isInteger()) {
        const i = val.toInteger();
        result.set(@as(u64, @intCast(if (i < 0) -i else i))) catch return error.Fatal;
    } else if (val.isBigInteger()) {
        result.copy(val.toBigIntegerObject().value.toConst()) catch return error.Fatal;
        if (!result.isPositive()) result.negate();
    } else {
        unreachable;
    }
    return result;
}

fn fdivBigInts(vm: *VM, a: Value, b: Value) !f64 {
    const a_neg = integerIsNegative(a);
    const b_neg = integerIsNegative(b);
    const sign: f64 = if (a_neg != b_neg) -1.0 else 1.0;

    var a_abs = try getIntegerAbsManaged(vm, a);
    defer a_abs.deinit();
    var b_abs = try getIntegerAbsManaged(vm, b);
    defer b_abs.deinit();

    const bits_a = a_abs.bitCountAbs();
    const bits_b = b_abs.bitCountAbs();

    const mantissa_bits: u64 = 53;
    const scale_a: u64 = if (bits_a > mantissa_bits) bits_a - mantissa_bits else 0;
    const scale_b: u64 = if (bits_b > mantissa_bits) bits_b - mantissa_bits else 0;

    if (scale_a > 0) a_abs.shiftRight(&a_abs, scale_a) catch return error.Fatal;
    if (scale_b > 0) b_abs.shiftRight(&b_abs, scale_b) catch return error.Fatal;

    const a_f = a_abs.toFloat(f64, .nearest_even)[0];
    const b_f = b_abs.toFloat(f64, .nearest_even)[0];

    var result = a_f / b_f;
    const exp_diff: i64 = @as(i64, @intCast(scale_a)) - @as(i64, @intCast(scale_b));
    if (exp_diff > 0) {
        result *= std.math.exp2(@as(f64, @floatFromInt(exp_diff)));
    } else if (exp_diff < 0) {
        result /= std.math.exp2(@as(f64, @floatFromInt(-exp_diff)));
    }

    return sign * result;
}

pub fn builtinIntegerFdiv(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (args[0].isRational()) {
        const rhs_rational = args[0].toRationalObject();
        const rhs_num_f = rhs_rational.numerator.integerToF64();
        const rhs_den_f = rhs_rational.denominator.integerToF64();
        return try vm.newFloat(receiver.integerToF64() * rhs_den_f / rhs_num_f);
    }
    if (args[0].isFloat()) {
        return try vm.newFloat(receiver.integerToF64() / args[0].toFloatObject().val);
    }
    if (args[0].isInteger() or args[0].isBigInteger()) {
        const lhs_f = receiver.integerToF64();
        const rhs_f = args[0].integerToF64();
        if (std.math.isFinite(lhs_f) and std.math.isFinite(rhs_f)) {
            return try vm.newFloat(lhs_f / rhs_f);
        }
        const result = try fdivBigInts(vm, receiver, args[0]);
        return try vm.newFloat(result);
    }
    return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "fdiv");
}

pub fn builtinIntegerModulo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger() and !args[0].isFloat()) {
        return coerceAndCallIntegerArithmetic(vm, receiver, args[0], "%");
    }
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
            break :blk modIntegers(vm, receiver, divisor);
        },
        .float => |divisor| {
            if (divisor == 0.0) {
                return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
            }
            const a = receiver.integerToF64();
            // Use @rem (truncated remainder, like C fmod) then adjust sign
            // to match Ruby's floored modulo semantics.
            var result = @rem(a, divisor);
            if (result != 0.0 and (result < 0.0) != (divisor < 0.0)) result += divisor;
            return try vm.newFloat(result);
        },
    };
}

pub fn builtinIntegerCeildiv(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (args[0].isRational()) {
        const rhs_rational = args[0].toRationalObject();
        const rhs_num = rhs_rational.numerator;
        if ((try vm.compareIntegerValues(rhs_num, Value.integer(0))) == .eq) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const numerator = try vm.mulIntegerValues(receiver, rhs_rational.denominator);
        var num_managed = try numerator.integerToManaged(vm);
        defer num_managed.deinit();
        var rhs_managed = try rhs_num.integerToManaged(vm);
        defer rhs_managed.deinit();
        const num_f = num_managed.toFloat(f64, .nearest_even)[0];
        const rhs_f = rhs_managed.toFloat(f64, .nearest_even)[0];
        const result = std.math.ceil(num_f / rhs_f);
        const rounded = @round(result);
        if (rounded == result) {
            return Value.integer(@intFromFloat(rounded));
        }
        return vm.newFloat(result);
    }
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
            break :blk try divCeilIntegers(vm, receiver, divisor);
        },
        .float => |divisor| {
            const lhs_f = receiver.integerToF64();
            const result = std.math.ceil(lhs_f / divisor);
            const rounded = @round(result);
            if (rounded == result) {
                return Value.integer(@intFromFloat(rounded));
            }
            return vm.newFloat(result);
        },
    };
}

pub fn builtinIntegerCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = args[0];

    if (rhs.isFloat()) {
        const rhs_f = rhs.toFloatObject().val;
        if (std.math.isNan(rhs_f)) return Value.nil();
        if (std.math.isInf(rhs_f)) {
            return if (rhs_f > 0) Value.integer(-1) else Value.integer(1);
        }
        const lhs_f = receiver.integerToF64();
        if (std.math.isInf(lhs_f)) {
            return if (lhs_f > 0) Value.integer(1) else Value.integer(-1);
        }
        if (lhs_f < rhs_f) return Value.integer(-1);
        if (lhs_f > rhs_f) return Value.integer(1);
        return Value.integer(0);
    }

    if (rhs.isInteger() or rhs.isBigInteger()) {
        const order = try compareIntegers(vm, receiver, rhs);
        return switch (order) {
            .lt => Value.integer(-1),
            .eq => Value.integer(0),
            .gt => Value.integer(1),
        };
    }

    return try integerCoerceCompare(vm, receiver, rhs);
}

fn integerCoerceCompare(vm: *VM, lhs: Value, rhs: Value) VMError!Value {
    var coerce_args = [_]Value{lhs};
    const coerce_result = try vm.checkCallMethodByName(rhs, "coerce", false, &coerce_args, null) orelse return Value.nil();
    if (!coerce_result.isArray()) return Value.nil();
    const arr = coerce_result.toArrayObject();
    if (arr.elements.items.len != 2) return Value.nil();
    var cmp_args = [_]Value{arr.elements.items[1]};
    return try vm.callMethodByName(arr.elements.items[0], "<=>", &cmp_args, null);
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

        if (!overflowed and std.math.cast(i63, result) != null) {
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

pub fn builtinIntegerPow(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try receiver.ensureInteger(vm);
    if (args.len == 2) {
        if (!args[1].isInteger() and !args[1].isBigInteger()) {
            if (args[1].isNumeric()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "2nd argument not allowed unless all arguments are integers", .{});
            }
            return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
        }
        const modulus = args[1];
        if (!args[0].isInteger() and !args[0].isBigInteger()) {
            if (args[0].isNumeric()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "2nd argument not allowed unless all arguments are integers", .{});
            }
            return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
        }
        if (modulus.isInteger() and modulus.toInteger() == 0) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        if (modulus.isBigInteger() and modulus.toBigIntegerObject().value.eqlZero()) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const exp = args[0];
        if (exp.isInteger() and exp.toInteger() < 0) {
            return vm.raiseExceptionFmt(vm.range_error_class, "pow() 2nd argument not allowed unless all arguments are integers", .{});
        }
        if (exp.isBigInteger() and !exp.toBigIntegerObject().value.isPositive()) {
            return vm.raiseExceptionFmt(vm.range_error_class, "pow() 2nd argument not allowed unless all arguments are integers", .{});
        }

        var base_val = try receiver.integerToManaged(vm);
        defer base_val.deinit();
        var mod_val = try modulus.integerToManaged(vm);
        defer mod_val.deinit();

        var abs_mod = BigInt.init(vm.allocator) catch return error.Fatal;
        defer abs_mod.deinit();
        abs_mod.copy(mod_val.toConst()) catch return error.Fatal;
        abs_mod.setSign(true);

        var result = BigInt.init(vm.allocator) catch return error.Fatal;
        defer result.deinit();
        result.set(1) catch return error.Fatal;

        var base = BigInt.init(vm.allocator) catch return error.Fatal;
        defer base.deinit();
        var tmp = BigInt.init(vm.allocator) catch return error.Fatal;
        defer tmp.deinit();
        var rem = BigInt.init(vm.allocator) catch return error.Fatal;
        defer rem.deinit();

        base.divFloor(&rem, &base_val, &abs_mod) catch return error.Fatal;
        base.copy(rem.toConst()) catch return error.Fatal;

        var exp_copy = try args[0].integerToManaged(vm);
        defer exp_copy.deinit();

        while (!exp_copy.eqlZero()) {
            if (exp_copy.isOdd()) {
                tmp.mul(&result, &base) catch return error.Fatal;
                result.divFloor(&rem, &tmp, &abs_mod) catch return error.Fatal;
                result.copy(rem.toConst()) catch return error.Fatal;
            }
            exp_copy.shiftRight(&exp_copy, 1) catch return error.Fatal;
            if (!exp_copy.eqlZero()) {
                tmp.mul(&base, &base) catch return error.Fatal;
                base.divFloor(&rem, &tmp, &abs_mod) catch return error.Fatal;
                base.copy(rem.toConst()) catch return error.Fatal;
            }
        }

        const mod_is_neg = if (modulus.isInteger()) modulus.toInteger() < 0 else !modulus.toBigIntegerObject().value.isPositive() and !modulus.toBigIntegerObject().value.eqlZero();
        if (mod_is_neg and !result.eqlZero()) {
            result.add(&result, &mod_val) catch return error.Fatal;
        }
        if (result.eqlZero()) {
            result.setSign(true);
        }

        return vm.valueFromManagedInteger(&result);
    }
    return try vm.callMethodByName(receiver, "**", args[0..1], null);
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
    return Value.boolean(result.isTruthy());
}

pub fn builtinIntegerEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger()) return Value.boolean(false);
    return Value.boolean((try compareIntegers(vm, receiver, args[0])) == .eq);
}

pub fn builtinIntegerElementReference(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try receiver.ensureInteger(vm);
    if (args.len != 1) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given {d}, expected 1)", .{args.len});
    }

    const bit = try args[0].coerceToIntegerValue(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
    );

    const b = if (bit.isInteger()) bit.toInteger() else blk: {
        const big = bit.toBigIntegerObject().value;
        if (!big.isPositive() and !big.eqlZero()) return Value.integer(0);
        break :blk @as(i64, std.math.maxInt(i64));
    };
    if (b < 0) return Value.integer(0);

    if (receiver.isInteger()) {
        const val = receiver.toInteger();
        if (b >= 63) return Value.integer(if (val < 0) @as(i64, 1) else 0);
        const shift: u6 = @intCast(b);
        return Value.integer((val >> shift) & 1);
    }

    if (receiver.isBigInteger()) {
        var managed = try receiver.integerToManaged(vm);
        defer managed.deinit();

        const abs_bits = managed.bitCountAbs();
        const is_neg = !managed.isPositive() and !managed.eqlZero();
        const ub = @as(u64, @intCast(@as(u63, @intCast(b))));

        if (ub >= abs_bits) return Value.integer(if (is_neg) @as(i64, 1) else 0);

        var shifted = BigInt.init(vm.allocator) catch return error.Fatal;
        defer shifted.deinit();
        shifted.shiftRight(&managed, ub) catch return error.Fatal;

        var two = BigInt.init(vm.allocator) catch return error.Fatal;
        defer two.deinit();
        two.set(2) catch return error.Fatal;

        if (!is_neg) {
            var dummy = BigInt.init(vm.allocator) catch return error.Fatal;
            defer dummy.deinit();
            var rem = BigInt.init(vm.allocator) catch return error.Fatal;
            defer rem.deinit();
            dummy.divTrunc(&rem, &shifted, &two) catch return error.Fatal;
            return Value.integer(if (rem.eqlZero()) @as(i64, 0) else 1);
        } else {
            managed.abs();
            var one = BigInt.init(vm.allocator) catch return error.Fatal;
            defer one.deinit();
            one.set(1) catch return error.Fatal;
            var sub_one = BigInt.init(vm.allocator) catch return error.Fatal;
            defer sub_one.deinit();
            sub_one.sub(&managed, &one) catch return error.Fatal;
            var shifted2 = BigInt.init(vm.allocator) catch return error.Fatal;
            defer shifted2.deinit();
            shifted2.shiftRight(&sub_one, ub) catch return error.Fatal;
            var dummy2 = BigInt.init(vm.allocator) catch return error.Fatal;
            defer dummy2.deinit();
            var rem2 = BigInt.init(vm.allocator) catch return error.Fatal;
            defer rem2.deinit();
            dummy2.divTrunc(&rem2, &shifted2, &two) catch return error.Fatal;
            return Value.integer(if (rem2.eqlZero()) @as(i64, 1) else 0);
        }
    }

    unreachable;
}

pub fn builtinIntegerNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const equal = try builtinIntegerEqual(vm, receiver, args, null);
    return Value.boolean(equal.isFalsey());
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

pub fn builtinIntegerNumerator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return receiver;
}

pub fn builtinIntegerToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    return try vm.newRationalValues(receiver, Value.integer(1));
}

pub fn builtinIntegerRationalize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);
    return try vm.newRationalValues(receiver, Value.integer(1));
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

pub fn builtinIntegerFloor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (args.len == 0) return receiver;

    const ndigits = try args[0].integerArgToI64(vm, "argument is not an Integer", "ndigits is too large");
    if (ndigits >= 0) return receiver;

    const factor = try integerDecimalFactor(vm, @intCast(-ndigits));

    const quotient = try divFloorIntegers(vm, receiver, factor);
    return mulIntegers(vm, quotient, factor);
}

pub fn builtinIntegerTruncate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (args.len == 0) return receiver;

    const ndigits = try args[0].integerArgToI64(vm, "argument is not an Integer", "ndigits is too large");
    if (ndigits >= 0) return receiver;

    const factor = try integerDecimalFactor(vm, @intCast(-ndigits));

    const quotient = try divTruncIntegers(vm, receiver, factor);
    return mulIntegers(vm, quotient, factor);
}

pub fn builtinIntegerRound(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (args.len == 0) return receiver;

    const half_sym = try vm.consumeKeywordArg("half");
    try vm.validateKeywordArgsConsumed();

    const half_mode = if (half_sym) |half_val| blk: {
        if (half_val.isNil()) break :blk @as([]const u8, "up");
        if (!half_val.isSymbol()) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid rounding mode: {s}", .{vm.className(half_val)});
        }
        const name = half_val.toSymbolObject().name;
        if (!std.mem.eql(u8, name, "up") and
            !std.mem.eql(u8, name, "down") and
            !std.mem.eql(u8, name, "even"))
        {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid rounding mode: {s}", .{name});
        }
        break :blk name;
    } else @as([]const u8, "up");

    const ndigits_val = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "no implicit conversion into Integer");
    const ndigits = try ndigits_val.integerToI64(vm, "ndigits is too large");

    if (ndigits > std.math.maxInt(i32) or ndigits < std.math.minInt(i32)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "ndigits is too large", .{});
    }

    if (ndigits >= 0) return receiver;

    const abs_ndigits: u64 = @intCast(-ndigits);
    const factor = try integerDecimalFactor(vm, abs_ndigits);
    const half_factor = try divTruncIntegers(vm, factor, Value.integer(2));

    const quotient = try divTruncIntegers(vm, receiver, factor);
    const product = try mulIntegers(vm, quotient, factor);
    const remainder = try subIntegers(vm, receiver, product);

    if ((try builtinIntegerZero(vm, remainder, &.{}, null)).isTruthy()) return receiver;

    const abs_remainder = try builtinIntegerAbs(vm, remainder, &.{}, null);
    const cmp = try compareIntegers(vm, abs_remainder, half_factor);

    if (cmp == .lt) return mulIntegers(vm, quotient, factor);

    if (cmp == .gt) {
        if (integerIsNegative(remainder)) {
            return mulIntegers(vm, try subIntegers(vm, quotient, Value.integer(1)), factor);
        }
        return mulIntegers(vm, try addIntegers(vm, quotient, Value.integer(1)), factor);
    }

    if (std.mem.eql(u8, half_mode, "down")) return mulIntegers(vm, quotient, factor);

    if (std.mem.eql(u8, half_mode, "even") and (try builtinIntegerEven(vm, quotient, &.{}, null)).isTruthy()) {
        return mulIntegers(vm, quotient, factor);
    }

    if (integerIsNegative(remainder)) {
        return mulIntegers(vm, try subIntegers(vm, quotient, Value.integer(1)), factor);
    }
    return mulIntegers(vm, try addIntegers(vm, quotient, Value.integer(1)), factor);
}

pub fn builtinIntegerCeil(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (args.len == 0) return receiver;

    const ndigits = try args[0].integerArgToI64(vm, "argument is not an Integer", "ndigits is too large");
    if (ndigits >= 0) return receiver;

    const factor = try integerDecimalFactor(vm, @intCast(-ndigits));

    const remainder = try modIntegers(vm, receiver, factor);
    if (integerIsZero(remainder)) return receiver;

    const floored = if (receiver.isInteger() and factor.isInteger())
        Value.integer(@divFloor(receiver.toInteger(), factor.toInteger()))
    else
        try divFloorIntegers(vm, receiver, factor);

    if (integerIsZero(floored) and integerIsNegative(receiver)) return Value.integer(0);

    const incremented = try addIntegers(vm, floored, Value.integer(1));
    return mulIntegers(vm, incremented, factor);
}

pub fn builtinIntegerDiv(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = args[0];

    if (!rhs.isInteger() and !rhs.isBigInteger() and !rhs.isFloat() and !rhs.isRational()) {
        var coerce_args = [_]Value{receiver};
        const maybe_coerced = try vm.checkCallMethodByName(rhs, "coerce", false, coerce_args[0..], null);
        if (maybe_coerced) |coerced| {
            if (coerced.isArray()) {
                const items = coerced.toArrayObject().elements.items;
                if (items.len == 2) {
                    var div_args = [_]Value{items[1]};
                    return vm.callMethodByName(items[0], "div", div_args[0..], null);
                }
            }
        }
        return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
    }

    if (rhs.isFloat() and rhs.toFloatObject().val == 0.0) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }
    if ((rhs.isInteger() or rhs.isBigInteger()) and (try vm.compareIntegerValues(rhs, Value.integer(0))) == .eq) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }

    if (rhs.isRational()) {
        const rhs_rational = rhs.toRationalObject();
        const numerator = try vm.mulIntegerValues(receiver, rhs_rational.denominator);
        var divide_args = [_]Value{rhs_rational.numerator};
        return builtinIntegerDivide(vm, numerator, divide_args[0..], null);
    }

    const divided = try builtinIntegerDivide(vm, receiver, args, null);
    return vm.callMethodByName(divided, "floor", &.{}, null);
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
        _ = try vm.yieldToBlock(blk, &yield_args);
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
    while (i <= stop) {
        const yield_args = [_]Value{Value.integer(i)};
        _ = try vm.yieldToBlock(blk, &yield_args);
        if (i == stop) break;
        i += 1;
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
    while (i >= stop) {
        const yield_args = [_]Value{Value.integer(i)};
        _ = try vm.yieldToBlock(blk, &yield_args);
        if (i == stop) break;
        i -= 1;
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

pub fn builtinIntegerRemainder(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);

    const rhs = args[0];

    if (!rhs.isInteger() and !rhs.isBigInteger() and !rhs.isFloat() and !rhs.isRational()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "argument is not numeric", .{});
    }

    if (rhs.isRational()) {
        const rat = rhs.toRationalObject();
        if ((try vm.compareIntegerValues(rat.numerator, Value.integer(0))) == .eq) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const product = try vm.mulIntegerValues(receiver, rat.denominator);
        const rem = if (product.isInteger() and rat.numerator.isInteger()) blk: {
            break :blk Value.integer(@rem(product.toInteger(), rat.numerator.toInteger()));
        } else blk: {
            var a = try product.integerToManaged(vm);
            defer a.deinit();
            var b = try rat.numerator.integerToManaged(vm);
            defer b.deinit();
            var quot = BigInt.init(vm.allocator) catch return error.Fatal;
            defer quot.deinit();
            var rem_val = BigInt.init(vm.allocator) catch return error.Fatal;
            defer rem_val.deinit();
            quot.divTrunc(&rem_val, &a, &b) catch return error.Fatal;
            break :blk try vm.valueFromManagedInteger(&rem_val);
        };
        return try vm.newRationalValues(rem, rat.denominator);
    }

    if (rhs.isFloat()) {
        const divisor = rhs.toFloatObject().val;
        if (divisor == 0.0) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const lhs_f = receiver.integerToF64();
        return try vm.newFloat(@rem(lhs_f, divisor));
    }

    if ((try vm.compareIntegerValues(rhs, Value.integer(0))) == .eq) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }

    if (receiver.isInteger() and rhs.isInteger()) {
        return Value.integer(@rem(receiver.toInteger(), rhs.toInteger()));
    }

    var a = try receiver.integerToManaged(vm);
    defer a.deinit();
    var b = try rhs.integerToManaged(vm);
    defer b.deinit();
    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();
    quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
    return try vm.valueFromManagedInteger(&rem);
}

pub fn builtinIntegerGcd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "not an integer", .{});
    }
    if (receiver.isInteger() and args[0].isInteger()) {
        var a = receiver.toInteger();
        var b = args[0].toInteger();
        if (a < 0) a = -a;
        if (b < 0) b = -b;
        while (b != 0) {
            const temp = b;
            b = @mod(a, b);
            a = temp;
        }
        return if (std.math.cast(i63, a) != null)
            Value.integer(a)
        else
            try vm.newBigIntegerFromI64(a);
    }
    var a = try receiver.integerToManaged(vm);
    defer a.deinit();
    if (!a.isPositive()) a.negate();
    var b = try args[0].integerToManaged(vm);
    defer b.deinit();
    if (!b.isPositive()) b.negate();
    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();
    while (!b.eqlZero()) {
        quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
        a.swap(&b);
        b.swap(&rem);
    }
    return vm.valueFromManagedInteger(&a);
}

pub fn builtinIntegerLcm(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    if (!args[0].isInteger() and !args[0].isBigInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "not an integer", .{});
    }
    if (receiver.isInteger() and args[0].isInteger()) {
        var a = receiver.toInteger();
        var b = args[0].toInteger();
        if (a < 0) a = -a;
        if (b < 0) b = -b;
        if (a == 0 or b == 0) return Value.integer(0);
        var gcd_val = a;
        var rem = b;
        while (rem != 0) {
            const temp = rem;
            rem = @mod(gcd_val, rem);
            gcd_val = temp;
        }
        const a_div_gcd = @divTrunc(a, gcd_val);
        if (std.math.mul(i63, @as(i63, @intCast(a_div_gcd)), @as(i63, @intCast(b)))) |prod| {
            return Value.integer(@as(i64, prod));
        } else |_| {}
    }
    var a = try receiver.integerToManaged(vm);
    defer a.deinit();
    if (!a.isPositive()) a.negate();
    var b = try args[0].integerToManaged(vm);
    defer b.deinit();
    if (!b.isPositive()) b.negate();
    if (a.eqlZero() or b.eqlZero()) return Value.integer(0);
    var a_saved = try receiver.integerToManaged(vm);
    defer a_saved.deinit();
    if (!a_saved.isPositive()) a_saved.negate();
    var b_saved = try args[0].integerToManaged(vm);
    defer b_saved.deinit();
    if (!b_saved.isPositive()) b_saved.negate();
    var quot = BigInt.init(vm.allocator) catch return error.Fatal;
    defer quot.deinit();
    var rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer rem.deinit();
    while (!b.eqlZero()) {
        quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
        a.swap(&b);
        b.swap(&rem);
    }
    var r_rem = BigInt.init(vm.allocator) catch return error.Fatal;
    defer r_rem.deinit();
    quot.divTrunc(&r_rem, &a_saved, &a) catch return error.Fatal;
    var result = BigInt.init(vm.allocator) catch return error.Fatal;
    defer result.deinit();
    result.mul(&quot, &b_saved) catch return error.Fatal;
    return vm.valueFromManagedInteger(&result);
}

pub fn builtinIntegerGcdlcm(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const gcd = try builtinIntegerGcd(vm, receiver, args, null);
    const lcm = try builtinIntegerLcm(vm, receiver, args, null);
    const arr = try vm.createArray();
    arr.elements.append(vm.gc_allocator, gcd) catch return error.Fatal;
    arr.elements.append(vm.gc_allocator, lcm) catch return error.Fatal;
    return Value.fromObject(&arr.object);
}

pub fn builtinIntegerDigits(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    if (integerIsNegative(receiver)) {
        return vm.raiseExceptionFmt(vm.math_domain_error_class, "out of domain", .{});
    }

    var base: u64 = 10;
    if (args.len == 1) {
        const base_val = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "can't convert to Integer",
            "base is too large",
        );
        if (base_val < 2) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "radix must be >= 2", .{});
        }
        base = @intCast(base_val);
    }

    if (base <= 36 and receiver.isInteger()) {
        return builtinIntegerDigitsGeneric(vm, receiver, @intCast(base));
    }

    return builtinIntegerDigitsBignum(vm, receiver, base);
}

fn builtinIntegerDigitsGeneric(vm: *VM, receiver: Value, base: u8) VMError!Value {
    const arr = try vm.createArray();

    if (receiver.isInteger() and receiver.toInteger() == 0) {
        arr.elements.append(vm.gc_allocator, Value.integer(0)) catch return error.Fatal;
        return Value.fromObject(&arr.object);
    }

    if (receiver.isInteger()) {
        var n = @as(u64, @bitCast(receiver.toInteger()));
        while (n > 0) {
            const digit = @as(u8, @intCast(n % base));
            arr.elements.append(vm.gc_allocator, Value.integer(digit)) catch return error.Fatal;
            n /= base;
        }
        return Value.fromObject(&arr.object);
    }

    var n = try receiver.integerToManaged(vm);
    defer n.deinit();

    var base_big = BigInt.init(vm.allocator) catch return error.Fatal;
    defer base_big.deinit();
    base_big.set(@as(u64, @intCast(base))) catch return error.Fatal;

    while (!n.eqlZero()) {
        var rem = BigInt.init(vm.allocator) catch return error.Fatal;
        defer rem.deinit();
        var quot = BigInt.init(vm.allocator) catch return error.Fatal;
        defer quot.deinit();

        quot.divTrunc(&rem, &n, &base_big) catch return error.Fatal;

        const digit_val = @as(i64, @intCast(rem.toInt(u64) catch @panic("digit overflow")));
        arr.elements.append(vm.gc_allocator, Value.integer(digit_val)) catch return error.Fatal;
        n.swap(&quot);
    }

    return Value.fromObject(&arr.object);
}

fn builtinIntegerDigitsBignum(vm: *VM, receiver: Value, base: u64) VMError!Value {
    const arr = try vm.createArray();

    if (receiver.isInteger() and receiver.toInteger() == 0) {
        arr.elements.append(vm.gc_allocator, Value.integer(0)) catch return error.Fatal;
        return Value.fromObject(&arr.object);
    }

    const allocator = vm.allocator;
    var n = try receiver.integerToManaged(vm);
    defer n.deinit();

    var base_big = BigInt.init(allocator) catch return error.Fatal;
    defer base_big.deinit();
    base_big.set(@as(u64, @intCast(base))) catch return error.Fatal;

    while (!n.eqlZero()) {
        var rem = BigInt.init(allocator) catch return error.Fatal;
        defer rem.deinit();
        var quot = BigInt.init(allocator) catch return error.Fatal;
        defer quot.deinit();

        quot.divTrunc(&rem, &n, &base_big) catch return error.Fatal;
        const digit_val = @as(i64, @intCast(rem.toInt(u64) catch @panic("digit overflow")));
        arr.elements.append(vm.gc_allocator, Value.integer(digit_val)) catch return error.Fatal;
        n.swap(&quot);
    }

    return Value.fromObject(&arr.object);
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
