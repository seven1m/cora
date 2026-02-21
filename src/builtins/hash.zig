const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const bracket_sym = try vm.intern("[]");
    try vm.hash_class.module.methods.put(bracket_sym, .{ .method = .{ .builtin = &builtinHashBracket } });

    const bracket_set_sym = try vm.intern("[]=");
    try vm.hash_class.module.methods.put(bracket_set_sym, .{ .method = .{ .builtin = &builtinHashBracketSet } });

    const keys_sym = try vm.intern("keys");
    try vm.hash_class.module.methods.put(keys_sym, .{ .method = .{ .builtin = &builtinHashKeys } });

    const values_sym = try vm.intern("values");
    try vm.hash_class.module.methods.put(values_sym, .{ .method = .{ .builtin = &builtinHashValues } });

    const size_sym = try vm.intern("size");
    try vm.hash_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinHashSize } });

    const length_sym = try vm.intern("length");
    try vm.hash_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinHashSize } });

    const each_sym = try vm.intern("each");
    try vm.hash_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinHashEach } });

    const to_s_sym = try vm.intern("to_s");
    try vm.hash_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinHashToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.hash_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinHashInspect } });

    const fetch_sym = try vm.intern("fetch");
    try vm.hash_class.module.methods.put(fetch_sym, .{ .method = .{ .builtin = &builtinHashFetch } });

    const dig_sym = try vm.intern("dig");
    try vm.hash_class.module.methods.put(dig_sym, .{ .method = .{ .builtin = &builtinHashDig } });

    const select_sym = try vm.intern("select");
    try vm.hash_class.module.methods.put(select_sym, .{ .method = .{ .builtin = &builtinHashSelect } });

    const delete_sym = try vm.intern("delete");
    try vm.hash_class.module.methods.put(delete_sym, .{ .method = .{ .builtin = &builtinHashDelete } });
}

pub fn builtinHashBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.data.hash;
    const key = args[0];
    const key_hash = key.hash();

    if (hash_obj.map.get(key_hash)) |idx| {
        if (hash_obj.entries.items[idx].key.eql(key)) {
            return hash_obj.entries.items[idx].value;
        }
    }

    return Value.nil();
}

pub fn builtinHashBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        const exc = try vm.createException(vm.runtime_error_class, "can't modify frozen Hash");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const hash_obj = receiver.data.hash;
    const key = args[0];
    const new_value = args[1];
    const key_hash = key.hash();

    if (hash_obj.map.get(key_hash)) |idx| {
        if (hash_obj.entries.items[idx].key.eql(key)) {
            hash_obj.entries.items[idx].value = new_value;
            return new_value;
        }
    }

    const new_idx = hash_obj.entries.items.len;
    hash_obj.entries.append(vm.gc_allocator, .{ .key = key, .value = new_value }) catch return error.Fatal;
    hash_obj.map.put(key_hash, new_idx) catch return error.Fatal;

    return new_value;
}

pub fn builtinHashDelete(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const hash_obj = receiver.data.hash;
    const key = args[0];
    const key_hash = key.hash();

    const idx = hash_obj.map.get(key_hash) orelse return Value.nil();
    if (!hash_obj.entries.items[idx].key.eql(key)) {
        return Value.nil();
    }

    const deleted = hash_obj.entries.orderedRemove(idx).value;
    hash_obj.map.clearRetainingCapacity();
    for (hash_obj.entries.items, 0..) |entry, i| {
        hash_obj.map.put(entry.key.hash(), i) catch return error.Fatal;
    }
    return deleted;
}

pub fn builtinHashKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.data.hash;
    const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
    array_obj.* = .{
        .object = .{ .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
        .elements = .empty,
    };

    for (hash_obj.entries.items) |entry| {
        array_obj.elements.append(vm.gc_allocator, entry.key) catch return error.Fatal;
    }

    return .{ .data = .{ .array = array_obj } };
}

pub fn builtinHashValues(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.data.hash;
    const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
    array_obj.* = .{
        .object = .{ .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
        .elements = .empty,
    };

    for (hash_obj.entries.items) |entry| {
        array_obj.elements.append(vm.gc_allocator, entry.value) catch return error.Fatal;
    }

    return .{ .data = .{ .array = array_obj } };
}

pub fn builtinHashSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.data.hash.entries.items.len));
}

pub fn builtinHashEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };
    const hash_obj = receiver.data.hash;

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

pub fn builtinHashToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_obj = receiver.data.hash;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    const writer = buf.writer(vm.allocator);

    writer.writeAll("{") catch return error.Fatal;
    for (hash_obj.entries.items, 0..) |entry, idx| {
        if (idx > 0) {
            writer.writeAll(", ") catch return error.Fatal;
        }

        // Check if key is a symbol - use shorthand syntax
        if (entry.key.data == .symbol) {
            // Write symbol name without the : prefix
            const sym = entry.key.data.symbol;
            writer.writeAll(sym.name) catch return error.Fatal;
            writer.writeAll(": ") catch return error.Fatal;
        } else {
            // Call inspect on non-symbol keys
            const key_val = try vm.callMethodByName(entry.key, "inspect", &.{}, null);
            if (key_val.data != .string) {
                const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
                vm.pending_exception = exc;
                return error.Unwind;
            }
            writer.writeAll(key_val.data.string.str) catch return error.Fatal;
            writer.writeAll(" => ") catch return error.Fatal;
        }

        // Call inspect on value
        const value_val = try vm.callMethodByName(entry.value, "inspect", &.{}, null);
        if (value_val.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(value_val.data.string.str) catch return error.Fatal;
    }
    writer.writeAll("}") catch return error.Fatal;

    const final_str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(final_str);
    return try vm.newString(final_str, false);
}

pub fn builtinHashInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try builtinHashToS(vm, receiver, args, null);
}

pub fn builtinHashFetch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (args.len == 2 and block != null) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "block supersedes default value argument",
            .{},
        );
    }

    const hash_obj = receiver.data.hash;
    const key = args[0];
    const key_hash = key.hash();

    // Try to find the key
    if (hash_obj.map.get(key_hash)) |idx| {
        if (hash_obj.entries.items[idx].key.eql(key)) {
            return hash_obj.entries.items[idx].value;
        }
    }

    // Key not found - use default value or block
    if (block) |blk| {
        const yield_args = [_]Value{key};
        const result = try vm.yieldToBlock(blk, &yield_args);
        return result.value;
    } else if (args.len == 2) {
        return args[1];
    } else {
        // Raise KeyError - need to format the key
        const key_str = try vm.callMethodByName(key, "inspect", &.{}, null);
        if (key_str.data != .string) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "inspect did not return String",
                .{},
            );
        }

        return vm.raiseExceptionFmt(
            vm.runtime_error_class,
            "key not found: {s}",
            .{key_str.data.string.str},
        );
    }
}

pub fn builtinHashDig(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    var current_value = receiver;

    for (args) |key| {
        // Check if current value is nil
        if (current_value.data == .nil) {
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
    const hash_obj = receiver.data.hash;

    // Create a new hash for the result
    const result_hash = try vm.createHash();

    // Iterate through entries
    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);

        // If break occurred, return immediately
        if (result.break_occurred) {
            return .{ .data = .{ .hash = result_hash } };
        }

        // Check if the block returned a truthy value
        const is_truthy = (result.value.data != .nil) and
            !(result.value.data == .boolean and !result.value.data.boolean);

        if (is_truthy) {
            // Add this entry to the result hash
            const key_hash = entry.key.hash();
            const new_idx = result_hash.entries.items.len;
            result_hash.entries.append(vm.gc_allocator, .{ .key = entry.key, .value = entry.value }) catch return error.Fatal;
            result_hash.map.put(key_hash, new_idx) catch return error.Fatal;
        }
    }

    return .{ .data = .{ .hash = result_hash } };
}
