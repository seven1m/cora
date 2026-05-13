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
