const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const env_obj = vm.env_object orelse return error.Fatal;
    const env_singleton = try vm.getOrCreateSingletonClass(env_obj);

    const bracket_sym = try vm.intern("[]");
    try env_singleton.module.methods.put(bracket_sym, .{ .method = .{ .builtin = &builtinEnvBracket } });

    const bracket_set_sym = try vm.intern("[]=");
    try env_singleton.module.methods.put(bracket_set_sym, .{ .method = .{ .builtin = &builtinEnvBracketSet } });

    const to_h_sym = try vm.intern("to_h");
    try env_singleton.module.methods.put(to_h_sym, .{ .method = .{ .builtin = &builtinEnvToH } });
}

pub fn builtinEnvBracket(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const key = try args[0].coerceToStr(vm, "no implicit conversion into String");
    return vm.envGet(key);
}

pub fn builtinEnvBracketSet(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const key = try args[0].coerceToStr(vm, "no implicit conversion into String");

    if (args[1].isNil()) {
        return vm.envUnset(key, true);
    }

    const value_str = try args[1].coerceToStr(vm, "no implicit conversion into String");
    return vm.envSetString(key, value_str, true);
}

pub fn builtinEnvToH(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.envToHash();
}
