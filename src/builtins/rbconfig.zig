const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const rbconfig_value = (try vm.resolveConstantPath("RbConfig")) orelse return;
    const rbconfig_singleton = try vm.getOrCreateSingletonClass(rbconfig_value);

    const ruby_sym = try vm.intern("ruby");
    try rbconfig_singleton.module.methods.put(ruby_sym, value.MethodEntry.builtin(&builtinRbConfigRuby, .{ .exact = 0 }));
}

pub fn builtinRbConfigRuby(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const ruby_path = vm.ruby_executable_path orelse "cora";
    return try vm.newString(ruby_path, false);
}
