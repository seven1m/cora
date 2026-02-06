const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.nil_class.module.methods.put(to_s_sym, .{ .builtin = &builtinNilClassToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.nil_class.module.methods.put(inspect_sym, .{ .builtin = &builtinNilClassInspect });
}

pub fn builtinNilClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.newString("", false);
}

pub fn builtinNilClassInspect(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.newString("nil", false);
}
