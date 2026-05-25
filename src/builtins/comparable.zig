const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const ComparableOp = enum {
    less_than,
    less_than_or_equal,
    greater_than,
    greater_than_or_equal,
};

const ComparisonMode = enum {
    ordered,
    equality,
};

const ClampBounds = struct {
    min: Value,
    max: Value,
};

fn comparableComparisonFailed(vm: *VM, receiver: Value, other: Value) VMError!void {
    const inspected_other = try other.inspect(vm);
    vm.setPendingException(try vm.createException(
        vm.argument_error_class,
        std.fmt.allocPrint(
            vm.gc_allocator,
            "comparison of {s} with {s} failed",
            .{ vm.className(receiver), inspected_other.toStringObject().str },
        ) catch return error.Fatal,
    ));
    return error.Unwind;
}

fn compareAgainstOther(vm: *VM, receiver: Value, other: Value) VMError!?Value {
    var args = [_]Value{other};
    return try vm.checkCallMethodByName(receiver, "<=>", false, args[0..], null);
}

fn comparableSign(vm: *VM, receiver: Value, other: Value, mode: ComparisonMode) VMError!?i8 {
    const maybe_cmp = compareAgainstOther(vm, receiver, other) catch |err| switch (err) {
        error.Unwind => {
            if (mode == .equality) {
                if (vm.pendingException()) |exc| {
                    if (exc.object.class == vm.no_method_error_class) {
                        vm.setPendingException(null);
                        return null;
                    }
                }
            }
            return error.Unwind;
        },
        else => return err,
    };
    const cmp = maybe_cmp orelse switch (mode) {
        .ordered => {
            try comparableComparisonFailed(vm, receiver, other);
            unreachable;
        },
        .equality => return null,
    };
    if (cmp.isNil()) {
        return switch (mode) {
            .ordered => {
                try comparableComparisonFailed(vm, receiver, other);
                unreachable;
            },
            .equality => null,
        };
    }
    return try compareSign(vm, receiver, other, cmp);
}

fn compareSign(vm: *VM, receiver: Value, other: Value, cmp_value: Value) VMError!i8 {
    if (cmp_value.isInteger()) {
        const n = cmp_value.toInteger();
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp_value.isFloat()) {
        const n = cmp_value.toFloatObject().val;
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    try comparableComparisonFailed(vm, receiver, other);
    unreachable;
}

fn comparablePredicate(vm: *VM, receiver: Value, other: Value, op: ComparableOp) VMError!Value {
    if (receiver.raw == other.raw) {
        return switch (op) {
            .less_than => Value.boolean(false),
            .less_than_or_equal => Value.boolean(true),
            .greater_than => Value.boolean(false),
            .greater_than_or_equal => Value.boolean(true),
        };
    }

    const sign = (try comparableSign(vm, receiver, other, .ordered)).?;
    return switch (op) {
        .less_than => Value.boolean(sign < 0),
        .less_than_or_equal => Value.boolean(sign <= 0),
        .greater_than => Value.boolean(sign > 0),
        .greater_than_or_equal => Value.boolean(sign >= 0),
    };
}

fn validateClampBounds(vm: *VM, min: Value, max: Value) VMError!void {
    if (min.isNil() or max.isNil()) return;

    const sign = (try comparableSign(vm, min, max, .ordered)).?;
    if (sign > 0) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "min argument must be less than or equal to max argument",
            .{},
        );
    }
}

fn clampBoundsFromArgs(vm: *VM, args: []Value) VMError!ClampBounds {
    try vm.requireArgCountRange(args, 1, 2);

    if (args.len == 1) {
        if (!args[0].isRange()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "wrong argument type {s} (expected Range)",
                .{vm.className(args[0])},
            );
        }

        const range_obj = args[0].toRangeObject();
        if (range_obj.exclude_end and !range_obj.end.isNil()) {
            return vm.raiseExceptionFmt(
                vm.argument_error_class,
                "cannot clamp with an exclusive range",
                .{},
            );
        }

        try validateClampBounds(vm, range_obj.begin, range_obj.end);
        return .{ .min = range_obj.begin, .max = range_obj.end };
    }

    try validateClampBounds(vm, args[0], args[1]);
    return .{ .min = args[0], .max = args[1] };
}

pub fn register(vm: *VM, comparable_module: *value.ModuleObject) !void {
    const less_than_sym = try vm.intern("<");
    try comparable_module.methods.put(less_than_sym, value.MethodEntry.builtin(&builtinComparableLessThan, .{ .exact = 1 }));

    const less_than_or_equal_sym = try vm.intern("<=");
    try comparable_module.methods.put(less_than_or_equal_sym, value.MethodEntry.builtin(&builtinComparableLessThanOrEqual, .{ .exact = 1 }));

    const greater_than_sym = try vm.intern(">");
    try comparable_module.methods.put(greater_than_sym, value.MethodEntry.builtin(&builtinComparableGreaterThan, .{ .exact = 1 }));

    const greater_than_or_equal_sym = try vm.intern(">=");
    try comparable_module.methods.put(greater_than_or_equal_sym, value.MethodEntry.builtin(&builtinComparableGreaterThanOrEqual, .{ .exact = 1 }));

    const equal_sym = try vm.intern("==");
    try comparable_module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinComparableEqual, .{ .exact = 1 }));

    const between_sym = try vm.intern("between?");
    try comparable_module.methods.put(between_sym, value.MethodEntry.builtin(&builtinComparableBetween, .{ .exact = 2 }));

    const clamp_sym = try vm.intern("clamp");
    try comparable_module.methods.put(clamp_sym, value.MethodEntry.builtin(&builtinComparableClamp, .{ .variadic = 0 }));
}

pub fn builtinComparableLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try comparablePredicate(vm, receiver, args[0], .less_than);
}

pub fn builtinComparableLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try comparablePredicate(vm, receiver, args[0], .less_than_or_equal);
}

pub fn builtinComparableGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try comparablePredicate(vm, receiver, args[0], .greater_than);
}

pub fn builtinComparableGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try comparablePredicate(vm, receiver, args[0], .greater_than_or_equal);
}

pub fn builtinComparableEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (receiver.raw == other.raw) return Value.boolean(true);

    if (try vm.enterRecursionGuard(.comparable_equal, receiver, other)) {
        return Value.boolean(false);
    }
    defer vm.leaveRecursionGuard(.comparable_equal, receiver, other);

    const sign = (try comparableSign(vm, receiver, other, .equality)) orelse return Value.boolean(false);
    return Value.boolean(sign == 0);
}

pub fn builtinComparableBetween(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const low_sign = (try comparableSign(vm, receiver, args[0], .ordered)).?;
    if (low_sign < 0) return Value.boolean(false);

    const high_sign = (try comparableSign(vm, receiver, args[1], .ordered)).?;
    return Value.boolean(high_sign <= 0);
}

pub fn builtinComparableClamp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const bounds = try clampBoundsFromArgs(vm, args);

    if (!bounds.min.isNil()) {
        const low_sign = (try comparableSign(vm, receiver, bounds.min, .ordered)).?;
        if (low_sign < 0) return bounds.min;
    }

    if (!bounds.max.isNil()) {
        const high_sign = (try comparableSign(vm, receiver, bounds.max, .ordered)).?;
        if (high_sign > 0) return bounds.max;
    }

    return receiver;
}
