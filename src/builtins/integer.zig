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

pub fn register(vm: *VM) !void {
    const plus_sym = try vm.intern("+");
    try vm.integer_class.module.methods.put(plus_sym, .{ .method = .{ .builtin = &builtinIntegerPlus } });

    const minus_sym = try vm.intern("-");
    try vm.integer_class.module.methods.put(minus_sym, .{ .method = .{ .builtin = &builtinIntegerMinus } });

    const multiply_sym = try vm.intern("*");
    try vm.integer_class.module.methods.put(multiply_sym, .{ .method = .{ .builtin = &builtinIntegerMultiply } });

    const divide_sym = try vm.intern("/");
    try vm.integer_class.module.methods.put(divide_sym, .{ .method = .{ .builtin = &builtinIntegerDivide } });

    const modulo_sym = try vm.intern("%");
    try vm.integer_class.module.methods.put(modulo_sym, .{ .method = .{ .builtin = &builtinIntegerModulo } });

    const power_sym = try vm.intern("**");
    try vm.integer_class.module.methods.put(power_sym, .{ .method = .{ .builtin = &builtinIntegerPower } });

    const equal_sym = try vm.intern("==");
    try vm.integer_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinIntegerEqual } });

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

    const inspect_sym = try vm.intern("inspect");
    try vm.integer_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinIntegerInspect } });

    const abs_sym = try vm.intern("abs");
    try vm.integer_class.module.methods.put(abs_sym, .{ .method = .{ .builtin = &builtinIntegerAbs } });

    const negative_sym = try vm.intern("negative?");
    try vm.integer_class.module.methods.put(negative_sym, .{ .method = .{ .builtin = &builtinIntegerNegative } });

    const zero_sym = try vm.intern("zero?");
    try vm.integer_class.module.methods.put(zero_sym, .{ .method = .{ .builtin = &builtinIntegerZero } });

    const times_sym = try vm.intern("times");
    try vm.integer_class.module.methods.put(times_sym, .{ .method = .{ .builtin = &builtinIntegerTimes } });

    const upto_sym = try vm.intern("upto");
    try vm.integer_class.module.methods.put(upto_sym, .{ .method = .{ .builtin = &builtinIntegerUpto } });

    const chr_sym = try vm.intern("chr");
    try vm.integer_class.module.methods.put(chr_sym, .{ .method = .{ .builtin = &builtinIntegerChr } });
}

pub fn builtinIntegerPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try addIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() + f),
    };
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

pub fn builtinIntegerMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| try mulIntegers(vm, receiver, i),
        .float => |f| try vm.newFloat(receiver.integerToF64() * f),
    };
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

    const rhs = coerceNumericArg(vm, args[0]) catch return Value.boolean(false);
    return switch (rhs) {
        .float => |f| Value.boolean(receiver.integerToF64() == f),
        .integer => |i| Value.boolean((try compareIntegers(vm, receiver, i)) == .eq),
    };
}

pub fn builtinIntegerNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const equal = try builtinIntegerEqual(vm, receiver, args, null);
    return Value.boolean(!equal.is_truthy());
}

pub fn builtinIntegerLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| Value.boolean((try compareIntegers(vm, receiver, i)) == .lt),
        .float => |f| Value.boolean(receiver.integerToF64() < f),
    };
}

pub fn builtinIntegerLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| {
            const ord = try compareIntegers(vm, receiver, i);
            return Value.boolean(ord == .lt or ord == .eq);
        },
        .float => |f| Value.boolean(receiver.integerToF64() <= f),
    };
}

pub fn builtinIntegerGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| Value.boolean((try compareIntegers(vm, receiver, i)) == .gt),
        .float => |f| Value.boolean(receiver.integerToF64() > f),
    };
}

pub fn builtinIntegerGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try receiver.ensureInteger(vm);
    const rhs = try coerceNumericArg(vm, args[0]);
    return switch (rhs) {
        .integer => |i| {
            const ord = try compareIntegers(vm, receiver, i);
            return Value.boolean(ord == .gt or ord == .eq);
        },
        .float => |f| Value.boolean(receiver.integerToF64() >= f),
    };
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
        const str = b.value.toString(vm.allocator, base, .lower) catch return error.Fatal;
        defer vm.allocator.free(str);
        return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
    } else unreachable;
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

pub fn builtinIntegerTimes(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try receiver.ensureInteger(vm);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("times"), &.{});
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
    try args[0].ensureInteger(vm);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("upto"), args);
    };

    const start = try receiver.integerToI64(vm, "integer is too large to iterate");
    const stop = try args[0].integerToI64(vm, "integer is too large to iterate");
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

pub fn builtinIntegerChr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try receiver.ensureInteger(vm);

    const codepoint = try receiver.integerToI64(vm, "integer is too large to convert into char");
    if (codepoint < 0) {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint});
    }

    const target_encoding: enc.Encoding = if (args.len == 0)
        if (codepoint <= 127) .{ .us_ascii = .{} } else .{ .ascii_8bit = .{} }
    else if (args[0].isEncoding())
        args[0].toEncodingObject().encoding
    else blk: {
        const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
        break :blk result.toEncodingObject().encoding;
    };

    const cp: u32 = @intCast(codepoint);
    var buf: [4]u8 = undefined;
    const encoded_len = target_encoding.fromUnicodeCodepoint(cp, &buf) orelse {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint});
    };
    const bytes = buf[0..encoded_len];

    return try vm.newStringWithEncoding(bytes, false, target_encoding);
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
