const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const equal_sym = try vm.intern("equal?");
    try vm.basic_object_class.module.methods.put(equal_sym, .{ .builtin = &builtinBasicObjectEqual });

    const not_sym = try vm.intern("!");
    try vm.basic_object_class.module.methods.put(not_sym, .{ .builtin = &builtinBasicObjectNot });
}

pub fn builtinBasicObjectEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(receiver.objectId() == args[0].objectId());
}

pub fn builtinBasicObjectNot(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(!receiver.is_truthy());
}
