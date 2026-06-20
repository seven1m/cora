const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const warning_builtin = @import("warning.zig");

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

    const key_query_sym = try vm.intern("key?");
    try env_singleton.module.methods.put(key_query_sym, value.MethodEntry.builtin(&builtinEnvInclude, .{ .exact = 1 }));

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

    const values_at_sym = try vm.intern("values_at");
    try env_singleton.module.methods.put(values_at_sym, value.MethodEntry.builtin(&builtinEnvValuesAt, .{ .variadic = 0 }));

    const key_sym = try vm.intern("key");
    try env_singleton.module.methods.put(key_sym, value.MethodEntry.builtin(&builtinEnvKey, .{ .exact = 1 }));

    const reject_sym = try vm.intern("reject");
    try env_singleton.module.methods.put(reject_sym, value.MethodEntry.builtin(&builtinEnvReject, .{ .exact = 0 }));

    const reject_bang_sym = try vm.intern("reject!");
    try env_singleton.module.methods.put(reject_bang_sym, value.MethodEntry.builtin(&builtinEnvRejectBang, .{ .exact = 0 }));

    const select_sym = try vm.intern("select");
    try env_singleton.module.methods.put(select_sym, value.MethodEntry.builtin(&builtinEnvSelect, .{ .variadic = 0 }));

    const merge_sym = try vm.intern("merge");
    try env_singleton.module.methods.put(merge_sym, value.MethodEntry.builtin(&builtinEnvMerge, .{ .variadic = 0 }));

    const update_sym = try vm.intern("update");
    try env_singleton.module.methods.put(update_sym, value.MethodEntry.builtin(&builtinEnvMerge, .{ .variadic = 0 }));

    const assoc_sym = try vm.intern("assoc");
    try env_singleton.module.methods.put(assoc_sym, value.MethodEntry.builtin(&builtinEnvAssoc, .{ .exact = 1 }));

    const rassoc_sym = try vm.intern("rassoc");
    try env_singleton.module.methods.put(rassoc_sym, value.MethodEntry.builtin(&builtinEnvRassoc, .{ .exact = 1 }));

    const clear_sym = try vm.intern("clear");
    try env_singleton.module.methods.put(clear_sym, value.MethodEntry.builtin(&builtinEnvClear, .{ .exact = 0 }));

    const empty_q_sym = try vm.intern("empty?");
    try env_singleton.module.methods.put(empty_q_sym, value.MethodEntry.builtin(&builtinEnvEmpty, .{ .exact = 0 }));

    const replace_sym = try vm.intern("replace");
    try env_singleton.module.methods.put(replace_sym, value.MethodEntry.builtin(&builtinEnvReplace, .{ .exact = 1 }));

    const except_sym = try vm.intern("except");
    try env_singleton.module.methods.put(except_sym, value.MethodEntry.builtin(&builtinEnvExcept, .{ .variadic = 0 }));

    const fetch_sym = try vm.intern("fetch");
    try env_singleton.module.methods.put(fetch_sym, value.MethodEntry.builtin(&builtinEnvFetch, .{ .variadic = 0 }));
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

pub fn builtinEnvValuesAt(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const result = try vm.createArray();
    for (args) |arg| {
        const key = try arg.coerceToStr(vm, "no implicit conversion into String");
        result.elements.append(vm.gc_allocator, try vm.envGet(key)) catch return error.Fatal;
    }
    return Value.fromObject(&result.object);
}

pub fn builtinEnvKey(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const value_to_find = try args[0].coerceToStr(vm, "no implicit conversion into String");

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*, value_to_find)) {
            return vm.newString(entry.key_ptr.*, false);
        }
    }
    return Value.nil();
}

pub fn builtinEnvReject(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (block == null) {
        var env_map = try vm.currentEnvMap();
        const size_value = Value.integer(@intCast(env_map.count()));
        env_map.deinit();
        return try vm.createMethodEnumeratorWithSize(vm.env_object.?, try vm.intern("reject"), &.{}, size_value);
    }

    const result = try vm.createHash();
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_val = try vm.newString(entry.key_ptr.*, false);
        const value_val = try vm.newString(entry.value_ptr.*, false);

        const yield_args = [_]Value{ key_val, value_val };
        const yielded = try vm.yieldToBlock(block.?, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.isFalsey()) {
            try vm.hashSetEntry(result, key_val, value_val);
        }
    }
    return Value.fromObject(&result.object);
}

pub fn builtinEnvRejectBang(vm: *VM, env_receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = env_receiver;
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        var env_map = try vm.currentEnvMap();
        const size_value = Value.integer(@intCast(env_map.count()));
        env_map.deinit();
        return try vm.createMethodEnumeratorWithSize(vm.env_object.?, try vm.intern("reject!"), &.{}, size_value);
    };

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var keys_to_delete = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer {
        for (keys_to_delete.items) |key| vm.allocator.free(key);
        keys_to_delete.deinit(vm.allocator);
    }

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_val = try vm.newString(entry.key_ptr.*, false);
        const value_val = try vm.newString(entry.value_ptr.*, false);

        const yield_args = [_]Value{ key_val, value_val };
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.isTruthy()) {
            const key_copy = vm.allocator.dupe(u8, entry.key_ptr.*) catch return error.Fatal;
            keys_to_delete.append(vm.allocator, key_copy) catch return error.Fatal;
        }
    }

    for (keys_to_delete.items) |key| {
        _ = try vm.envUnset(key, true);
    }

    if (keys_to_delete.items.len == 0) {
        return Value.nil();
    }
    return vm.env_object.?;
}

pub fn builtinEnvSelect(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    if (args.len > 0 and block == null) {
        const hash_arg = try vm.probeToHash(args[0]);
        switch (hash_arg) {
            .hash => |h| {
                const result = try vm.createHash();
                const source_hash = h.toHashObject();
                for (source_hash.entries.items) |entry| {
                    try vm.hashSetEntry(result, entry.key, entry.value);
                }
                return Value.fromObject(&result.object);
            },
            else => {},
        }
    }

    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);

    const result = try vm.createHash();
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_val = try vm.newString(entry.key_ptr.*, false);
        const value_val = try vm.newString(entry.value_ptr.*, false);

        const yield_args = [_]Value{ key_val, value_val };
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.isTruthy()) {
            try vm.hashSetEntry(result, key_val, value_val);
        }
    }
    return Value.fromObject(&result.object);
}

pub fn builtinEnvMerge(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    const result = try vm.createHash();
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_val = try vm.newString(entry.key_ptr.*, false);
        const value_val = try vm.newString(entry.value_ptr.*, false);
        try vm.hashSetEntry(result, key_val, value_val);
    }

    for (args) |arg| {
        const source_hash = (try vm.coerceToHashValue(arg)).toHashObject();

        for (source_hash.entries.items) |entry| {
            if (block) |blk| {
                const existing = try vm.hashGetEntry(result, entry.key);
                if (existing != null) {
                    const yield_args = [_]Value{ entry.key, existing.?.value, entry.value };
                    const yielded = try vm.yieldToBlock(blk, &yield_args);
                    try vm.hashSetEntry(result, entry.key, yielded.value);
                } else {
                    try vm.hashSetEntry(result, entry.key, entry.value);
                }
            } else {
                try vm.hashSetEntry(result, entry.key, entry.value);
            }
        }
    }

    return Value.fromObject(&result.object);
}

pub fn builtinEnvExcept(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const result = try vm.createHash();
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_val = try vm.newString(entry.key_ptr.*, false);
        const value_val = try vm.newString(entry.value_ptr.*, false);

        try vm.hashSetEntry(result, key_val, value_val);
    }

    for (args) |arg| {
        _ = try vm.hashDeleteEntry(result, arg);
    }

    return Value.fromObject(&result.object);
}

pub fn builtinEnvFetch(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (args.len == 2 and block != null) {
        try warning_builtin.writeWarning(vm, "warning: block supersedes default value argument\n");
    }

    const key = try args[0].coerceToStr(vm, "no implicit conversion into String");

    const value_opt = try vm.envGet(key);

    if (!value_opt.isNil()) {
        return value_opt;
    }

    if (block) |blk| {
        const yield_args = [_]Value{args[0]};
        const result = try vm.yieldToBlock(blk, &yield_args);
        return result.value;
    } else if (args.len == 2) {
        return args[1];
    } else {
        return vm.raiseExceptionFmt(vm.key_error_class, "key not found: \"{s}\"", .{key});
    }
}

pub fn builtinEnvAssoc(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const key = try args[0].coerceToStr(vm, "no implicit conversion of Object into String");
    const value_opt = try vm.envGet(key);
    if (value_opt.isNil()) return Value.nil();
    const key_val = try vm.newString(key, false);
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, key_val) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, value_opt) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinEnvRassoc(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    const string_opt = try vm.probeToStringValue(arg);
    const value_to_find: []const u8 = switch (string_opt) {
        .string => |s| s.toStringObject().str,
        .missing, .nil_result => return Value.nil(),
    };

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.*, value_to_find)) {
            const key_val = try vm.newString(entry.key_ptr.*, false);
            const value_val = try vm.newString(entry.value_ptr.*, false);
            const result = try vm.createArray();
            result.elements.append(vm.gc_allocator, key_val) catch return error.Fatal;
            result.elements.append(vm.gc_allocator, value_val) catch return error.Fatal;
            return Value.fromObject(&result.object);
        }
    }
    return Value.nil();
}

fn clearCurrentEnv(vm: *VM) VMError!void {
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var keys = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer {
        for (keys.items) |key| vm.allocator.free(key);
        keys.deinit(vm.allocator);
    }

    var iter = env_map.iterator();
    while (iter.next()) |entry| {
        const key_copy = vm.allocator.dupe(u8, entry.key_ptr.*) catch return error.Fatal;
        keys.append(vm.allocator, key_copy) catch return error.Fatal;
    }

    for (keys.items) |key| {
        _ = try vm.envUnset(key, true);
    }
}

pub fn builtinEnvClear(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try clearCurrentEnv(vm);
    return vm.env_object.?;
}

pub fn builtinEnvEmpty(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();
    return Value.boolean(env_map.count() == 0);
}

pub fn builtinEnvReplace(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const source_hash = (try vm.coerceToHashValue(args[0])).toHashObject();
    try clearCurrentEnv(vm);
    for (source_hash.entries.items) |entry| {
        const key_str = try entry.key.coerceToStr(vm, "no implicit conversion of Object into String");
        const value_str = try entry.value.coerceToStr(vm, "no implicit conversion of Object into String");
        _ = try vm.envSetString(key_str, value_str, true);
    }

    return vm.env_object.?;
}
