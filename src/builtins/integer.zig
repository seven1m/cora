const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const plus_sym = try vm.intern("+");
    try vm.integer_class.module.methods.put(plus_sym, .{ .builtin = &builtinIntegerPlus });

    const minus_sym = try vm.intern("-");
    try vm.integer_class.module.methods.put(minus_sym, .{ .builtin = &builtinIntegerMinus });

    const multiply_sym = try vm.intern("*");
    try vm.integer_class.module.methods.put(multiply_sym, .{ .builtin = &builtinIntegerMultiply });

    const equal_sym = try vm.intern("==");
    try vm.integer_class.module.methods.put(equal_sym, .{ .builtin = &builtinIntegerEqual });

    const less_than_sym = try vm.intern("<");
    try vm.integer_class.module.methods.put(less_than_sym, .{ .builtin = &builtinIntegerLessThan });

    const less_than_or_equal_sym = try vm.intern("<=");
    try vm.integer_class.module.methods.put(less_than_or_equal_sym, .{ .builtin = &builtinIntegerLessThanOrEqual });

    const greater_than_sym = try vm.intern(">");
    try vm.integer_class.module.methods.put(greater_than_sym, .{ .builtin = &builtinIntegerGreaterThan });

    const greater_than_or_equal_sym = try vm.intern(">=");
    try vm.integer_class.module.methods.put(greater_than_or_equal_sym, .{ .builtin = &builtinIntegerGreaterThanOrEqual });

    const to_s_sym = try vm.intern("to_s");
    try vm.integer_class.module.methods.put(to_s_sym, .{ .builtin = &builtinIntegerToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.integer_class.module.methods.put(inspect_sym, .{ .builtin = &builtinIntegerInspect });
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
    try vm.requireArgCount(args, 0);
    const str = std.fmt.allocPrint(vm.gc_allocator, "{d}", .{receiver.data.integer}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinIntegerInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinIntegerToS(vm, receiver, args, null);
}
