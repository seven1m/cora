const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const data = @import("../rbconfig/data.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const rbconfig_value = (try vm.resolveConstantPath("RbConfig")) orelse return;
    const rbconfig_singleton = try vm.getOrCreateSingletonClass(rbconfig_value);

    const ruby_sym = try vm.intern("ruby");
    try rbconfig_singleton.module.methods.put(ruby_sym, value.MethodEntry.builtin(&builtinRbConfigRuby, .{ .exact = 0 }));

    const expand_sym = try vm.intern("expand");
    try rbconfig_singleton.module.methods.put(expand_sym, value.MethodEntry.builtin(&builtinRbConfigExpand, .{ .variadic = 1 }));

    const fire_update_sym = try vm.intern("fire_update!");
    try rbconfig_singleton.module.methods.put(fire_update_sym, value.MethodEntry.builtin(&builtinRbConfigFireUpdate, .{ .variadic = 2 }));
}

pub fn builtinRbConfigRuby(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const ruby_path = vm.ruby_executable_path orelse "cora";
    return try vm.newString(ruby_path, false);
}

pub fn builtinRbConfigExpand(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const val_arg = args[0];
    if (!val_arg.isString()) return val_arg;

    const config_val = if (args.len >= 2) args[1] else config: {
        const c = (try vm.resolveConstantPath("RbConfig::CONFIG")) orelse return val_arg;
        break :config c;
    };
    if (!config_val.isHash()) return val_arg;

    return try data.expandValue(vm, val_arg, config_val);
}

pub fn builtinRbConfigFireUpdate(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 4);

    const key_val = args[0];
    const val_val = args[1];
    if (!key_val.isString()) return Value.nil();

    const mkconf_val = if (args.len >= 3) args[2] else config: {
        const c = (try vm.resolveConstantPath("RbConfig::MAKEFILE_CONFIG")) orelse return Value.nil();
        break :config c;
    };
    const conf_val = if (args.len >= 4) args[3] else config: {
        const c = (try vm.resolveConstantPath("RbConfig::CONFIG")) orelse return Value.nil();
        break :config c;
    };

    if (!mkconf_val.isHash() or !conf_val.isHash()) return Value.nil();
    const mkconf = mkconf_val.toHashObject();

    if (try vm.hashGetEntry(mkconf, key_val)) |existing| {
        if (existing.value.isString() and val_val.isString()) {
            if (std.mem.eql(u8, existing.value.toStringObject().str, val_val.toStringObject().str)) {
                return Value.nil();
            }
        }
    }

    try vm.hashSetEntry(mkconf, key_val, val_val);
    try data.rebuildExpandedConfig(vm, mkconf_val, conf_val);
    return Value.nil();
}
