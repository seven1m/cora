const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const bracket_sym = try vm.intern("[]");
    try vm.hash_class.module.methods.put(bracket_sym, .{ .builtin = &builtinHashBracket });

    const bracket_set_sym = try vm.intern("[]=");
    try vm.hash_class.module.methods.put(bracket_set_sym, .{ .builtin = &builtinHashBracketSet });

    const keys_sym = try vm.intern("keys");
    try vm.hash_class.module.methods.put(keys_sym, .{ .builtin = &builtinHashKeys });

    const values_sym = try vm.intern("values");
    try vm.hash_class.module.methods.put(values_sym, .{ .builtin = &builtinHashValues });

    const size_sym = try vm.intern("size");
    try vm.hash_class.module.methods.put(size_sym, .{ .builtin = &builtinHashSize });

    const length_sym = try vm.intern("length");
    try vm.hash_class.module.methods.put(length_sym, .{ .builtin = &builtinHashSize });

    const each_sym = try vm.intern("each");
    try vm.hash_class.module.methods.put(each_sym, .{ .builtin = &builtinHashEach });

    const to_s_sym = try vm.intern("to_s");
    try vm.hash_class.module.methods.put(to_s_sym, .{ .builtin = &builtinHashToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.hash_class.module.methods.put(inspect_sym, .{ .builtin = &builtinHashInspect });
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
    const blk = try vm.requireBlock(block);
    const hash_obj = receiver.data.hash;

    // Iterate in insertion order
    for (hash_obj.entries.items) |entry| {
        const yield_args = [_]Value{ entry.key, entry.value };
        const result = try vm.yieldToBlock(blk, &yield_args);

        // If break occurred, return immediately
        if (result.break_occurred) {
            return receiver;
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
