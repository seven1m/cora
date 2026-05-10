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
    try env_singleton.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinEnvBracket, .{ .exact = 1 }));

    const bracket_set_sym = try vm.intern("[]=");
    try env_singleton.module.methods.put(bracket_set_sym, value.MethodEntry.builtin(&builtinEnvBracketSet, .{ .exact = 2 }));

    const delete_sym = try vm.intern("delete");
    try env_singleton.module.methods.put(delete_sym, value.MethodEntry.builtin(&builtinEnvDelete, .{ .exact = 1 }));

    const include_sym = try vm.intern("include?");
    try env_singleton.module.methods.put(include_sym, value.MethodEntry.builtin(&builtinEnvInclude, .{ .exact = 1 }));

    const key_sym = try vm.intern("key?");
    try env_singleton.module.methods.put(key_sym, value.MethodEntry.builtin(&builtinEnvInclude, .{ .exact = 1 }));

    const has_key_sym = try vm.intern("has_key?");
    try env_singleton.module.methods.put(has_key_sym, value.MethodEntry.builtin(&builtinEnvInclude, .{ .exact = 1 }));

    const member_sym = try vm.intern("member?");
    try env_singleton.module.methods.put(member_sym, value.MethodEntry.builtin(&builtinEnvInclude, .{ .exact = 1 }));

    const size_sym = try vm.intern("size");
    try env_singleton.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinEnvSize, .{ .exact = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try env_singleton.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinEnvToA, .{ .exact = 0 }));

    const to_hash_sym = try vm.intern("to_hash");
    try env_singleton.module.methods.put(to_hash_sym, value.MethodEntry.builtin(&builtinEnvToH, .{ .exact = 0 }));

    const to_h_sym = try vm.intern("to_h");
    try env_singleton.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinEnvToH, .{ .exact = 0 }));
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

pub fn builtinEnvDelete(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const key = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const old_value = try vm.envGet(key);
    _ = try vm.envUnset(key, true);
    return old_value;
}

pub fn builtinEnvInclude(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const key = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const value_opt = try vm.envGet(key);
    return Value.boolean(!value_opt.isNil());
}

pub fn builtinEnvSize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.envSize();
}

pub fn builtinEnvToA(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.envToArray();
}

pub fn builtinEnvToH(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.envToHash();
}
