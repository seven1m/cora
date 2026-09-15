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

    const to_r_sym = try vm.intern("to_r");
    try vm.rational_class.module.methods.put(to_r_sym, value.MethodEntry.builtin(&builtinRationalToR, .{ .exact = 0 }));

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

    const plus_sym = try vm.intern("+");
    try vm.rational_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinRationalPlus, .{ .exact = 1 }));

    const minus_sym = try vm.intern("-");
    try vm.rational_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinRationalMinus, .{ .exact = 1 }));

    const multiply_sym = try vm.intern("*");
    try vm.rational_class.module.methods.put(multiply_sym, value.MethodEntry.builtin(&builtinRationalMultiply, .{ .exact = 1 }));

    const divide_entry = value.MethodEntry.builtin(&builtinRationalDivide, .{ .exact = 1 });
    const divide_sym = try vm.intern("/");
    try vm.rational_class.module.methods.put(divide_sym, divide_entry);

    const quo_sym = try vm.intern("quo");
    try vm.rational_class.module.methods.put(quo_sym, divide_entry);

    const coerce_sym = try vm.intern("coerce");
    try vm.rational_class.module.methods.put(coerce_sym, value.MethodEntry.builtin(&builtinRationalCoerce, .{ .exact = 1 }));

    const truncate_sym = try vm.intern("truncate");
    try vm.rational_class.module.methods.put(truncate_sym, value.MethodEntry.builtin(&builtinRationalTruncate, .{ .variadic = 0 }));

    const round_sym = try vm.intern("round");
    try vm.rational_class.module.methods.put(round_sym, value.MethodEntry.builtin(&builtinRationalRound, .{ .variadic = 0 }));
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
    const num_str_val = try vm.callMethodByName(rational.numerator, "to_s", &.{}, null);
    const den_str_val = try vm.callMethodByName(rational.denominator, "to_s", &.{}, null);
    const num_str = num_str_val.toStringObject().str;
    const den_str = den_str_val.toStringObject().str;
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();

    buf.writer.writeAll(num_str) catch return error.Fatal;
    buf.writer.writeByte('/') catch return error.Fatal;
    buf.writer.writeAll(den_str) catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
}

pub fn builtinRationalInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    const num_str_val = try vm.callMethodByName(rational.numerator, "to_s", &.{}, null);
    const den_str_val = try vm.callMethodByName(rational.denominator, "to_s", &.{}, null);
    const num_str = num_str_val.toStringObject().str;
    const den_str = den_str_val.toStringObject().str;
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();

    buf.writer.writeByte('(') catch return error.Fatal;
    buf.writer.writeAll(num_str) catch return error.Fatal;
    buf.writer.writeByte('/') catch return error.Fatal;
    buf.writer.writeAll(den_str) catch return error.Fatal;
    buf.writer.writeByte(')') catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
}

pub fn builtinRationalToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    const num_f64 = rational.numerator.integerToF64();
    const den_f64 = rational.denominator.integerToF64();
    if (std.math.isFinite(num_f64) and std.math.isFinite(den_f64)) {
        return vm.newFloat(num_f64 / den_f64);
    }
    // Huge numerator/denominator overflow f64 individually (e.g. 10**343),
    // but their ratio fits. Divide in f128 (max ~1e4932) then narrow.
    const num_f128 = integerValueToF128(rational.numerator);
    const den_f128 = integerValueToF128(rational.denominator);
    return vm.newFloat(@floatCast(num_f128 / den_f128));
}

fn integerValueToF128(v: Value) f128 {
    if (v.isBigInteger()) return v.toBigIntegerObject().value.toFloat(f128, .nearest_even)[0];
    if (v.isInteger()) return @floatFromInt(v.toInteger());
    return v.integerToF64();
}

pub fn builtinRationalToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const rational = receiver.toRationalObject();
    if ((try vm.compareIntegerValues(rational.denominator, Value.integer(0))) == .eq) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }
    return vm.divTruncIntegerValues(rational.numerator, rational.denominator);
}

pub fn builtinRationalToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn rationalDecimalFactor(vm: *VM, abs_ndigits: u64) VMError!Value {
    var factor = Value.integer(1);
    var i: u64 = 0;
    while (i < abs_ndigits) : (i += 1) {
        factor = try vm.mulIntegerValues(factor, Value.integer(10));
    }
    return factor;
}

pub fn builtinRationalTruncate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const rational = receiver.toRationalObject();
    if (args.len == 0) {
        return builtinRationalToI(vm, receiver, &.{}, null);
    }
    const ndigits = try args[0].integerArgToI64(vm, "not an integer", "ndigits is too large");
    if (ndigits == 0) {
        return builtinRationalToI(vm, receiver, &.{}, null);
    }
    if (ndigits < 0) {
        const factor = try rationalDecimalFactor(vm, @intCast(-ndigits));
        const scaled_den = try vm.mulIntegerValues(rational.denominator, factor);
        const quotient = try vm.divTruncIntegerValues(rational.numerator, scaled_den);
        return vm.mulIntegerValues(quotient, factor);
    }
    const factor = try rationalDecimalFactor(vm, @intCast(ndigits));
    const scaled_num = try vm.mulIntegerValues(rational.numerator, factor);
    const truncated = try vm.divTruncIntegerValues(scaled_num, rational.denominator);
    return vm.newRationalValues(truncated, factor);
}

fn rationalRoundHalfMode(vm: *VM, half_val: ?Value) VMError![]const u8 {
    const half = half_val orelse return "up";
    if (half.isNil()) return "up";
    if (!half.isSymbol()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid rounding mode: {s}", .{vm.className(half)});
    }
    const name = half.toSymbolObject().name;
    if (!std.mem.eql(u8, name, "up") and
        !std.mem.eql(u8, name, "down") and
        !std.mem.eql(u8, name, "even"))
    {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid rounding mode: {s}", .{name});
    }
    return name;
}

fn rationalRoundQuotient(vm: *VM, numerator: Value, denominator: Value, half_mode: []const u8) VMError!Value {
    const zero = Value.integer(0);
    const one = Value.integer(1);
    const negative_one = Value.integer(-1);
    const two = Value.integer(2);

    const quotient = try vm.divTruncIntegerValues(numerator, denominator);
    const product = try vm.mulIntegerValues(quotient, denominator);
    const remainder = try vm.subIntegerValues(numerator, product);
    if ((try vm.compareIntegerValues(remainder, zero)) == .eq) return quotient;

    const abs_remainder = if ((try vm.compareIntegerValues(remainder, zero)) == .lt)
        try vm.mulIntegerValues(negative_one, remainder)
    else
        remainder;
    const abs_denominator = if ((try vm.compareIntegerValues(denominator, zero)) == .lt)
        try vm.mulIntegerValues(negative_one, denominator)
    else
        denominator;
    const twice_remainder = try vm.mulIntegerValues(two, abs_remainder);
    const cmp = try vm.compareIntegerValues(twice_remainder, abs_denominator);

    // Rational values are normalized with a positive denominator, so the
    // sign of the quotient matches the sign of the numerator.
    const positive = (try vm.compareIntegerValues(numerator, zero)) != .lt;
    const round_away = if (positive)
        try vm.addIntegerValues(quotient, one)
    else
        try vm.subIntegerValues(quotient, one);

    if (cmp == .gt) return round_away;
    if (cmp == .lt) return quotient;

    if (std.mem.eql(u8, half_mode, "down")) return quotient;

    if (std.mem.eql(u8, half_mode, "even")) {
        const half_quotient = try vm.divTruncIntegerValues(quotient, two);
        const doubled = try vm.mulIntegerValues(half_quotient, two);
        if ((try vm.compareIntegerValues(doubled, quotient)) == .eq) return quotient;
    }

    return round_away;
}

fn rationalPowerOfTenDivisible(vm: *VM, denominator: Value, ndigits: u64) VMError!bool {
    const one = Value.integer(1);
    const two = Value.integer(2);
    const five = Value.integer(5);

    var remaining = denominator;
    var twos: u64 = 0;
    var fives: u64 = 0;
    while ((try vm.compareIntegerValues(remaining, one)) != .eq) {
        const half = try vm.divTruncIntegerValues(remaining, two);
        if ((try vm.compareIntegerValues(try vm.mulIntegerValues(half, two), remaining)) == .eq) {
            remaining = half;
            twos += 1;
            continue;
        }
        const fifth = try vm.divTruncIntegerValues(remaining, five);
        if ((try vm.compareIntegerValues(try vm.mulIntegerValues(fifth, five), remaining)) == .eq) {
            remaining = fifth;
            fives += 1;
            continue;
        }
        return false;
    }
    return twos <= ndigits and fives <= ndigits;
}

pub fn builtinRationalRound(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const half_mode = try rationalRoundHalfMode(vm, try vm.consumeKeywordArg("half"));
    try vm.validateKeywordArgsConsumed();
    const rational = receiver.toRationalObject();
    const ndigits: i64 = if (args.len == 0)
        0
    else
        try args[0].integerArgToI64(vm, "not an integer", "ndigits is too large");
    if (ndigits == 0) {
        return rationalRoundQuotient(vm, rational.numerator, rational.denominator, half_mode);
    }
    if (ndigits < 0) {
        const factor = try rationalDecimalFactor(vm, @intCast(-ndigits));
        const scaled_den = try vm.mulIntegerValues(rational.denominator, factor);
        const quotient = try rationalRoundQuotient(vm, rational.numerator, scaled_den, half_mode);
        return vm.mulIntegerValues(quotient, factor);
    }
    const abs_ndigits: u64 = @intCast(ndigits);
    // Avoid materializing enormous powers of ten when the scaled division is
    // exact; the rounded value is then self (e.g. round(2097171)).
    if (abs_ndigits > 100 and try rationalPowerOfTenDivisible(vm, rational.denominator, abs_ndigits)) {
        return receiver;
    }
    const factor = try rationalDecimalFactor(vm, abs_ndigits);
    const scaled_num = try vm.mulIntegerValues(rational.numerator, factor);
    const quotient = try rationalRoundQuotient(vm, scaled_num, rational.denominator, half_mode);
    return vm.newRationalValues(quotient, factor);
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
    return Value.boolean(result.isTruthy());
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

fn rationalToF64(rational: *value.RationalObject) f64 {
    return rational.numerator.integerToF64() / rational.denominator.integerToF64();
}

fn coerceAndCallRationalArithmetic(vm: *VM, receiver: Value, arg: Value, op_name: []const u8) VMError!Value {
    var coerce_args = [_]Value{receiver};
    const maybe_coerced = try vm.checkCallMethodByName(arg, "coerce", true, coerce_args[0..], null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Rational", .{vm.className(arg)});
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

pub fn builtinRationalPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (other.isRational()) {
        const rhs = other.toRationalObject();
        const ad = try vm.mulIntegerValues(rational.numerator, rhs.denominator);
        const bc = try vm.mulIntegerValues(rhs.numerator, rational.denominator);
        const num = try vm.addIntegerValues(ad, bc);
        const den = try vm.mulIntegerValues(rational.denominator, rhs.denominator);
        return vm.newRationalValues(num, den);
    }
    if (other.isInteger() or other.isBigInteger()) {
        const c_times_b = try vm.mulIntegerValues(other, rational.denominator);
        const num = try vm.addIntegerValues(rational.numerator, c_times_b);
        return vm.newRationalValues(num, rational.denominator);
    }
    if (other.isFloat()) {
        return vm.newFloat(rationalToF64(rational) + other.toFloatObject().val);
    }
    return coerceAndCallRationalArithmetic(vm, receiver, other, "+");
}

pub fn builtinRationalMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (other.isRational()) {
        const rhs = other.toRationalObject();
        const ad = try vm.mulIntegerValues(rational.numerator, rhs.denominator);
        const bc = try vm.mulIntegerValues(rhs.numerator, rational.denominator);
        const num = try vm.subIntegerValues(ad, bc);
        const den = try vm.mulIntegerValues(rational.denominator, rhs.denominator);
        return vm.newRationalValues(num, den);
    }
    if (other.isInteger() or other.isBigInteger()) {
        const c_times_b = try vm.mulIntegerValues(other, rational.denominator);
        const num = try vm.subIntegerValues(rational.numerator, c_times_b);
        return vm.newRationalValues(num, rational.denominator);
    }
    if (other.isFloat()) {
        return vm.newFloat(rationalToF64(rational) - other.toFloatObject().val);
    }
    return coerceAndCallRationalArithmetic(vm, receiver, other, "-");
}

pub fn builtinRationalMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (other.isRational()) {
        const rhs = other.toRationalObject();
        const num = try vm.mulIntegerValues(rational.numerator, rhs.numerator);
        const den = try vm.mulIntegerValues(rational.denominator, rhs.denominator);
        return vm.newRationalValues(num, den);
    }
    if (other.isInteger() or other.isBigInteger()) {
        const num = try vm.mulIntegerValues(rational.numerator, other);
        return vm.newRationalValues(num, rational.denominator);
    }
    if (other.isFloat()) {
        return vm.newFloat(rationalToF64(rational) * other.toFloatObject().val);
    }
    return coerceAndCallRationalArithmetic(vm, receiver, other, "*");
}

pub fn builtinRationalDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const rational = receiver.toRationalObject();
    const other = args[0];
    if (other.isRational()) {
        const rhs = other.toRationalObject();
        if ((try vm.compareIntegerValues(rhs.numerator, Value.integer(0))) == .eq) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const num = try vm.mulIntegerValues(rational.numerator, rhs.denominator);
        const den = try vm.mulIntegerValues(rational.denominator, rhs.numerator);
        return vm.newRationalValues(num, den);
    }
    if (other.isInteger() or other.isBigInteger()) {
        if ((try vm.compareIntegerValues(other, Value.integer(0))) == .eq) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        const den = try vm.mulIntegerValues(rational.denominator, other);
        return vm.newRationalValues(rational.numerator, den);
    }
    if (other.isFloat()) {
        return vm.newFloat(rationalToF64(rational) / other.toFloatObject().val);
    }
    return coerceAndCallRationalArithmetic(vm, receiver, other, "/");
}

pub fn builtinRationalCoerce(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    const result = try vm.createArray();
    if (other.isRational()) {
        result.elements.append(vm.gc_allocator, other) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    if (other.isInteger() or other.isBigInteger()) {
        const coerced = try vm.newRationalValues(other, Value.integer(1));
        result.elements.append(vm.gc_allocator, coerced) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, receiver) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    if (other.isFloat()) {
        const rational = receiver.toRationalObject();
        result.elements.append(vm.gc_allocator, other) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, try vm.newFloat(rationalToF64(rational))) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    if (other.isComplex()) {
        const as_complex = try vm.newComplex(receiver, Value.integer(0));
        result.elements.append(vm.gc_allocator, other) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, as_complex) catch return error.Fatal;
        return Value.fromObject(&result.object);
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "{s} can't be coerced into Rational", .{vm.className(other)});
}
