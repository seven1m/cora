const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const init_sym = try vm.intern("initialize");
    try vm.range_class.module.methods.put(init_sym, value.MethodEntry.builtin(&builtinRangeInitialize, .{ .variadic = 0 }));

    const begin_sym = try vm.intern("begin");
    try vm.range_class.module.methods.put(begin_sym, value.MethodEntry.builtin(&builtinRangeBegin, .{ .exact = 0 }));

    const end_sym = try vm.intern("end");
    try vm.range_class.module.methods.put(end_sym, value.MethodEntry.builtin(&builtinRangeEnd, .{ .exact = 0 }));

    const exclude_end_sym = try vm.intern("exclude_end?");
    try vm.range_class.module.methods.put(exclude_end_sym, value.MethodEntry.builtin(&builtinRangeExcludeEnd, .{ .exact = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.range_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinRangeToA, .{ .exact = 0 }));

    const each_sym = try vm.intern("each");
    try vm.range_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinRangeEach, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.range_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinRangeInspect, .{ .exact = 0 }));

    const case_equal_sym = try vm.intern("===");
    try vm.range_class.module.methods.put(case_equal_sym, value.MethodEntry.builtin(&builtinRangeCaseEqual, .{ .exact = 1 }));

    const bsearch_sym = try vm.intern("bsearch");
    try vm.range_class.module.methods.put(bsearch_sym, value.MethodEntry.builtin(&builtinRangeBsearch, .{ .exact = 0 }));
}

pub fn builtinRangeInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const exclude_end = if (args.len == 3) args[2].is_truthy() else false;

    receiver.toRangeObject().begin = args[0];
    receiver.toRangeObject().end = args[1];
    receiver.toRangeObject().exclude_end = exclude_end;

    return Value.nil();
}

pub fn builtinRangeBegin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }
    return receiver.toRangeObject().begin;
}

pub fn builtinRangeEnd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }
    return receiver.toRangeObject().end;
}

pub fn builtinRangeExcludeEnd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }
    return Value.boolean(receiver.toRangeObject().exclude_end);
}

pub fn builtinRangeToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;
    const exclude_end = range_obj.exclude_end;

    if (begin_val.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert beginless range to an array", .{});
    }

    if (end_val.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert endless range to an array", .{});
    }

    const array_obj = try vm.createArray();

    if (begin_val.isInteger() and end_val.isInteger()) {
        const start_i = begin_val.toInteger();
        const end_i = end_val.toInteger();

        if (exclude_end) {
            var current = start_i;
            while (current < end_i) : (current += 1) {
                array_obj.elements.append(vm.gc_allocator, Value.integer(current)) catch return error.Fatal;
                if (current == std.math.maxInt(i64)) break;
            }
        } else {
            var current = start_i;
            while (current <= end_i) : (current += 1) {
                array_obj.elements.append(vm.gc_allocator, Value.integer(current)) catch return error.Fatal;
                if (current == std.math.maxInt(i64)) break;
            }
        }
        return Value.fromObject(&array_obj.object);
    }

    if (begin_val.isString() and end_val.isString()) {
        try appendStringRangeToArray(vm, array_obj, begin_val, end_val, exclude_end);
        return Value.fromObject(&array_obj.object);
    }

    return vm.raiseExceptionFmt(
        vm.type_error_class,
        "wrong argument type (expected Integer)",
        .{},
    );
}

pub fn builtinRangeEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    };

    const range_obj = receiver.toRangeObject();
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;
    const exclude_end = range_obj.exclude_end;

    if (begin_val.isNil() or end_val.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot iterate from beginless or endless range", .{});
    }

    if (begin_val.isInteger() and end_val.isInteger()) {
        const start_i = begin_val.toInteger();
        const end_i = end_val.toInteger();

        if (exclude_end) {
            var current = start_i;
            while (current < end_i) : (current += 1) {
                const yield_args = [_]Value{Value.integer(current)};
                const result = try vm.yieldToBlock(blk, &yield_args);
                if (result.controlFlowValue()) |return_value| return return_value;
                if (current == std.math.maxInt(i64)) break;
            }
        } else {
            var current = start_i;
            while (current <= end_i) : (current += 1) {
                const yield_args = [_]Value{Value.integer(current)};
                const result = try vm.yieldToBlock(blk, &yield_args);
                if (result.controlFlowValue()) |return_value| return return_value;
                if (current == std.math.maxInt(i64)) break;
            }
        }
        return receiver;
    }

    if (begin_val.isString() and end_val.isString()) {
        if (try eachStringRange(vm, blk, begin_val, end_val, exclude_end)) |return_value| {
            return return_value;
        }
        return receiver;
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from Range", .{});
}

fn appendStringRangeToArray(
    vm: *VM,
    array_obj: *value.ArrayObject,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
) VMError!void {
    var empty_args = [_]Value{};
    var compare_args = [_]Value{end_val};
    var current = begin_val;

    while (true) {
        const comparison = try vm.callMethodByName(current, "<=>", compare_args[0..], null);
        if (!comparison.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from Range", .{});
        }

        const order = comparison.toInteger();
        if (order > 0 or (exclude_end and order == 0)) break;

        array_obj.elements.append(vm.gc_allocator, current) catch return error.Fatal;
        if (order == 0) break;

        current = try vm.callMethodByName(current, "succ", empty_args[0..], null);
        if (!current.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from Range", .{});
        }
    }
}

fn eachStringRange(
    vm: *VM,
    blk: Block,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
) VMError!?Value {
    var empty_args = [_]Value{};
    var compare_args = [_]Value{end_val};
    var current = begin_val;

    while (true) {
        const comparison = try vm.callMethodByName(current, "<=>", compare_args[0..], null);
        if (!comparison.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from Range", .{});
        }

        const order = comparison.toInteger();
        if (order > 0 or (exclude_end and order == 0)) break;

        const yield_args = [_]Value{current};
        const result = try vm.yieldToBlock(blk, &yield_args);
        if (result.controlFlowValue()) |return_value| return return_value;
        if (order == 0) break;

        current = try vm.callMethodByName(current, "succ", empty_args[0..], null);
        if (!current.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from Range", .{});
        }
    }

    return null;
}

pub fn builtinRangeInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }
    if (try vm.enterRecursionGuard(.range_inspect, receiver, Value.nil())) {
        return try vm.newStringWithEncoding(
            if (receiver.toRangeObject().exclude_end) "(... ... ...)" else "(... .. ...)",
            false,
            .{ .us_ascii = .{} },
        );
    }
    defer vm.leaveRecursionGuard(.range_inspect, receiver, Value.nil());

    const range_obj = receiver.toRangeObject();

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    var output_encoding: enc.Encoding = .{ .us_ascii = .{} };
    var has_dynamic_part = false;

    if (!range_obj.begin.isNil() or range_obj.end.isNil()) {
        const begin_inspected = try range_obj.begin.inspect(vm);
        const begin_obj = begin_inspected.toStringObject();
        output_encoding = begin_obj.encoding;
        has_dynamic_part = true;
        writer.writeAll(begin_obj.str) catch return error.Fatal;
    }

    if (range_obj.exclude_end) {
        writer.writeAll("...") catch return error.Fatal;
    } else {
        writer.writeAll("..") catch return error.Fatal;
    }

    if (range_obj.begin.isNil() or !range_obj.end.isNil()) {
        const end_inspected = try range_obj.end.inspect(vm);
        const end_obj = end_inspected.toStringObject();
        if (!has_dynamic_part) {
            output_encoding = end_obj.encoding;
            has_dynamic_part = true;
        } else {
            output_encoding = enc.negotiate(output_encoding, buf.written(), end_obj.encoding, end_obj.str) orelse {
                return vm.raiseEncodingCompatibilityError(output_encoding, end_obj.encoding);
            };
        }
        writer.writeAll(end_obj.str) catch return error.Fatal;
    }

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, output_encoding);
}

pub fn builtinRangeCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();
    const candidate = args[0];

    if (!candidate.isInteger()) return Value.boolean(false);
    const n = candidate.toInteger();

    if (!range_obj.begin.isInteger() or !range_obj.end.isInteger()) {
        return Value.boolean(false);
    }

    const begin_i = range_obj.begin.toInteger();
    const end_i = range_obj.end.toInteger();

    if (range_obj.exclude_end) {
        return Value.boolean(n >= begin_i and n < end_i);
    }
    return Value.boolean(n >= begin_i and n <= end_i);
}

pub fn builtinRangeBsearch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;

    if (!begin_val.isNil() and !begin_val.isInteger() and !begin_val.isFloat()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't do binary search for {s}", .{vm.className(begin_val)});
    }
    if (!end_val.isNil() and !end_val.isInteger() and !end_val.isFloat()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't do binary search for {s}", .{vm.className(end_val)});
    }

    const blk = block orelse {
        return try vm.createMethodEnumerator(receiver, try vm.intern("bsearch"), &.{});
    };

    const is_float = (!begin_val.isNil() and begin_val.isFloat()) or (!end_val.isNil() and end_val.isFloat());

    if (is_float) return bsearchFloat(vm, blk, range_obj);
    return bsearchInteger(vm, blk, range_obj);
}

const BsearchAction = enum { found, smaller, larger, control_flow };

fn bsearchDispatch(vm: *VM, blk: Block, element: Value) VMError!struct { action: BsearchAction, value: Value } {
    const yield_result = try vm.yieldToBlock(blk, &[_]Value{element});
    if (yield_result.controlFlowValue()) |return_value| {
        return .{ .action = .control_flow, .value = return_value };
    }
    const result = yield_result.value;
    if (result.isTrue()) return .{ .action = .smaller, .value = result };
    if (result.isFalse() or result.isNil()) return .{ .action = .larger, .value = result };
    if (result.isInteger()) {
        const val = result.toInteger();
        if (val == 0) return .{ .action = .found, .value = result };
        return .{ .action = if (val < 0) .smaller else .larger, .value = result };
    }
    if (result.isFloat()) {
        const val = result.toFloatObject().val;
        if (val == 0.0) return .{ .action = .found, .value = result };
        return .{ .action = if (val < 0.0) .smaller else .larger, .value = result };
    }
    if (result.isBigInteger()) {
        const val = result.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        if (val == 0.0) return .{ .action = .found, .value = result };
        return .{ .action = if (val < 0.0) .smaller else .larger, .value = result };
    }
    if (result.isRational()) {
        const r = result.toRationalObject();
        const num_f64 = r.numerator.integerToF64();
        if (num_f64 == 0.0) return .{ .action = .found, .value = result };
        const den_f64 = r.denominator.integerToF64();
        const val = num_f64 / den_f64;
        return .{ .action = if (val < 0.0) .smaller else .larger, .value = result };
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (must be numeric, true, false or nil)", .{vm.className(result)});
}

fn bsearchIntegerEndlessUp(vm: *VM, blk: Block, begin: i64) VMError!Value {
    const d0 = try bsearchDispatch(vm, blk, Value.integer(begin));
    switch (d0.action) {
        .control_flow => return d0.value,
        .found => return Value.integer(begin),
        .smaller => {
            if (d0.value.isTrue()) return Value.integer(begin);
        },
        .larger => {},
    }
    const begin_find_min = d0.value.isFalse() or d0.value.isNil();
    var pos: i64 = 1;
    var last_neg: ?i64 = null;
    var last_pos: ?i64 = null;
    if (!begin_find_min) {
        if (d0.value.isInteger() and d0.value.toInteger() > 0) last_pos = begin;
        if (d0.value.isFloat() and d0.value.toFloatObject().val > 0.0) last_pos = begin;
    }
    while (true) {
        const probe = begin + pos;
        const d = try bsearchDispatch(vm, blk, Value.integer(probe));
        switch (d.action) {
            .control_flow => return d.value,
            .found => return Value.integer(probe),
            .smaller => {
                if (d.value.isTrue()) {
                    return Value.integer(probe);
                }
                if (begin_find_min) {
                    return Value.nil();
                }
                last_neg = probe;
                if (last_pos) |lp| {
                    return bsearchIntegerRange(vm, blk, lp + 1, last_neg.? + 1, false);
                }
                return Value.nil();
            },
            .larger => {
                if (begin_find_min) {
                    pos = if (std.math.add(i64, pos, pos)) |p| p else |_| return Value.nil();
                } else {
                    last_pos = probe;
                    pos = if (std.math.add(i64, pos, pos)) |p| p else |_| return Value.nil();
                }
            },
        }
    }
}

fn bsearchIntegerEndlessDown(vm: *VM, blk: Block, end_val: i64, exclude_end: bool) VMError!Value {
    const first = if (exclude_end) end_val - 1 else end_val;
    const d0 = try bsearchDispatch(vm, blk, Value.integer(first));
    const is_find_min = switch (d0.action) {
        .control_flow => return d0.value,
        .found => return Value.integer(first),
        .smaller => d0.value.isTrue(),
        .larger => d0.value.isFalse() or d0.value.isNil(),
    };
    if (!is_find_min) {
        const init_small = d0.action == .smaller;
        const init_large = d0.action == .larger;
        if (!init_small and !init_large) return Value.nil();
        var last_small: ?i64 = if (init_small) first else null;
        var last_large: ?i64 = if (init_large) first else null;
        var pos: i64 = 1;
        while (true) {
            const probe = first - pos;
            const d = try bsearchDispatch(vm, blk, Value.integer(probe));
            switch (d.action) {
                .control_flow => return d.value,
                .found => return Value.integer(probe),
                .smaller => {
                    last_small = probe;
                    if (last_large) |ll| return bsearchIntegerRange(vm, blk, ll + 1, last_small.? + 1, false);
                },
                .larger => {
                    last_large = probe;
                    if (last_small) |ls| return bsearchIntegerRange(vm, blk, probe + 1, ls + 1, false);
                },
            }
            pos = if (std.math.add(i64, pos, pos)) |p| p else |_| return Value.nil();
        }
    }
    var last_true: i64 = first;
    var pos: i64 = 1;
    while (true) {
        const probe = first - pos;
        const d = try bsearchDispatch(vm, blk, Value.integer(probe));
        switch (d.action) {
            .control_flow => return d.value,
            .found => return Value.integer(probe),
            .smaller => {
                if (!d.value.isTrue()) return Value.nil();
                last_true = probe;
            },
            .larger => {
                if (d.value.isFalse() or d.value.isNil()) {
                    return bsearchIntegerRange(vm, blk, probe + 1, last_true + 1, false);
                }
                return Value.nil();
            },
        }
        pos = if (std.math.add(i64, pos, pos)) |p| p else |_| return Value.nil();
    }
}

fn bsearchInteger(vm: *VM, blk: Block, range_obj: *value.RangeObject) VMError!Value {
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;
    const exclude_end = range_obj.exclude_end;

    if (end_val.isNil()) {
        return bsearchIntegerEndlessUp(vm, blk, begin_val.toInteger());
    }

    if (begin_val.isNil()) {
        return bsearchIntegerEndlessDown(vm, blk, end_val.toInteger(), exclude_end);
    }

    const start_i = begin_val.toInteger();
    const end_i = end_val.toInteger();

    if (start_i > end_i) return Value.nil();

    const len = if (exclude_end) end_i - start_i else end_i - start_i + 1;
    if (len <= 0) return Value.nil();

    return bsearchIntegerRange(vm, blk, start_i, start_i + len, false);
}

fn bsearchIntegerRange(vm: *VM, blk: Block, start_i: i64, exclusive_end: i64, initial_satisfied: bool) VMError!Value {
    var low = start_i;
    var high = exclusive_end;
    var satisfied = initial_satisfied;

    while (low < high) {
        const mid = low + @divTrunc(high - low, 2);
        const element = Value.integer(mid);
        const d = try bsearchDispatch(vm, blk, element);
        switch (d.action) {
            .control_flow => return d.value,
            .found => return element,
            .smaller => {
                if (d.value.isTrue()) satisfied = true;
                high = mid;
            },
            .larger => {
                low = mid + 1;
            },
        }
    }

    if (satisfied) return Value.integer(low);
    return Value.nil();
}

fn f64ToOrdered(f: f64) u64 {
    const bits = @as(u64, @bitCast(f));
    if (f < 0) return ~bits;
    return bits ^ (@as(u64, 1) << 63);
}

fn orderedToF64(bits: u64) f64 {
    if (bits & (@as(u64, 1) << 63) != 0) return @as(f64, @bitCast(bits ^ (@as(u64, 1) << 63)));
    return @as(f64, @bitCast(~bits));
}

fn toFloat(val: Value) f64 {
    if (val.isFloat()) return val.toFloatObject().val;
    return @as(f64, @floatFromInt(val.toInteger()));
}

fn bsearchFloat(vm: *VM, blk: Block, range_obj: *value.RangeObject) VMError!Value {
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;
    const exclude_end = range_obj.exclude_end;

    const start_f = if (begin_val.isNil()) -std.math.inf(f64) else toFloat(begin_val);
    const end_f = if (end_val.isNil()) std.math.inf(f64) else toFloat(end_val);
    const start_ordered = f64ToOrdered(start_f);
    var end_ordered = f64ToOrdered(end_f);

    if (exclude_end) {
        if (end_ordered == 0) return Value.nil();
        end_ordered -= 1;
    }

    if (start_ordered > end_ordered) return Value.nil();

    return bsearchFloatOrdered(vm, blk, start_ordered, end_ordered);
}

fn bsearchFloatOrdered(vm: *VM, blk: Block, start_ordered: u64, end_ordered: u64) VMError!Value {
    var low = start_ordered;
    var high = end_ordered;
    var satisfied = false;

    while (low <= high) {
        const mid = low + (high - low) / 2;
        const element = try vm.newFloat(orderedToF64(mid));
        const d = try bsearchDispatch(vm, blk, element);
        switch (d.action) {
            .control_flow => return d.value,
            .found => return element,
            .smaller => {
                if (d.value.isTrue()) satisfied = true;
                if (mid == 0) return if (satisfied) element else Value.nil();
                high = mid - 1;
            },
            .larger => {
                low = mid + 1;
            },
        }
    }

    if (satisfied) return try vm.newFloat(orderedToF64(low));
    return Value.nil();
}

fn bsearchFloatRange(vm: *VM, blk: Block, start_f: f64, end_f: f64) VMError!Value {
    var low_bits = f64ToOrdered(start_f);
    var high_bits = f64ToOrdered(end_f);
    var satisfied = false;

    while (low_bits <= high_bits) {
        const mid_bits = low_bits + (high_bits - low_bits) / 2;
        const mid = orderedToF64(mid_bits);
        const element = try vm.newFloat(mid);

        const d = try bsearchDispatch(vm, blk, element);
        switch (d.action) {
            .control_flow => return d.value,
            .found => return element,
            .smaller => {
                if (d.value.isTrue()) satisfied = true;
                if (mid_bits == 0) return if (satisfied) element else Value.nil();
                high_bits = mid_bits - 1;
            },
            .larger => {
                low_bits = mid_bits + 1;
            },
        }
    }

    if (satisfied) return try vm.newFloat(orderedToF64(low_bits));
    return Value.nil();
}
