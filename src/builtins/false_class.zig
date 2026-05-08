const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.false_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinFalseClassToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.false_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinFalseClassInspect, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.false_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinFalseClassEqual, .{ .exact = 1 }));

    const and_sym = try vm.intern("&");
    try vm.false_class.module.methods.put(and_sym, value.MethodEntry.builtin(&builtinFalseClassAnd, .{ .exact = 1 }));

    const or_sym = try vm.intern("|");
    try vm.false_class.module.methods.put(or_sym, value.MethodEntry.builtin(&builtinFalseClassOr, .{ .exact = 1 }));

    const xor_sym = try vm.intern("^");
    try vm.false_class.module.methods.put(xor_sym, value.MethodEntry.builtin(&builtinFalseClassXor, .{ .exact = 1 }));
}

pub fn builtinFalseClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.getOrCreateCanonicalFString("false", .{ .utf8 = .{} });
}

pub fn builtinFalseClassInspect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinFalseClassToS(vm, receiver, args, block);
}

pub fn builtinFalseClassEqual(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isFalse());
}

pub fn builtinFalseClassAnd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(false);
}

pub fn builtinFalseClassOr(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].is_truthy());
}

pub fn builtinFalseClassXor(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].is_truthy());
}
