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

    const first_sym = try vm.intern("first");
    try vm.range_class.module.methods.put(first_sym, value.MethodEntry.builtin(&builtinRangeFirst, .{ .variadic = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.range_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinRangeToA, .{ .exact = 0 }));

    const each_sym = try vm.intern("each");
    try vm.range_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinRangeEach, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.range_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinRangeSize, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.range_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinRangeInspect, .{ .exact = 0 }));

    const case_equal_sym = try vm.intern("===");
    try vm.range_class.module.methods.put(case_equal_sym, value.MethodEntry.builtin(&builtinRangeCaseEqual, .{ .exact = 1 }));

    const bsearch_sym = try vm.intern("bsearch");
    try vm.range_class.module.methods.put(bsearch_sym, value.MethodEntry.builtin(&builtinRangeBsearch, .{ .exact = 0 }));

    const include_sym = try vm.intern("include?");
    try vm.range_class.module.methods.put(include_sym, value.MethodEntry.builtin(&builtinRangeInclude, .{ .exact = 1 }));

    const member_sym = try vm.intern("member?");
    try vm.range_class.module.methods.put(member_sym, value.MethodEntry.builtin(&builtinRangeInclude, .{ .exact = 1 }));

    const cover_sym = try vm.intern("cover?");
    try vm.range_class.module.methods.put(cover_sym, value.MethodEntry.builtin(&builtinRangeCover, .{ .exact = 1 }));
}

pub fn builtinRangeInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const exclude_end = if (args.len == 3) args[2].isTruthy() else false;

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

pub fn builtinRangeFirst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();

    if (range_obj.begin.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot get the first element of beginless range", .{});
    }

    if (args.len == 0) {
        return range_obj.begin;
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

    const array_obj = try vm.createArray();
    try walkRangeElements(
        vm,
        range_obj.begin,
        range_obj.end,
        range_obj.exclude_end,
        AppendLimitedVisitor{ .vm = vm, .array = array_obj, .limit = @intCast(count) },
        visitAppendLimited,
    );
    return Value.fromObject(&array_obj.object);
}

const WalkControl = enum { proceed, stop };

const r_less_stop: i64 = std.math.maxInt(i64);

/// Normalized `<=>` comparison used by range iteration (MRI `r_less`):
/// returns -1/0/1, or `r_less_stop` when `<=>` yields nil so that callers
/// silently stop iterating instead of raising.
fn rLess(vm: *VM, a: Value, b: Value) VMError!i64 {
    var cmp_args = [_]Value{b};
    const cmp = try vm.callMethodByName(a, "<=>", cmp_args[0..], null);
    if (cmp.isNil()) return r_less_stop;

    if (cmp.isInteger()) {
        const n = cmp.toInteger();
        return if (n < 0) -1 else if (n > 0) 1 else 0;
    }
    if (cmp.isFloat()) {
        const f = cmp.toFloatObject().val;
        return if (f < 0.0) -1 else if (f > 0.0) 1 else 0;
    }
    if (cmp.isBigInteger()) {
        const f = cmp.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        return if (f < 0.0) -1 else if (f > 0.0) 1 else 0;
    }
    if (cmp.isRational()) {
        const rat = cmp.toRationalObject();
        const num_f64 = rat.numerator.integerToF64();
        const den_f64 = rat.denominator.integerToF64();
        const f = num_f64 / den_f64;
        return if (f < 0.0) -1 else if (f > 0.0) 1 else 0;
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "comparison of {s} with {s} failed", .{ vm.className(a), vm.className(b) });
}

/// Low-level Range element walker following MRI `range_each` /
/// `range_each_func` semantics: visits successive elements from `begin_val`
/// up to and including `end_val` (or up to but excluding it when
/// `exclude_end`). Endless ranges iterate until the visitor halts. Raises
/// `TypeError` unless `begin_val` is iterable (`Integer`, or responds to
/// `succ`).
fn walkRangeElements(
    vm: *VM,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
    ctx: anytype,
    comptime visit: fn (@TypeOf(ctx), Value) VMError!WalkControl,
) VMError!void {
    if (begin_val.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from NilClass", .{});
    }

    if (begin_val.isInteger() and (end_val.isNil() or end_val.isInteger())) {
        var current = begin_val.toInteger();
        if (end_val.isNil()) {
            while (true) {
                const control = try visit(ctx, Value.integer(current));
                if (control == .stop) return;
                if (current == std.math.maxInt(i64)) return;
                current += 1;
            }
        }
        const end_i = end_val.toInteger();
        const limit: ?i64 = if (exclude_end)
            (if (end_i == std.math.minInt(i64)) null else end_i - 1)
        else
            end_i;
        if (limit) |lim| {
            while (current <= lim) {
                const control = try visit(ctx, Value.integer(current));
                if (control == .stop) return;
                if (current == lim) return;
                if (current == std.math.maxInt(i64)) return;
                current += 1;
            }
        }
        return;
    }

    if (!try vm.respondsToMethodByName(begin_val, "succ", false)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from {s}", .{vm.className(begin_val)});
    }

    var empty_args = [_]Value{};
    var current = begin_val;

    if (end_val.isNil()) {
        while (true) {
            const control = try visit(ctx, current);
            if (control == .stop) return;
            current = try vm.callMethodByName(current, "succ", empty_args[0..], null);
        }
    }

    if (exclude_end) {
        while ((try rLess(vm, current, end_val)) < 0) {
            const control = try visit(ctx, current);
            if (control == .stop) return;
            current = try vm.callMethodByName(current, "succ", empty_args[0..], null);
        }
        return;
    }

    while (true) {
        const order = try rLess(vm, current, end_val);
        if (order > 0) return;
        const control = try visit(ctx, current);
        if (control == .stop) return;
        if (order == 0) return;
        current = try vm.callMethodByName(current, "succ", empty_args[0..], null);
    }
}

const EachVisitor = struct { vm: *VM, blk: Block };

fn visitEach(ctx: EachVisitor, element: Value) VMError!WalkControl {
    const yield_args = [_]Value{element};
    _ = try ctx.vm.yieldToBlock(ctx.blk, &yield_args);
    return .proceed;
}

const AppendVisitor = struct { vm: *VM, array: *value.ArrayObject };

fn visitAppend(ctx: AppendVisitor, element: Value) VMError!WalkControl {
    ctx.array.elements.append(ctx.vm.gc_allocator, element) catch return error.Fatal;
    return .proceed;
}

const AppendLimitedVisitor = struct { vm: *VM, array: *value.ArrayObject, limit: usize };

fn visitAppendLimited(ctx: AppendLimitedVisitor, element: Value) VMError!WalkControl {
    if (ctx.array.elements.items.len >= ctx.limit) return .stop;
    ctx.array.elements.append(ctx.vm.gc_allocator, element) catch return error.Fatal;
    return .proceed;
}

pub fn builtinRangeToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();

    if (range_obj.begin.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert beginless range to an array", .{});
    }

    if (range_obj.end.isNil()) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert endless range to an array", .{});
    }

    const array_obj = try vm.createArray();
    try walkRangeElements(
        vm,
        range_obj.begin,
        range_obj.end,
        range_obj.exclude_end,
        AppendVisitor{ .vm = vm, .array = array_obj },
        visitAppend,
    );
    return Value.fromObject(&array_obj.object);
}

pub fn builtinRangeEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const blk = block orelse {
        return try vm.createMethodEnumeratorWithSize(
            receiver,
            try vm.intern("each"),
            &.{},
            try rangeSizeValue(vm, receiver),
        );
    };

    const range_obj = receiver.toRangeObject();

    try walkRangeElements(
        vm,
        range_obj.begin,
        range_obj.end,
        range_obj.exclude_end,
        EachVisitor{ .vm = vm, .blk = blk },
        visitEach,
    );
    return receiver;
}

/// MRI `range_size`: element count for Integer bounds, Float::INFINITY for
/// endless Integer ranges, nil for other iterable ranges; raises TypeError
/// when begin cannot be iterated.
pub fn rangeSizeValue(vm: *VM, receiver: Value) VMError!Value {
    const range_obj = receiver.toRangeObject();
    const begin_val = range_obj.begin;
    const end_val = range_obj.end;

    if ((begin_val.isInteger() or begin_val.isBigInteger()) and end_val.isNil()) {
        return vm.newFloat(std.math.inf(f64));
    }

    if (begin_val.isInteger() and end_val.isInteger()) {
        const diff: i128 = @as(i128, end_val.toInteger()) - @as(i128, begin_val.toInteger());
        const count: i128 = if (range_obj.exclude_end) diff else diff + 1;
        if (count <= 0) return Value.integer(0);
        if (count > std.math.maxInt(i64)) {
            return vm.newFloat(@floatFromInt(count));
        }
        return Value.integer(@intCast(count));
    }

    if (begin_val.isBigInteger() and (end_val.isInteger() or end_val.isBigInteger())) {
        // Approximate huge-interval sizes as a Float via f64 endpoints.
        const beg_f64 = if (begin_val.isInteger())
            @as(f64, @floatFromInt(begin_val.toInteger()))
        else
            begin_val.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        const end_f64 = if (end_val.isInteger())
            @as(f64, @floatFromInt(end_val.toInteger()))
        else
            end_val.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        var count = @floor(end_f64 - beg_f64);
        if (!range_obj.exclude_end) count += 1.0;
        if (count <= 0.0) return Value.integer(0);
        return vm.newFloat(count);
    }

    if (!begin_val.isNil() and !try vm.respondsToMethodByName(begin_val, "succ", false)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't iterate from {s}", .{vm.className(begin_val)});
    }

    return Value.nil();
}

pub fn builtinRangeSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    return rangeSizeValue(vm, receiver);
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
    return Value.boolean(try rCoverP(vm, range_obj.begin, range_obj.end, range_obj.exclude_end, args[0]));
}

/// MRI `linear_object_p`: numeric values (including Integer/Float immediates,
/// Rational/Complex, and Numeric/Time descendants) can be compared without
/// iteration.
fn isLinearObject(vm: *VM, val: Value) bool {
    if (val.isInteger() or val.isFloat()) return true;
    var current: ?*value.ClassObject = vm.getClass(val);
    while (current) |class_obj| : (current = class_obj.superclass) {
        if (class_obj == vm.numeric_class or class_obj == vm.time_class) return true;
    }
    return false;
}

/// MRI `range_integer_edge_p`: an endpoint that converts to an Integer via
/// `to_int` switches `include?` to comparison semantics.
fn endpointConvertsToInteger(vm: *VM, val: Value) VMError!bool {
    if (!val.isObject()) return false;
    const maybe = try vm.checkCallMethodByName(val, "to_int", false, &[_]Value{}, null);
    const coerced = maybe orelse return false;
    return coerced.isInteger();
}

/// MRI `r_cover_p`: pure `<=>`-based coverage used by `===`, `cover?`, and
/// the numeric fast path of `include?`. Non-comparable values (`<=>` yields
/// nil) simply do not cover instead of raising.
fn rCoverP(vm: *VM, beg: Value, end_val: Value, exclude_end: bool, val: Value) VMError!bool {
    if (beg.isNil() or (try rLess(vm, beg, val)) <= 0) {
        const limit: i64 = if (exclude_end) -1 else 0;
        if (end_val.isNil() or (try rLess(vm, val, end_val)) <= limit) return true;
    }
    return false;
}

/// MRI `r_cover_range_p`: whether `self` covers another Range.
fn rCoverRangeP(vm: *VM, self_obj: *value.RangeObject, val_value: Value, val_obj: *value.RangeObject) VMError!bool {
    const beg = self_obj.begin;
    const end_v = self_obj.end;

    const val_beg = val_obj.begin;
    const val_end = val_obj.end;

    if (!end_v.isNil() and val_end.isNil()) return false;
    if (!beg.isNil() and val_beg.isNil()) return false;
    if (!val_beg.isNil() and !val_end.isNil()) {
        const empty_limit: i64 = if (val_obj.exclude_end) -1 else 0;
        if ((try rLess(vm, val_beg, val_end)) > empty_limit) return false;
    }
    if (!val_beg.isNil() and !(try rCoverP(vm, beg, end_v, self_obj.exclude_end, val_beg))) return false;

    var cmp_end: i64 = undefined;
    if (!val_end.isNil() and !end_v.isNil()) {
        cmp_end = try rLess(vm, end_v, val_end);
        if (cmp_end == r_less_stop) return false;
    } else {
        cmp_end = try rLess(vm, end_v, val_end);
    }

    if (self_obj.exclude_end == val_obj.exclude_end) {
        return cmp_end >= 0;
    } else if (self_obj.exclude_end) {
        return cmp_end > 0;
    } else if (cmp_end >= 0) {
        return true;
    }

    const maybe_max = try vm.checkCallMethodByName(val_value, "max", false, &[_]Value{}, null);
    const max_value = maybe_max orelse return false;
    if (max_value.isNil()) return false;
    return (try rLess(vm, end_v, max_value)) >= 0;
}

pub fn builtinRangeCover(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();
    const val = args[0];
    if (val.isRange()) {
        return Value.boolean(try rCoverRangeP(vm, range_obj, val, val.toRangeObject()));
    }
    return Value.boolean(try rCoverP(vm, range_obj.begin, range_obj.end, range_obj.exclude_end, val));
}

fn succStringBytes(vm: *VM, str_val: Value) VMError![]const u8 {
    var empty_args = [_]Value{};
    const next = try vm.callMethodByName(str_val, "succ", empty_args[0..], null);
    return next.toStringObject().str;
}

/// MRI `rb_str_include_range_p`: string ranges check membership by iterating
/// from begin with `succ` up to a length-bounded limit, comparing with `==`.
fn stringRangeIncludeP(vm: *VM, beg_val: Value, end_val: Value, val: Value, exclude_end: bool) VMError!Value {
    const val_probe = try vm.probeToStringValue(val);
    const val_string = switch (val_probe) {
        .string => |v| v,
        else => return Value.boolean(false),
    };

    const end_bytes = end_val.toStringObject().str;
    const order = std.mem.order(u8, beg_val.toStringObject().str, end_bytes);
    if (order == .gt or (exclude_end and order == .eq)) return Value.boolean(false);

    const after_end_bytes = try succStringBytes(vm, end_val);

    var current = try vm.newString(beg_val.toStringObject().str, false);
    while (!std.mem.eql(u8, current.toStringObject().str, after_end_bytes)) {
        var next: ?Value = null;
        const current_bytes = current.toStringObject().str;
        if (exclude_end or !std.mem.eql(u8, current_bytes, end_bytes)) {
            next = try vm.callMethodByName(current, "succ", &[_]Value{}, null);
        }

        var eq_args = [_]Value{val_string};
        const eq_result = try vm.callMethodByName(current, "==", eq_args[0..], null);
        if (eq_result.isTruthy()) return Value.boolean(true);

        const next_value = next orelse break;
        _ = next_value.toStringObject();
        current = next_value;

        const len = current.toStringObject().str.len;
        if (exclude_end and std.mem.eql(u8, current.toStringObject().str, end_bytes)) break;
        if (len > end_bytes.len or len == 0) break;
    }

    return Value.boolean(false);
}

const IncludeVisitor = struct { vm: *VM, val: Value, found: bool = false };

fn visitInclude(ctx: *IncludeVisitor, element: Value) VMError!WalkControl {
    var eq_args = [_]Value{ctx.val};
    const eq_result = try ctx.vm.callMethodByName(element, "==", eq_args[0..], null);
    if (eq_result.isTruthy()) {
        ctx.found = true;
        return .stop;
    }
    return .proceed;
}

/// Fallback for non-linear, non-string ranges: iterate with `each` comparing
/// elements via `==` (what Enumerable#include? does in MRI).
fn enumerableStyleInclude(vm: *VM, range_obj: *value.RangeObject, val: Value) VMError!Value {
    var ctx = IncludeVisitor{ .vm = vm, .val = val };
    try walkRangeElements(vm, range_obj.begin, range_obj.end, range_obj.exclude_end, &ctx, visitInclude);
    return Value.boolean(ctx.found);
}

pub fn builtinRangeInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (!receiver.isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.toRangeObject();
    const beg = range_obj.begin;
    const end_v = range_obj.end;
    const val = args[0];

    if (isLinearObject(vm, beg) or isLinearObject(vm, end_v) or
        (try endpointConvertsToInteger(vm, beg)) or (try endpointConvertsToInteger(vm, end_v)))
    {
        return Value.boolean(try rCoverP(vm, beg, end_v, range_obj.exclude_end, val));
    }

    if (beg.isString() and end_v.isString()) {
        return stringRangeIncludeP(vm, beg, end_v, val, range_obj.exclude_end);
    }

    if (beg.isNil() and end_v.isNil()) {
        return Value.boolean(isLinearObject(vm, val));
    }
    if (beg.isNil() or end_v.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "cannot determine inclusion in beginless/endless ranges", .{});
    }

    return enumerableStyleInclude(vm, range_obj, val);
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

const BsearchAction = enum { found, smaller, larger };

fn bsearchDispatch(vm: *VM, blk: Block, element: Value) VMError!struct { action: BsearchAction, value: Value } {
    const result = try vm.yieldToBlock(blk, &[_]Value{element});
    if (result.isTrue()) return .{ .action = .smaller, .value = result };
    if (result.isFalsey()) return .{ .action = .larger, .value = result };
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
        .found => return Value.integer(begin),
        .smaller => {
            if (d0.value.isTrue()) return Value.integer(begin);
        },
        .larger => {},
    }
    const begin_find_min = d0.value.isFalsey();
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
        .found => return Value.integer(first),
        .smaller => d0.value.isTrue(),
        .larger => d0.value.isFalsey(),
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
            .found => return Value.integer(probe),
            .smaller => {
                if (!d.value.isTrue()) return Value.nil();
                last_true = probe;
            },
            .larger => {
                if (d.value.isFalsey()) {
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
