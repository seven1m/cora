const std = @import("std");
const enc = @import("../encoding.zig");
const inspect_util = @import("../inspect.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const warning_builtin = @import("warning.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

fn coerceToProcForHashDefault(vm: *VM, proc_like: Value) VMError!*value.ProcObject {
    var proc_val = proc_like;

    if (!proc_val.isProc()) {
        proc_val = (try vm.checkCallMethodByName(proc_val, "to_proc", &.{}, null)) orelse {
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

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.hash_class.module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinHashInitialize } });

    const bracket_sym = try vm.intern("[]");
    try vm.hash_class.module.methods.put(bracket_sym, .{ .method = .{ .builtin = &builtinHashBracket } });

    const bracket_set_sym = try vm.intern("[]=");
    try vm.hash_class.module.methods.put(bracket_set_sym, .{ .method = .{ .builtin = &builtinHashBracketSet } });

    const keys_sym = try vm.intern("keys");
    try vm.hash_class.module.methods.put(keys_sym, .{ .method = .{ .builtin = &builtinHashKeys } });

    const values_sym = try vm.intern("values");
    try vm.hash_class.module.methods.put(values_sym, .{ .method = .{ .builtin = &builtinHashValues } });

    const include_sym = try vm.intern("include?");
    try vm.hash_class.module.methods.put(include_sym, .{ .method = .{ .builtin = &builtinHashIncludeQ } });

    const has_key_sym = try vm.intern("has_key?");
    try vm.hash_class.module.methods.put(has_key_sym, .{ .method = .{ .builtin = &builtinHashIncludeQ } });

    const member_sym = try vm.intern("member?");
    try vm.hash_class.module.methods.put(member_sym, .{ .method = .{ .builtin = &builtinHashIncludeQ } });

    const key_query_sym = try vm.intern("key?");
    try vm.hash_class.module.methods.put(key_query_sym, .{ .method = .{ .builtin = &builtinHashIncludeQ } });

    const key_sym = try vm.intern("key");
    try vm.hash_class.module.methods.put(key_sym, .{ .method = .{ .builtin = &builtinHashKey } });

    const size_sym = try vm.intern("size");
    try vm.hash_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinHashSize } });

    const length_sym = try vm.intern("length");
    try vm.hash_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinHashSize } });

    const empty_sym = try vm.intern("empty?");
    try vm.hash_class.module.methods.put(empty_sym, .{ .method = .{ .builtin = &builtinHashEmpty } });

    const each_sym = try vm.intern("each");
    try vm.hash_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinHashEach } });

    const each_pair_sym = try vm.intern("each_pair");
    try vm.hash_class.module.methods.put(each_pair_sym, .{ .method = .{ .builtin = &builtinHashEachPair } });

    const to_s_sym = try vm.intern("to_s");
    try vm.hash_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinHashToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.hash_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinHashInspect } });

    const equal_sym = try vm.intern("==");
    try vm.hash_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinHashEqual } });

    const fetch_sym = try vm.intern("fetch");
    try vm.hash_class.module.methods.put(fetch_sym, .{ .method = .{ .builtin = &builtinHashFetch } });

    const dig_sym = try vm.intern("dig");
    try vm.hash_class.module.methods.put(dig_sym, .{ .method = .{ .builtin = &builtinHashDig } });

    const select_sym = try vm.intern("select");
    try vm.hash_class.module.methods.put(select_sym, .{ .method = .{ .builtin = &builtinHashSelect } });

    const delete_sym = try vm.intern("delete");
    try vm.hash_class.module.methods.put(delete_sym, .{ .method = .{ .builtin = &builtinHashDelete } });

    const default_sym = try vm.intern("default");
    try vm.hash_class.module.methods.put(default_sym, .{ .method = .{ .builtin = &builtinHashDefault } });

    const default_set_sym = try vm.intern("default=");
    try vm.hash_class.module.methods.put(default_set_sym, .{ .method = .{ .builtin = &builtinHashDefaultSet } });

    const default_proc_sym = try vm.intern("default_proc");
    try vm.hash_class.module.methods.put(default_proc_sym, .{ .method = .{ .builtin = &builtinHashDefaultProc } });

    const default_proc_set_sym = try vm.intern("default_proc=");
    try vm.hash_class.module.methods.put(default_proc_set_sym, .{ .method = .{ .builtin = &builtinHashDefaultProcSet } });
}

fn hashGetValue(hash_obj: *value.HashObject, vm: *VM, key: Value) VMError!?Value {
    const entry = (try vm.hashGetEntry(hash_obj, key)) orelse return null;
    return entry.value;
}

pub fn builtinHashInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 1 and block != null) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given 1, expected 0)", .{});
    }

    const hash_obj = receiver.toHashObject();
    hash_obj.default_value = null;
    hash_obj.default_proc = null;

    if (block) |blk| {
        const proc_val = try vm.newProc(blk);
        hash_obj.default_proc = proc_val.toProcObject();
    } else if (args.len == 1) {
        hash_obj.default_value = args[0];
    }

    return receiver;
}

pub fn builtinHashBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.toHashObject();
    const key = args[0];
    if (try hashGetValue(hash_obj, vm, key)) |found| {
        return found;
    }

    if (hash_obj.default_proc) |default_proc| {
        const call_args = [_]Value{ receiver, key };
        return vm.callProcObject(default_proc, call_args[0..], null, null);
    }
    return hash_obj.default_value orelse Value.nil();
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
    if (receiver.isFrozen()) {
        const exc = try vm.createException(vm.frozen_error_class, "can't modify frozen Hash");
        vm.pending_exception = exc;
        return error.Unwind;
    }
    const hash_obj = receiver.toHashObject();
    hash_obj.default_value = args[0];
    hash_obj.default_proc = null;
    return args[0];
}

pub fn builtinHashDefaultProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.toHashObject();
    if (hash_obj.default_proc) |default_proc| {
        return Value.fromObject(default_proc);
    }
    return Value.nil();
}

pub fn builtinHashDefaultProcSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        const exc = try vm.createException(vm.frozen_error_class, "can't modify frozen Hash");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const hash_obj = receiver.toHashObject();
    if (args[0].isNil()) {
        hash_obj.default_proc = null;
        return Value.nil();
    }

    const proc_obj = try coerceToProcForHashDefault(vm, args[0]);
    try validateHashDefaultProc(vm, proc_obj);

    hash_obj.default_proc = proc_obj;
    hash_obj.default_value = null;
    return args[0];
}

pub fn builtinHashBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        const exc = try vm.createException(vm.frozen_error_class, "can't modify frozen Hash");
        vm.pending_exception = exc;
        return error.Unwind;
    }

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

    return Value.fromObject(array_obj);
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

    return Value.fromObject(array_obj);
}

pub fn builtinHashIncludeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean((try vm.hashFindEntryIndex(receiver.toHashObject(), args[0])) != null);
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
        return try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };
    const hash_obj = receiver.toHashObject();

    // Iterate in insertion order
    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);

        // If break occurred, return immediately
        if (result.break_occurred) {
            return result.value;
        }
    }

    return receiver;
}

pub fn builtinHashEachPair(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("each_pair"), &.{});
    };
    const hash_obj = receiver.toHashObject();
    const snapshot = vm.allocator.alloc(value.HashEntry, hash_obj.entries.items.len) catch return error.Fatal;
    defer vm.allocator.free(snapshot);
    @memcpy(snapshot, hash_obj.entries.items);

    for (snapshot) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.break_occurred) {
            return result.value;
        }
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
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    const writer = buf.writer(vm.allocator);
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
                output_encoding = enc.negotiate(output_encoding, buf.items, key_encoding, key_bytes) orelse {
                    return vm.raiseExceptionFmt(
                        vm.encoding_compatibility_error_class,
                        "incompatible character encodings: {s} and {s}",
                        .{ output_encoding.name(), key_encoding.name() },
                    );
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
                output_encoding = enc.negotiate(output_encoding, buf.items, key_obj.encoding, key_obj.str) orelse {
                    return vm.raiseExceptionFmt(
                        vm.encoding_compatibility_error_class,
                        "incompatible character encodings: {s} and {s}",
                        .{ output_encoding.name(), key_obj.encoding.name() },
                    );
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
            output_encoding = enc.negotiate(output_encoding, buf.items, value_obj.encoding, value_obj.str) orelse {
                return vm.raiseExceptionFmt(
                    vm.encoding_compatibility_error_class,
                    "incompatible character encodings: {s} and {s}",
                    .{ output_encoding.name(), value_obj.encoding.name() },
                );
            };
        }
        writer.writeAll(value_obj.str) catch return error.Fatal;
    }
    writer.writeAll("}") catch return error.Fatal;

    const final_str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(final_str);
    return try vm.newStringWithEncoding(final_str, false, output_encoding);
}

pub fn builtinHashEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isHash()) return Value.boolean(false);

    const lhs = receiver.toHashObject();
    const rhs = args[0].toHashObject();
    if (lhs.entries.items.len != rhs.entries.items.len) return Value.boolean(false);

    for (lhs.entries.items) |entry| {
        const rhs_entry = (try vm.hashGetEntry(rhs, entry.key)) orelse return Value.boolean(false);
        if (!rhs_entry.value.eql(entry.value)) return Value.boolean(false);
    }

    return Value.boolean(true);
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
        vm.pending_exception = exc;
        return error.Unwind;
    }
}

pub fn builtinHashDig(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    var current_value = receiver;

    for (args) |key| {
        // Check if current value is nil
        if (current_value.isNil()) {
            return Value.nil();
        }

        // Try to call [] on the current value
        var bracket_args = [_]Value{key};
        const next_value = vm.callMethodByName(current_value, "[]", &bracket_args, null) catch |err| {
            if (err == error.Unwind) {
                // If [] raised an exception (e.g., NoMethodError), return nil instead
                vm.pending_exception = null;
                return Value.nil();
            }
            return err;
        };

        current_value = next_value;
    }

    return current_value;
}

pub fn builtinHashSelect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("select"), &.{});
    };
    const hash_obj = receiver.toHashObject();

    // Create a new hash for the result
    const result_hash = try vm.createHash();

    // Iterate through entries
    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);

        // If break occurred, return immediately
        if (result.break_occurred) {
            return Value.fromObject(result_hash);
        }

        // Check if the block returned a truthy value
        const is_truthy = result.value.is_truthy();

        if (is_truthy) {
            try vm.hashSetEntry(result_hash, entry.key, entry.value);
        }
    }

    return Value.fromObject(result_hash);
}
