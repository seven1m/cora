const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub const Result = struct {
    hash: u64,
    recursive: bool,
};

pub fn mix(seed: u64, value_hash: u64) u64 {
    var mixed = seed ^ (value_hash +% 0x9e3779b97f4a7c15 +% (seed << 6) +% (seed >> 2));
    mixed ^= mixed >> 33;
    mixed *%= 0xff51afd7ed558ccd;
    mixed ^= mixed >> 33;
    return mixed;
}

pub fn structuralValueHash(vm: *VM, value_to_hash: Value) VMError!Result {
    if (value_to_hash.isArray()) {
        return try structuralArrayHash(vm, value_to_hash);
    }
    if (value_to_hash.isHash()) {
        return try structuralHashHash(vm, value_to_hash);
    }
    return .{
        .hash = try vm.hashKeyHash(value_to_hash),
        .recursive = false,
    };
}

pub fn structuralArrayHash(vm: *VM, receiver: Value) VMError!Result {
    if (try vm.enterRecursionGuard(.array_hash, receiver, Value.nil())) {
        return .{ .hash = 0, .recursive = true };
    }
    defer vm.leaveRecursionGuard(.array_hash, receiver, Value.nil());

    const array = receiver.toArrayObject();
    var hash_value: u64 = 0;
    for (array.elements.items) |elem| {
        const elem_hash = try structuralValueHash(vm, elem);
        if (elem_hash.recursive) return .{ .hash = 0, .recursive = true };
        hash_value = mix(hash_value, elem_hash.hash);
    }
    return .{ .hash = hash_value, .recursive = false };
}

pub fn structuralHashHash(vm: *VM, receiver: Value) VMError!Result {
    if (try vm.enterRecursionGuard(.hash_hash, receiver, Value.nil())) {
        return .{ .hash = 0, .recursive = true };
    }
    defer vm.leaveRecursionGuard(.hash_hash, receiver, Value.nil());

    const hash_obj = receiver.toHashObject();
    var hash_value: u64 = 0;
    for (hash_obj.entries.items) |entry| {
        const key_hash = try structuralValueHash(vm, entry.key);
        if (key_hash.recursive) return .{ .hash = 0, .recursive = true };

        const value_hash = try structuralValueHash(vm, entry.value);
        if (value_hash.recursive) return .{ .hash = 0, .recursive = true };

        const pair_hash = mix(key_hash.hash, value_hash.hash);
        hash_value ^= pair_hash;
    }
    return .{ .hash = hash_value, .recursive = false };
}
