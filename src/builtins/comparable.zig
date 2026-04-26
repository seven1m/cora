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

fn comparableComparisonFailed(vm: *VM, receiver: Value, other: Value) VMError!void {
    const inspected_other = try other.inspect(vm);
    vm.pending_exception = try vm.createException(
        vm.argument_error_class,
        std.fmt.allocPrint(
            vm.gc_allocator,
            "comparison of {s} with {s} failed",
            .{ vm.className(receiver), inspected_other.toStringObject().str },
        ) catch return error.Fatal,
    );
    return error.Unwind;
}

fn compareAgainstOther(vm: *VM, receiver: Value, other: Value) VMError!?Value {
    var args = [_]Value{other};
    return try vm.checkCallMethodByName(receiver, "<=>", false, args[0..], null);
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

    const maybe_cmp = try compareAgainstOther(vm, receiver, other);
    const cmp = maybe_cmp orelse {
        try comparableComparisonFailed(vm, receiver, other);
        unreachable;
    };

    const sign = try compareSign(vm, receiver, other, cmp);
    return switch (op) {
        .less_than => Value.boolean(sign < 0),
        .less_than_or_equal => Value.boolean(sign <= 0),
        .greater_than => Value.boolean(sign > 0),
        .greater_than_or_equal => Value.boolean(sign >= 0),
    };
}

pub fn register(vm: *VM, comparable_module: *value.ModuleObject) !void {
    const less_than_sym = try vm.intern("<");
    try comparable_module.methods.put(less_than_sym, .{ .method = .{ .builtin = &builtinComparableLessThan } });

    const less_than_or_equal_sym = try vm.intern("<=");
    try comparable_module.methods.put(less_than_or_equal_sym, .{ .method = .{ .builtin = &builtinComparableLessThanOrEqual } });

    const greater_than_sym = try vm.intern(">");
    try comparable_module.methods.put(greater_than_sym, .{ .method = .{ .builtin = &builtinComparableGreaterThan } });

    const greater_than_or_equal_sym = try vm.intern(">=");
    try comparable_module.methods.put(greater_than_or_equal_sym, .{ .method = .{ .builtin = &builtinComparableGreaterThanOrEqual } });

    const equal_sym = try vm.intern("==");
    try comparable_module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinComparableEqual } });

    const between_sym = try vm.intern("between?");
    try comparable_module.methods.put(between_sym, .{ .method = .{ .builtin = &builtinComparableBetween } });
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

    const maybe_cmp = try compareAgainstOther(vm, receiver, other);
    const cmp = maybe_cmp orelse return Value.boolean(false);
    if (cmp.isNil()) return Value.boolean(false);
    const sign = try compareSign(vm, receiver, other, cmp);
    return Value.boolean(sign == 0);
}

pub fn builtinComparableBetween(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const low_cmp = try compareAgainstOther(vm, receiver, args[0]);
    const low = low_cmp orelse {
        try comparableComparisonFailed(vm, receiver, args[0]);
        unreachable;
    };
    const low_sign = try compareSign(vm, receiver, args[0], low);
    if (low_sign < 0) return Value.boolean(false);

    const high_cmp = try compareAgainstOther(vm, receiver, args[1]);
    const high = high_cmp orelse {
        try comparableComparisonFailed(vm, receiver, args[1]);
        unreachable;
    };
    const high_sign = try compareSign(vm, receiver, args[1], high);
    return Value.boolean(high_sign <= 0);
}
