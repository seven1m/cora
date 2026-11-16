const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    var to_s_entry = value.MethodEntry.builtin(&builtinTrueClassToS, .{ .exact = 0 });
    to_s_entry.original_name = to_s_sym;
    try vm.true_class.module.methods.put(to_s_sym, to_s_entry);

    const inspect_sym = try vm.intern("inspect");
    try vm.true_class.module.methods.put(inspect_sym, to_s_entry);

    const equal_sym = try vm.intern("==");
    try vm.true_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinTrueClassEqual, .{ .exact = 1 }));

    const and_sym = try vm.intern("&");
    try vm.true_class.module.methods.put(and_sym, value.MethodEntry.builtin(&builtinTrueClassAnd, .{ .exact = 1 }));

    const or_sym = try vm.intern("|");
    try vm.true_class.module.methods.put(or_sym, value.MethodEntry.builtin(&builtinTrueClassOr, .{ .exact = 1 }));

    const xor_sym = try vm.intern("^");
    try vm.true_class.module.methods.put(xor_sym, value.MethodEntry.builtin(&builtinTrueClassXor, .{ .exact = 1 }));
}

pub fn builtinTrueClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.getOrCreateCanonicalFString("true", .{ .utf8 = .{} });
}

pub fn builtinTrueClassEqual(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isTrue());
}

pub fn builtinTrueClassAnd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isTruthy());
}

pub fn builtinTrueClassOr(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(true);
}

pub fn builtinTrueClassXor(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isFalsey());
}
