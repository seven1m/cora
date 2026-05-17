const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const pack_runtime = @import("../pack.zig");
const aggregate_hash = @import("aggregate_hash.zig");
const warning_builtin = @import("warning.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const JoinState = struct {
    bytes: std.ArrayList(u8) = .empty,
    encoding: enc.Encoding = .{ .us_ascii = .{} },
};

fn arrayJoinConcatBytes(vm: *VM, left: []const u8, right: []const u8) VMError![]const u8 {
    const out = vm.gc_allocator_atomic.alloc(u8, left.len + right.len) catch return error.Fatal;
    @memcpy(out[0..left.len], left);
    @memcpy(out[left.len..], right);
    return out;
}

fn arrayJoinResolveEncoding(
    lhs_encoding: enc.Encoding,
    lhs_bytes: []const u8,
    rhs_encoding: enc.Encoding,
    rhs_bytes: []const u8,
) ?enc.Encoding {
    if (lhs_encoding.eql(rhs_encoding)) return lhs_encoding;
    if (rhs_bytes.len == 0) return lhs_encoding;
    if (lhs_bytes.len == 0) return rhs_encoding;
    if (!lhs_encoding.isAsciiCompatible() or !rhs_encoding.isAsciiCompatible()) return null;

    const lhs_ascii_only = enc.isAsciiOnly(lhs_bytes);
    const rhs_ascii_only = enc.isAsciiOnly(rhs_bytes);

    if (lhs_ascii_only and !rhs_ascii_only) return rhs_encoding;
    if (!lhs_ascii_only and rhs_ascii_only) return lhs_encoding;
    if (lhs_ascii_only and rhs_ascii_only) return lhs_encoding;

    return null;
}

fn arrayJoinAppendString(vm: *VM, state: *JoinState, str_value: Value) VMError!void {
    const str_obj = str_value.toStringObject();
    const result_encoding = arrayJoinResolveEncoding(state.encoding, state.bytes.items, str_obj.encoding, str_obj.str) orelse {
        return vm.raiseEncodingCompatibilityError(state.encoding, str_obj.encoding);
    };

    state.bytes.appendSlice(vm.allocator, str_obj.str) catch return error.Fatal;
    state.encoding = result_encoding;
}

fn arrayJoinWarnDefaultSeparator(vm: *VM) VMError!void {
    try warning_builtin.writeWarning(vm, "warning: $, is set to non-nil value\n");
}

fn arrayPatternMatches(vm: *VM, pattern: Value, element: Value) VMError!bool {
    var match_args = [_]Value{element};
    const result = try vm.callMethodByName(pattern, "===", match_args[0..], null);
    return result.is_truthy();
}

fn arrayProbePairElement(vm: *VM, element: Value, pair_index: usize) VMError!?struct { pair: *value.ArrayObject, item: Value } {
    const pair = switch (try vm.probeToAry(element)) {
        .array => |pair_value| pair_value.toArrayObject(),
        .missing, .nil_result => return null,
    };
    if (pair.elements.items.len <= pair_index) return null;

    return .{
        .pair = pair,
        .item = pair.elements.items[pair_index],
    };
}

fn arrayToHashPair(vm: *VM, source: Value, index: usize) VMError!struct { key: Value, value: Value } {
    const pair_value = switch (try vm.probeToAry(source)) {
        .array => |array_value| array_value,
        .missing, .nil_result => {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "wrong element type {s} at {d} (expected array)",
                .{ vm.className(source), index },
            );
        },
    };

    const pair = pair_value.toArrayObject().elements.items;
    if (pair.len != 2) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "wrong array length at {d} (expected 2, was {d})",
            .{ index, pair.len },
        );
    }

    return .{ .key = pair[0], .value = pair[1] };
}

fn arrayFindIndexByEquality(vm: *VM, elements: []Value, needle: Value) VMError!?usize {
    for (elements, 0..) |element, idx| {
        if (try vm.valueEquals(element, needle)) return idx;
    }
    return null;
}

fn arrayJoinAppendElement(
    vm: *VM,
    state: *JoinState,
    elem: Value,
    separator: ?Value,
    seen: *std.AutoHashMap(usize, void),
) VMError!void {
    if (elem.isArray()) {
        try arrayJoinAppendArray(vm, state, elem.toArrayObject(), separator, seen);
        return;
    }

    switch (try vm.probeToStringValue(elem)) {
        .string => |string_value| {
            try arrayJoinAppendString(vm, state, string_value);
            return;
        },
        .missing, .nil_result => {},
    }

    switch (try vm.probeToAry(elem)) {
        .array => |array_value| {
            try arrayJoinAppendArray(vm, state, array_value.toArrayObject(), separator, seen);
            return;
        },
        .missing, .nil_result => {},
    }

    const to_s_sym = try vm.intern("to_s");
    _ = try vm.findMethod(elem, to_s_sym) orelse {
        return vm.raiseExceptionFmt(
            vm.no_method_error_class,
            "undefined method 'to_s'",
            .{},
        );
    };
    const to_s_value = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
    if (!to_s_value.isString()) {
        const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
        vm.setPendingException(exc);
        return error.Unwind;
    }
    try arrayJoinAppendString(vm, state, to_s_value);
}

fn arrayJoinAppendArray(
    vm: *VM,
    state: *JoinState,
    array: *value.ArrayObject,
    separator: ?Value,
    seen: *std.AutoHashMap(usize, void),
) VMError!void {
    const key = @intFromPtr(array);
    if (seen.contains(key)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "recursive array join", .{});
    }
    seen.put(key, {}) catch return error.Fatal;
    defer _ = seen.remove(key);

    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) {
            if (separator) |sep| {
                try arrayJoinAppendString(vm, state, sep);
            }
        }
        try arrayJoinAppendElement(vm, state, elem, separator, seen);
    }
}

fn arrayFlattenInto(
    vm: *VM,
    out: *value.ArrayObject,
    array: *value.ArrayObject,
    seen: *std.AutoHashMap(usize, void),
    remaining_depth: ?usize,
    modified: ?*bool,
) VMError!void {
    const key = @intFromPtr(array);
    if (seen.contains(key)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "tried to flatten recursive array", .{});
    }
    seen.put(key, {}) catch return error.Fatal;
    defer _ = seen.remove(key);

    for (array.elements.items) |element| {
        if (remaining_depth) |depth| {
            if (depth == 0) {
                out.elements.append(vm.gc_allocator, element) catch return error.Fatal;
                continue;
            }
        }

        switch (try vm.probeToAry(element)) {
            .array => |nested| {
                if (modified) |did_modify| did_modify.* = true;
                const next_depth = if (remaining_depth) |depth| depth - 1 else null;
                try arrayFlattenInto(vm, out, nested.toArrayObject(), seen, next_depth, modified);
            },
            .missing, .nil_result => out.elements.append(vm.gc_allocator, element) catch return error.Fatal,
        }
    }
}

fn arrayFlattenDepthArg(vm: *VM, args: []Value) VMError!?usize {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 0) return null;

    const depth = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (depth < 0) return null;
    return @intCast(depth);
}

const ArrayFillPlan = struct {
    start: i64,
    count: i64,
};

fn coerceFillIndex(vm: *VM, value_to_coerce: Value) VMError!i64 {
    return try value_to_coerce.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
}

fn coerceFetchIndex(vm: *VM, value_to_coerce: Value) VMError!i64 {
    if (value_to_coerce.isInteger() or value_to_coerce.isBigInteger()) {
        return value_to_coerce.integerToI64(vm, "bignum too big to convert into `long`");
    }

    const maybe_index = try vm.checkCallMethodByName(value_to_coerce, "to_int", false, &[_]Value{}, null);
    const coerced = maybe_index orelse {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "no implicit conversion of {s} into Integer",
            .{vm.className(value_to_coerce)},
        );
    };
    if (!coerced.isInteger() and !coerced.isBigInteger()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Integer ({s}#to_int gives {s})",
            .{ vm.className(value_to_coerce), vm.className(value_to_coerce), vm.className(coerced) },
        );
    }

    return coerced.integerToI64(vm, "bignum too big to convert into `long`");
}

fn planArrayFillFromStartLength(
    vm: *VM,
    array_len: i64,
    raw_start: i64,
    raw_length: ?i64,
) VMError!ArrayFillPlan {
    var start = raw_start;
    if (start < 0) start += array_len;
    if (start < 0) start = 0;

    const count = raw_length orelse blk: {
        if (start >= array_len) break :blk 0;
        break :blk array_len - start;
    };
    if (count <= 0) {
        return .{ .start = start, .count = 0 };
    }

    const fill_end = std.math.add(i64, start, count) catch {
        return vm.raiseExceptionFmt(vm.argument_error_class, "argument too big", .{});
    };
    _ = fill_end;
    return .{ .start = start, .count = count };
}

fn planArrayFillFromRange(vm: *VM, array_len: i64, range: *value.RangeObject) VMError!ArrayFillPlan {
    var start = if (range.begin.isNil()) 0 else try coerceFillIndex(vm, range.begin);
    if (start < 0) start += array_len;
    if (start < 0) {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d}..{d} out of range", .{ start, start });
    }

    var finish = if (range.end.isNil())
        array_len
    else
        try coerceFillIndex(vm, range.end);
    if (!range.end.isNil() and finish < 0) finish += array_len;
    if (!range.exclude_end) finish += 1;

    if (finish <= start) {
        return .{ .start = start, .count = 0 };
    }

    const count = std.math.sub(i64, finish, start) catch return error.Fatal;
    return .{ .start = start, .count = count };
}

fn ensureArrayFillCapacity(vm: *VM, array: *value.ArrayObject, target_len: i64) VMError!void {
    while (@as(i64, @intCast(array.elements.items.len)) < target_len) {
        array.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    }
}

fn performArrayFill(vm: *VM, receiver: Value, plan: ArrayFillPlan, fill_value: ?Value, block: ?Block) VMError!Value {
    if (plan.count <= 0) return receiver;

    const array = receiver.toArrayObject();
    const fill_end = std.math.add(i64, plan.start, plan.count) catch {
        return vm.raiseExceptionFmt(vm.argument_error_class, "argument too big", .{});
    };
    try ensureArrayFillCapacity(vm, array, fill_end);

    var idx = plan.start;
    while (idx < fill_end) : (idx += 1) {
        const replacement = if (block) |blk| blk: {
            const yield_args = [_]Value{Value.integer(idx)};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            break :blk yielded.value;
        } else fill_value.?;
        array.elements.items[@intCast(idx)] = replacement;
    }

    return receiver;
}

fn builtinArrayTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    return switch (try vm.probeToAry(args[0])) {
        .array => |array| array,
        .missing, .nil_result => Value.nil(),
    };
}

pub fn register(vm: *VM) !void {
    const array_class_val = Value.fromObject(&vm.array_class.module.object);
    const array_singleton = try vm.getOrCreateSingletonClass(array_class_val);

    const class_bracket_sym = try vm.intern("[]");
    try array_singleton.module.methods.put(class_bracket_sym, value.MethodEntry.builtin(&builtinArrayClassBracket, .{ .variadic = 0 }));

    const try_convert_sym = try vm.intern("try_convert");
    try array_singleton.module.methods.put(try_convert_sym, value.MethodEntry.builtin(&builtinArrayTryConvert, .{ .exact = 1 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.array_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinArrayInitialize, .{ .variadic = 0 }, .private));

    const push_sym = try vm.intern("<<");
    try vm.array_class.module.methods.put(push_sym, value.MethodEntry.builtin(&builtinArrayPush, .{ .exact = 1 }));

    const append_sym = try vm.intern("append");
    try vm.array_class.module.methods.put(append_sym, value.MethodEntry.builtin(&builtinArrayAppend, .{ .variadic = 0 }));

    const push_method_sym = try vm.intern("push");
    try vm.array_class.module.methods.put(push_method_sym, value.MethodEntry.builtin(&builtinArrayAppend, .{ .variadic = 0 }));

    const concat_sym = try vm.intern("concat");
    try vm.array_class.module.methods.put(concat_sym, value.MethodEntry.builtin(&builtinArrayConcat, .{ .variadic = 0 }));

    const unshift_sym = try vm.intern("unshift");
    try vm.array_class.module.methods.put(unshift_sym, value.MethodEntry.builtin(&builtinArrayUnshift, .{ .variadic = 0 }));
    const prepend_sym = try vm.intern("prepend");
    try vm.array_class.module.methods.put(prepend_sym, value.MethodEntry.builtin(&builtinArrayUnshift, .{ .variadic = 0 }));

    const each_sym = try vm.intern("each");
    try vm.array_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinArrayEach, .{ .exact = 0 }));

    const reverse_each_sym = try vm.intern("reverse_each");
    try vm.array_class.module.methods.put(reverse_each_sym, value.MethodEntry.builtin(&builtinArrayReverseEach, .{ .exact = 0 }));

    const each_with_index_sym = try vm.intern("each_with_index");
    try vm.array_class.module.methods.put(each_with_index_sym, value.MethodEntry.builtin(&builtinArrayEachWithIndex, .{ .variadic = 0 }));

    const each_index_sym = try vm.intern("each_index");
    try vm.array_class.module.methods.put(each_index_sym, value.MethodEntry.builtin(&builtinArrayEachIndex, .{ .exact = 0 }));

    const bracket_sym = try vm.intern("[]");
    try vm.array_class.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinArrayBracket, .{ .variadic = 0 }));

    const bracket_set_sym = try vm.intern("[]=");
    try vm.array_class.module.methods.put(bracket_set_sym, value.MethodEntry.builtin(&builtinArrayBracketSet, .{ .variadic = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.array_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinArrayEqual, .{ .exact = 1 }));
    const eql_sym = try vm.intern("eql?");
    try vm.array_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinArrayEql, .{ .exact = 1 }));
    const hash_sym = try vm.intern("hash");
    try vm.array_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinArrayHash, .{ .exact = 0 }));
    const cmp_sym = try vm.intern("<=>");
    try vm.array_class.module.methods.put(cmp_sym, value.MethodEntry.builtin(&builtinArrayCmp, .{ .exact = 1 }));

    const length_sym = try vm.intern("length");
    try vm.array_class.module.methods.put(length_sym, value.MethodEntry.builtin(&builtinArrayLength, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.array_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinArrayLength, .{ .exact = 0 }));

    const map_sym = try vm.intern("map");
    try vm.array_class.module.methods.put(map_sym, value.MethodEntry.builtin(&builtinArrayMap, .{ .exact = 0 }));

    const collect_sym = try vm.intern("collect");
    try vm.array_class.module.methods.put(collect_sym, value.MethodEntry.builtin(&builtinArrayCollect, .{ .exact = 0 }));

    const map_bang_sym = try vm.intern("map!");
    try vm.array_class.module.methods.put(map_bang_sym, value.MethodEntry.builtin(&builtinArrayMapBang, .{ .exact = 0 }));

    const collect_bang_sym = try vm.intern("collect!");
    try vm.array_class.module.methods.put(collect_bang_sym, value.MethodEntry.builtin(&builtinArrayCollectBang, .{ .exact = 0 }));

    const compact_sym = try vm.intern("compact");
    try vm.array_class.module.methods.put(compact_sym, value.MethodEntry.builtin(&builtinArrayCompact, .{ .exact = 0 }));

    const compact_bang_sym = try vm.intern("compact!");
    try vm.array_class.module.methods.put(compact_bang_sym, value.MethodEntry.builtin(&builtinArrayCompactBang, .{ .exact = 0 }));

    const flatten_sym = try vm.intern("flatten");
    try vm.array_class.module.methods.put(flatten_sym, value.MethodEntry.builtin(&builtinArrayFlatten, .{ .variadic = 0 }));
    const flatten_bang_sym = try vm.intern("flatten!");
    try vm.array_class.module.methods.put(flatten_bang_sym, value.MethodEntry.builtin(&builtinArrayFlattenBang, .{ .variadic = 0 }));

    const select_sym = try vm.intern("select");
    try vm.array_class.module.methods.put(select_sym, value.MethodEntry.builtin(&builtinArraySelect, .{ .exact = 0 }));
    const find_all_sym = try vm.intern("find_all");
    try vm.array_class.module.methods.put(find_all_sym, value.MethodEntry.builtin(&builtinArraySelect, .{ .exact = 0 }));
    const filter_sym = try vm.intern("filter");
    try vm.array_class.module.methods.put(filter_sym, value.MethodEntry.builtin(&builtinArraySelect, .{ .exact = 0 }));

    const reject_sym = try vm.intern("reject");
    try vm.array_class.module.methods.put(reject_sym, value.MethodEntry.builtin(&builtinArrayReject, .{ .exact = 0 }));

    const partition_sym = try vm.intern("partition");
    try vm.array_class.module.methods.put(partition_sym, value.MethodEntry.builtin(&builtinArrayPartition, .{ .exact = 0 }));

    const select_bang_sym = try vm.intern("select!");
    try vm.array_class.module.methods.put(select_bang_sym, value.MethodEntry.builtin(&builtinArraySelectBang, .{ .exact = 0 }));
    const filter_bang_sym = try vm.intern("filter!");
    try vm.array_class.module.methods.put(filter_bang_sym, value.MethodEntry.builtin(&builtinArraySelectBang, .{ .exact = 0 }));

    const keep_if_sym = try vm.intern("keep_if");
    try vm.array_class.module.methods.put(keep_if_sym, value.MethodEntry.builtin(&builtinArrayKeepIf, .{ .exact = 0 }));

    const delete_if_sym = try vm.intern("delete_if");
    try vm.array_class.module.methods.put(delete_if_sym, value.MethodEntry.builtin(&builtinArrayDeleteIf, .{ .exact = 0 }));

    const reject_bang_sym = try vm.intern("reject!");
    try vm.array_class.module.methods.put(reject_bang_sym, value.MethodEntry.builtin(&builtinArrayRejectBang, .{ .exact = 0 }));

    const delete_sym = try vm.intern("delete");
    try vm.array_class.module.methods.put(delete_sym, value.MethodEntry.builtin(&builtinArrayDelete, .{ .exact = 1 }));

    const any_sym = try vm.intern("any?");
    try vm.array_class.module.methods.put(any_sym, value.MethodEntry.builtin(&builtinArrayAny, .{ .variadic = 0 }));

    const none_sym = try vm.intern("none?");
    try vm.array_class.module.methods.put(none_sym, value.MethodEntry.builtin(&builtinArrayNone, .{ .variadic = 0 }));

    const one_sym = try vm.intern("one?");
    try vm.array_class.module.methods.put(one_sym, value.MethodEntry.builtin(&builtinArrayOne, .{ .variadic = 0 }));

    const include_sym = try vm.intern("include?");
    try vm.array_class.module.methods.put(include_sym, value.MethodEntry.builtin(&builtinArrayInclude, .{ .exact = 1 }));

    const empty_sym = try vm.intern("empty?");
    try vm.array_class.module.methods.put(empty_sym, value.MethodEntry.builtin(&builtinArrayEmpty, .{ .exact = 0 }));

    const join_sym = try vm.intern("join");
    try vm.array_class.module.methods.put(join_sym, value.MethodEntry.builtin(&builtinArrayJoin, .{ .variadic = 0 }));

    const first_sym = try vm.intern("first");
    try vm.array_class.module.methods.put(first_sym, value.MethodEntry.builtin(&builtinArrayFirst, .{ .variadic = 0 }));

    const last_sym = try vm.intern("last");
    try vm.array_class.module.methods.put(last_sym, value.MethodEntry.builtin(&builtinArrayLast, .{ .variadic = 0 }));

    const at_sym = try vm.intern("at");
    try vm.array_class.module.methods.put(at_sym, value.MethodEntry.builtin(&builtinArrayAt, .{ .exact = 1 }));

    const fetch_sym = try vm.intern("fetch");
    try vm.array_class.module.methods.put(fetch_sym, value.MethodEntry.builtin(&builtinArrayFetch, .{ .variadic = 0 }));

    const assoc_sym = try vm.intern("assoc");
    try vm.array_class.module.methods.put(assoc_sym, value.MethodEntry.builtin(&builtinArrayAssoc, .{ .exact = 1 }));

    const rassoc_sym = try vm.intern("rassoc");
    try vm.array_class.module.methods.put(rassoc_sym, value.MethodEntry.builtin(&builtinArrayRassoc, .{ .exact = 1 }));

    const index_sym = try vm.intern("index");
    try vm.array_class.module.methods.put(index_sym, value.MethodEntry.builtin(&builtinArrayIndex, .{ .variadic = 0 }));
    const rindex_sym = try vm.intern("rindex");
    try vm.array_class.module.methods.put(rindex_sym, value.MethodEntry.builtin(&builtinArrayRindex, .{ .variadic = 0 }));
    const find_index_sym = try vm.intern("find_index");
    try vm.array_class.module.methods.put(find_index_sym, value.MethodEntry.builtin(&builtinArrayIndex, .{ .variadic = 0 }));
    const bsearch_sym = try vm.intern("bsearch");
    try vm.array_class.module.methods.put(bsearch_sym, value.MethodEntry.builtin(&builtinArrayBsearch, .{ .exact = 0 }));

    const dig_sym = try vm.intern("dig");
    try vm.array_class.module.methods.put(dig_sym, value.MethodEntry.builtin(&builtinArrayDig, .{ .variadic = 0 }));

    const intersection_sym = try vm.intern("&");
    try vm.array_class.module.methods.put(intersection_sym, value.MethodEntry.builtin(&builtinArrayIntersection, .{ .exact = 1 }));

    const union_sym = try vm.intern("|");
    try vm.array_class.module.methods.put(union_sym, value.MethodEntry.builtin(&builtinArrayUnion, .{ .exact = 1 }));

    const minus_sym = try vm.intern("-");
    try vm.array_class.module.methods.put(minus_sym, value.MethodEntry.builtin(&builtinArrayMinus, .{ .exact = 1 }));

    const plus_sym = try vm.intern("+");
    try vm.array_class.module.methods.put(plus_sym, value.MethodEntry.builtin(&builtinArrayPlus, .{ .exact = 1 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.array_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinArrayToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.array_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinArrayInspect, .{ .exact = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.array_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinArrayToA, .{ .exact = 0 }));
    const to_ary_sym = try vm.intern("to_ary");
    try vm.array_class.module.methods.put(to_ary_sym, value.MethodEntry.builtin(&builtinArrayToAry, .{ .exact = 0 }));
    const to_h_sym = try vm.intern("to_h");
    try vm.array_class.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinArrayToH, .{ .exact = 0 }));

    const replace_sym = try vm.intern("replace");
    try vm.array_class.module.methods.put(replace_sym, value.MethodEntry.builtin(&builtinArrayReplace, .{ .exact = 1 }));

    const all_sym = try vm.intern("all?");
    try vm.array_class.module.methods.put(all_sym, value.MethodEntry.builtin(&builtinArrayAll, .{ .variadic = 0 }));

    const count_sym = try vm.intern("count");
    try vm.array_class.module.methods.put(count_sym, value.MethodEntry.builtin(&builtinArrayCount, .{ .variadic = 1 }));

    const sort_sym = try vm.intern("sort");
    try vm.array_class.module.methods.put(sort_sym, value.MethodEntry.builtin(&builtinArraySort, .{ .variadic = 0 }));

    const sort_bang_sym = try vm.intern("sort!");
    try vm.array_class.module.methods.put(sort_bang_sym, value.MethodEntry.builtin(&builtinArraySortBang, .{ .variadic = 0 }));

    const max_sym = try vm.intern("max");
    try vm.array_class.module.methods.put(max_sym, value.MethodEntry.builtin(&builtinArrayMax, .{ .exact = 0 }));

    const reverse_sym = try vm.intern("reverse");
    try vm.array_class.module.methods.put(reverse_sym, value.MethodEntry.builtin(&builtinArrayReverse, .{ .exact = 0 }));

    const reverse_bang_sym = try vm.intern("reverse!");
    try vm.array_class.module.methods.put(reverse_bang_sym, value.MethodEntry.builtin(&builtinArrayReverseBang, .{ .exact = 0 }));

    const pack_sym = try vm.intern("pack");
    try vm.array_class.module.methods.put(pack_sym, value.MethodEntry.builtin(&builtinArrayPack, .{ .variadic = 1 }));

    const multiply_sym = try vm.intern("*");
    try vm.array_class.module.methods.put(multiply_sym, value.MethodEntry.builtin(&builtinArrayMultiply, .{ .exact = 1 }));

    const clear_sym = try vm.intern("clear");
    try vm.array_class.module.methods.put(clear_sym, value.MethodEntry.builtin(&builtinArrayClear, .{ .exact = 0 }));

    const fill_sym = try vm.intern("fill");
    try vm.array_class.module.methods.put(fill_sym, value.MethodEntry.builtin(&builtinArrayFill, .{ .variadic = 0 }));

    const shift_sym = try vm.intern("shift");
    try vm.array_class.module.methods.put(shift_sym, value.MethodEntry.builtin(&builtinArrayShift, .{ .variadic = 0 }));

    const pop_sym = try vm.intern("pop");
    try vm.array_class.module.methods.put(pop_sym, value.MethodEntry.builtin(&builtinArrayPop, .{ .variadic = 0 }));

    const delete_at_sym = try vm.intern("delete_at");
    try vm.array_class.module.methods.put(delete_at_sym, value.MethodEntry.builtin(&builtinArrayDeleteAt, .{ .exact = 1 }));

    const dup_sym = try vm.intern("dup");
    try vm.array_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinArrayDup, .{ .exact = 0 }));

    const clone_sym = try vm.intern("clone");
    try vm.array_class.module.methods.put(clone_sym, value.MethodEntry.builtin(&builtinArrayClone, .{ .variadic = 0 }));

    const uniq_sym = try vm.intern("uniq");
    try vm.array_class.module.methods.put(uniq_sym, value.MethodEntry.builtin(&builtinArrayUniq, .{ .exact = 0 }));

    const uniq_bang_sym = try vm.intern("uniq!");
    try vm.array_class.module.methods.put(uniq_bang_sym, value.MethodEntry.builtin(&builtinArrayUniqBang, .{ .exact = 0 }));
}

pub fn builtinArrayPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }
    const array = receiver.toArrayObject();
    array.elements.append(vm.gc_allocator, args[0]) catch return error.Fatal;

    return receiver;
}

pub fn builtinArrayAppend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    for (args) |arg| {
        array.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    }

    return receiver;
}

pub fn builtinArrayConcat(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    if (args.len == 0) return receiver;

    const array = receiver.toArrayObject();
    const coerced_args = vm.allocator.alloc(Value, args.len) catch return error.Fatal;
    defer vm.allocator.free(coerced_args);

    var needs_self_snapshot = false;
    for (args, 0..) |arg, i| {
        const coerced = try vm.coerceToArrayValue(arg);
        coerced_args[i] = coerced;
        if (coerced.toArrayObject() == array) needs_self_snapshot = true;
    }

    var self_snapshot_storage: ?[]Value = null;
    defer if (self_snapshot_storage) |snapshot| vm.allocator.free(snapshot);

    var self_elements: []const Value = array.elements.items;
    if (needs_self_snapshot) {
        const snapshot = vm.allocator.alloc(Value, array.elements.items.len) catch return error.Fatal;
        @memcpy(snapshot, array.elements.items);
        self_snapshot_storage = snapshot;
        self_elements = snapshot;
    }

    for (coerced_args) |coerced| {
        const other = coerced.toArrayObject();
        const elements = if (other == array) self_elements else other.elements.items;
        array.elements.appendSlice(vm.gc_allocator, elements) catch return error.Fatal;
    }

    return receiver;
}

pub fn builtinArrayUnshift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    for (args, 0..) |arg, idx| {
        array.elements.insert(vm.gc_allocator, idx, arg) catch return error.Fatal;
    }

    return receiver;
}

pub fn builtinArrayInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    array.elements.clearRetainingCapacity();

    if (args.len == 0) {
        if (block != null) {
            try warning_builtin.warnBlockUnused(vm);
        }
        return receiver;
    }

    if (args.len == 1) {
        if (args[0].isArray()) {
            const source = args[0].toArrayObject();
            for (source.elements.items) |elem| {
                array.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
            }
            return receiver;
        }

        switch (try probeToAryForInitialize(vm, args[0])) {
            .array => |array_value| {
                const source = array_value.toArrayObject();
                for (source.elements.items) |elem| {
                    array.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
                }
                return receiver;
            },
            .missing, .nil_result => {},
        }
    } else {
        if (args[0].isArray()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Array into Integer", .{});
        }

        switch (try probeToAryForInitialize(vm, args[0])) {
            .array => {
                return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Array into Integer", .{});
            },
            .missing, .nil_result => {},
        }
    }

    const size = args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    ) catch |err| switch (err) {
        error.Unwind => {
            if (vm.pendingException()) |exc| {
                if (exc.object.class == vm.range_error_class) {
                    return vm.raiseExceptionFmt(vm.argument_error_class, "array size too big", .{});
                }
            }
            return err;
        },
        else => return err,
    };
    if (size < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    var i: i64 = 0;
    if (block != null and args.len == 2) {
        try warning_builtin.writeWarning(vm, "warning: block supersedes default value argument\n");
    }
    if (block) |blk| {
        while (i < size) : (i += 1) {
            const yield_args = [_]Value{Value.integer(i)};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            array.elements.append(vm.gc_allocator, yielded.value) catch return error.Fatal;
        }
        return receiver;
    }

    const fill_value = if (args.len == 2) args[1] else Value.nil();
    while (i < size) : (i += 1) {
        array.elements.append(vm.gc_allocator, fill_value) catch return error.Fatal;
    }

    return receiver;
}

fn probeToAryForInitialize(vm: *VM, arg: Value) VMError!VM.ToAryResult {
    return vm.probeToAryWithVisibility(arg, true);
}

pub fn builtinArrayBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);

    if (args.len == 1) {
        // Single argument: arr[index] or arr[range]
        if (args[0].isRange()) {
            const range_obj = args[0].toRangeObject();
            var actual_start: i64 = 0;
            if (!range_obj.begin.isNil()) {
                const start = try range_obj.begin.coerceToI64ViaToInt(
                    vm,
                    "no implicit conversion into Integer",
                    "no implicit conversion into Integer",
                    "bignum too big to convert into `long`",
                );
                actual_start = start;
                if (actual_start < 0) actual_start += len;
            }
            if (actual_start < 0 or actual_start > len) {
                return Value.nil();
            }

            var finish: i64 = len;
            if (!range_obj.end.isNil()) {
                finish = try range_obj.end.coerceToI64ViaToInt(
                    vm,
                    "no implicit conversion into Integer",
                    "no implicit conversion into Integer",
                    "bignum too big to convert into `long`",
                );
                if (finish < 0) finish += len;
                if (!range_obj.exclude_end) finish += 1;
            }

            if (finish < actual_start) {
                const empty = try vm.createArray();
                return Value.fromObject(&empty.object);
            }

            const clamped_end = @max(actual_start, @min(finish, len));

            const result_array = try vm.createArray();
            var i: i64 = actual_start;
            while (i < clamped_end) : (i += 1) {
                const idx: usize = @intCast(i);
                result_array.elements.append(vm.gc_allocator, array.elements.items[idx]) catch return error.Fatal;
            }
            return Value.fromObject(&result_array.object);
        }

        const index = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );

        var actual_index: i64 = index;
        if (actual_index < 0) {
            actual_index = len + actual_index;
        }

        if (actual_index < 0 or actual_index >= len) {
            return Value.nil();
        }

        return array.elements.items[@intCast(actual_index)];
    } else if (args.len == 2) {
        // Two arguments: arr[start, length] - array slicing
        const start = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        const length = try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );

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

        return Value.fromObject(&result_array.object);
    }

    unreachable; // requireArgCountRange ensures args.len is 1 or 2
}

pub fn builtinArrayBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);

    const array = receiver.toArrayObject();

    if (args.len == 2) {
        try vm.requireIntegerArg(args, 0, "Integer");

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

    const start = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const delete_count = try args[1].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const replacement = args[2];

    if (delete_count < 0) {
        return vm.raiseExceptionFmt(vm.index_error_class, "negative length ({d})", .{delete_count});
    }

    const original_len: i64 = @intCast(array.elements.items.len);
    var actual_start = start;
    if (actual_start < 0) {
        actual_start = original_len + actual_start;
        if (actual_start < 0) {
            return vm.raiseExceptionFmt(
                vm.index_error_class,
                "index {d} too small for array; minimum: -{d}",
                .{ start, original_len },
            );
        }
    }

    while (@as(i64, @intCast(array.elements.items.len)) < actual_start) {
        array.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    }

    const replace_start: usize = @intCast(actual_start);
    const current_len: i64 = @intCast(array.elements.items.len);
    const replace_len: usize = @intCast(@min(delete_count, current_len - actual_start));

    switch (try vm.probeToAry(replacement)) {
        .array => |replacement_array| {
            array.elements.replaceRange(
                vm.gc_allocator,
                replace_start,
                replace_len,
                replacement_array.toArrayObject().elements.items,
            ) catch return error.Fatal;
        },
        .missing, .nil_result => {
            const scalar = [_]Value{replacement};
            array.elements.replaceRange(vm.gc_allocator, replace_start, replace_len, &scalar) catch return error.Fatal;
        },
    }

    return replacement;
}

pub fn builtinArrayEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isArray()) {
        return Value.boolean(false);
    }

    const left = receiver.toArrayObject();
    const right = other.toArrayObject();

    if (left == right) {
        return Value.boolean(true);
    }
    if (try vm.enterRecursionGuard(.array_equal, receiver, other)) {
        return Value.boolean(true);
    }
    defer vm.leaveRecursionGuard(.array_equal, receiver, other);

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

pub fn builtinArrayEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isArray()) {
        return Value.boolean(false);
    }

    const left = receiver.toArrayObject();
    const right = other.toArrayObject();

    if (left == right) {
        return Value.boolean(true);
    }
    if (try vm.enterRecursionGuard(.array_eql, receiver, other)) {
        return Value.boolean(true);
    }
    defer vm.leaveRecursionGuard(.array_eql, receiver, other);

    if (left.elements.items.len != right.elements.items.len) {
        return Value.boolean(false);
    }

    for (left.elements.items, 0..) |elem, idx| {
        if (!(try vm.hashKeysEqual(elem, right.elements.items[idx]))) {
            return Value.boolean(false);
        }
    }

    return Value.boolean(true);
}

pub fn builtinArrayHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const result = try aggregate_hash.structuralArrayHash(vm, receiver);
    return Value.integer(@bitCast(result.hash));
}

pub fn builtinArrayFill(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    if (block == null) {
        try vm.requireArgCountRange(args, 1, 3);
    } else {
        try vm.requireArgCountRange(args, 0, 2);
    }

    const array_len: i64 = @intCast(receiver.toArrayObject().elements.items.len);

    if (block) |blk| {
        var plan = ArrayFillPlan{ .start = 0, .count = array_len };
        if (args.len == 1) {
            if (args[0].isRange()) {
                plan = try planArrayFillFromRange(vm, array_len, args[0].toRangeObject());
            } else {
                const start = try coerceFillIndex(vm, args[0]);
                plan = try planArrayFillFromStartLength(vm, array_len, start, null);
            }
        } else if (args.len == 2) {
            const start = try coerceFillIndex(vm, args[0]);
            const length = if (args[1].isNil()) null else try coerceFillIndex(vm, args[1]);
            plan = try planArrayFillFromStartLength(vm, array_len, start, length);
        }
        return try performArrayFill(vm, receiver, plan, null, blk);
    }

    var plan = ArrayFillPlan{ .start = 0, .count = array_len };
    if (args.len >= 2) {
        if (args[1].isRange()) {
            if (args.len == 3) {
                return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Integer into Range", .{});
            }
            plan = try planArrayFillFromRange(vm, array_len, args[1].toRangeObject());
        } else {
            const start = try coerceFillIndex(vm, args[1]);
            const length = if (args.len == 2 or args[2].isNil()) null else try coerceFillIndex(vm, args[2]);
            plan = try planArrayFillFromStartLength(vm, array_len, start, length);
        }
    }

    return try performArrayFill(vm, receiver, plan, args[0], null);
}

pub fn builtinArrayCmp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const other = switch (try vm.probeToAry(args[0])) {
        .array => |array_value| array_value,
        .missing, .nil_result => return Value.nil(),
    };

    if (receiver.raw == other.raw) {
        return Value.integer(0);
    }
    if (try vm.enterRecursionGuard(.array_compare, receiver, other)) {
        return Value.integer(0);
    }
    defer vm.leaveRecursionGuard(.array_compare, receiver, other);

    const left = receiver.toArrayObject().elements.items;
    const right = other.toArrayObject().elements.items;
    const shared_len = @min(left.len, right.len);

    for (0..shared_len) |idx| {
        var cmp_args = [_]Value{right[idx]};
        const cmp = try vm.callMethodByName(left[idx], "<=>", cmp_args[0..], null);
        if (cmp.isNil()) return Value.nil();
        if (cmp.isInteger()) {
            const n = cmp.toInteger();
            if (n != 0) return cmp;
            continue;
        }
        if (cmp.isFloat()) {
            const n = cmp.toFloatObject().val;
            if (n != 0) return cmp;
            continue;
        }
        return cmp;
    }

    if (left.len < right.len) return Value.integer(-1);
    if (left.len > right.len) return Value.integer(1);
    return Value.integer(0);
}

pub fn builtinArrayEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each"), &.{}, size_value);
    };
    const array_obj = receiver.toArrayObject();

    var idx: usize = 0;
    while (idx < array_obj.elements.items.len) : (idx += 1) {
        const element = array_obj.elements.items[idx];
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinArrayReverseEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("reverse_each"), &.{}, size_value);
    };
    const array_obj = receiver.toArrayObject();

    var idx = array_obj.elements.items.len;
    while (idx > 0) {
        idx -= 1;
        const element = array_obj.elements.items[idx];
        const yield_args = [_]Value{element};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
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
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinArrayEachIndex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each_index"), &.{}, size_value);
    };
    const array_obj = receiver.toArrayObject();

    var idx: usize = 0;
    while (idx < array_obj.elements.items.len) : (idx += 1) {
        const yield_args = [_]Value{Value.integer(@intCast(idx))};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
    }

    return receiver;
}

pub fn builtinArrayToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinArrayInspect(vm, receiver, args, null);
}

pub fn builtinArrayLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    return Value.integer(@intCast(array.elements.items.len));
}

pub fn builtinArrayMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayMapShared(vm, receiver, args, block, "map");
}

pub fn builtinArrayCollect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayMapShared(vm, receiver, args, block, "collect");
}

fn arrayMapShared(vm: *VM, receiver: Value, args: []Value, block: ?Block, method_name: []const u8) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern(method_name), &.{}, size_value);
    };
    const source = receiver.toArrayObject();
    const result = try vm.createArray();

    var idx: usize = 0;
    while (idx < source.elements.items.len) : (idx += 1) {
        const element = source.elements.items[idx];
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        result.elements.append(vm.gc_allocator, yielded.value) catch return error.Fatal;
    }

    return Value.fromObject(&result.object);
}

pub fn builtinArrayMapBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayMapBangShared(vm, receiver, args, block, "map!");
}

pub fn builtinArrayCollectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayMapBangShared(vm, receiver, args, block, "collect!");
}

fn arrayMapBangShared(vm: *VM, receiver: Value, args: []Value, block: ?Block, method_name: []const u8) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern(method_name), &.{}, size_value);
    };
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }
    const array = receiver.toArrayObject();

    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        const element = array.elements.items[idx];
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        array.elements.items[idx] = yielded.value;
    }

    return receiver;
}

pub fn builtinArraySelect(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("select"), &.{}, size_value);
    };
    const source = receiver.toArrayObject();
    const result = try vm.createArray();

    var idx: usize = 0;
    while (idx < source.elements.items.len) : (idx += 1) {
        const element = source.elements.items[idx];
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.is_truthy()) {
            result.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        }
    }

    return Value.fromObject(&result.object);
}

pub fn builtinArrayReject(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("reject"), &.{}, size_value);
    };
    const source = receiver.toArrayObject();
    const result = try vm.createArray();

    var idx: usize = 0;
    while (idx < source.elements.items.len) : (idx += 1) {
        const element = source.elements.items[idx];
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (!yielded.value.is_truthy()) {
            result.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        }
    }

    return Value.fromObject(&result.object);
}

pub fn builtinArrayRejectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayFilterBangShared(vm, receiver, args, block, "reject!", false, true);
}

pub fn builtinArrayPartition(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("partition"), &.{}, size_value);
    };
    const source = receiver.toArrayObject();
    const truthy = try vm.createArray();
    const falsey = try vm.createArray();
    const pair = try vm.createArray();

    var idx: usize = 0;
    while (idx < source.elements.items.len) : (idx += 1) {
        const element = source.elements.items[idx];
        const yield_args = [_]Value{element};
        const yielded = try vm.yieldToBlock(blk, &yield_args);
        if (yielded.controlFlowValue()) |return_value| return return_value;

        const target = if (yielded.value.is_truthy()) truthy else falsey;
        target.elements.append(vm.gc_allocator, element) catch return error.Fatal;
    }

    pair.elements.append(vm.gc_allocator, Value.fromObject(&truthy.object)) catch return error.Fatal;
    pair.elements.append(vm.gc_allocator, Value.fromObject(&falsey.object)) catch return error.Fatal;
    return Value.fromObject(&pair.object);
}

pub fn builtinArraySelectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayFilterBangShared(vm, receiver, args, block, "select!", true, true);
}

pub fn builtinArrayKeepIf(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayFilterBangShared(vm, receiver, args, block, "keep_if", true, false);
}

pub fn builtinArrayDeleteIf(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return arrayFilterBangShared(vm, receiver, args, block, "delete_if", false, false);
}

pub fn builtinArrayDelete(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const array = receiver.toArrayObject();
    const kept = vm.allocator.alloc(Value, array.elements.items.len) catch return error.Fatal;
    defer vm.allocator.free(kept);

    var kept_len: usize = 0;
    var deleted = false;
    for (array.elements.items) |element| {
        if (try vm.valueEquals(element, args[0])) {
            deleted = true;
            continue;
        }

        kept[kept_len] = element;
        kept_len += 1;
    }

    if (!deleted) {
        if (block) |blk| {
            const yielded = try vm.yieldToBlock(blk, &[_]Value{});
            if (yielded.controlFlowValue()) |return_value| return return_value;
            return yielded.value;
        }
        return Value.nil();
    }

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    std.mem.copyForwards(Value, array.elements.items[0..kept_len], kept[0..kept_len]);
    array.elements.items.len = kept_len;
    return args[0];
}

pub fn builtinArrayCompact(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const source = receiver.toArrayObject();
    const out = try vm.createArray();
    for (source.elements.items) |element| {
        if (!element.isNil()) {
            out.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        }
    }

    return Value.fromObject(&out.object);
}

pub fn builtinArrayCompactBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    var write_idx: usize = 0;
    for (array.elements.items, 0..) |element, read_idx| {
        if (!element.isNil()) {
            if (write_idx != read_idx) {
                array.elements.items[write_idx] = element;
            }
            write_idx += 1;
        }
    }

    if (write_idx == array.elements.items.len) {
        return Value.nil();
    }

    array.elements.items.len = write_idx;
    return receiver;
}

pub fn builtinArrayFlatten(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const remaining_depth = try arrayFlattenDepthArg(vm, args);

    const out = try vm.createArray();
    var seen = std.AutoHashMap(usize, void).init(vm.allocator);
    defer seen.deinit();

    try arrayFlattenInto(vm, out, receiver.toArrayObject(), &seen, remaining_depth, null);
    return Value.fromObject(&out.object);
}

pub fn builtinArrayFlattenBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const remaining_depth = try arrayFlattenDepthArg(vm, args);
    if (remaining_depth == 0) return Value.nil();

    const out = try vm.createArray();
    var seen = std.AutoHashMap(usize, void).init(vm.allocator);
    defer seen.deinit();

    var modified = false;
    try arrayFlattenInto(vm, out, receiver.toArrayObject(), &seen, remaining_depth, &modified);
    if (!modified) return Value.nil();

    const array = receiver.toArrayObject();
    array.elements.clearRetainingCapacity();
    array.elements.appendSlice(vm.gc_allocator, out.elements.items) catch return error.Fatal;
    return receiver;
}

pub fn builtinArrayAny(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const array = receiver.toArrayObject();
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    if (pattern) |pat| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            if (try arrayPatternMatches(vm, pat, array.elements.items[idx])) {
                return Value.boolean(true);
            }
        }
        return Value.boolean(false);
    }

    if (block) |blk| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            const element = array.elements.items[idx];
            const yield_args = [_]Value{element};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            if (yielded.value.is_truthy()) return Value.boolean(true);
        }
        return Value.boolean(false);
    }

    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        if (array.elements.items[idx].is_truthy()) return Value.boolean(true);
    }
    return Value.boolean(false);
}

pub fn builtinArrayNone(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const array = receiver.toArrayObject();
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    if (pattern) |pat| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            if (try arrayPatternMatches(vm, pat, array.elements.items[idx])) {
                return Value.boolean(false);
            }
        }
        return Value.boolean(true);
    }

    if (block) |blk| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            const element = array.elements.items[idx];
            const yield_args = [_]Value{element};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            if (yielded.value.is_truthy()) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        if (array.elements.items[idx].is_truthy()) return Value.boolean(false);
    }
    return Value.boolean(true);
}

pub fn builtinArrayOne(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const array = receiver.toArrayObject();
    const pattern = if (args.len == 1) args[0] else null;
    var matched: usize = 0;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    if (pattern) |pat| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            if (try arrayPatternMatches(vm, pat, array.elements.items[idx])) {
                matched += 1;
                if (matched > 1) return Value.boolean(false);
            }
        }
        return Value.boolean(matched == 1);
    }

    if (block) |blk| {
        var idx: usize = 0;
        while (idx < array.elements.items.len) : (idx += 1) {
            const element = array.elements.items[idx];
            const yield_args = [_]Value{element};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            if (yielded.value.is_truthy()) {
                matched += 1;
                if (matched > 1) return Value.boolean(false);
            }
        }
        return Value.boolean(matched == 1);
    }

    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        if (array.elements.items[idx].is_truthy()) {
            matched += 1;
            if (matched > 1) return Value.boolean(false);
        }
    }
    return Value.boolean(matched == 1);
}

pub fn builtinArrayPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const rhs_value = try vm.coerceToArrayValue(args[0]);

    const lhs = receiver.toArrayObject();
    const rhs = rhs_value.toArrayObject();
    const out = try vm.createArray();
    out.elements.appendSlice(vm.gc_allocator, lhs.elements.items) catch return error.Fatal;
    out.elements.appendSlice(vm.gc_allocator, rhs.elements.items) catch return error.Fatal;
    return Value.fromObject(&out.object);
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

    const array = receiver.toArrayObject();
    const uses_default_separator = args.len == 0 or args[0].isNil();
    const global_separator = if (uses_default_separator) vm.globals.get("$,") orelse Value.nil() else Value.nil();

    if (array.elements.items.len == 0) {
        if (uses_default_separator and !global_separator.isNil()) {
            try arrayJoinWarnDefaultSeparator(vm);
        }
        return try vm.newStringWithEncoding("", false, .{ .us_ascii = .{} });
    }

    const separator = blk: {
        if (!uses_default_separator) {
            break :blk try args[0].coerceToStringValue(vm, "no implicit conversion into String");
        }
        if (global_separator.isNil()) break :blk null;
        try arrayJoinWarnDefaultSeparator(vm);
        break :blk try global_separator.coerceToStringValue(vm, "no implicit conversion into String");
    };

    var seen = std.AutoHashMap(usize, void).init(vm.allocator);
    defer seen.deinit();

    var state = JoinState{};
    defer state.bytes.deinit(vm.allocator);

    try arrayJoinAppendArray(vm, &state, array, separator, &seen);
    const out = state.bytes.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(out);
    return try vm.newStringWithEncoding(out, false, state.encoding);
}

pub fn builtinArrayMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    switch (try vm.probeToStringValue(args[0])) {
        .string => |separator| {
            var join_args = [_]Value{separator};
            return builtinArrayJoin(vm, receiver, join_args[0..], null);
        },
        .missing, .nil_result => {},
    }

    const count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (count < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative argument", .{});
    }

    const array = receiver.toArrayObject();
    const out = try vm.createArray();

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        for (array.elements.items) |elem| {
            out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }

    return Value.fromObject(&out.object);
}

pub fn builtinArrayClassBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }

    const out = try vm.newObjectForClass(receiver.toClassObject());
    const array = out.toArrayObject();
    for (args) |arg| {
        array.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    }
    return out;
}

pub fn builtinArrayUniq(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const input = receiver.toArrayObject();
    const out = try vm.createArray();

    for (input.elements.items) |candidate| {
        var seen = false;
        for (out.elements.items) |existing| {
            if (try vm.hashKeysEqual(candidate, existing)) {
                seen = true;
                break;
            }
        }
        if (!seen) {
            out.elements.append(vm.gc_allocator, candidate) catch return error.Fatal;
        }
    }

    return Value.fromObject(&out.object);
}

pub fn builtinArrayUniqBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const array = receiver.toArrayObject();
    const kept = vm.allocator.alloc(Value, array.elements.items.len) catch return error.Fatal;
    defer vm.allocator.free(kept);

    var kept_len: usize = 0;
    var changed = false;
    for (array.elements.items) |candidate| {
        var seen = false;
        for (kept[0..kept_len]) |existing| {
            if (try vm.hashKeysEqual(candidate, existing)) {
                seen = true;
                changed = true;
                break;
            }
        }
        if (!seen) {
            kept[kept_len] = candidate;
            kept_len += 1;
        }
    }

    if (!changed) return Value.nil();
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    std.mem.copyForwards(Value, array.elements.items[0..kept_len], kept[0..kept_len]);
    array.elements.items.len = kept_len;
    return receiver;
}

pub fn builtinArrayFirst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const array = receiver.toArrayObject();

    if (args.len == 0) {
        if (array.elements.items.len == 0) return Value.nil();
        return array.elements.items[0];
    }

    try vm.requireArgCount(args, 1);
    const count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (count < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    const out = try vm.createArray();
    const clamped_count: usize = @intCast(@min(count, @as(i64, @intCast(array.elements.items.len))));
    for (array.elements.items[0..clamped_count]) |elem| {
        out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinArrayLast(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const array = receiver.toArrayObject();

    if (args.len == 0) {
        if (array.elements.items.len == 0) return Value.nil();
        return array.elements.items[array.elements.items.len - 1];
    }

    try vm.requireArgCount(args, 1);
    const count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (count < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    const out = try vm.createArray();
    const clamped_count: usize = @intCast(@min(count, @as(i64, @intCast(array.elements.items.len))));
    const start = array.elements.items.len - clamped_count;
    for (array.elements.items[start..]) |elem| {
        out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinArrayAt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const index = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);
    var actual_index = index;
    if (actual_index < 0) actual_index += len;

    if (actual_index < 0 or actual_index >= len) {
        return Value.nil();
    }

    return array.elements.items[@intCast(actual_index)];
}

pub fn builtinArrayFetch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (args.len == 2 and block != null) {
        try warning_builtin.writeWarning(vm, "warning: block supersedes default value argument\n");
    }

    const index_value = args[0];
    const index = try coerceFetchIndex(vm, index_value);

    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);
    var actual_index = index;
    if (actual_index < 0) actual_index += len;

    if (actual_index < 0 or actual_index >= len) {
        if (block) |blk| {
            const yielded = try vm.yieldToBlock(blk, &[_]Value{index_value});
            if (yielded.controlFlowValue()) |return_value| return return_value;
            return yielded.value;
        }

        if (args.len == 2) return args[1];

        const lower_bound: i64 = if (len == 0) 0 else -len;
        return vm.raiseExceptionFmt(
            vm.index_error_class,
            "index {d} outside of array bounds: {d}...{d}",
            .{ index, lower_bound, len },
        );
    }

    return array.elements.items[@intCast(actual_index)];
}

pub fn builtinArrayAssoc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const key = args[0];
    const array = receiver.toArrayObject();
    for (array.elements.items) |element| {
        const match = (try arrayProbePairElement(vm, element, 0)) orelse continue;
        if (try vm.valueEquals(match.item, key)) return Value.fromObject(&match.pair.object);
    }

    return Value.nil();
}

pub fn builtinArrayRassoc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const key = args[0];
    const array = receiver.toArrayObject();
    for (array.elements.items) |element| {
        const match = (try arrayProbePairElement(vm, element, 1)) orelse continue;
        if (try vm.valueEquals(match.item, key)) return Value.fromObject(&match.pair.object);
    }

    return Value.nil();
}

pub fn builtinArrayIndex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
    if (args.len == 0 and block == null) {
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("index"), &.{}, size_value);
    }

    if (args.len == 1 and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    const array = receiver.toArrayObject();

    if (args.len == 1) {
        if (try arrayFindIndexByEquality(vm, array.elements.items, args[0])) |idx| {
            return Value.integer(@intCast(idx));
        }
        return Value.nil();
    }

    const blk = block.?;
    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{array.elements.items[idx]});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.is_truthy()) return Value.integer(@intCast(idx));
    }
    return Value.nil();
}

pub fn builtinArrayRindex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
    if (args.len == 0 and block == null) {
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("rindex"), &.{}, size_value);
    }

    if (args.len == 1 and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    const array = receiver.toArrayObject();

    if (args.len == 1) {
        var idx = array.elements.items.len;
        while (idx > 0) {
            if (try vm.valueEquals(array.elements.items[idx - 1], args[0])) {
                return Value.integer(@intCast(idx - 1));
            }
            idx -= 1;
        }
        return Value.nil();
    }

    const blk = block.?;
    var idx: usize = array.elements.items.len;
    while (idx > 0) {
        const current_len = array.elements.items.len;
        if (idx > current_len) idx = current_len;
        if (idx == 0) break;

        idx -= 1;
        const yielded = try vm.yieldToBlock(blk, &[_]Value{array.elements.items[idx]});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        if (yielded.value.is_truthy()) return Value.integer(@intCast(idx));
    }
    return Value.nil();
}

pub fn builtinArrayBsearch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (block == null) {
        return try vm.createMethodEnumerator(receiver, try vm.intern("bsearch"), &.{});
    }

    return vm.raiseExceptionFmt(vm.runtime_error_class, "Array#bsearch is not implemented yet", .{});
}

pub fn builtinArrayDig(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const current_value = try builtinArrayAt(vm, receiver, args[0..1], null);
    if (args.len == 1 or current_value.isNil()) {
        return current_value;
    }

    if (!try vm.respondsToMethodByName(current_value, "dig", false)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} does not have #dig method", .{vm.className(current_value)});
    }

    return vm.callMethodByName(current_value, "dig", args[1..], null);
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

    return Value.fromObject(&result.object);
}

pub fn builtinArrayClear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    array.elements.clearRetainingCapacity();
    return receiver;
}

pub fn builtinArrayShift(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    if (args.len == 0) {
        if (array.elements.items.len == 0) return Value.nil();
        return array.elements.orderedRemove(0);
    }

    const count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (count < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    const out = try vm.createArray();
    const shift_count: usize = @intCast(@min(count, @as(i64, @intCast(array.elements.items.len))));
    var i: usize = 0;
    while (i < shift_count) : (i += 1) {
        out.elements.append(vm.gc_allocator, array.elements.orderedRemove(0)) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinArrayPop(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    if (args.len == 0) {
        if (array.elements.items.len == 0) return Value.nil();
        return array.elements.pop().?;
    }

    const count = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (count < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    const out = try vm.createArray();
    const pop_count: usize = @intCast(@min(count, @as(i64, @intCast(array.elements.items.len))));
    const start = array.elements.items.len - pop_count;
    for (array.elements.items[start..]) |element| {
        out.elements.append(vm.gc_allocator, element) catch return error.Fatal;
    }
    array.elements.shrinkRetainingCapacity(start);
    return Value.fromObject(&out.object);
}

pub fn builtinArrayDeleteAt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const index_value = try args[0].coerceToIntegerValue(vm, "no implicit conversion to Integer", "can't convert to Integer");
    const index = try index_value.integerToI64(vm, "index too big");
    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);
    var actual_index = index;
    if (actual_index < 0) actual_index += len;
    if (actual_index < 0 or actual_index >= len) return Value.nil();

    return array.elements.orderedRemove(@intCast(actual_index));
}

pub fn builtinArrayDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const out = try vm.newObjectForClass(vm.getClass(receiver));
    const source = receiver.toArrayObject();
    const duplicate = out.toArrayObject();
    duplicate.elements.appendSlice(vm.gc_allocator, source.elements.items) catch return error.Fatal;

    const src_obj = receiver.getObjectPointer().?;
    const dst_obj = out.getObjectPointer().?;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    var initialize_dup_args = [_]Value{receiver};
    _ = try vm.callMethodByName(out, "initialize_dup", initialize_dup_args[0..], null);
    return out;
}

pub fn builtinArrayClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const kwfreeze = try vm.consumeCloneFreezeOpt();

    const out = try vm.newObjectForClass(vm.getClass(receiver));
    const source = receiver.toArrayObject();
    const duplicate = out.toArrayObject();
    duplicate.elements.appendSlice(vm.gc_allocator, source.elements.items) catch return error.Fatal;

    const src_obj = receiver.getObjectPointer().?;
    const dst_obj = out.getObjectPointer().?;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    try vm.callInitializeClone(out, receiver, kwfreeze);
    vm.applyCloneFreeze(receiver, out, kwfreeze);
    try vm.copySingletonClassMetadata(receiver, out);
    return out;
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

    return Value.fromObject(&result.object);
}

pub fn builtinArrayMinus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .array, "Array");
    const left = receiver.toArrayObject();
    const right = args[0].toArrayObject();
    const result = try vm.createArray();

    for (left.elements.items) |elem| {
        if (!(try arrayContainsEquivalent(vm, right.elements.items, elem))) {
            result.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
        }
    }

    return Value.fromObject(&result.object);
}

pub fn builtinArrayInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (try vm.enterRecursionGuard(.array_inspect, receiver, Value.nil())) {
        return try vm.newStringWithEncoding("[...]", false, .{ .us_ascii = .{} });
    }
    defer vm.leaveRecursionGuard(.array_inspect, receiver, Value.nil());

    const array = receiver.toArrayObject();
    if (array.elements.items.len == 0) {
        return try vm.newStringWithEncoding("[]", false, .{ .us_ascii = .{} });
    }

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    var output_encoding: enc.Encoding = .{ .us_ascii = .{} };

    writer.writeAll("[") catch return error.Fatal;
    for (array.elements.items, 0..) |elem, idx| {
        if (idx > 0) {
            writer.writeAll(", ") catch return error.Fatal;
        }

        const inspected = try elem.inspect(vm);
        const inspected_obj = inspected.toStringObject();
        if (idx == 0) {
            output_encoding = inspected_obj.encoding;
        } else {
            output_encoding = arrayJoinResolveEncoding(output_encoding, buf.written(), inspected_obj.encoding, inspected_obj.str) orelse {
                return vm.raiseEncodingCompatibilityError(output_encoding, inspected_obj.encoding);
            };
        }
        writer.writeAll(inspected_obj.str) catch return error.Fatal;
    }
    writer.writeAll("]") catch return error.Fatal;

    const out = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(out);
    return try vm.newStringWithEncoding(out, false, output_encoding);
}

pub fn builtinArrayToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.toArrayObject().object.class == vm.array_class) {
        return receiver;
    }

    const source = receiver.toArrayObject();
    const out = try vm.createArray();
    for (source.elements.items) |elem| {
        out.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinArrayToAry(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinArrayToH(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const array = receiver.toArrayObject();
    const hash = try vm.createHash();

    var idx: usize = 0;
    while (idx < array.elements.items.len) : (idx += 1) {
        const source = if (block) |blk| blk: {
            const yield_args = [_]Value{array.elements.items[idx]};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;
            break :blk yielded.value;
        } else array.elements.items[idx];

        const pair = try arrayToHashPair(vm, source, idx);
        try vm.hashSetEntry(hash, pair.key, pair.value);
    }

    return Value.fromObject(&hash.object);
}

pub fn builtinArrayReplace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const replacement = try vm.coerceToArrayValue(args[0]);

    const target = receiver.toArrayObject();
    const source = replacement.toArrayObject();
    target.elements.clearRetainingCapacity();
    for (source.elements.items) |elem| {
        target.elements.append(vm.gc_allocator, elem) catch return error.Fatal;
    }
    return receiver;
}

pub fn builtinArrayAll(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const array_obj = receiver.toArrayObject();
    const pattern = if (args.len == 1) args[0] else null;

    if (pattern != null and block != null) {
        try warning_builtin.warnBlockUnused(vm);
    }

    if (pattern) |pat| {
        var idx: usize = 0;
        while (idx < array_obj.elements.items.len) : (idx += 1) {
            if (!try arrayPatternMatches(vm, pat, array_obj.elements.items[idx])) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    if (block) |blk| {
        var idx: usize = 0;
        while (idx < array_obj.elements.items.len) : (idx += 1) {
            const element = array_obj.elements.items[idx];
            const yield_args = [_]Value{element};
            const result = try vm.yieldToBlock(blk, &yield_args);
            if (result.controlFlowValue()) |return_value| return return_value;

            if (!result.value.is_truthy()) return Value.boolean(false);
        }
        return Value.boolean(true);
    }

    var idx: usize = 0;
    while (idx < array_obj.elements.items.len) : (idx += 1) {
        if (!array_obj.elements.items[idx].is_truthy()) return Value.boolean(false);
    }

    return Value.boolean(true);
}

pub fn builtinArrayCount(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const array_obj = receiver.toArrayObject();

    if (args.len == 1) {
        const pattern = args[0];
        if (block) |_| {
            try warning_builtin.warnBlockUnused(vm);
        }
        var count: usize = 0;
        var idx: usize = 0;
        while (idx < array_obj.elements.items.len) : (idx += 1) {
            if (try arrayPatternMatches(vm, pattern, array_obj.elements.items[idx])) count += 1;
        }
        return Value.integer(@intCast(count));
    }

    if (block) |blk| {
        var count: usize = 0;
        var idx: usize = 0;
        while (idx < array_obj.elements.items.len) : (idx += 1) {
            const yield_args = [_]Value{array_obj.elements.items[idx]};
            const result = try vm.yieldToBlock(blk, &yield_args);
            if (result.controlFlowValue()) |return_value| return return_value;
            if (result.value.is_truthy()) count += 1;
        }
        return Value.integer(@intCast(count));
    }

    return Value.integer(@intCast(array_obj.elements.items.len));
}

pub fn builtinArraySort(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
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
            const less_than = if (block) |blk| blk: {
                const cmp_result = try arraySortBlockLessThan(vm, blk, key, prev);
                switch (cmp_result) {
                    .less_than => |lt| break :blk lt,
                    .control_flow_value => |value_to_return| return value_to_return,
                }
            } else try arrayValueLessThan(vm, key, prev);
            if (!less_than) break;
            result.elements.items[j] = prev;
            j -= 1;
        }
        result.elements.items[j] = key;
    }

    return Value.fromObject(&result.object);
}

pub fn builtinArraySortBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }
    const array = receiver.toArrayObject();

    var i: usize = 1;
    while (i < array.elements.items.len) : (i += 1) {
        const key = array.elements.items[i];
        var j = i;
        while (j > 0) {
            const prev = array.elements.items[j - 1];
            const less_than = if (block) |blk| blk: {
                const cmp_result = try arraySortBlockLessThan(vm, blk, key, prev);
                switch (cmp_result) {
                    .less_than => |lt| break :blk lt,
                    .control_flow_value => |value_to_return| return value_to_return,
                }
            } else try arrayValueLessThan(vm, key, prev);
            if (!less_than) break;
            array.elements.items[j] = prev;
            j -= 1;
        }
        array.elements.items[j] = key;
    }

    return receiver;
}

pub fn builtinArrayReverse(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const source = receiver.toArrayObject();
    const out = try vm.createArray();
    out.elements.appendSlice(vm.gc_allocator, source.elements.items) catch return error.Fatal;
    std.mem.reverse(Value, out.elements.items);

    return Value.fromObject(&out.object);
}

pub fn builtinArrayReverseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    std.mem.reverse(Value, array.elements.items);
    return receiver;
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

fn arrayFilterBangFinalize(
    vm: *VM,
    receiver: Value,
    target: *value.ArrayObject,
    processed_len: usize,
    kept_len: usize,
    return_nil_if_unchanged: bool,
) VMError!Value {
    const current_len = target.elements.items.len;

    if (kept_len < current_len and kept_len < processed_len) {
        if (receiver.isFrozen()) {
            return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
        }

        const tail_len = if (processed_len < current_len) current_len - processed_len else 0;
        if (tail_len > 0) {
            std.mem.copyForwards(
                Value,
                target.elements.items[kept_len .. kept_len + tail_len],
                target.elements.items[processed_len .. processed_len + tail_len],
            );
        }
        target.elements.items.len = kept_len + tail_len;
    }

    if (return_nil_if_unchanged and processed_len == kept_len) return Value.nil();
    return receiver;
}

fn arrayFilterBangShared(
    vm: *VM,
    receiver: Value,
    args: []Value,
    block: ?Block,
    method_name: []const u8,
    keep_truthy: bool,
    return_nil_if_unchanged: bool,
) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern(method_name), &.{}, size_value);
    };
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen Array", .{});
    }

    const array = receiver.toArrayObject();
    var processed_len: usize = 0;
    var kept_len: usize = 0;

    while (processed_len < array.elements.items.len) {
        const element = array.elements.items[processed_len];
        const yield_args = [_]Value{element};
        const yielded = vm.yieldToBlock(blk, &yield_args) catch |err| {
            _ = try arrayFilterBangFinalize(vm, receiver, array, processed_len, kept_len, return_nil_if_unchanged);
            return err;
        };
        if (yielded.controlFlowValue()) |return_value| {
            _ = try arrayFilterBangFinalize(vm, receiver, array, processed_len, kept_len, return_nil_if_unchanged);
            return return_value;
        }

        if (yielded.value.is_truthy() == keep_truthy) {
            if (processed_len != kept_len) {
                array.elements.items[kept_len] = element;
            }
            kept_len += 1;
        }
        processed_len += 1;
    }

    return try arrayFilterBangFinalize(vm, receiver, array, processed_len, kept_len, return_nil_if_unchanged);
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

pub fn builtinArrayMax(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    const items = array.elements.items;
    if (items.len == 0) return Value.nil();

    var max = items[0];
    if (block) |blk| {
        for (items[1..]) |item| {
            const yield_args = [_]Value{ item, max };
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.controlFlowValue()) |return_value| return return_value;

            const sign = try arraySortBlockResultSign(vm, yielded.value);
            if (sign > 0) max = item;
        }
        return max;
    }

    for (items[1..]) |item| {
        if (try arrayValueLessThan(vm, max, item)) max = item;
    }
    return max;
}

const SortBlockCompareResult = union(enum) {
    less_than: bool,
    control_flow_value: Value,
};

fn arraySortBlockLessThan(vm: *VM, blk: Block, lhs: Value, rhs: Value) VMError!SortBlockCompareResult {
    const yield_args = [_]Value{ lhs, rhs };
    const result = try vm.yieldToBlock(blk, &yield_args);
    if (result.controlFlowValue()) |return_value| {
        return .{ .control_flow_value = return_value };
    }

    const cmp = try arraySortBlockResultSign(vm, result.value);
    return .{ .less_than = cmp < 0 };
}

fn arraySortBlockResultSign(vm: *VM, cmp_value: Value) VMError!i8 {
    if (cmp_value.isNil()) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "comparison of {s} with {s} failed",
            .{ vm.className(cmp_value), "0" },
        );
    }
    if (cmp_value.isInteger()) {
        const n = cmp_value.toInteger();
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp_value.isFloat()) {
        const n = cmp_value.toFloatObject().val;
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp_value.isBigInteger()) {
        const n = cmp_value.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }

    var zero_arg = [_]Value{Value.integer(0)};
    const cmp = try vm.callMethodByName(cmp_value, "<=>", zero_arg[0..], null);
    if (cmp.isInteger()) {
        const n = cmp.toInteger();
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp.isFloat()) {
        const n = cmp.toFloatObject().val;
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp.isBigInteger()) {
        const n = cmp.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }

    return vm.raiseExceptionFmt(
        vm.argument_error_class,
        "comparison of {s} with 0 failed",
        .{vm.className(cmp_value)},
    );
}
