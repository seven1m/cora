const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const pack_runtime = @import("../pack.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const push_sym = try vm.intern("<<");
    try vm.array_class.module.methods.put(push_sym, .{ .method = .{ .builtin = &builtinArrayPush } });

    const each_sym = try vm.intern("each");
    try vm.array_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinArrayEach } });

    const each_with_index_sym = try vm.intern("each_with_index");
    try vm.array_class.module.methods.put(each_with_index_sym, .{ .method = .{ .builtin = &builtinArrayEachWithIndex } });

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

    const sort_sym = try vm.intern("sort");
    try vm.array_class.module.methods.put(sort_sym, .{ .method = .{ .builtin = &builtinArraySort } });

    const pack_sym = try vm.intern("pack");
    try vm.array_class.module.methods.put(pack_sym, .{ .method = .{ .builtin = &builtinArrayPack } });
}

pub fn builtinArrayPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const array = receiver.toArrayObject();
    array.elements.append(vm.gc_allocator, args[0]) catch return error.Fatal;

    return receiver;
}

pub fn builtinArrayBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);

    if (args.len == 1) {
        // Single argument: arr[index]
        try vm.requireIntegerArg(args, 0, "Integer");
        const index = args[0].toInteger();

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
        try vm.requireIntegerArg(args, 0, "Integer");
        try vm.requireIntegerArg(args, 1, "Integer");

        const start = args[0].toInteger();
        const length = args[1].toInteger();

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
                .type_tag = .array,
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

        return Value.fromObject(result_array);
    }

    unreachable; // requireArgCountRange ensures args.len is 1 or 2
}

pub fn builtinArrayBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    try vm.requireIntegerArg(args, 0, "Integer");

    const array = receiver.toArrayObject();
    const index = args[0].toInteger();
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
    if (!other.isArray()) {
        return Value.boolean(false);
    }

    const left = receiver.toArrayObject();
    const right = other.toArrayObject();
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
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };
    const array_obj = receiver.toArrayObject();

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

pub fn builtinArrayEachWithIndex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("each_with_index"), &.{});
    };
    const array_obj = receiver.toArrayObject();

    for (array_obj.elements.items, 0..) |element, idx| {
        const yield_args = [_]Value{ element, Value.integer(@intCast(idx)) };
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.break_occurred) {
            return result.value;
        }
    }

    return receiver;
}

pub fn builtinArrayToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("[") catch return error.Fatal;
    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(", ") catch return error.Fatal;

        const elem_str = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
        if (!elem_str.isString()) {
            const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_str.toStringObject().str) catch return error.Fatal;
    }
    writer.writeAll("]") catch return error.Fatal;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinArrayLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    return Value.integer(@intCast(array.elements.items.len));
}

pub fn builtinArrayMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("map"), &.{});
    };
    const source = receiver.toArrayObject();
    const result = try vm.createArray();

    for (source.elements.items) |element| {
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.break_occurred) {
            return yielded.value;
        }
        result.elements.append(vm.gc_allocator, yielded.value) catch return error.Fatal;
    }

    return Value.fromObject(result);
}

pub fn builtinArrayMapBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("map!"), &.{});
    };
    const array = receiver.toArrayObject();

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
    const array = receiver.toArrayObject();

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
    const array = receiver.toArrayObject();
    for (array.elements.items) |element| {
        if (try vm.valueEquals(element, args[0])) return Value.boolean(true);
    }
    return Value.boolean(false);
}

pub fn builtinArrayEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    return Value.boolean(array.elements.items.len == 0);
}

pub fn builtinArrayJoin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const sep = if (args.len == 1) try args[0].coerceToStr(vm, "no implicit conversion into String") else "";

    const array = receiver.toArrayObject();
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(sep) catch return error.Fatal;
        const elem_str = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
        if (!elem_str.isString()) {
            const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_str.toStringObject().str) catch return error.Fatal;
    }

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinArrayFirst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    if (array.elements.items.len == 0) return Value.nil();
    return array.elements.items[0];
}

pub fn builtinArrayLast(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    if (array.elements.items.len == 0) return Value.nil();
    return array.elements.items[array.elements.items.len - 1];
}

pub fn builtinArrayIntersection(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .array, "Array");
    const left = receiver.toArrayObject();
    const right = args[0].toArrayObject();
    const result = try vm.createArray();

    for (left.elements.items) |elem| {
        if (try arrayContainsEquivalent(vm, result.elements.items, elem)) continue;
        if (try arrayContainsEquivalent(vm, right.elements.items, elem)) {
            result.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }

    return Value.fromObject(result);
}

pub fn builtinArrayUnion(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .array, "Array");
    const left = receiver.toArrayObject();
    const right = args[0].toArrayObject();
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

    return Value.fromObject(result);
}

pub fn builtinArrayInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("[") catch return error.Fatal;
    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) writer.writeAll(", ") catch return error.Fatal;

        const elem_inspected = try vm.callMethodByName(elem, "inspect", &[_]Value{}, null);
        if (!elem_inspected.isString()) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(elem_inspected.toStringObject().str) catch return error.Fatal;
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
    const array_obj = receiver.toArrayObject();

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

pub fn builtinArraySort(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const source = receiver.toArrayObject();
    const result = try vm.createArray();
    result.elements.appendSlice(vm.gc_allocator, source.elements.items) catch return error.Fatal;

    // In-place insertion sort on the duplicate, sufficient for current spec usage.
    var i: usize = 1;
    while (i < result.elements.items.len) : (i += 1) {
        const key = result.elements.items[i];
        var j = i;
        while (j > 0) {
            const prev = result.elements.items[j - 1];
            if (!(try arrayValueLessThan(vm, key, prev))) break;
            result.elements.items[j] = prev;
            j -= 1;
        }
        result.elements.items[j] = key;
    }

    return Value.fromObject(result);
}

pub fn builtinArrayPack(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const format = try args[0].coerceToStr(vm, "no implicit conversion into String");
    return pack_runtime.arrayPack(vm, receiver.toArrayObject().elements.items, format);
}

fn arrayContainsEquivalent(vm: *VM, haystack: []Value, needle: Value) VMError!bool {
    for (haystack) |item| {
        if (try vm.valueEquals(item, needle)) return true;
    }
    return false;
}

fn arrayValueLessThan(vm: *VM, lhs: Value, rhs: Value) VMError!bool {
    if (lhs.isInteger() and rhs.isInteger()) return lhs.toInteger() < rhs.toInteger();
    if (lhs.isSymbol() and rhs.isSymbol()) {
        return std.mem.order(u8, lhs.toSymbolObject().name, rhs.toSymbolObject().name) == .lt;
    }
    if (lhs.isString() and rhs.isString()) {
        return std.mem.order(u8, lhs.toStringObject().str, rhs.toStringObject().str) == .lt;
    }

    var cmp_args = [_]Value{rhs};
    const cmp = try vm.callMethodByName(lhs, "<=>", cmp_args[0..], null);
    if (cmp.isInteger()) return cmp.toInteger() < 0;
    if (cmp.isFloat()) return cmp.toFloatObject().val < 0.0;

    return vm.raiseExceptionFmt(
        vm.argument_error_class,
        "comparison of {s} with {s} failed",
        .{ vm.className(lhs), vm.className(rhs) },
    );
}
