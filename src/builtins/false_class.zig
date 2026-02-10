const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.false_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinFalseClassToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.false_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinFalseClassInspect } });

    const equal_sym = try vm.intern("==");
    try vm.false_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinFalseClassEqual } });
}

pub fn builtinFalseClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.newString("false", false);
}

pub fn builtinFalseClassInspect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinFalseClassToS(vm, receiver, args, block);
}

pub fn builtinFalseClassEqual(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].data == .boolean and args[0].data.boolean == false);
}
