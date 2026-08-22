const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const warning_builtin = @import("warning.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const enumerable_sym = try vm.intern("Enumerable");
    const enumerable_entry = vm.object_class.module.constants.get(enumerable_sym) orelse return error.Fatal;
    const enumerable_val = enumerable_entry.value;
    const entries_sym = try vm.intern("entries");
    try enumerable_val.toModuleObject().methods.put(entries_sym, value.MethodEntry.builtin(&builtinEnumerableEntries, .{ .variadic = 0 }));
    const to_a_sym = try vm.intern("to_a");
    try enumerable_val.toModuleObject().methods.put(to_a_sym, value.MethodEntry.builtin(&builtinEnumerableToA, .{ .variadic = 0 }));
    const map_sym = try vm.intern("map");
    try enumerable_val.toModuleObject().methods.put(map_sym, value.MethodEntry.builtin(&builtinEnumerableMap, .{ .exact = 0 }));
    const collect_sym = try vm.intern("collect");
    try enumerable_val.toModuleObject().methods.put(collect_sym, value.MethodEntry.builtin(&builtinEnumerableMap, .{ .exact = 0 }));
    const select_sym = try vm.intern("select");
    try enumerable_val.toModuleObject().methods.put(select_sym, value.MethodEntry.builtin(&builtinEnumerableSelect, .{ .exact = 0 }));
    const find_all_sym = try vm.intern("find_all");
    try enumerable_val.toModuleObject().methods.put(find_all_sym, value.MethodEntry.builtin(&builtinEnumerableSelect, .{ .exact = 0 }));
    const filter_sym = try vm.intern("filter");
    try enumerable_val.toModuleObject().methods.put(filter_sym, value.MethodEntry.builtin(&builtinEnumerableSelect, .{ .exact = 0 }));
    const any_sym = try vm.intern("any?");
    try enumerable_val.toModuleObject().methods.put(any_sym, value.MethodEntry.builtin(&builtinEnumerableAny, .{ .variadic = 0 }));
    const all_sym = try vm.intern("all?");
    try enumerable_val.toModuleObject().methods.put(all_sym, value.MethodEntry.builtin(&builtinEnumerableAll, .{ .variadic = 0 }));
    const filter_map_sym = try vm.intern("filter_map");
    try enumerable_val.toModuleObject().methods.put(filter_map_sym, value.MethodEntry.builtin(&builtinEnumerableFilterMap, .{ .exact = 0 }));
    const each_with_object_sym = try vm.intern("each_with_object");
    try enumerable_val.toModuleObject().methods.put(each_with_object_sym, value.MethodEntry.builtin(&builtinEnumerableEachWithObject, .{ .exact = 1 }));
    const each_slice_sym = try vm.intern("each_slice");
    try enumerable_val.toModuleObject().methods.put(each_slice_sym, value.MethodEntry.builtin(&builtinEnumerableEachSlice, .{ .exact = 1 }));
    const find_sym = try vm.intern("find");
    try enumerable_val.toModuleObject().methods.put(find_sym, value.MethodEntry.builtin(&builtinEnumerableFind, .{ .variadic = 0 }));
    const detect_sym = try vm.intern("detect");
    try enumerable_val.toModuleObject().methods.put(detect_sym, value.MethodEntry.builtin(&builtinEnumerableFind, .{ .variadic = 0 }));
    const group_by_sym = try vm.intern("group_by");
    try enumerable_val.toModuleObject().methods.put(group_by_sym, value.MethodEntry.builtin(&builtinEnumerableGroupBy, .{ .exact = 0 }));
    const grep_sym = try vm.intern("grep");
    try enumerable_val.toModuleObject().methods.put(grep_sym, value.MethodEntry.builtin(&builtinEnumerableGrep, .{ .exact = 1 }));
    const inject_sym = try vm.intern("inject");
    try enumerable_val.toModuleObject().methods.put(inject_sym, value.MethodEntry.builtin(&builtinEnumerableInject, .{ .variadic = 0 }));
    const reduce_sym = try vm.intern("reduce");
    try enumerable_val.toModuleObject().methods.put(reduce_sym, value.MethodEntry.builtin(&builtinEnumerableInject, .{ .variadic = 0 }));
    const max_by_sym = try vm.intern("max_by");
    try enumerable_val.toModuleObject().methods.put(max_by_sym, value.MethodEntry.builtin(&builtinEnumerableMaxBy, .{ .exact = 0 }));
    const min_by_sym = try vm.intern("min_by");
    try enumerable_val.toModuleObject().methods.put(min_by_sym, value.MethodEntry.builtin(&builtinEnumerableMinBy, .{ .variadic = 0 }));
    const sort_by_sym = try vm.intern("sort_by");
    try enumerable_val.toModuleObject().methods.put(sort_by_sym, value.MethodEntry.builtin(&builtinEnumerableSortBy, .{ .exact = 0 }));
    const flat_map_sym = try vm.intern("flat_map");
    try enumerable_val.toModuleObject().methods.put(flat_map_sym, value.MethodEntry.builtin(&builtinEnumerableFlatMap, .{ .exact = 0 }));
    const collect_concat_sym = try vm.intern("collect_concat");
    try enumerable_val.toModuleObject().methods.put(collect_concat_sym, value.MethodEntry.builtin(&builtinEnumerableFlatMap, .{ .exact = 0 }));
    const include_sym = try vm.intern("include?");
    try enumerable_val.toModuleObject().methods.put(include_sym, value.MethodEntry.builtin(&builtinEnumerableInclude, .{ .exact = 1 }));
    const member_sym = try vm.intern("member?");
    try enumerable_val.toModuleObject().methods.put(member_sym, value.MethodEntry.builtin(&builtinEnumerableInclude, .{ .exact = 1 }));
    const sum_sym = try vm.intern("sum");
    try enumerable_val.toModuleObject().methods.put(sum_sym, value.MethodEntry.builtin(&builtinEnumerableSum, .{ .variadic = 0 }));
    const count_sym = try vm.intern("count");
    try enumerable_val.toModuleObject().methods.put(count_sym, value.MethodEntry.builtin(&builtinEnumerableCount, .{ .variadic = 0 }));
}

fn builtinEnumerableFlatMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("flat_map");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    const out = try vm.createArray();

    while (true) {
        const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };
        const result = try enumerableYieldCollapsed(vm, blk, next_values.toArrayObject());

        const to_ary_result = try vm.probeToAry(result);
        switch (to_ary_result) {
            .array => |ary| {
                for (ary.toArrayObject().elements.items) |elem| {
                    out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
                }
            },
            .missing, .nil_result => {
                out.elements.append(vm.gc_allocator, result) catch return error.Fatal;
            },
        }
    }

    return Value.fromObject(&out.object);
}

fn builtinEnumerableMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("map");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const out = try vm.createArray();
    const callable = try vm.procValueForBlock(blk);
    const state = try vm.createArray();
    state.elements.append(vm.gc_allocator, Value.fromObject(&out.object)) catch return error.Fatal;
    state.elements.append(vm.gc_allocator, callable) catch return error.Fatal;

    const arity = try vm.blockArity(blk);
    const each_block = Block{ .kind = .{ .receiver_builtin = .{
        .receiver = Value.fromObject(&state.object),
        .func = &enumerableMapEach,
        .arity = arity,
    } } };
    _ = try vm.callMethodByName(receiver, "each", &.{}, each_block);

    return Value.fromObject(&out.object);
}

fn enumerableMapEach(vm: *VM, receiver: Value, args: []Value) VMError!Value {
    const state = receiver.toArrayObject();
    const out = state.elements.items[0].toArrayObject();
    const result = try vm.callMethodByName(state.elements.items[1], "call", args, null);
    out.elements.append(vm.gc_allocator, result) catch return error.Fatal;
    return result;
}

fn builtinEnumerableSelect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("select");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    const out = try vm.createArray();

    while (true) {
        const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };
        const result = try enumerableYieldCollapsed(vm, blk, next_values.toArrayObject());
        if (result.isTruthy()) {
            out.elements.append(vm.gc_allocator, collapseYieldValues(next_values.toArrayObject())) catch return error.Fatal;
        }
    }

    return Value.fromObject(&out.object);
}

fn builtinEnumerableFilterMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("filter_map");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    const out = try vm.createArray();

    while (true) {
        const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };
        const result = try enumerableYieldCollapsed(vm, blk, next_values.toArrayObject());
        if (result.isTruthy()) {
            out.elements.append(vm.gc_allocator, result) catch return error.Fatal;
        }
    }

    return Value.fromObject(&out.object);
}

fn builtinEnumerableAny(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    if (pattern) |pat| {
        while (try enumerableNextElement(vm, enum_value)) |element| {
            if (try enumerablePatternMatches(vm, pat, element)) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    if (block) |blk| {
        while (true) {
            const next_values = try enumerableNextValues(vm, enum_value) orelse break;
            const result = try vm.yieldToBlock(blk, next_values.elements.items);
            if (result.isTruthy()) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    while (try enumerableNextElement(vm, enum_value)) |element| {
        if (element.isTruthy()) return Value.boolean(true);
    }
    return Value.boolean(false);
}

fn builtinEnumerableAll(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    if (pattern) |pat| {
        while (try enumerableNextElement(vm, enum_value)) |element| {
            if (!try enumerablePatternMatches(vm, pat, element)) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    if (block) |blk| {
        while (true) {
            const next_values = try enumerableNextValues(vm, enum_value) orelse break;
            const result = try vm.yieldToBlock(blk, next_values.elements.items);
            if (result.isFalsey()) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    while (try enumerableNextElement(vm, enum_value)) |element| {
        if (element.isFalsey()) return Value.boolean(false);
    }
    return Value.boolean(true);
}

fn collapseYieldValues(yield_values: *value.ArrayObject) Value {
    return switch (yield_values.elements.items.len) {
        0 => Value.nil(),
        1 => yield_values.elements.items[0],
        else => Value.fromObject(&yield_values.object),
    };
}

fn enumerablePatternMatches(vm: *VM, pattern: Value, element: Value) VMError!bool {
    var match_args = [_]Value{element};
    const result = try vm.callMethodByName(pattern, "===", match_args[0..], null);
    return result.isTruthy();
}

fn enumerableNextValues(vm: *VM, enum_value: Value) VMError!?*value.ArrayObject {
    const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
        if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
            vm.setPendingException(null);
            return null;
        }
        return err;
    };
    return next_values.toArrayObject();
}

fn enumerableNextElement(vm: *VM, enum_value: Value) VMError!?Value {
    const next_values = try enumerableNextValues(vm, enum_value) orelse return null;
    return collapseYieldValues(next_values);
}

fn enumerableYieldCollapsed(vm: *VM, blk: Block, next_values: *value.ArrayObject) @TypeOf(vm.yieldToBlock(blk, &[_]Value{Value.nil()})) {
    const element = collapseYieldValues(next_values);
    const yield_args = [_]Value{element};
    return vm.yieldToBlock(blk, &yield_args);
}

fn builtinEnumerableInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    while (try enumerableNextElement(vm, enum_value)) |element| {
        if (try vm.valueEquals(element, args[0])) return Value.boolean(true);
    }
    return Value.boolean(false);
}

fn builtinEnumerableEntries(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.callMethodByName(receiver, "to_a", &.{}, null);
}

fn builtinEnumerableToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), args);
    const out = try vm.createArray();
    while (try enumerableNextElement(vm, enum_value)) |element| {
        out.elements.append(vm.gc_allocator, element) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

fn builtinEnumerableEachWithObject(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const memo = args[0];
    const blk = block orelse {
        const method_name = try vm.intern("each_with_object");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, args, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, args);
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    while (try enumerableNextElement(vm, enum_value)) |element| {
        const yield_args = [_]Value{ element, memo };
        _ = try vm.yieldToBlock(blk, &yield_args);
    }

    return memo;
}

fn builtinEnumerableEachSlice(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const n_value = if (try vm.checkCallMethodByName(args[0], "to_int", false, &[_]Value{}, null)) |coerced|
        coerced
    else
        args[0];

    if (!n_value.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into Integer", .{vm.className(n_value)});
    }

    const n = n_value.toInteger();
    if (n <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid slice size", .{});
    }

    const n_usize: usize = @intCast(n);

    const blk = block orelse {
        const method_name = try vm.intern("each_slice");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size_val| {
            if (size_val.isInteger()) {
                const size = size_val.toInteger();
                const slice_count = @divTrunc(size + n - 1, n);
                return vm.createMethodEnumeratorWithSize(receiver, method_name, args, Value.integer(slice_count));
            }
        }
        return vm.createMethodEnumerator(receiver, method_name, args);
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    var slice: std.ArrayList(Value) = .empty;
    defer slice.deinit(vm.allocator);

    while (true) {
        const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };

        const element = collapseYieldValues(next_values.toArrayObject());
        slice.append(vm.allocator, element) catch return error.Fatal;

        if (slice.items.len == n_usize) {
            const slice_ary = try vm.createArray();
            for (slice.items) |elem| {
                slice_ary.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
            }
            const yield_args = [_]Value{Value.fromObject(&slice_ary.object)};
            _ = try vm.yieldToBlock(blk, &yield_args);
            slice.clearRetainingCapacity();
        }
    }

    if (slice.items.len > 0) {
        const slice_ary = try vm.createArray();
        for (slice.items) |elem| {
            slice_ary.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
        const yield_args = [_]Value{Value.fromObject(&slice_ary.object)};
        _ = try vm.yieldToBlock(blk, &yield_args);
    }

    return receiver;
}

fn builtinEnumerableGroupBy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("group_by");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const grouped = try vm.createHash();
    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    while (try enumerableNextElement(vm, enum_value)) |element| {
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);

        const bucket_value = if (try vm.hashGetEntry(grouped, result)) |entry|
            entry.value
        else blk: {
            const new_bucket = try vm.createArray();
            const new_bucket_value = Value.fromObject(&new_bucket.object);
            try vm.hashSetEntry(grouped, result, new_bucket_value);
            break :blk new_bucket_value;
        };
        bucket_value.toArrayObject().elements.append(vm.gc_allocator, element) catch return error.Fatal;
    }

    return Value.fromObject(&grouped.object);
}

fn builtinEnumerableGrep(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const saved_last_match = vm.getGlobalValue("$~");
    errdefer if (block == null) {
        if (saved_last_match.isMatchData()) {
            vm.setLastMatch(saved_last_match.toMatchDataObject()) catch unreachable;
        } else {
            vm.clearLastMatch() catch unreachable;
        }
    };

    const pattern = args[0];
    const out = try vm.createArray();
    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    while (try enumerableNextElement(vm, enum_value)) |element| {
        if (!try enumerablePatternMatches(vm, pattern, element)) continue;

        if (block) |blk| {
            const yield_args = [_]Value{element};
            const result = try vm.yieldToBlock(blk, &yield_args);
            out.elements.append(vm.gc_allocator, result) catch return error.Fatal;
        } else {
            out.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        }
    }

    if (block == null) {
        if (saved_last_match.isMatchData()) {
            try vm.setLastMatch(saved_last_match.toMatchDataObject());
        } else {
            try vm.clearLastMatch();
        }
    }

    return Value.fromObject(&out.object);
}

fn builtinEnumerableFind(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const blk = block orelse {
        return vm.createMethodEnumerator(receiver, try vm.intern("find"), args);
    };

    const ifnone = if (args.len == 1) args[0] else Value.nil();
    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    while (try enumerableNextElement(vm, enum_value)) |element| {
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.isTruthy()) return element;
    }

    if (!ifnone.isNil()) {
        return vm.callMethodByName(ifnone, "call", &.{}, null);
    }
    return Value.nil();
}

fn raiseEnumerableInjectArgError(vm: *VM, given: usize, expected: []const u8) VMError {
    return vm.raiseExceptionFmt(
        vm.argument_error_class,
        "wrong number of arguments (given {d}, expected {s})",
        .{ given, expected },
    );
}

fn builtinEnumerableInject(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (args.len > 2) return raiseEnumerableInjectArgError(vm, args.len, "0..2");
    if (args.len == 0 and block == null) return raiseEnumerableInjectArgError(vm, 0, "1..2");

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    if (args.len == 2) {
        if (block != null) try warning_builtin.warnBlockUnused(vm);

        const method_name = try vm.coerceToMethodNameString(args[1]);
        var accumulator = args[0];
        while (try enumerableNextElement(vm, enum_value)) |element| {
            var method_args = [_]Value{element};
            accumulator = try vm.callMethodByName(accumulator, method_name, method_args[0..], null);
        }
        return accumulator;
    }

    if (block) |blk| {
        var has_accumulator = args.len == 1;
        var accumulator = if (has_accumulator) args[0] else Value.nil();

        while (try enumerableNextElement(vm, enum_value)) |element| {
            if (!has_accumulator) {
                accumulator = element;
                has_accumulator = true;
                continue;
            }

            const yield_args = [_]Value{ accumulator, element };
            const result = try vm.yieldToBlock(blk, &yield_args);
            accumulator = result;
        }

        return if (has_accumulator) accumulator else Value.nil();
    }

    const method_name = try vm.coerceToMethodNameString(args[0]);
    var accumulator = (try enumerableNextElement(vm, enum_value)) orelse return Value.nil();
    while (try enumerableNextElement(vm, enum_value)) |element| {
        var method_args = [_]Value{element};
        accumulator = try vm.callMethodByName(accumulator, method_name, method_args[0..], null);
    }
    return accumulator;
}

fn builtinEnumerableCount(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    var count: i64 = 0;

    if (pattern) |pat| {
        while (try enumerableNextElement(vm, enum_value)) |element| {
            if (try vm.valueEquals(element, pat)) {
                count += 1;
            }
        }
    } else if (block) |blk| {
        while (true) {
            const next_values = try enumerableNextValues(vm, enum_value) orelse break;
            const result = try vm.yieldToBlock(blk, next_values.elements.items);
            if (result.isTruthy()) {
                count += 1;
            }
        }
    } else {
        while (try enumerableNextElement(vm, enum_value)) |_| {
            count += 1;
        }
    }

    return Value.integer(count);
}

fn builtinEnumerableSum(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const init = if (args.len == 1) args[0] else Value.integer(0);

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    var accumulator = init;
    var compensation: f64 = 0.0;
    var use_kahan = false;

    while (try enumerableNextElement(vm, enum_value)) |element| {
        var operand = element;

        if (block) |blk| {
            const yield_args = [_]Value{element};
            const result = try vm.yieldToBlock(blk, &yield_args);
            operand = result;
        }

        if (use_kahan) {
            const acc_f64 = accumulator.toFloatObject().val;
            const op_f64 = operand.toFloatObject().val;
            const y = op_f64 - compensation;
            const t = acc_f64 + y;
            compensation = (t - acc_f64) - y;
            accumulator = try vm.newFloat(t);
        } else {
            var plus_args = [_]Value{operand};
            accumulator = try vm.callMethodByName(accumulator, "+", plus_args[0..], null);
            if (accumulator.isFloat()) {
                use_kahan = true;
                compensation = 0.0;
            }
        }
    }

    return accumulator;
}

fn builtinEnumerableMaxBy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("max_by");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    var best_value: ?Value = null;
    var best_key: Value = Value.nil();

    while (try enumerableNextElement(vm, enum_value)) |element| {
        const result = try vm.yieldToBlock(blk, &.{element});

        if (best_value == null) {
            best_value = element;
            best_key = result;
            continue;
        }

        var cmp_args = [_]Value{best_key};
        const cmp = try vm.callMethodByName(result, "<=>", cmp_args[0..], null);
        if (cmp.isInteger() and cmp.toInteger() > 0) {
            best_value = element;
            best_key = result;
        }
    }

    return best_value orelse Value.nil();
}

fn builtinEnumerableMinBy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const n_arg = if (args.len == 1 and !args[0].isNil()) args[0] else null;

    if (n_arg) |n| {
        if (!n.isInteger() or n.toInteger() < 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size (or size too big)", .{});
        }
    }

    const blk = block orelse {
        const method_name = try vm.intern("min_by");
        if (n_arg) |n| {
            if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
                return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{n}, size);
            }
            return vm.createMethodEnumerator(receiver, method_name, &.{n});
        }
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});

    if (n_arg) |n| {
        const n_i64 = n.toInteger();
        if (n_i64 == 0) return Value.fromObject(&(try vm.createArray()).object);

        const decorated = try vm.createArray();
        var index: i64 = 0;

        while (try enumerableNextElement(vm, enum_value)) |element| {
            const result = try vm.yieldToBlock(blk, &.{element});

            const entry = try vm.createArray();
            entry.elements.append(vm.gc_allocator, result) catch return error.Fatal;
            entry.elements.append(vm.gc_allocator, Value.integer(index)) catch return error.Fatal;
            entry.elements.append(vm.gc_allocator, element) catch return error.Fatal;
            decorated.elements.append(vm.gc_allocator, Value.fromObject(&entry.object)) catch return error.Fatal;
            index += 1;
        }

        const sorted = try vm.callMethodByName(Value.fromObject(&decorated.object), "sort", &.{}, null);

        const out = try vm.createArray();
        const count = @min(n_i64, @as(i64, @intCast(sorted.toArrayObject().elements.items.len)));
        for (sorted.toArrayObject().elements.items[0..@intCast(count)]) |entry| {
            const tuple = entry.toArrayObject().elements.items;
            out.elements.append(vm.gc_allocator, tuple[2]) catch return error.Fatal;
        }
        return Value.fromObject(&out.object);
    }

    var best_value: ?Value = null;
    var best_key: Value = Value.nil();

    while (try enumerableNextElement(vm, enum_value)) |element| {
        const result = try vm.yieldToBlock(blk, &.{element});

        if (best_value == null) {
            best_value = element;
            best_key = result;
            continue;
        }

        var cmp_args = [_]Value{best_key};
        const cmp = try vm.callMethodByName(result, "<=>", cmp_args[0..], null);
        if (cmp.isInteger() and cmp.toInteger() < 0) {
            best_value = element;
            best_key = result;
        }
    }

    return best_value orelse Value.nil();
}

fn builtinEnumerableSortBy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("sort_by");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    const decorated = try vm.createArray();
    var index: i64 = 0;

    while (try enumerableNextElement(vm, enum_value)) |element| {
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);

        const entry = try vm.createArray();
        entry.elements.append(vm.gc_allocator, result) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, Value.integer(index)) catch return error.Fatal;
        entry.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        decorated.elements.append(vm.gc_allocator, Value.fromObject(&entry.object)) catch return error.Fatal;
        index += 1;
    }

    const sorted = try vm.callMethodByName(Value.fromObject(&decorated.object), "sort", &.{}, null);
    const out = try vm.createArray();
    for (sorted.toArrayObject().elements.items) |entry| {
        const tuple = entry.toArrayObject().elements.items;
        out.elements.append(vm.gc_allocator, tuple[2]) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}
