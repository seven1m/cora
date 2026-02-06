const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const push_sym = try vm.intern("<<");
    try vm.array_class.module.methods.put(push_sym, .{ .builtin = &builtinArrayPush });

    const each_sym = try vm.intern("each");
    try vm.array_class.module.methods.put(each_sym, .{ .builtin = &builtinArrayEach });

    const bracket_sym = try vm.intern("[]");
    try vm.array_class.module.methods.put(bracket_sym, .{ .builtin = &builtinArrayBracket });

    const equal_sym = try vm.intern("==");
    try vm.array_class.module.methods.put(equal_sym, .{ .builtin = &builtinArrayEqual });

    const length_sym = try vm.intern("length");
    try vm.array_class.module.methods.put(length_sym, .{ .builtin = &builtinArrayLength });

    const to_s_sym = try vm.intern("to_s");
    try vm.array_class.module.methods.put(to_s_sym, .{ .builtin = &builtinArrayToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.array_class.module.methods.put(inspect_sym, .{ .builtin = &builtinArrayInspect });

    const to_a_sym = try vm.intern("to_a");
    try vm.array_class.module.methods.put(to_a_sym, .{ .builtin = &builtinArrayToA });

    const all_sym = try vm.intern("all?");
    try vm.array_class.module.methods.put(all_sym, .{ .builtin = &builtinArrayAll });
}

pub fn builtinArrayPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const array = receiver.data.array;
    array.elements.append(vm.gc_allocator, args[0]) catch return error.Fatal;

    return receiver;
}

pub fn builtinArrayBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .integer, "Integer");
    const array = receiver.data.array;
    const index = args[0].data.integer;
    const len: i64 = @intCast(array.elements.items.len);

    // Handle negative indices (count from end)
    var actual_index: i64 = index;
    if (index < 0) {
        actual_index = len + index;
    }

    // Return nil for out of bounds
    if (actual_index < 0 or actual_index >= len) {
        return Value.nil();
    }

    return array.elements.items[@intCast(actual_index)];
}

pub fn builtinArrayEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (other.data != .array) {
        return Value.boolean(false);
    }

    const left = receiver.data.array;
    const right = other.data.array;
    if (left.elements.items.len != right.elements.items.len) {
        return Value.boolean(false);
    }

    for (left.elements.items, 0..) |elem, idx| {
        const other_elem = right.elements.items[idx];
        var eq_args = [_]Value{other_elem};
        const eq_val = try vm.callMethodByName(elem, "==", eq_args[0..], null);
        if (eq_val.data == .boolean) {
            if (!eq_val.data.boolean) {
                return Value.boolean(false);
            }
        } else if (eq_val.data == .nil) {
            return Value.boolean(false);
        }
    }

    return Value.boolean(true);
}

pub fn builtinArrayEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);
    const array_obj = receiver.data.array;

    // Iterate over array elements
    for (array_obj.elements.items) |element| {
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);

        // If break occurred, return immediately
        if (result.break_occurred) {
            return receiver;
        }
    }

    return receiver;
}

pub fn builtinArrayToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("[") catch return error.Fatal;
    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(", ") catch return error.Fatal;

        const elem_str = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
        if (elem_str.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_str.data.string.str) catch return error.Fatal;
    }
    writer.writeAll("]") catch return error.Fatal;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinArrayLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    return Value{ .data = .{ .integer = @intCast(array.elements.items.len) } };
}

pub fn builtinArrayInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("[") catch return error.Fatal;
    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(", ") catch return error.Fatal;

        const elem_inspected = try vm.callMethodByName(elem, "inspect", &[_]Value{}, null);
        if (elem_inspected.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_inspected.data.string.str) catch return error.Fatal;
    }
    writer.writeAll("]") catch return error.Fatal;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinArrayToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinArrayAll(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array_obj = receiver.data.array;

    if (block) |blk| {
        for (array_obj.elements.items) |element| {
            const yield_args = [_]Value{element};
            const result = try vm.yieldToBlock(blk, &yield_args);
            if (result.break_occurred) {
                return result.value;
            }

            const is_truthy = switch (result.value.data) {
                .nil => false,
                .boolean => result.value.data.boolean,
                else => true,
            };
            if (!is_truthy) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    for (array_obj.elements.items) |element| {
        const is_truthy = switch (element.data) {
            .nil => false,
            .boolean => element.data.boolean,
            else => true,
        };
        if (!is_truthy) return Value.boolean(false);
    }

    return Value.boolean(true);
}
