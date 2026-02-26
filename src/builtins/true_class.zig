const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.true_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinTrueClassToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.true_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinTrueClassInspect } });

    const equal_sym = try vm.intern("==");
    try vm.true_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinTrueClassEqual } });
}

pub fn builtinTrueClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.newString("true", false);
}

pub fn builtinTrueClassInspect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinTrueClassToS(vm, receiver, args, block);
}

pub fn builtinTrueClassEqual(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isTrue());
}
