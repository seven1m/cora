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
    try rbconfig_singleton.module.methods.put(expand_sym, value.MethodEntry.builtin(&builtinRbConfigExpand, .{ .exact = 0 }));

    const fire_update_sym = try vm.intern("fire_update!");
    try rbconfig_singleton.module.methods.put(fire_update_sym, value.MethodEntry.builtin(&builtinRbConfigFireUpdate, .{ .exact = 0 }));
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

    const mkconf = mkconf_val.toHashObject();
    const conf = conf_val.toHashObject();

    if (try vm.hashGetEntry(mkconf, key_val)) |existing| {
        if (existing.value.isString() and val_val.isString()) {
            if (std.mem.eql(u8, existing.value.toStringObject().str, val_val.toStringObject().str)) {
                return Value.nil();
            }
        }
    }

    try vm.hashSetEntry(mkconf, key_val, val_val);

    var changed_keys: std.ArrayList(Value) = .empty;
    defer changed_keys.deinit(vm.allocator);
    changed_keys.append(vm.allocator, key_val) catch return error.Fatal;

    while (true) {
        var new_keys: std.ArrayList(Value) = .empty;
        defer new_keys.deinit(vm.allocator);

        for (mkconf.entries.items) |entry| {
            if (!entry.value.isString()) continue;
            const entry_val_str = entry.value.toStringObject().str;

            for (changed_keys.items) |ck| {
                if (!ck.isString()) continue;
                const ck_str = ck.toStringObject().str;
                const ref_paren = std.fmt.allocPrint(vm.allocator, "$({s})", .{ck_str}) catch return error.Fatal;
                defer vm.allocator.free(ref_paren);
                const ref_brace = std.fmt.allocPrint(vm.allocator, "${{{s}}}", .{ck_str}) catch return error.Fatal;
                defer vm.allocator.free(ref_brace);

                if (std.mem.indexOf(u8, entry_val_str, ref_paren) != null or
                    std.mem.indexOf(u8, entry_val_str, ref_brace) != null)
                {
                    var already: bool = false;
                    for (changed_keys.items) |existing| {
                        if (existing.isString() and std.mem.eql(u8, existing.toStringObject().str, entry.key.toStringObject().str)) {
                            already = true;
                            break;
                        }
                    }
                    for (new_keys.items) |existing| {
                        if (existing.isString() and std.mem.eql(u8, existing.toStringObject().str, entry.key.toStringObject().str)) {
                            already = true;
                            break;
                        }
                    }
                    if (!already) {
                        new_keys.append(vm.allocator, entry.key) catch return error.Fatal;
                    }
                    break;
                }
            }
        }

        if (new_keys.items.len == 0) break;
        changed_keys.appendSlice(vm.allocator, new_keys.items) catch return error.Fatal;
    }

    for (changed_keys.items) |ck| {
        if (try vm.hashGetEntry(mkconf, ck)) |mkentry| {
            const mk_val = mkentry.value;
            try vm.hashSetEntry(conf, ck, mk_val);
            if (try vm.hashGetEntry(conf, ck)) |cfentry| {
                const expanded = data.expandValue(vm, cfentry.value, conf_val) catch return error.Fatal;
                try vm.hashSetEntry(conf, ck, expanded);
            }
        }
    }

    const result = try vm.createArray();
    for (changed_keys.items) |ck| {
        result.elements.append(vm.gc_allocator, ck) catch return error.Fatal;
    }
    return Value.fromObject(&result.object);
}
