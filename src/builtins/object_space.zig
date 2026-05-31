const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const weak_map_class = vm.weak_map_class;

    const initialize_sym = try vm.intern("initialize");
    try weak_map_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinWeakMapInitialize, .{ .variadic = 0 }));

    const bracket_sym = try vm.intern("[]");
    try weak_map_class.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinWeakMapBracket, .{ .exact = 1 }));

    const bracket_set_sym = try vm.intern("[]=");
    try weak_map_class.module.methods.put(bracket_set_sym, value.MethodEntry.builtin(&builtinWeakMapBracketSet, .{ .exact = 2 }));

    const values_sym = try vm.intern("values");
    try weak_map_class.module.methods.put(values_sym, value.MethodEntry.builtin(&builtinWeakMapValues, .{ .exact = 0 }));
}

fn builtinWeakMapInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = vm;
    _ = args;
    _ = block;
    const wm = receiver.toWeakMapObject();
    wm.keys = .empty;
    wm.values = .empty;
    return receiver;
}

fn weakMapIndex(wm: *value.WeakMapObject, key: Value) ?usize {
    for (wm.keys.items, 0..) |k, i| {
        if (k.eql(key)) return i;
    }
    return null;
}

fn builtinWeakMapBracket(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = vm;
    _ = block;
    const wm = receiver.toWeakMapObject();
    const idx = weakMapIndex(wm, args[0]) orelse return Value.nil();
    return wm.values.items[idx];
}

fn builtinWeakMapBracketSet(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = block;
    const wm = receiver.toWeakMapObject();
    const key = args[0];
    const val = args[1];
    if (weakMapIndex(wm, key)) |idx| {
        wm.values.items[idx] = val;
    } else {
        wm.keys.append(vm.gc_allocator, key) catch return error.Fatal;
        wm.values.append(vm.gc_allocator, val) catch return error.Fatal;
    }
    return val;
}

fn builtinWeakMapValues(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = args;
    _ = block;
    const wm = receiver.toWeakMapObject();
    const result = try vm.createArray();
    for (wm.values.items) |v| {
        result.elements.append(vm.gc_allocator, v) catch return error.Fatal;
    }
    return Value.fromObject(&result.object);
}
