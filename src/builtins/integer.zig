const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const encoding_builtin = @import("encoding.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

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

    const chr_sym = try vm.intern("chr");
    try vm.integer_class.module.methods.put(chr_sym, .{ .method = .{ .builtin = &builtinIntegerChr } });
}

pub fn builtinIntegerPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer + args[0].data.integer;
    return Value.integer(result);
}

pub fn builtinIntegerMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer - args[0].data.integer;
    return Value.integer(result);
}

pub fn builtinIntegerMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer * args[0].data.integer;
    return Value.integer(result);
}

pub fn builtinIntegerDivide(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const divisor = args[0].data.integer;
    if (divisor == 0) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }
    const result = std.math.divFloor(i64, receiver.data.integer, divisor) catch {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
    };
    return Value.integer(result);
}

pub fn builtinIntegerModulo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const divisor = args[0].data.integer;
    if (divisor == 0) {
        return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
    }
    const quotient = std.math.divFloor(i64, receiver.data.integer, divisor) catch {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
    };
    const prod = std.math.mul(i64, quotient, divisor) catch {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
    };
    const result = std.math.sub(i64, receiver.data.integer, prod) catch {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
    };
    return Value.integer(result);
}

pub fn builtinIntegerPower(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const exponent = args[0].data.integer;
    if (exponent < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative exponent not supported", .{});
    }

    var result: i64 = 1;
    var base = receiver.data.integer;
    var exp: u64 = @intCast(exponent);

    while (exp > 0) : (exp >>= 1) {
        if ((exp & 1) == 1) {
            result = std.math.mul(i64, result, base) catch {
                return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
            };
        }
        if (exp > 1) {
            base = std.math.mul(i64, base, base) catch {
                return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
            };
        }
    }

    return Value.integer(result);
}

pub fn builtinIntegerEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer == args[0].data.integer;
    return Value.boolean(result);
}

pub fn builtinIntegerLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer < args[0].data.integer;
    return Value.boolean(result);
}

pub fn builtinIntegerLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer <= args[0].data.integer;
    return Value.boolean(result);
}

pub fn builtinIntegerGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer > args[0].data.integer;
    return Value.boolean(result);
}

pub fn builtinIntegerGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const result = receiver.data.integer >= args[0].data.integer;
    return Value.boolean(result);
}

pub fn builtinIntegerToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgRange(args, 0, 1);

    var base: u8 = 10;
    if (args.len == 1) {
        try vm.requireArgType(args, 0, .integer, "Integer");
        const base_int = args[0].data.integer;
        if (base_int < 2 or base_int > 36) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid radix {d}", .{base_int});
        }
        base = @intCast(base_int);
    }

    var buf: [65]u8 = undefined;
    const str = integerToBaseString(receiver.data.integer, base, &buf);
    return try vm.newStringWithEncoding(str, false, .{ .us_ascii = .{} });
}

pub fn builtinIntegerInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinIntegerToS(vm, receiver, args, null);
}

pub fn builtinIntegerAbs(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const val = receiver.data.integer;
    if (val >= 0) return Value.integer(val);
    const abs_val = std.math.negate(val) catch {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer overflow", .{});
    };
    return Value.integer(abs_val);
}

pub fn builtinIntegerNegative(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.data.integer < 0);
}

pub fn builtinIntegerZero(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.data.integer == 0);
}

pub fn builtinIntegerChr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgRange(args, 0, 1);

    const codepoint = receiver.data.integer;
    if (codepoint < 0) {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{codepoint});
    }

    const target_encoding: enc.Encoding = if (args.len == 0)
        if (codepoint <= 127) .{ .us_ascii = .{} } else .{ .ascii_8bit = .{} }
    else switch (args[0].data) {
        .encoding => |e| e.encoding,
        else => blk: {
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
            break :blk result.data.encoding.encoding;
        },
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
