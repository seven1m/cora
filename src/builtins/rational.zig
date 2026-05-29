const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const BigInt = std.math.big.int.Managed;

pub const RationalParts = struct {
    numerator: Value,
    denominator: Value,
};

fn integerValueFromDecimalDigits(vm: *VM, digits: []const u8) VMError!Value {
    if (digits.len == 0) return Value.integer(0);
    return vm.newBigIntegerFromDecimalString(digits);
}

fn parseRationalInteger(vm: *VM, bytes: []const u8, negative: bool) VMError!Value {
    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(vm.allocator);

    for (bytes) |c| {
        if (std.ascii.isDigit(c)) {
            digits.append(vm.allocator, c) catch return error.Fatal;
        } else {
            return Value.integer(0);
        }
    }

    if (digits.items.len == 0) return Value.integer(0);

    var val = try integerValueFromDecimalDigits(vm, digits.items);
    if (negative) {
        val = try vm.mulIntegerValues(Value.integer(-1), val);
    }
    return val;
}

pub fn parseStringToRational(vm: *VM, bytes: []const u8) VMError!?RationalParts {
    const trimmed = std.mem.trim(u8, bytes, " \t\n\r\x0B\x0C");
    if (trimmed.len == 0) return null;

    var i: usize = 0;
    var negative = false;
    if (trimmed[i] == '+' or trimmed[i] == '-') {
        negative = trimmed[i] == '-';
        i += 1;
        if (i >= trimmed.len) return null;
    }

    var slash_idx: ?usize = null;
    var k: usize = i;
    while (k < trimmed.len) : (k += 1) {
        if (trimmed[k] == '/') {
            slash_idx = k;
            break;
        }
    }

if (slash_idx) |si| {
        const num_bytes = trimmed[i..si];
        const den_bytes = trimmed[si + 1..];
        if (num_bytes.len == 0 or den_bytes.len == 0) return null;

        const num_trimmed = std.mem.trim(u8, num_bytes, " \t\n\r\x0B\x0C");
        const den_trimmed = std.mem.trim(u8, den_bytes, " \t\n\r\x0B\x0C");

        if (num_trimmed.len == 0 or den_trimmed.len == 0) return null;

        var num_sign: bool = negative;
        var num_num_start: usize = 0;
        if (num_trimmed[0] == '+' or num_trimmed[0] == '-') {
            num_sign = (num_trimmed[0] == '-') != negative;
            num_num_start = 1;
        }

        const parsed_den = try parseRationalInteger(vm, den_trimmed, false);
        const den_int = parsed_den.toInteger();

        var num_val: Value = undefined;
        var num_frac_digits: usize = 0;
        var num_denom: Value = Value.integer(1);

        {
            var digits: std.ArrayList(u8) = .empty;
            defer digits.deinit(vm.allocator);

            var saw_digit = false;
            var saw_dot = false;
            var prev_was_digit = false;

            for (num_trimmed[num_num_start..]) |c| {
                if (std.ascii.isDigit(c)) {
                    digits.append(vm.allocator, c) catch return error.Fatal;
                    saw_digit = true;
                    prev_was_digit = true;
                    if (saw_dot) num_frac_digits += 1;
                    continue;
                }

                if (c == '_') {
                    const next_idx = digits.items.len;
                    if (prev_was_digit and next_idx + 1 < num_trimmed[num_num_start..].len) {
                        const next_c = num_trimmed[num_num_start..][next_idx + 1];
                        if (std.ascii.isDigit(next_c)) {
                            prev_was_digit = false;
                            continue;
                        }
                    }
                    return null;
                }

                if (c == '.' and !saw_dot) {
                    saw_dot = true;
                    prev_was_digit = false;
                    continue;
                }

                if (!saw_digit) return null;
                break;
            }

            if (!saw_digit) return null;

            num_val = try integerValueFromDecimalDigits(vm, digits.items);
            if (num_sign and (try vm.compareIntegerValues(num_val, Value.integer(0))) != .eq) {
                num_val = try vm.mulIntegerValues(Value.integer(-1), num_val);
            }

            if (num_frac_digits > 0) {
                const denominator_digits = vm.allocator.alloc(u8, num_frac_digits + 1) catch return error.Fatal;
                defer vm.allocator.free(denominator_digits);
                denominator_digits[0] = '1';
                @memset(denominator_digits[1..], '0');
                num_denom = try integerValueFromDecimalDigits(vm, denominator_digits);
            }
        }

        var result_num: Value = undefined;
        var result_den: Value = undefined;
        if (num_frac_digits > 0) {
            result_num = num_val;
            result_den = try vm.mulIntegerValues(num_denom, Value.integer(den_int));
        } else {
            result_num = num_val;
            result_den = Value.integer(den_int);
        }

        return .{
            .numerator = result_num,
            .denominator = result_den,
        };
    }

    const result = try parseRationalCore(vm, trimmed[i..], negative);
    return result;
}

fn parseRationalCore(vm: *VM, bytes: []const u8, negative: bool) VMError!?RationalParts {
    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(vm.allocator);

    var saw_digit = false;
    var saw_dot = false;
    var prev_was_digit = false;
    var fractional_digits: usize = 0;

    for (bytes) |c| {
        if (std.ascii.isDigit(c)) {
            digits.append(vm.allocator, c) catch return error.Fatal;
            saw_digit = true;
            prev_was_digit = true;
            if (saw_dot) fractional_digits += 1;
            continue;
        }

        if (c == '_') {
            const next_idx = digits.items.len;
            if (prev_was_digit and next_idx + 1 < bytes.len) {
                const next_c = bytes[next_idx + 1];
                if (std.ascii.isDigit(next_c)) {
                    prev_was_digit = false;
                    continue;
                }
            }
            return null;
        }

        if (c == '.' and !saw_dot) {
            saw_dot = true;
            prev_was_digit = false;
            continue;
        }

        if (!saw_digit) return null;
        break;
    }

    if (!saw_digit) return null;

    var numerator = try integerValueFromDecimalDigits(vm, digits.items);
    if (negative and (try vm.compareIntegerValues(numerator, Value.integer(0))) != .eq) {
        numerator = try vm.mulIntegerValues(Value.integer(-1), numerator);
    }

    if (fractional_digits == 0) {
        return .{ .numerator = numerator, .denominator = Value.integer(1) };
    }

    const denominator_digits = vm.allocator.alloc(u8, fractional_digits + 1) catch return error.Fatal;
    defer vm.allocator.free(denominator_digits);
    denominator_digits[0] = '1';
    @memset(denominator_digits[1..], '0');

    return .{
        .numerator = numerator,
        .denominator = try integerValueFromDecimalDigits(vm, denominator_digits),
    };
}

pub fn floatToRationalParts(vm: *VM, f: f64) VMError!RationalParts {
    if (std.math.isNan(f) or std.math.isInf(f)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "float out of range of rational", .{});
    }

    if (f == 0.0) {
        return .{ .numerator = Value.integer(0), .denominator = Value.integer(1) };
    }

    const bits: u64 = @bitCast(f);
    const negative = (bits >> 63) != 0;
    const exponent_bits: u16 = @intCast((bits >> 52) & 0x7ff);
    const fraction_bits = bits & 0x000f_ffff_ffff_ffff;

    const mantissa: u64 = if (exponent_bits == 0)
        fraction_bits
    else
        fraction_bits | (1 << 52);
    const exponent: i32 = if (exponent_bits == 0)
        1 - 1023 - 52
    else
        @as(i32, exponent_bits) - 1023 - 52;

    var numerator = Value.integer(@intCast(mantissa));
    var denominator = Value.integer(1);

    if (exponent >= 0) {
        var shifted = BigInt.initSet(vm.allocator, @as(i64, @intCast(mantissa))) catch return error.Fatal;
        defer shifted.deinit();
        shifted.shiftLeft(&shifted, @intCast(exponent)) catch return error.Fatal;
        numerator = try vm.valueFromManagedInteger(&shifted);
    } else {
        const shift: u32 = @intCast(-exponent);
        if (shift < 63) {
            denominator = Value.integer(@as(i64, 1) << @intCast(shift));
        } else {
            var den = BigInt.initSet(vm.allocator, 1) catch return error.Fatal;
            defer den.deinit();
            den.shiftLeft(&den, shift) catch return error.Fatal;
            denominator = try vm.valueFromManagedInteger(&den);
        }
    }

    if (negative) numerator = try vm.mulIntegerValues(Value.integer(-1), numerator);
    return .{ .numerator = numerator, .denominator = denominator };
}

pub fn register(vm: *VM) !void {
    const rational_new_sym = try vm.intern("new");
    try vm.rational_class.module.methods.put(rational_new_sym, value.MethodEntry.builtinWithVisibility(&builtinRationalNewForbidden, .{ .variadic = 0 }, .private));

    const numerator_sym = try vm.intern("numerator");
    try vm.rational_class.module.methods.put(numerator_sym, value.MethodEntry.builtin(&builtinRationalNumerator, .{ .exact = 0 }));

    const denominator_sym = try vm.intern("denominator");
    try vm.rational_class.module.methods.put(denominator_sym, value.MethodEntry.builtin(&builtinRationalDenominator, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.rational_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinRationalToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.rational_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinRationalInspect, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.rational_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinRationalToF, .{ .exact = 0 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.rational_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinRationalToI, .{ .exact = 0 }));

    const to_int_sym = try vm.intern("to_int");
    try vm.rational_class.module.methods.put(to_int_sym, value.MethodEntry.builtin(&builtinRationalToI, .{ .exact = 0 }));

    const freeze_sym = try vm.intern("freeze");
    try vm.rational_class.module.methods.put(freeze_sym, value.MethodEntry.builtin(&builtinRationalFreeze, .{ .exact = 0 }));

    const clone_sym = try vm.intern("clone");
    try vm.rational_class.module.methods.put(clone_sym, value.MethodEntry.builtin(&builtinRationalClone, .{ .variadic = 0 }));

    const dup_sym = try vm.intern("dup");
    try vm.rational_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinRationalClone, .{ .variadic = 0 }));

    const hash_sym = try vm.intern("hash");
    try vm.rational_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinRationalHash, .{ .exact = 0 }));

    const eql_sym = try vm.intern("eql?");
    try vm.rational_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinRationalEql, .{ .exact = 1 }));

    const equal_sym = try vm.intern("==");
    try vm.rational_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinRationalEqual, .{ .exact = 1 }));

    const compare_sym = try vm.intern("<=>");
    try vm.rational_class.module.methods.put(compare_sym, value.MethodEntry.builtin(&builtinRationalCompare, .{ .exact = 1 }));

    const unary_minus_sym = try vm.intern("-@");
    try vm.rational_class.module.methods.put(unary_minus_sym, value.MethodEntry.builtin(&builtinRationalUnaryMinus, .{ .exact = 0 }));

    const unary_plus_sym = try vm.intern("+@");
    try vm.rational_class.module.methods.put(unary_plus_sym, value.MethodEntry.builtin(&builtinRationalUnaryPlus, .{ .exact = 0 }));
}

pub fn builtinRationalNewForbidden(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.raiseExceptionFmt(vm.no_method_error_class, "private method `new' called for Rational", .{});
}

pub fn builtinRationalNumerator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    return rational.numerator;
}

pub fn builtinRationalDenominator(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    return rational.denominator;
}

pub fn builtinRationalToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();

    rational.numerator.format(&buf.writer) catch return error.Fatal;
    buf.writer.writeByte('/') catch return error.Fatal;
    rational.denominator.format(&buf.writer) catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
}

pub fn builtinRationalInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinRationalToS(vm, receiver, args, null);
}

pub fn builtinRationalToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    const f = rational.numerator.integerToF64() / rational.denominator.integerToF64();
    return vm.newFloat(f);
}

pub fn builtinRationalToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    if ((try vm.compareIntegerValues(rational.denominator, Value.integer(0))) == .eq) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }
    return vm.divTruncIntegerValues(rational.numerator, rational.denominator);
}

pub fn builtinRationalFreeze(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinRationalClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.consumeCloneFreezeOpt();
    return receiver;
}

pub fn builtinRationalHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    const combined = rational.numerator.hash() ^ (rational.denominator.hash() << 1);
    return Value.integer(@bitCast(combined));
}

pub fn builtinRationalEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (!other.isRational()) return Value.boolean(false);
    const other_rational = other.toRationalObject();
    return Value.boolean(
        (try vm.compareIntegerValues(rational.numerator, other_rational.numerator)) == .eq and
            (try vm.compareIntegerValues(rational.denominator, other_rational.denominator)) == .eq,
    );
}

pub fn builtinRationalEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (other.isRational()) {
        const other_rational = other.toRationalObject();
        return Value.boolean(
            (try vm.compareIntegerValues(rational.numerator, other_rational.numerator)) == .eq and
                (try vm.compareIntegerValues(rational.denominator, other_rational.denominator)) == .eq,
        );
    }
    if (other.isInteger() or other.isBigInteger()) {
        if ((try vm.compareIntegerValues(rational.denominator, Value.integer(1))) == .eq) {
            return Value.boolean((try vm.compareIntegerValues(rational.numerator, other)) == .eq);
        }
        return Value.boolean(false);
    }
    if (other.isFloat()) {
        const lhs = rational.numerator.integerToF64() / rational.denominator.integerToF64();
        return Value.boolean(lhs == other.toFloatObject().val);
    }
    var reverse_args = [_]Value{receiver};
    const result = try vm.callMethodByName(other, "==", reverse_args[0..], null);
    return Value.boolean(result.is_truthy());
}

pub fn builtinRationalCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];

    if (other.isRational()) {
        const other_rational = other.toRationalObject();
        const lhs_cross = try vm.mulIntegerValues(rational.numerator, other_rational.denominator);
        const rhs_cross = try vm.mulIntegerValues(other_rational.numerator, rational.denominator);
        const order = try vm.compareIntegerValues(lhs_cross, rhs_cross);
        if (order == .lt) return Value.integer(-1);
        if (order == .gt) return Value.integer(1);
        return Value.integer(0);
    }
    if (other.isInteger() or other.isBigInteger()) {
        const rhs_cross = try vm.mulIntegerValues(other, rational.denominator);
        const order = try vm.compareIntegerValues(rational.numerator, rhs_cross);
        if (order == .lt) return Value.integer(-1);
        if (order == .gt) return Value.integer(1);
        return Value.integer(0);
    }
    if (other.isFloat()) {
        const lhs = @as(f128, rational.numerator.integerToF64()) / @as(f128, rational.denominator.integerToF64());
        const rhs = @as(f128, other.toFloatObject().val);
        if (lhs < rhs) return Value.integer(-1);
        if (lhs > rhs) return Value.integer(1);
        return Value.integer(0);
    }

    var reverse_args = [_]Value{receiver};
    const cmp = try vm.callMethodByName(other, "<=>", reverse_args[0..], null);
    if (cmp.isNil()) return Value.nil();
    if (!cmp.isInteger()) return Value.nil();
    return cmp;
}

pub fn builtinRationalUnaryMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    const neg_num = try vm.mulIntegerValues(Value.integer(-1), rational.numerator);
    return vm.newRationalValues(neg_num, rational.denominator);
}

pub fn builtinRationalUnaryPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}
