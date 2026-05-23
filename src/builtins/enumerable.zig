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
    const map_sym = try vm.intern("map");
    try enumerable_val.toModuleObject().methods.put(map_sym, value.MethodEntry.builtin(&builtinEnumerableMap, .{ .exact = 0 }));
    const collect_sym = try vm.intern("collect");
    try enumerable_val.toModuleObject().methods.put(collect_sym, value.MethodEntry.builtin(&builtinEnumerableMap, .{ .exact = 0 }));
    const select_sym = try vm.intern("select");
    try enumerable_val.toModuleObject().methods.put(select_sym, value.MethodEntry.builtin(&builtinEnumerableSelect, .{ .exact = 0 }));
    const find_all_sym = try vm.intern("find_all");
    try enumerable_val.toModuleObject().methods.put(find_all_sym, value.MethodEntry.builtin(&builtinEnumerableSelect, .{ .exact = 0 }));
    const any_sym = try vm.intern("any?");
    try enumerable_val.toModuleObject().methods.put(any_sym, value.MethodEntry.builtin(&builtinEnumerableAny, .{ .variadic = 0 }));
    const filter_map_sym = try vm.intern("filter_map");
    try enumerable_val.toModuleObject().methods.put(filter_map_sym, value.MethodEntry.builtin(&builtinEnumerableFilterMap, .{ .exact = 0 }));
    const each_with_object_sym = try vm.intern("each_with_object");
    try enumerable_val.toModuleObject().methods.put(each_with_object_sym, value.MethodEntry.builtin(&builtinEnumerableEachWithObject, .{ .exact = 1 }));
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
    const max_by_sym = try vm.intern("max_by");
    try enumerable_val.toModuleObject().methods.put(max_by_sym, value.MethodEntry.builtin(&builtinEnumerableMaxBy, .{ .exact = 0 }));
    const sort_by_sym = try vm.intern("sort_by");
    try enumerable_val.toModuleObject().methods.put(sort_by_sym, value.MethodEntry.builtin(&builtinEnumerableSortBy, .{ .exact = 0 }));
    const flat_map_sym = try vm.intern("flat_map");
    try enumerable_val.toModuleObject().methods.put(flat_map_sym, value.MethodEntry.builtin(&builtinEnumerableFlatMap, .{ .exact = 0 }));
    const collect_concat_sym = try vm.intern("collect_concat");
    try enumerable_val.toModuleObject().methods.put(collect_concat_sym, value.MethodEntry.builtin(&builtinEnumerableFlatMap, .{ .exact = 0 }));
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
        if (result.controlFlowValue()) |return_value| return return_value;

        const to_ary_result = try vm.probeToAry(result.value);
        switch (to_ary_result) {
            .array => |ary| {
                for (ary.toArrayObject().elements.items) |elem| {
                    out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
                }
            },
            .missing, .nil_result => {
                out.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
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
        if (result.controlFlowValue()) |return_value| return return_value;
        out.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
    }

    return Value.fromObject(&out.object);
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
        if (result.controlFlowValue()) |return_value| return return_value;
        if (result.value.is_truthy()) {
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
        if (result.controlFlowValue()) |return_value| return return_value;
        if (result.value.is_truthy()) {
            out.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
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
            if (result.controlFlowValue()) |return_value| return return_value;
            if (result.value.is_truthy()) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    while (try enumerableNextElement(vm, enum_value)) |element| {
        if (element.is_truthy()) return Value.boolean(true);
    }
    return Value.boolean(false);
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
    return result.is_truthy();
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

fn builtinEnumerableEntries(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.callMethodByName(receiver, "to_a", &.{}, null);
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
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return memo;
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
        if (result.controlFlowValue()) |return_value| return return_value;

        const bucket_value = if (try vm.hashGetEntry(grouped, result.value)) |entry|
            entry.value
        else blk: {
            const new_bucket = try vm.createArray();
            const new_bucket_value = Value.fromObject(&new_bucket.object);
            try vm.hashSetEntry(grouped, result.value, new_bucket_value);
            break :blk new_bucket_value;
        };
        bucket_value.toArrayObject().elements.append(vm.gc_allocator, element) catch return error.Fatal;
    }

    return Value.fromObject(&grouped.object);
}

fn builtinEnumerableGrep(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const saved_last_match = vm.globals.get("$~") orelse Value.nil();
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
            if (result.controlFlowValue()) |return_value| return return_value;
            out.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
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
        if (result.controlFlowValue()) |return_value| return return_value;
        if (result.value.is_truthy()) return element;
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
            if (result.controlFlowValue()) |return_value| return return_value;
            accumulator = result.value;
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
        if (result.controlFlowValue()) |return_value| return return_value;

        if (best_value == null) {
            best_value = element;
            best_key = result.value;
            continue;
        }

        var cmp_args = [_]Value{best_key};
        const cmp = try vm.callMethodByName(result.value, "<=>", cmp_args[0..], null);
        if (cmp.isInteger() and cmp.toInteger() > 0) {
            best_value = element;
            best_key = result.value;
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
        if (result.controlFlowValue()) |return_value| return return_value;

        const entry = try vm.createArray();
        entry.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
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
