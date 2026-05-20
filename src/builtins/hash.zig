const std = @import("std");
const enc = @import("../encoding.zig");
const inspect_util = @import("../inspect.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const aggregate_hash = @import("aggregate_hash.zig");
const warning_builtin = @import("warning.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

fn coerceToProcForHashDefault(vm: *VM, proc_like: Value) VMError!*value.ProcObject {
    var proc_val = proc_like;

    if (!proc_val.isProc()) {
        proc_val = (try vm.checkCallMethodByName(proc_val, "to_proc", false, &.{}, null)) orelse {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "wrong argument type {s} (expected Proc)",
                .{vm.className(proc_val)},
            );
        };
        if (!proc_val.isProc()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} to Proc ({s}#to_proc gives {s})",
                .{
                    vm.className(proc_like),
                    vm.className(proc_like),
                    vm.className(proc_val),
                },
            );
        }
    }

    return proc_val.toProcObject();
}

fn validateHashDefaultProc(vm: *VM, proc_obj: *value.ProcObject) VMError!void {
    switch (proc_obj.block.kind) {
        .chunk => |chunk_blk| {
            const chunk_ptr = chunk_blk.chunk;
            if (chunk_ptr.is_lambda) {
                if (chunk_ptr.arity != 2 or
                    chunk_ptr.optional_params.items.len != 0 or
                    chunk_ptr.rest_param_index != null or
                    chunk_ptr.post_required_count != 0)
                {
                    return vm.raiseExceptionFmt(
                        vm.type_error_class,
                        "default_proc takes two arguments (2 for {d})",
                        .{chunk_ptr.arity},
                    );
                }
            }
        },
        else => {},
    }
}

fn hashProcCall(vm: *VM, receiver: Value, args: []Value) VMError!Value {
    return builtinHashBracket(vm, receiver, args, null);
}

fn builtinHashTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    return switch (try vm.probeToHash(args[0])) {
        .hash => |hash| hash,
        .missing, .nil_result => Value.nil(),
        .non_hash => |coerced| vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Hash ({s}#to_hash gives {s})",
            .{ vm.className(args[0]), vm.className(args[0]), vm.className(coerced) },
        ),
    };
}

pub fn register(vm: *VM) !void {
    const hash_class_val = Value.fromObject(&vm.hash_class.module.object);
    const hash_singleton = try vm.getOrCreateSingletonClass(hash_class_val);

    const try_convert_sym = try vm.intern("try_convert");
    try hash_singleton.module.methods.put(try_convert_sym, value.MethodEntry.builtin(&builtinHashTryConvert, .{ .exact = 1 }));

    const singleton_bracket_sym = try vm.intern("[]");
    try hash_singleton.module.methods.put(singleton_bracket_sym, value.MethodEntry.builtin(&builtinHashConstructor, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.hash_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinHashInitialize, .{ .variadic = 0 }, .private));

    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.hash_class.module.methods.put(initialize_copy_sym, value.MethodEntry.builtinWithVisibility(&builtinHashInitializeCopy, .{ .exact = 1 }, .private));

    const bracket_sym = try vm.intern("[]");
    try vm.hash_class.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinHashBracket, .{ .exact = 1 }));

    const bracket_set_sym = try vm.intern("[]=");
    try vm.hash_class.module.methods.put(bracket_set_sym, value.MethodEntry.builtin(&builtinHashBracketSet, .{ .exact = 2 }));

    const store_sym = try vm.intern("store");
    try vm.hash_class.module.methods.put(store_sym, value.MethodEntry.builtin(&builtinHashBracketSet, .{ .exact = 2 }));

    const keys_sym = try vm.intern("keys");
    try vm.hash_class.module.methods.put(keys_sym, value.MethodEntry.builtin(&builtinHashKeys, .{ .exact = 0 }));

    const values_sym = try vm.intern("values");
    try vm.hash_class.module.methods.put(values_sym, value.MethodEntry.builtin(&builtinHashValues, .{ .exact = 0 }));

    const values_at_sym = try vm.intern("values_at");
    try vm.hash_class.module.methods.put(values_at_sym, value.MethodEntry.builtin(&builtinHashValuesAt, .{ .variadic = 0 }));

    const fetch_values_sym = try vm.intern("fetch_values");
    try vm.hash_class.module.methods.put(fetch_values_sym, value.MethodEntry.builtin(&builtinHashFetchValues, .{ .variadic = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.hash_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinHashToA, .{ .exact = 0 }));

    const to_hash_sym = try vm.intern("to_hash");
    try vm.hash_class.module.methods.put(to_hash_sym, value.MethodEntry.builtin(&builtinHashToHash, .{ .exact = 0 }));

    const to_h_sym = try vm.intern("to_h");
    try vm.hash_class.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinHashToH, .{ .variadic = 0 }));

    const include_sym = try vm.intern("include?");
    try vm.hash_class.module.methods.put(include_sym, value.MethodEntry.builtin(&builtinHashIncludeQ, .{ .exact = 1 }));

    const has_key_sym = try vm.intern("has_key?");
    try vm.hash_class.module.methods.put(has_key_sym, value.MethodEntry.builtin(&builtinHashIncludeQ, .{ .exact = 1 }));

    const member_sym = try vm.intern("member?");
    try vm.hash_class.module.methods.put(member_sym, value.MethodEntry.builtin(&builtinHashIncludeQ, .{ .exact = 1 }));

    const key_query_sym = try vm.intern("key?");
    try vm.hash_class.module.methods.put(key_query_sym, value.MethodEntry.builtin(&builtinHashIncludeQ, .{ .exact = 1 }));

    const has_value_sym = try vm.intern("has_value?");
    try vm.hash_class.module.methods.put(has_value_sym, value.MethodEntry.builtin(&builtinHashHasValueQ, .{ .exact = 1 }));

    const value_query_sym = try vm.intern("value?");
    try vm.hash_class.module.methods.put(value_query_sym, value.MethodEntry.builtin(&builtinHashHasValueQ, .{ .exact = 1 }));

    const key_sym = try vm.intern("key");
    try vm.hash_class.module.methods.put(key_sym, value.MethodEntry.builtin(&builtinHashKey, .{ .exact = 1 }));

    const assoc_sym = try vm.intern("assoc");
    try vm.hash_class.module.methods.put(assoc_sym, value.MethodEntry.builtin(&builtinHashAssoc, .{ .exact = 1 }));

    const rassoc_sym = try vm.intern("rassoc");
    try vm.hash_class.module.methods.put(rassoc_sym, value.MethodEntry.builtin(&builtinHashRassoc, .{ .exact = 1 }));

    const size_sym = try vm.intern("size");
    try vm.hash_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinHashSize, .{ .exact = 0 }));

    const length_sym = try vm.intern("length");
    try vm.hash_class.module.methods.put(length_sym, value.MethodEntry.builtin(&builtinHashSize, .{ .exact = 0 }));

    const empty_sym = try vm.intern("empty?");
    try vm.hash_class.module.methods.put(empty_sym, value.MethodEntry.builtin(&builtinHashEmpty, .{ .exact = 0 }));

    const each_sym = try vm.intern("each");
    try vm.hash_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinHashEach, .{ .exact = 0 }));

    const each_pair_sym = try vm.intern("each_pair");
    try vm.hash_class.module.methods.put(each_pair_sym, value.MethodEntry.builtin(&builtinHashEachPair, .{ .exact = 0 }));

    const each_key_sym = try vm.intern("each_key");
    try vm.hash_class.module.methods.put(each_key_sym, value.MethodEntry.builtin(&builtinHashEachKey, .{ .exact = 0 }));

    const each_value_sym = try vm.intern("each_value");
    try vm.hash_class.module.methods.put(each_value_sym, value.MethodEntry.builtin(&builtinHashEachValue, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.hash_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinHashToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.hash_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinHashInspect, .{ .exact = 0 }));

    const invert_sym = try vm.intern("invert");
    try vm.hash_class.module.methods.put(invert_sym, value.MethodEntry.builtin(&builtinHashInvert, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.hash_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinHashEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.hash_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinHashEql, .{ .exact = 1 }));

    const hash_sym = try vm.intern("hash");
    try vm.hash_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinHashHash, .{ .exact = 0 }));

    const fetch_sym = try vm.intern("fetch");
    try vm.hash_class.module.methods.put(fetch_sym, value.MethodEntry.builtin(&builtinHashFetch, .{ .variadic = 0 }));

    const dig_sym = try vm.intern("dig");
    try vm.hash_class.module.methods.put(dig_sym, value.MethodEntry.builtin(&builtinHashDig, .{ .variadic = 0 }));

    const select_sym = try vm.intern("select");
    try vm.hash_class.module.methods.put(select_sym, value.MethodEntry.builtin(&builtinHashSelect, .{ .exact = 0 }));

    const select_bang_sym = try vm.intern("select!");
    try vm.hash_class.module.methods.put(select_bang_sym, value.MethodEntry.builtin(&builtinHashSelectBang, .{ .exact = 0 }));

    const filter_sym = try vm.intern("filter");
    try vm.hash_class.module.methods.put(filter_sym, value.MethodEntry.builtin(&builtinHashSelect, .{ .exact = 0 }));

    const filter_bang_sym = try vm.intern("filter!");
    try vm.hash_class.module.methods.put(filter_bang_sym, value.MethodEntry.builtin(&builtinHashSelectBang, .{ .exact = 0 }));

    const reject_sym = try vm.intern("reject");
    try vm.hash_class.module.methods.put(reject_sym, value.MethodEntry.builtin(&builtinHashReject, .{ .exact = 0 }));

    const reject_bang_sym = try vm.intern("reject!");
    try vm.hash_class.module.methods.put(reject_bang_sym, value.MethodEntry.builtin(&builtinHashRejectBang, .{ .exact = 0 }));

    const delete_sym = try vm.intern("delete");
    try vm.hash_class.module.methods.put(delete_sym, value.MethodEntry.builtin(&builtinHashDelete, .{ .exact = 1 }));

    const delete_if_sym = try vm.intern("delete_if");
    try vm.hash_class.module.methods.put(delete_if_sym, value.MethodEntry.builtin(&builtinHashDeleteIf, .{ .exact = 0 }));

    const keep_if_sym = try vm.intern("keep_if");
    try vm.hash_class.module.methods.put(keep_if_sym, value.MethodEntry.builtin(&builtinHashKeepIf, .{ .exact = 0 }));

    const clear_sym = try vm.intern("clear");
    try vm.hash_class.module.methods.put(clear_sym, value.MethodEntry.builtin(&builtinHashClear, .{ .exact = 0 }));

    const default_sym = try vm.intern("default");
    try vm.hash_class.module.methods.put(default_sym, value.MethodEntry.builtin(&builtinHashDefault, .{ .variadic = 0 }));

    const default_set_sym = try vm.intern("default=");
    try vm.hash_class.module.methods.put(default_set_sym, value.MethodEntry.builtin(&builtinHashDefaultSet, .{ .exact = 1 }));

    const default_proc_sym = try vm.intern("default_proc");
    try vm.hash_class.module.methods.put(default_proc_sym, value.MethodEntry.builtin(&builtinHashDefaultProc, .{ .exact = 0 }));

    const default_proc_set_sym = try vm.intern("default_proc=");
    try vm.hash_class.module.methods.put(default_proc_set_sym, value.MethodEntry.builtin(&builtinHashDefaultProcSet, .{ .exact = 1 }));

    const compare_by_identity_sym = try vm.intern("compare_by_identity");
    try vm.hash_class.module.methods.put(compare_by_identity_sym, value.MethodEntry.builtin(&builtinHashCompareByIdentity, .{ .exact = 0 }));

    const compare_by_identity_q_sym = try vm.intern("compare_by_identity?");
    try vm.hash_class.module.methods.put(compare_by_identity_q_sym, value.MethodEntry.builtin(&builtinHashCompareByIdentityQ, .{ .exact = 0 }));

    const merge_sym = try vm.intern("merge");
    try vm.hash_class.module.methods.put(merge_sym, value.MethodEntry.builtin(&builtinHashMerge, .{ .variadic = 0 }));

    const merge_bang_sym = try vm.intern("merge!");
    try vm.hash_class.module.methods.put(merge_bang_sym, value.MethodEntry.builtin(&builtinHashMergeBang, .{ .variadic = 0 }));

    const update_sym = try vm.intern("update");
    try vm.hash_class.module.methods.put(update_sym, value.MethodEntry.builtin(&builtinHashMergeBang, .{ .variadic = 0 }));

    const compact_sym = try vm.intern("compact");
    try vm.hash_class.module.methods.put(compact_sym, value.MethodEntry.builtin(&builtinHashCompact, .{ .exact = 0 }));

    const compact_bang_sym = try vm.intern("compact!");
    try vm.hash_class.module.methods.put(compact_bang_sym, value.MethodEntry.builtin(&builtinHashCompactBang, .{ .exact = 0 }));

    const shift_sym = try vm.intern("shift");
    try vm.hash_class.module.methods.put(shift_sym, value.MethodEntry.builtin(&builtinHashShift, .{ .exact = 0 }));

    const replace_sym = try vm.intern("replace");
    try vm.hash_class.module.methods.put(replace_sym, value.MethodEntry.builtin(&builtinHashReplace, .{ .variadic = 0 }));

    const transform_keys_sym = try vm.intern("transform_keys");
    try vm.hash_class.module.methods.put(transform_keys_sym, value.MethodEntry.builtin(&builtinHashTransformKeys, .{ .variadic = 0 }));

    const transform_keys_bang_sym = try vm.intern("transform_keys!");
    try vm.hash_class.module.methods.put(transform_keys_bang_sym, value.MethodEntry.builtin(&builtinHashTransformKeysBang, .{ .variadic = 0 }));

    const transform_values_sym = try vm.intern("transform_values");
    try vm.hash_class.module.methods.put(transform_values_sym, value.MethodEntry.builtin(&builtinHashTransformValues, .{ .exact = 0 }));

    const transform_values_bang_sym = try vm.intern("transform_values!");
    try vm.hash_class.module.methods.put(transform_values_bang_sym, value.MethodEntry.builtin(&builtinHashTransformValuesBang, .{ .exact = 0 }));

    const any_sym = try vm.intern("any?");
    try vm.hash_class.module.methods.put(any_sym, value.MethodEntry.builtin(&builtinHashAny, .{ .variadic = 0 }));

    const to_proc_sym = try vm.intern("to_proc");
    try vm.hash_class.module.methods.put(to_proc_sym, value.MethodEntry.builtin(&builtinHashToProc, .{ .exact = 0 }));

    const sort_sym = try vm.intern("sort");
    try vm.hash_class.module.methods.put(sort_sym, value.MethodEntry.builtin(&builtinHashSort, .{ .variadic = 0 }));

    const flatten_sym = try vm.intern("flatten");
    try vm.hash_class.module.methods.put(flatten_sym, value.MethodEntry.builtin(&builtinHashFlatten, .{ .variadic = 0 }));

    const slice_sym = try vm.intern("slice");
    try vm.hash_class.module.methods.put(slice_sym, value.MethodEntry.builtin(&builtinHashSlice, .{ .variadic = 0 }));

    const except_sym = try vm.intern("except");
    try vm.hash_class.module.methods.put(except_sym, value.MethodEntry.builtin(&builtinHashExcept, .{ .variadic = 0 }));

    const rehash_sym = try vm.intern("rehash");
    try vm.hash_class.module.methods.put(rehash_sym, value.MethodEntry.builtin(&builtinHashRehash, .{ .exact = 0 }));

    const lt_sym = try vm.intern("<");
    try vm.hash_class.module.methods.put(lt_sym, value.MethodEntry.builtin(&builtinHashLessThan, .{ .exact = 1 }));

    const lte_sym = try vm.intern("<=");
    try vm.hash_class.module.methods.put(lte_sym, value.MethodEntry.builtin(&builtinHashLessThanOrEqual, .{ .exact = 1 }));

    const gt_sym = try vm.intern(">");
    try vm.hash_class.module.methods.put(gt_sym, value.MethodEntry.builtin(&builtinHashGreaterThan, .{ .exact = 1 }));

    const gte_sym = try vm.intern(">=");
    try vm.hash_class.module.methods.put(gte_sym, value.MethodEntry.builtin(&builtinHashGreaterThanOrEqual, .{ .exact = 1 }));
}

fn hashSubsetComparison(vm: *VM, receiver: Value, other: Value, is_strict: bool) VMError!Value {
    const lhs = receiver.toHashObject();
    const other_hash = (try vm.coerceToHashValue(other)).toHashObject();

    if (is_strict and lhs.entries.items.len == other_hash.entries.items.len) {
        return Value.boolean(false);
    }

    if (lhs.entries.items.len > other_hash.entries.items.len) {
        return Value.boolean(false);
    }

    for (lhs.entries.items) |entry| {
        const other_entry = (try vm.hashGetEntry(other_hash, entry.key)) orelse return Value.boolean(false);
        if (!(try vm.hashKeysEqual(entry.value, other_entry.value))) return Value.boolean(false);
    }

    return Value.boolean(true);
}

pub fn builtinHashLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try hashSubsetComparison(vm, receiver, args[0], true);
}

pub fn builtinHashLessThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try hashSubsetComparison(vm, receiver, args[0], false);
}

pub fn builtinHashGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try hashSubsetComparison(vm, args[0], receiver, true);
}

pub fn builtinHashGreaterThanOrEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return try hashSubsetComparison(vm, args[0], receiver, false);
}

fn hashGetValue(hash_obj: *value.HashObject, vm: *VM, key: Value) VMError!?Value {
    const entry = (try vm.hashGetEntry(hash_obj, key)) orelse return null;
    return entry.value;
}

fn ensureMutableHash(vm: *VM, receiver: Value) VMError!void {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Hash", .{});
    }
}

fn clearHashDefaultBehavior(hash_obj: *value.HashObject) void {
    hash_obj.default_value = null;
    hash_obj.default_proc = null;
}

fn setHashDefaultValue(hash_obj: *value.HashObject, default_value: Value) void {
    hash_obj.default_value = default_value;
    hash_obj.default_proc = null;
}

fn setHashDefaultProc(hash_obj: *value.HashObject, proc_obj: *value.ProcObject) void {
    hash_obj.default_proc = proc_obj;
    hash_obj.default_value = null;
}

fn copyHashEntries(vm: *VM, target: *value.HashObject, source: *value.HashObject) VMError!void {
    for (source.entries.items) |entry| {
        try vm.hashSetEntry(target, entry.key, entry.value);
    }
}

fn mergeEntriesIntoHash(
    vm: *VM,
    target: *value.HashObject,
    source: *value.HashObject,
    block: ?Block,
) VMError!void {
    for (source.entries.items) |entry| {
        if (block) |blk| {
            const key = entry.key;
            const existing = try hashGetValue(target, vm, key);
            if (existing) |old_val| {
                const yield_args = [_]Value{ key, old_val, entry.value };
                const yielded = try vm.yieldToBlock(blk, &yield_args);
                try vm.hashSetEntry(target, key, yielded.value);
            } else {
                try vm.hashSetEntry(target, key, entry.value);
            }
        } else {
            try vm.hashSetEntry(target, entry.key, entry.value);
        }
    }
}

fn copyHashProperties(target: *value.HashObject, source: *value.HashObject) void {
    target.compare_by_identity = source.compare_by_identity;
    if (source.default_proc) |default_proc| {
        setHashDefaultProc(target, default_proc);
    } else if (source.default_value) |default_value| {
        setHashDefaultValue(target, default_value);
    }
}

fn replaceHashFrom(vm: *VM, hash_obj: *value.HashObject, source_hash: *value.HashObject) VMError!void {
    hash_obj.entries.clearRetainingCapacity();
    hash_obj.map.clearRetainingCapacity();
    clearHashDefaultBehavior(hash_obj);
    try copyHashEntries(vm, hash_obj, source_hash);
    copyHashProperties(hash_obj, source_hash);
}

fn replaceHashEntriesOnly(vm: *VM, hash_obj: *value.HashObject, source_hash: *value.HashObject) VMError!void {
    hash_obj.entries.clearRetainingCapacity();
    hash_obj.map.clearRetainingCapacity();
    try copyHashEntries(vm, hash_obj, source_hash);
}

fn coerceTransformMappingHash(vm: *VM, args: []Value) VMError!?*value.HashObject {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 0) return null;
    return (try vm.coerceToHashValue(args[0])).toHashObject();
}

fn hashConstructorElementTypeName(vm: *VM, element: Value) []const u8 {
    if (element.isNil()) return "nil";
    return vm.className(element);
}

fn populateHashFromPairsArray(vm: *VM, target: *value.HashObject, array_obj: *value.ArrayObject) VMError!void {
    for (array_obj.elements.items, 0..) |element, idx| {
        const pair_value = switch (try vm.probeToAry(element)) {
            .array => |array| array,
            .missing, .nil_result => {
                return vm.raiseExceptionFmt(
                    vm.argument_error_class,
                    "wrong element type {s} at {d} (expected array)",
                    .{ hashConstructorElementTypeName(vm, element), idx },
                );
            },
        };

        const pair = pair_value.toArrayObject().elements.items;
        if (pair.len < 1 or pair.len > 2) {
            return vm.raiseExceptionFmt(
                vm.argument_error_class,
                "invalid number of elements ({d} for 1..2)",
                .{pair.len},
            );
        }

        const value_to_set = if (pair.len == 2) pair[1] else Value.nil();
        try vm.hashSetEntry(target, pair[0], value_to_set);
    }
}

pub fn builtinHashConstructor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }

    const result = try vm.newObjectForClass(receiver.toClassObject());
    const hash_obj = result.toHashObject();

    if (args.len == 0) {
        if (try vm.consumeKeywordArgHash()) |keyword_hash| {
            try copyHashEntries(vm, hash_obj, keyword_hash.toHashObject());
        }
        return result;
    }

    if (args.len == 1) {
        switch (try vm.probeToHash(args[0])) {
            .hash => |source_hash| {
                try copyHashEntries(vm, hash_obj, source_hash.toHashObject());
                return result;
            },
            .non_hash => |coerced| {
                return vm.raiseExceptionFmt(
                    vm.type_error_class,
                    "can't convert {s} to Hash ({s}#to_hash gives {s})",
                    .{ vm.className(args[0]), vm.className(args[0]), vm.className(coerced) },
                );
            },
            .missing, .nil_result => {},
        }

        switch (try vm.probeToAry(args[0])) {
            .array => |array_value| {
                try populateHashFromPairsArray(vm, hash_obj, array_value.toArrayObject());
                return result;
            },
            .missing, .nil_result => {
                return vm.raiseExceptionFmt(
                    vm.type_error_class,
                    "can't convert {s} into Hash",
                    .{vm.className(args[0])},
                );
            },
        }
    }

    if (args.len % 2 != 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "odd number of arguments for Hash", .{});
    }

    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        try vm.hashSetEntry(hash_obj, args[i], args[i + 1]);
    }
    return result;
}

fn digIntoValue(vm: *VM, current_value: Value, remaining_args: []Value) VMError!Value {
    if (remaining_args.len == 0) return current_value;
    if (current_value.isNil()) return Value.nil();

    if (!try vm.respondsToMethodByName(current_value, "dig", false)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} does not have #dig method", .{vm.className(current_value)});
    }

    return vm.callMethodByName(current_value, "dig", remaining_args, null);
}

fn yieldHashEntryPair(vm: *VM, blk: Block, entry: value.HashEntry) VMError!VM.YieldResult {
    const pair = try vm.createArray();
    pair.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
    pair.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
    const pair_value = Value.fromObject(&pair.object);

    const yielded = switch (blk.kind) {
        .chunk => |chunk_blk| blk_result: {
            if (chunk_blk.chunk.is_lambda or chunk_blk.chunk.rest_param_index != null) {
                const yield_args = [_]Value{pair_value};
                break :blk_result try vm.yieldToBlock(blk, &yield_args);
            }

            const yield_args = [_]Value{ entry.key, entry.value };
            break :blk_result try vm.yieldToBlock(blk, &yield_args);
        },
        .receiver_builtin, .symbol, .builtin, .callable => blk_result: {
            const yield_args = [_]Value{pair_value};
            break :blk_result try vm.yieldToBlock(blk, &yield_args);
        },
    };

    return yielded;
}

pub fn builtinHashInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 1 and block != null) {
        return vm.raiseArgumentErrorWrongArgCount(args.len, 0);
    }
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    clearHashDefaultBehavior(hash_obj);

    if (block) |blk| {
        const proc_val = try vm.procValueForBlock(blk);
        setHashDefaultProc(hash_obj, proc_val.toProcObject());
    } else if (args.len == 1) {
        setHashDefaultValue(hash_obj, args[0]);
    }

    return receiver;
}

pub fn builtinHashInitializeCopy(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (receiver.objectId() == args[0].objectId()) {
        return receiver;
    }

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Hash", .{});
    }

    const source = args[0].toHashObject();
    const target = receiver.toHashObject();
    target.entries.clearRetainingCapacity();
    target.map.clearRetainingCapacity();
    clearHashDefaultBehavior(target);
    target.compare_by_identity = source.compare_by_identity;
    if (source.default_proc) |default_proc| {
        setHashDefaultProc(target, default_proc);
    } else if (source.default_value) |default_value| {
        setHashDefaultValue(target, default_value);
    }
    try copyHashEntries(vm, target, source);
    return receiver;
}

pub fn builtinHashShift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    if (hash_obj.entries.items.len == 0) {
        return Value.nil();
    }

    const first_entry = hash_obj.entries.orderedRemove(0);
    try vm.hashRebuildIndexes(hash_obj);

    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, first_entry.key) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, first_entry.value) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinHashBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.toHashObject();
    const key = args[0];
    if (try hashGetValue(hash_obj, vm, key)) |found| {
        return found;
    }

    var default_args = [_]Value{key};
    return vm.callMethodByName(receiver, "default", default_args[0..], null);
}

pub fn builtinHashDefault(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const hash_obj = receiver.toHashObject();
    if (args.len == 1) {
        if (hash_obj.default_proc) |default_proc| {
            const call_args = [_]Value{ receiver, args[0] };
            return vm.callProcObject(default_proc, call_args[0..], null, null);
        }
    }
    return hash_obj.default_value orelse Value.nil();
}

pub fn builtinHashDefaultSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try ensureMutableHash(vm, receiver);
    const hash_obj = receiver.toHashObject();
    setHashDefaultValue(hash_obj, args[0]);
    return args[0];
}

pub fn builtinHashDefaultProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    if (hash_obj.default_proc) |default_proc| {
        return Value.fromObject(&default_proc.object);
    }
    return Value.nil();
}

pub fn builtinHashDefaultProcSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    if (args[0].isNil()) {
        hash_obj.default_proc = null;
        return Value.nil();
    }

    const proc_obj = try coerceToProcForHashDefault(vm, args[0]);
    try validateHashDefaultProc(vm, proc_obj);

    setHashDefaultProc(hash_obj, proc_obj);
    return args[0];
}

pub fn builtinHashCompareByIdentity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try ensureMutableHash(vm, receiver);
    receiver.toHashObject().compare_by_identity = true;
    return receiver;
}

pub fn builtinHashCompareByIdentityQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toHashObject().compare_by_identity);
}

pub fn builtinHashBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    const new_value = args[1];
    try vm.hashSetEntry(hash_obj, args[0], new_value);
    return new_value;
}

pub fn builtinHashDelete(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Hash", .{});
    }

    const hash_obj = receiver.toHashObject();
    const deleted = try vm.hashDeleteEntry(hash_obj, args[0]) orelse {
        if (block) |blk| {
            const yielded = try vm.yieldToBlock(blk, &.{});
            return yielded.value;
        }
        return Value.nil();
    };
    return deleted;
}

fn hashFilterBangShared(
    vm: *VM,
    receiver: Value,
    args: []Value,
    block: ?Block,
    method_name: []const u8,
    delete_if_truthy: bool,
    return_nil_if_unchanged: bool,
) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toHashObject().entries.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern(method_name), &.{}, size_value);
    };
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    var changed = false;
    for (snapshot) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;

        const should_delete = if (delete_if_truthy) yielded.value.is_truthy() else !yielded.value.is_truthy();
        if (should_delete) {
            _ = try vm.hashDeleteEntry(hash_obj, entry.key);
            changed = true;
        }
    }

    if (return_nil_if_unchanged and !changed) {
        return Value.nil();
    }

    return receiver;
}

pub fn builtinHashDeleteIf(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return hashFilterBangShared(vm, receiver, args, block, "delete_if", true, false);
}

pub fn builtinHashKeepIf(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return hashFilterBangShared(vm, receiver, args, block, "keep_if", false, false);
}

pub fn builtinHashRejectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return hashFilterBangShared(vm, receiver, args, block, "reject!", true, true);
}

pub fn builtinHashClear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    hash_obj.entries.clearRetainingCapacity();
    hash_obj.map.clearRetainingCapacity();
    return receiver;
}

pub fn builtinHashReplace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();

    if (vm.keywordArgsGiven()) {
        const kw_hash = try vm.consumeKeywordArgHash();
        if (kw_hash) |kh| {
            try vm.requireArgCount(args, 0);
            try replaceHashFrom(vm, hash_obj, kh.toHashObject());
        } else {
            try vm.requireArgCount(args, 1);
            const source_hash = (try vm.coerceToHashValue(args[0])).toHashObject();
            try replaceHashFrom(vm, hash_obj, source_hash);
        }
    } else {
        try vm.requireArgCount(args, 1);
        const source_hash = (try vm.coerceToHashValue(args[0])).toHashObject();
        try replaceHashFrom(vm, hash_obj, source_hash);
    }

    return receiver;
}

pub fn builtinHashTransformKeys(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const mapping_hash = try coerceTransformMappingHash(vm, args);
    if (mapping_hash == null and block == null) {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("transform_keys"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    }

    const result_hash = try vm.createHash();
    const hash_obj = receiver.toHashObject();

    for (hash_obj.entries.items) |entry| {
        const new_key = if (mapping_hash) |mapping|
            (try hashGetValue(mapping, vm, entry.key)) orelse blk: {
                if (block) |blk| {
                    const yielded = try vm.yieldToBlock(blk, &[_]Value{entry.key});
                    if (yielded.controlFlowValue()) |return_value| return return_value;
                    break :blk yielded.value;
                }
                break :blk entry.key;
            }
        else blk: {
            const yielded = try vm.yieldToBlock(block.?, &[_]Value{entry.key});
            if (yielded.controlFlowValue()) |return_value| return return_value;
            break :blk yielded.value;
        };
        try vm.hashSetEntry(result_hash, new_key, entry.value);
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashTransformKeysBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const mapping_hash = try coerceTransformMappingHash(vm, args);
    if (mapping_hash == null and block == null) {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("transform_keys!"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    }
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    const transformed = try vm.createHash();
    transformed.compare_by_identity = hash_obj.compare_by_identity;

    for (snapshot, 0..) |entry, idx| {
        const new_key = if (mapping_hash) |mapping|
            (try hashGetValue(mapping, vm, entry.key)) orelse blk: {
                if (block) |blk| {
                    const yielded = try vm.yieldToBlock(blk, &[_]Value{entry.key});
                    if (yielded.non_local_return_occurred) {
                        try replaceHashEntriesOnly(vm, hash_obj, transformed);
                        return yielded.value;
                    }
                    if (yielded.break_occurred) {
                        for (snapshot[idx..]) |remaining| {
                            if ((try vm.hashFindEntryIndex(transformed, remaining.key)) == null) {
                                try vm.hashSetEntry(transformed, remaining.key, remaining.value);
                            }
                        }
                        try replaceHashEntriesOnly(vm, hash_obj, transformed);
                        return yielded.value;
                    }
                    break :blk yielded.value;
                }
                break :blk entry.key;
            }
        else blk: {
            const yielded = try vm.yieldToBlock(block.?, &[_]Value{entry.key});
            if (yielded.non_local_return_occurred) {
                try replaceHashEntriesOnly(vm, hash_obj, transformed);
                return yielded.value;
            }
            if (yielded.break_occurred) {
                for (snapshot[idx..]) |remaining| {
                    if ((try vm.hashFindEntryIndex(transformed, remaining.key)) == null) {
                        try vm.hashSetEntry(transformed, remaining.key, remaining.value);
                    }
                }
                try replaceHashEntriesOnly(vm, hash_obj, transformed);
                return yielded.value;
            }
            break :blk yielded.value;
        };
        try vm.hashSetEntry(transformed, new_key, entry.value);
    }

    try replaceHashEntriesOnly(vm, hash_obj, transformed);
    return receiver;
}

pub fn builtinHashTransformValues(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("transform_values"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };

    const result_hash = try vm.createHash();
    const hash_obj = receiver.toHashObject();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;
    for (hash_obj.entries.items) |entry| {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{entry.value});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        try vm.hashSetEntry(result_hash, entry.key, yielded.value);
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashTransformValuesBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("transform_values!"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    try ensureMutableHash(vm, receiver);

    const hash_obj = receiver.toHashObject();
    var idx: usize = 0;
    while (idx < hash_obj.entries.items.len) : (idx += 1) {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{hash_obj.entries.items[idx].value});
        if (yielded.non_local_return_occurred or yielded.break_occurred) {
            return yielded.value;
        }
        hash_obj.entries.items[idx].value = yielded.value;
    }

    return receiver;
}

pub fn builtinHashKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
    array_obj.* = .{
        .object = .{ .type_tag = .array, .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
        .elements = .empty,
    };

    for (hash_obj.entries.items) |entry| {
        array_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
    }

    return Value.fromObject(&array_obj.object);
}

pub fn builtinHashValues(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
    array_obj.* = .{
        .object = .{ .type_tag = .array, .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
        .elements = .empty,
    };

    for (hash_obj.entries.items) |entry| {
        array_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
    }

    return Value.fromObject(&array_obj.object);
}

pub fn builtinHashValuesAt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const hash_obj = receiver.toHashObject();
    const array_obj = try vm.createArray();

    for (args) |arg| {
        const value_at_key = if (try hashGetValue(hash_obj, vm, arg)) |found|
            found
        else blk: {
            var default_args = [_]Value{arg};
            break :blk try vm.callMethodByName(receiver, "default", default_args[0..], null);
        };
        array_obj.elements.append(vm.gc_allocator, value_at_key) catch return error.Fatal;
    }

    return Value.fromObject(&array_obj.object);
}

pub fn builtinHashFetchValues(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 256);
    const hash_obj = receiver.toHashObject();
    const array_obj = try vm.createArray();

    for (args) |arg| {
        if (try hashGetValue(hash_obj, vm, arg)) |found| {
            array_obj.elements.append(vm.gc_allocator, found) catch return error.Fatal;
        } else if (block) |blk| {
            const yield_args = [_]Value{arg};
            const result = try vm.yieldToBlock(blk, &yield_args);
            array_obj.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
        } else {
            const key_str = try arg.inspect(vm);
            const exc = try vm.createException(
                vm.key_error_class,
                std.fmt.allocPrint(vm.gc_allocator, "key not found: {s}", .{key_str.toStringObject().str}) catch return error.Fatal,
            );
            exc.receiver = receiver;
            exc.key = arg;
            vm.setPendingException(exc);
            return error.Unwind;
        }
    }

    return Value.fromObject(&array_obj.object);
}

pub fn builtinHashToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    const array_obj = try vm.createArray();

    for (hash_obj.entries.items) |entry| {
        const pair_obj = try vm.createArray();
        pair_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
        pair_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
        array_obj.elements.append(vm.gc_allocator, Value.fromObject(&pair_obj.object)) catch return error.Fatal;
    }

    return Value.fromObject(&array_obj.object);
}

pub fn builtinHashInvert(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const result_hash = try vm.createHash();

    for (receiver.toHashObject().entries.items) |entry| {
        try vm.hashSetEntry(result_hash, entry.value, entry.key);
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashToHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinHashToH(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (receiver.toHashObject().object.class != vm.hash_class) {
        const hash_obj = receiver.toHashObject();
        const result_hash = try vm.createHash();
        result_hash.compare_by_identity = hash_obj.compare_by_identity;
        if (hash_obj.default_proc) |default_proc| {
            setHashDefaultProc(result_hash, default_proc);
        } else if (hash_obj.default_value) |default_value| {
            setHashDefaultValue(result_hash, default_value);
        }
        for (hash_obj.entries.items) |entry| {
            try vm.hashSetEntry(result_hash, entry.key, entry.value);
        }
        return Value.fromObject(&result_hash.object);
    }

    if (block) |blk| {
        const hash_obj = receiver.toHashObject();
        const result_hash = try vm.createHash();

        for (hash_obj.entries.items) |entry| {
            const yield_args = [_]Value{ entry.key, entry.value };
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;

            const pair_value = switch (try vm.probeToAry(yielded.value)) {
                .array => |array_value| array_value,
                .missing, .nil_result => {
                    return vm.raiseExceptionFmt(
                        vm.type_error_class,
                        "wrong element type {s} at {d} (expected array)",
                        .{ vm.className(yielded.value), 0 },
                    );
                },
            };

            const pair = pair_value.toArrayObject().elements.items;
            if (pair.len != 2) {
                return vm.raiseExceptionFmt(
                    vm.argument_error_class,
                    "element has wrong array length at {d} (expected 2, was {d})",
                    .{ 0, pair.len },
                );
            }

            try vm.hashSetEntry(result_hash, pair[0], pair[1]);
        }

        return Value.fromObject(&result_hash.object);
    }

    return receiver;
}

pub fn builtinHashIncludeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean((try vm.hashFindEntryIndex(receiver.toHashObject(), args[0])) != null);
}

pub fn builtinHashHasValueQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.toHashObject();
    const needle = args[0];

    for (hash_obj.entries.items) |entry| {
        if (try vm.valueEquals(entry.value, needle)) {
            return Value.boolean(true);
        }
    }

    return Value.boolean(false);
}

pub fn builtinHashKey(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const needle = args[0];
    const hash_obj = receiver.toHashObject();

    for (hash_obj.entries.items) |entry| {
        if (try vm.valueEquals(entry.value, needle)) {
            return entry.key;
        }
    }

    return Value.nil();
}

pub fn builtinHashAssoc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.toHashObject();
    const needle = args[0];

    for (hash_obj.entries.items) |entry| {
        if (try vm.valueEquals(entry.key, needle)) {
            const pair_obj = try vm.createArray();
            pair_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
            pair_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
            return Value.fromObject(&pair_obj.object);
        }
    }

    return Value.nil();
}

pub fn builtinHashRassoc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.toHashObject();
    const needle = args[0];

    for (hash_obj.entries.items) |entry| {
        if (try vm.valueEquals(entry.value, needle)) {
            const pair_obj = try vm.createArray();
            pair_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
            pair_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
            return Value.fromObject(&pair_obj.object);
        }
    }

    return Value.nil();
}

pub fn builtinHashSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.toHashObject().entries.items.len));
}

pub fn builtinHashEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toHashObject().entries.items.len == 0);
}

pub fn builtinHashEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each"), &.{}, Value.integer(@intCast(receiver.toHashObject().entries.items.len)));
    };
    const hash_obj = receiver.toHashObject();

    // Iterate in insertion order
    for (hash_obj.entries.items) |entry| {
        const result = try yieldHashEntryPair(vm, blk, entry);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinHashEachPair(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("each_pair"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    for (snapshot) |entry| {
        const result = try yieldHashEntryPair(vm, blk, entry);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinHashEachKey(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("each_key"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    for (snapshot) |entry| {
        const yield_args = [_]Value{entry.key};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinHashEachValue(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("each_value"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    for (snapshot) |entry| {
        const yield_args = [_]Value{entry.value};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinHashToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (try vm.enterRecursionGuard(.hash_inspect, receiver, Value.nil())) {
        return try vm.newStringWithEncoding("{...}", false, .{ .us_ascii = .{} });
    }
    defer vm.leaveRecursionGuard(.hash_inspect, receiver, Value.nil());

    const hash_obj = receiver.toHashObject();
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    var output_encoding: enc.Encoding = .{ .us_ascii = .{} };
    var has_dynamic_part = false;
    const target_encoding = vm.inspectTargetEncoding();

    writer.writeAll("{") catch return error.Fatal;
    for (hash_obj.entries.items, 0..) |entry, idx| {
        if (idx > 0) {
            writer.writeAll(", ") catch return error.Fatal;
        }

        // Check if key is a symbol - use shorthand syntax
        if (entry.key.isSymbol()) {
            const sym = entry.key.toSymbolObject();
            const quote_symbol = !inspect_util.isBareHashKeySymbol(sym, target_encoding);
            const key_bytes = if (quote_symbol)
                inspect_util.inspectStringBytes(vm.allocator, sym.name, sym.encoding, target_encoding) catch return error.Fatal
            else
                sym.name;
            defer if (quote_symbol) vm.allocator.free(key_bytes);
            const key_encoding = if (quote_symbol) target_encoding else sym.encoding;

            if (!has_dynamic_part) {
                output_encoding = key_encoding;
                has_dynamic_part = true;
            } else {
                output_encoding = enc.negotiate(output_encoding, buf.written(), key_encoding, key_bytes) orelse {
                    return vm.raiseEncodingCompatibilityError(output_encoding, key_encoding);
                };
            }
            writer.writeAll(key_bytes) catch return error.Fatal;
            writer.writeAll(": ") catch return error.Fatal;
        } else {
            // Call inspect on non-symbol keys
            const key_val = try entry.key.inspect(vm);
            const key_obj = key_val.toStringObject();
            if (!has_dynamic_part) {
                output_encoding = key_obj.encoding;
                has_dynamic_part = true;
            } else {
                output_encoding = enc.negotiate(output_encoding, buf.written(), key_obj.encoding, key_obj.str) orelse {
                    return vm.raiseEncodingCompatibilityError(output_encoding, key_obj.encoding);
                };
            }
            writer.writeAll(key_val.toStringObject().str) catch return error.Fatal;
            writer.writeAll(" => ") catch return error.Fatal;
        }

        // Call inspect on value
        const value_val = try entry.value.inspect(vm);
        const value_obj = value_val.toStringObject();
        if (!has_dynamic_part) {
            output_encoding = value_obj.encoding;
            has_dynamic_part = true;
        } else {
            output_encoding = enc.negotiate(output_encoding, buf.written(), value_obj.encoding, value_obj.str) orelse {
                return vm.raiseEncodingCompatibilityError(output_encoding, value_obj.encoding);
            };
        }
        writer.writeAll(value_obj.str) catch return error.Fatal;
    }
    writer.writeAll("}") catch return error.Fatal;

    const final_str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(final_str);
    return try vm.newStringWithEncoding(final_str, false, output_encoding);
}

pub fn builtinHashEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isHash()) return Value.boolean(false);

    const lhs = receiver.toHashObject();
    const rhs = args[0].toHashObject();
    if (lhs == rhs) return Value.boolean(true);
    if (try vm.enterRecursionGuard(.hash_equal, receiver, args[0])) {
        return Value.boolean(true);
    }
    defer vm.leaveRecursionGuard(.hash_equal, receiver, args[0]);
    if (lhs.entries.items.len != rhs.entries.items.len) return Value.boolean(false);

    for (lhs.entries.items) |entry| {
        const rhs_entry = (try vm.hashGetEntry(rhs, entry.key)) orelse return Value.boolean(false);
        if (!(try vm.valueEquals(entry.value, rhs_entry.value))) return Value.boolean(false);
    }

    return Value.boolean(true);
}

pub fn builtinHashEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isHash()) return Value.boolean(false);

    const lhs = receiver.toHashObject();
    const rhs = args[0].toHashObject();
    if (lhs == rhs) return Value.boolean(true);
    if (try vm.enterRecursionGuard(.hash_eql, receiver, args[0])) {
        return Value.boolean(true);
    }
    defer vm.leaveRecursionGuard(.hash_eql, receiver, args[0]);
    if (lhs.entries.items.len != rhs.entries.items.len) return Value.boolean(false);

    for (lhs.entries.items) |entry| {
        const rhs_entry = (try vm.hashGetEntry(rhs, entry.key)) orelse return Value.boolean(false);
        if (!(try vm.hashKeysEqual(entry.value, rhs_entry.value))) return Value.boolean(false);
    }

    return Value.boolean(true);
}

pub fn builtinHashHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const result = try aggregate_hash.structuralHashHash(vm, receiver);
    return Value.integer(@bitCast(result.hash));
}

pub fn builtinHashInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try builtinHashToS(vm, receiver, args, null);
}

pub fn builtinHashFetch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (args.len == 2 and block != null) {
        try warning_builtin.writeWarning(vm, "warning: block supersedes default value argument\n");
    }

    const hash_obj = receiver.toHashObject();
    const key = args[0];

    if (try hashGetValue(hash_obj, vm, key)) |found| {
        return found;
    }

    // Key not found - use default value or block
    if (block) |blk| {
        const yield_args = [_]Value{key};
        const result = try vm.yieldToBlock(blk, &yield_args);
        return result.value;
    } else if (args.len == 2) {
        return args[1];
    } else {
        const key_str = try key.inspect(vm);
        const exc = try vm.createException(
            vm.key_error_class,
            std.fmt.allocPrint(vm.gc_allocator, "key not found: {s}", .{key_str.toStringObject().str}) catch return error.Fatal,
        );
        exc.receiver = receiver;
        exc.key = key;
        vm.setPendingException(exc);
        return error.Unwind;
    }
}

pub fn builtinHashDig(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const current_value = try vm.callMethodByName(receiver, "[]", args[0..1], null);
    return digIntoValue(vm, current_value, args[1..]);
}

pub fn builtinHashSelect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("select"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    const hash_obj = receiver.toHashObject();

    const result_hash = try vm.createHash();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;

    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;

        if (result.value.is_truthy()) {
            try vm.hashSetEntry(result_hash, entry.key, entry.value);
        }
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashSelectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return hashFilterBangShared(vm, receiver, args, block, "select!", false, true);
}

pub fn builtinHashCompact(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    const result_hash = try vm.createHash();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;
    if (hash_obj.default_proc) |default_proc| {
        setHashDefaultProc(result_hash, default_proc);
    } else if (hash_obj.default_value) |default_value| {
        setHashDefaultValue(result_hash, default_value);
    }
    for (hash_obj.entries.items) |entry| {
        if (!entry.value.isNil()) {
            try vm.hashSetEntry(result_hash, entry.key, entry.value);
        }
    }
    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashCompactBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try ensureMutableHash(vm, receiver);
    const hash_obj = receiver.toHashObject();
    var changed = false;
    var i: usize = 0;
    while (i < hash_obj.entries.items.len) {
        const entry = hash_obj.entries.items[i];
        if (entry.value.isNil()) {
            _ = try vm.hashDeleteEntry(hash_obj, entry.key);
            changed = true;
        } else {
            i += 1;
        }
    }
    if (!changed) {
        return Value.nil();
    }
    return receiver;
}

pub fn builtinHashToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.newProc(.{ .kind = .{ .receiver_builtin = .{
        .receiver = receiver,
        .func = &hashProcCall,
        .arity = 1,
    } } });
}

pub fn builtinHashReject(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("reject"),
            &.{},
            Value.integer(@intCast(receiver.toHashObject().entries.items.len)),
        );
    };
    const hash_obj = receiver.toHashObject();
    const keep_entries = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(keep_entries);
    var keep_count: usize = 0;

    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;

        if (!result.value.is_truthy()) {
            keep_entries[keep_count] = entry;
            keep_count += 1;
        }
    }

    const result_hash = try vm.createHash();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;
    for (keep_entries[0..keep_count]) |entry| {
        try vm.hashSetEntry(result_hash, entry.key, entry.value);
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashMerge(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const result = try vm.newObjectForClass(vm.getClass(receiver));
    const result_hash = result.toHashObject();
    try copyHashEntries(vm, result_hash, receiver.toHashObject());

    const hash_obj = receiver.toHashObject();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;
    if (hash_obj.default_proc) |default_proc| {
        setHashDefaultProc(result_hash, default_proc);
    } else if (hash_obj.default_value) |default_value| {
        setHashDefaultValue(result_hash, default_value);
    }

    if (vm.keywordArgsGiven()) {
        const kw_hash = try vm.consumeKeywordArgHash();
        if (kw_hash) |kh| {
            try mergeEntriesIntoHash(vm, result_hash, kh.toHashObject(), block);
        }
    }

    for (args) |arg| {
        const source_hash = (try vm.coerceToHashValue(arg)).toHashObject();

        try mergeEntriesIntoHash(vm, result_hash, source_hash, block);
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashMergeBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try ensureMutableHash(vm, receiver);
    const hash_obj = receiver.toHashObject();

    if (vm.keywordArgsGiven()) {
        const kw_hash = try vm.consumeKeywordArgHash();
        if (kw_hash) |kh| {
            try mergeEntriesIntoHash(vm, hash_obj, kh.toHashObject(), block);
        }
    }

    for (args) |arg| {
        const source_hash = (try vm.coerceToHashValue(arg)).toHashObject();

        try mergeEntriesIntoHash(vm, hash_obj, source_hash, block);
    }

    return receiver;
}

pub fn builtinHashAny(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const hash_obj = receiver.toHashObject();
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    if (pattern) |pat| {
        for (hash_obj.entries.items) |entry| {
            const pair = try vm.createArray();
            pair.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
            pair.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
            var pattern_args = [_]Value{Value.fromObject(&pair.object)};
            const matched = try vm.callMethodByName(pat, "===", pattern_args[0..], null);
            if (matched.is_truthy()) {
                return Value.boolean(true);
            }
        }
        return Value.boolean(false);
    }

    if (block) |blk| {
        for (hash_obj.entries.items) |entry| {
            const yield_args = [_]Value{ entry.key, entry.value };
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            if (yielded.value.is_truthy()) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    return Value.boolean(hash_obj.entries.items.len > 0);
}

pub fn builtinHashSort(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    const result = try vm.createArray();

    for (hash_obj.entries.items) |entry| {
        const pair_obj = try vm.createArray();
        pair_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
        pair_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, Value.fromObject(&pair_obj.object)) catch return error.Fatal;
    }

    const sorted = try vm.callMethodByName(Value.fromObject(&result.object), "sort", &.{}, block);
    return sorted;
}

pub fn builtinHashFlatten(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const hash_obj = receiver.toHashObject();
    const result = try vm.createArray();

    for (hash_obj.entries.items) |entry| {
        result.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
        result.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
    }

    if (args.len == 0) {
        return Value.fromObject(&result.object);
    }

    const depth = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (depth < 0) {
        return Value.fromObject(&result.object);
    }
    if (depth == 0) {
        return Value.fromObject(&result.object);
    }

    const result_ref = Value.fromObject(&result.object);
    if (depth == 1) {
        return result_ref;
    }

    var depth_arg: [1]Value = .{Value.integer(depth - 1)};
    const flattened = try vm.callMethodByName(result_ref, "flatten", &depth_arg, null);
    return flattened;
}

pub fn builtinHashSlice(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 256);

    const hash_obj = receiver.toHashObject();
    const result_hash = try vm.createHash();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;

    for (args) |key| {
        if (try hashGetValue(hash_obj, vm, key)) |found| {
            try vm.hashSetEntry(result_hash, key, found);
        }
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashExcept(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 256);

    const hash_obj = receiver.toHashObject();
    const result_hash = try vm.createHash();
    result_hash.compare_by_identity = hash_obj.compare_by_identity;

    for (hash_obj.entries.items) |entry| {
        var found = false;
        for (args) |key| {
            if (try vm.valueEquals(entry.key, key)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try vm.hashSetEntry(result_hash, entry.key, entry.value);
        }
    }

    return Value.fromObject(&result_hash.object);
}

pub fn builtinHashRehash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try ensureMutableHash(vm, receiver);

    try vm.hashRebuildIndexes(receiver.toHashObject());

    return receiver;
}
