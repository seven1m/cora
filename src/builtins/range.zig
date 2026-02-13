const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const init_sym = try vm.intern("initialize");
    try vm.range_class.module.methods.put(init_sym, .{ .method = .{ .builtin = &builtinRangeInitialize } });

    const to_a_sym = try vm.intern("to_a");
    try vm.range_class.module.methods.put(to_a_sym, .{ .method = .{ .builtin = &builtinRangeToA } });

    const inspect_sym = try vm.intern("inspect");
    try vm.range_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinRangeInspect } });

    const case_equal_sym = try vm.intern("===");
    try vm.range_class.module.methods.put(case_equal_sym, .{ .method = .{ .builtin = &builtinRangeCaseEqual } });
}

pub fn builtinRangeInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);

    if (receiver.data != .range) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const exclude_end = if (args.len == 3) args[2].is_truthy() else false;

    receiver.data.range.begin = args[0];
    receiver.data.range.end = args[1];
    receiver.data.range.exclude_end = exclude_end;

    return Value.nil();
}

pub fn builtinRangeToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (receiver.data != .range) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const begin_val = receiver.data.range.begin;
    const end_val = receiver.data.range.end;
    const exclude_end = receiver.data.range.exclude_end;

    if (begin_val.data == .nil) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert beginless range to an array", .{});
    }

    if (end_val.data == .nil) {
        return vm.raiseExceptionFmt(vm.range_error_class, "cannot convert endless range to an array", .{});
    }

    if (begin_val.data != .integer) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "wrong argument type {s} (expected Integer)",
            .{@tagName(begin_val.data)},
        );
    }

    if (end_val.data != .integer) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "wrong argument type {s} (expected Integer)",
            .{@tagName(end_val.data)},
        );
    }

    const start_i = begin_val.data.integer;
    const end_i = end_val.data.integer;

    const array_obj = try vm.createArray();

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

    return Value{ .data = .{ .array = array_obj } };
}

pub fn builtinRangeInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (receiver.data != .range) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.data.range;

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    if (range_obj.begin.data != .nil) {
        const begin_inspected = try vm.callMethodByName(range_obj.begin, "inspect", &[_]Value{}, null);
        if (begin_inspected.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(begin_inspected.data.string.str) catch return error.Fatal;
    }

    if (range_obj.exclude_end) {
        writer.writeAll("...") catch return error.Fatal;
    } else {
        writer.writeAll("..") catch return error.Fatal;
    }

    if (range_obj.end.data != .nil) {
        const end_inspected = try vm.callMethodByName(range_obj.end, "inspect", &[_]Value{}, null);
        if (end_inspected.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }
        writer.writeAll(end_inspected.data.string.str) catch return error.Fatal;
    }

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

pub fn builtinRangeCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (receiver.data != .range) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Range", .{});
    }

    const range_obj = receiver.data.range;
    const candidate = args[0];

    if (candidate.data != .integer) return Value.boolean(false);
    const n = candidate.data.integer;

    if (range_obj.begin.data != .integer or range_obj.end.data != .integer) {
        return Value.boolean(false);
    }

    const begin_i = range_obj.begin.data.integer;
    const end_i = range_obj.end.data.integer;

    if (range_obj.exclude_end) {
        return Value.boolean(n >= begin_i and n < end_i);
    }
    return Value.boolean(n >= begin_i and n <= end_i);
}
