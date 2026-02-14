const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const push_sym = try vm.intern("<<");
    try vm.array_class.module.methods.put(push_sym, .{ .method = .{ .builtin = &builtinArrayPush } });

    const each_sym = try vm.intern("each");
    try vm.array_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinArrayEach } });

    const bracket_sym = try vm.intern("[]");
    try vm.array_class.module.methods.put(bracket_sym, .{ .method = .{ .builtin = &builtinArrayBracket } });

    const bracket_set_sym = try vm.intern("[]=");
    try vm.array_class.module.methods.put(bracket_set_sym, .{ .method = .{ .builtin = &builtinArrayBracketSet } });

    const equal_sym = try vm.intern("==");
    try vm.array_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinArrayEqual } });

    const length_sym = try vm.intern("length");
    try vm.array_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinArrayLength } });

    const size_sym = try vm.intern("size");
    try vm.array_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinArrayLength } });

    const map_sym = try vm.intern("map");
    try vm.array_class.module.methods.put(map_sym, .{ .method = .{ .builtin = &builtinArrayMap } });

    const map_bang_sym = try vm.intern("map!");
    try vm.array_class.module.methods.put(map_bang_sym, .{ .method = .{ .builtin = &builtinArrayMapBang } });

    const any_sym = try vm.intern("any?");
    try vm.array_class.module.methods.put(any_sym, .{ .method = .{ .builtin = &builtinArrayAny } });

    const include_sym = try vm.intern("include?");
    try vm.array_class.module.methods.put(include_sym, .{ .method = .{ .builtin = &builtinArrayInclude } });

    const empty_sym = try vm.intern("empty?");
    try vm.array_class.module.methods.put(empty_sym, .{ .method = .{ .builtin = &builtinArrayEmpty } });

    const join_sym = try vm.intern("join");
    try vm.array_class.module.methods.put(join_sym, .{ .method = .{ .builtin = &builtinArrayJoin } });

    const first_sym = try vm.intern("first");
    try vm.array_class.module.methods.put(first_sym, .{ .method = .{ .builtin = &builtinArrayFirst } });

    const last_sym = try vm.intern("last");
    try vm.array_class.module.methods.put(last_sym, .{ .method = .{ .builtin = &builtinArrayLast } });

    const intersection_sym = try vm.intern("&");
    try vm.array_class.module.methods.put(intersection_sym, .{ .method = .{ .builtin = &builtinArrayIntersection } });

    const union_sym = try vm.intern("|");
    try vm.array_class.module.methods.put(union_sym, .{ .method = .{ .builtin = &builtinArrayUnion } });

    const to_s_sym = try vm.intern("to_s");
    try vm.array_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinArrayToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.array_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinArrayInspect } });

    const to_a_sym = try vm.intern("to_a");
    try vm.array_class.module.methods.put(to_a_sym, .{ .method = .{ .builtin = &builtinArrayToA } });

    const all_sym = try vm.intern("all?");
    try vm.array_class.module.methods.put(all_sym, .{ .method = .{ .builtin = &builtinArrayAll } });
}

pub fn builtinArrayPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const array = receiver.data.array;
    array.elements.append(vm.gc_allocator, args[0]) catch return error.Fatal;

    return receiver;
}

pub fn builtinArrayBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const array = receiver.data.array;
    const len: i64 = @intCast(array.elements.items.len);

    if (args.len == 1) {
        // Single argument: arr[index]
        try vm.requireArgType(args, 0, .integer, "Integer");
        const index = args[0].data.integer;

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
    } else if (args.len == 2) {
        // Two arguments: arr[start, length] - array slicing
        try vm.requireArgType(args, 0, .integer, "Integer");
        try vm.requireArgType(args, 1, .integer, "Integer");

        const start = args[0].data.integer;
        const length = args[1].data.integer;

        // Handle negative start index
        var actual_start: i64 = start;
        if (start < 0) {
            actual_start = len + start;
        }

        // Return nil if start is out of bounds
        if (actual_start < 0 or actual_start > len) {
            return Value.nil();
        }

        // Negative length is invalid
        if (length < 0) {
            return Value.nil();
        }

        // Calculate end index (capped at array length)
        const end_idx: i64 = @min(actual_start + length, len);

        // Create new array with sliced elements
        const result_array = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        result_array.* = .{
            .object = .{
                .flags = 0,
                .class = vm.array_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .elements = .empty,
        };

        // Copy elements from start to end
        var i: i64 = actual_start;
        while (i < end_idx) : (i += 1) {
            const idx: usize = @intCast(i);
            result_array.elements.append(vm.gc_allocator, array.elements.items[idx]) catch return error.Fatal;
        }

        return Value{ .data = .{ .array = result_array } };
    }

    unreachable; // requireArgCountRange ensures args.len is 1 or 2
}

pub fn builtinArrayBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    try vm.requireArgType(args, 0, .integer, "Integer");

    const array = receiver.data.array;
    const index = args[0].data.integer;
    const len: i64 = @intCast(array.elements.items.len);
    const value_to_set = args[1];

    var actual_index = index;
    if (actual_index < 0) {
        actual_index = len + actual_index;
        if (actual_index < 0) {
            return vm.raiseExceptionFmt(vm.range_error_class, "index {d} too small for array", .{index});
        }
    }

    if (actual_index < len) {
        array.elements.items[@intCast(actual_index)] = value_to_set;
        return value_to_set;
    }

    while (@as(i64, @intCast(array.elements.items.len)) < actual_index) {
        array.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    }
    array.elements.append(vm.gc_allocator, value_to_set) catch return error.Fatal;
    return value_to_set;
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
        if (!(try vm.valueEquals(elem, right.elements.items[idx]))) {
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
            return result.value;
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

pub fn builtinArrayMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);
    const source = receiver.data.array;
    const result = try vm.createArray();

    for (source.elements.items) |element| {
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.break_occurred) {
            return yielded.value;
        }
        result.elements.append(vm.gc_allocator, yielded.value) catch return error.Fatal;
    }

    return Value{ .data = .{ .array = result } };
}

pub fn builtinArrayMapBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);
    const array = receiver.data.array;

    for (array.elements.items, 0..) |element, idx| {
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.break_occurred) {
            return yielded.value;
        }
        array.elements.items[idx] = yielded.value;
    }

    return receiver;
}

pub fn builtinArrayAny(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;

    if (block) |blk| {
        for (array.elements.items) |element| {
            const yield_args = [_]Value{element};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.break_occurred) {
                return yielded.value;
            }
            if (yielded.value.is_truthy()) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    for (array.elements.items) |element| {
        if (element.is_truthy()) return Value.boolean(true);
    }
    return Value.boolean(false);
}

pub fn builtinArrayInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const array = receiver.data.array;
    for (array.elements.items) |element| {
        if (try vm.valueEquals(element, args[0])) return Value.boolean(true);
    }
    return Value.boolean(false);
}

pub fn builtinArrayEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    return Value.boolean(array.elements.items.len == 0);
}

pub fn builtinArrayJoin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const sep = if (args.len == 1) try vm.coerceToStr(args[0], "no implicit conversion into String") else "";

    const array = receiver.data.array;
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(sep) catch return error.Fatal;
        const elem_str = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
        if (elem_str.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_str.data.string.str) catch return error.Fatal;
    }

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinArrayFirst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    if (array.elements.items.len == 0) return Value.nil();
    return array.elements.items[0];
}

pub fn builtinArrayLast(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.data.array;
    if (array.elements.items.len == 0) return Value.nil();
    return array.elements.items[array.elements.items.len - 1];
}

pub fn builtinArrayIntersection(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .array, "Array");
    const left = receiver.data.array;
    const right = args[0].data.array;
    const result = try vm.createArray();

    for (left.elements.items) |elem| {
        if (try arrayContainsEquivalent(vm, result.elements.items, elem)) continue;
        if (try arrayContainsEquivalent(vm, right.elements.items, elem)) {
            result.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }

    return Value{ .data = .{ .array = result } };
}

pub fn builtinArrayUnion(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .array, "Array");
    const left = receiver.data.array;
    const right = args[0].data.array;
    const result = try vm.createArray();

    for (left.elements.items) |elem| {
        if (!(try arrayContainsEquivalent(vm, result.elements.items, elem))) {
            result.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }
    for (right.elements.items) |elem| {
        if (!(try arrayContainsEquivalent(vm, result.elements.items, elem))) {
            result.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }

    return Value{ .data = .{ .array = result } };
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

            if (!result.value.is_truthy()) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    for (array_obj.elements.items) |element| {
        if (!element.is_truthy()) return Value.boolean(false);
    }

    return Value.boolean(true);
}

fn arrayContainsEquivalent(vm: *VM, haystack: []Value, needle: Value) VMError!bool {
    for (haystack) |item| {
        if (try vm.valueEquals(item, needle)) return true;
    }
    return false;
}
