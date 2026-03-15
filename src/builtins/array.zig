const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const pack_runtime = @import("../pack.zig");
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
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ state.encoding.name(), str_obj.encoding.name() },
        );
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

    if (try vm.checkCallMethodByName(elem, "to_str", &[_]Value{}, null)) |to_str_value| {
        if (!to_str_value.isNil()) {
            if (!to_str_value.isString()) {
                const exc = try vm.createException(vm.type_error_class, "no implicit conversion into String");
                vm.pending_exception = exc;
                return error.Unwind;
            }
            try arrayJoinAppendString(vm, state, to_str_value);
            return;
        }
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
        vm.pending_exception = exc;
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

pub fn register(vm: *VM) !void {
    const array_class_val = Value.fromObject(vm.array_class);
    const array_singleton = try vm.getOrCreateSingletonClass(array_class_val);

    const class_bracket_sym = try vm.intern("[]");
    try array_singleton.module.methods.put(class_bracket_sym, .{ .method = .{ .builtin = &builtinArrayClassBracket } });

    const initialize_sym = try vm.intern("initialize");
    try vm.array_class.module.methods.put(initialize_sym, .{
        .method = .{ .builtin = &builtinArrayInitialize },
        .visibility = .private,
    });

    const push_sym = try vm.intern("<<");
    try vm.array_class.module.methods.put(push_sym, .{ .method = .{ .builtin = &builtinArrayPush } });

    const append_sym = try vm.intern("append");
    try vm.array_class.module.methods.put(append_sym, .{ .method = .{ .builtin = &builtinArrayAppend } });

    const push_method_sym = try vm.intern("push");
    try vm.array_class.module.methods.put(push_method_sym, .{ .method = .{ .builtin = &builtinArrayAppend } });

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

    const select_sym = try vm.intern("select");
    try vm.array_class.module.methods.put(select_sym, .{ .method = .{ .builtin = &builtinArraySelect } });

    const select_bang_sym = try vm.intern("select!");
    try vm.array_class.module.methods.put(select_bang_sym, .{ .method = .{ .builtin = &builtinArraySelectBang } });

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

    const at_sym = try vm.intern("at");
    try vm.array_class.module.methods.put(at_sym, .{ .method = .{ .builtin = &builtinArrayAt } });

    const intersection_sym = try vm.intern("&");
    try vm.array_class.module.methods.put(intersection_sym, .{ .method = .{ .builtin = &builtinArrayIntersection } });

    const union_sym = try vm.intern("|");
    try vm.array_class.module.methods.put(union_sym, .{ .method = .{ .builtin = &builtinArrayUnion } });

    const plus_sym = try vm.intern("+");
    try vm.array_class.module.methods.put(plus_sym, .{ .method = .{ .builtin = &builtinArrayPlus } });

    const to_s_sym = try vm.intern("to_s");
    try vm.array_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinArrayToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.array_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinArrayInspect } });

    const to_a_sym = try vm.intern("to_a");
    try vm.array_class.module.methods.put(to_a_sym, .{ .method = .{ .builtin = &builtinArrayToA } });

    const replace_sym = try vm.intern("replace");
    try vm.array_class.module.methods.put(replace_sym, .{ .method = .{ .builtin = &builtinArrayReplace } });

    const all_sym = try vm.intern("all?");
    try vm.array_class.module.methods.put(all_sym, .{ .method = .{ .builtin = &builtinArrayAll } });

    const sort_sym = try vm.intern("sort");
    try vm.array_class.module.methods.put(sort_sym, .{ .method = .{ .builtin = &builtinArraySort } });

    const pack_sym = try vm.intern("pack");
    try vm.array_class.module.methods.put(pack_sym, .{ .method = .{ .builtin = &builtinArrayPack } });

    const multiply_sym = try vm.intern("*");
    try vm.array_class.module.methods.put(multiply_sym, .{ .method = .{ .builtin = &builtinArrayMultiply } });

    const clear_sym = try vm.intern("clear");
    try vm.array_class.module.methods.put(clear_sym, .{ .method = .{ .builtin = &builtinArrayClear } });

    const shift_sym = try vm.intern("shift");
    try vm.array_class.module.methods.put(shift_sym, .{ .method = .{ .builtin = &builtinArrayShift } });

    const dup_sym = try vm.intern("dup");
    try vm.array_class.module.methods.put(dup_sym, .{ .method = .{ .builtin = &builtinArrayDup } });
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

pub fn builtinArrayInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    const array = receiver.toArrayObject();
    array.elements.clearRetainingCapacity();

    if (args.len == 0) {
        return receiver;
    }

    const size = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (size < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative array size", .{});
    }

    var i: i64 = 0;
    if (block) |blk| {
        while (i < size) : (i += 1) {
            const yield_args = [_]Value{Value.integer(i)};
            const yielded = try vm.yieldToBlock(blk, &yield_args);
            if (yielded.break_occurred) {
                return yielded.value;
            }
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

pub fn builtinArrayBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const array = receiver.toArrayObject();
    const len: i64 = @intCast(array.elements.items.len);

    if (args.len == 1) {
        // Single argument: arr[index] or arr[range]
        if (args[0].isInteger()) {
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
        }

        if (args[0].isRange()) {
            const range_obj = args[0].toRangeObject();
            if (!range_obj.begin.isInteger() or !range_obj.end.isInteger()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Range into Integer", .{});
            }

            var start = range_obj.begin.toInteger();
            if (start < 0) start += len;
            if (start < 0 or start > len) {
                return Value.nil();
            }

            var finish = range_obj.end.toInteger();
            if (finish < 0) finish += len;
            if (!range_obj.exclude_end) finish += 1;

            if (finish < start) {
                const empty = try vm.createArray();
                return Value.fromObject(empty);
            }

            const clamped_end = @max(start, @min(finish, len));

            const result_array = try vm.createArray();
            var i: i64 = start;
            while (i < clamped_end) : (i += 1) {
                const idx: usize = @intCast(i);
                result_array.elements.append(vm.gc_allocator, array.elements.items[idx]) catch return error.Fatal;
            }
            return Value.fromObject(result_array);
        }

        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into Integer", .{vm.className(args[0])});
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
    return builtinArrayInspect(vm, receiver, args, null);
}

pub fn builtinArrayLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = receiver.toArrayObject();
    return Value.integer(@intCast(array.elements.items.len));
}

pub fn builtinArrayMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("map"), &.{}, size_value);
    };
    const source = receiver.toArrayObject();
    const result = try vm.createArray();

    var idx: usize = 0;
    while (idx < source.elements.items.len) : (idx += 1) {
        const element = source.elements.items[idx];
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
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("map!"), &.{}, size_value);
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
        if (yielded.break_occurred) {
            return yielded.value;
        }
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
        if (yielded.break_occurred) {
            return yielded.value;
        }
        if (yielded.value.is_truthy()) {
            result.elements.append(vm.gc_allocator, element) catch return error.Fatal;
        }
    }

    return Value.fromObject(result);
}

pub fn builtinArraySelectBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const size_value = Value.integer(@intCast(receiver.toArrayObject().elements.items.len));
        return try vm.createMethodEnumeratorWithSize(receiver, try vm.intern("select!"), &.{}, size_value);
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
            _ = try arraySelectBangFinalize(vm, receiver, array, processed_len, kept_len);
            return err;
        };
        if (yielded.break_occurred) {
            _ = try arraySelectBangFinalize(vm, receiver, array, processed_len, kept_len);
            return yielded.value;
        }
        if (yielded.value.is_truthy()) {
            if (processed_len != kept_len) {
                array.elements.items[kept_len] = element;
            }
            kept_len += 1;
        }
        processed_len += 1;
    }

    return try arraySelectBangFinalize(vm, receiver, array, processed_len, kept_len);
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
            if (yielded.break_occurred) {
                return yielded.value;
            }
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

pub fn builtinArrayPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const rhs_value = try vm.coerceToArrayValue(args[0]);

    const lhs = receiver.toArrayObject();
    const rhs = rhs_value.toArrayObject();
    const out = try vm.createArray();
    out.elements.appendSlice(vm.gc_allocator, lhs.elements.items) catch return error.Fatal;
    out.elements.appendSlice(vm.gc_allocator, rhs.elements.items) catch return error.Fatal;
    return Value.fromObject(out);
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

    return Value.fromObject(out);
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
    return Value.fromObject(out);
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
    return Value.fromObject(out);
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
    return Value.fromObject(out);
}

pub fn builtinArrayDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const out = try vm.newObjectForClass(vm.getClass(receiver));
    const source = receiver.toArrayObject();
    const duplicate = out.toArrayObject();
    duplicate.elements.appendSlice(vm.gc_allocator, source.elements.items) catch return error.Fatal;
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

    return Value.fromObject(result);
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

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    const writer = buf.writer(vm.allocator);
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
            output_encoding = arrayJoinResolveEncoding(output_encoding, buf.items, inspected_obj.encoding, inspected_obj.str) orelse {
                return vm.raiseExceptionFmt(
                    vm.encoding_compatibility_error_class,
                    "incompatible character encodings: {s} and {s}",
                    .{ output_encoding.name(), inspected_obj.encoding.name() },
                );
            };
        }
        writer.writeAll(inspected_obj.str) catch return error.Fatal;
    }
    writer.writeAll("]") catch return error.Fatal;

    const out = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
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
    return Value.fromObject(out);
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
            if (result.break_occurred) {
                return result.value;
            }

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

fn arraySelectBangFinalize(
    vm: *VM,
    receiver: Value,
    target: *value.ArrayObject,
    processed_len: usize,
    kept_len: usize,
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

    if (processed_len == kept_len) return Value.nil();
    return receiver;
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
