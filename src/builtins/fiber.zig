const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const fiber_class_val = Value{ .data = .{ .class = vm.fiber_class } };
    const fiber_singleton = try vm.getOrCreateSingletonClass(fiber_class_val);

    const new_sym = try vm.intern("new");
    try fiber_singleton.module.methods.put(new_sym, .{ .builtin = &builtinFiberNew });

    const current_sym = try vm.intern("current");
    try fiber_singleton.module.methods.put(current_sym, .{ .builtin = &builtinFiberCurrent });

    const yield_sym = try vm.intern("yield");
    try fiber_singleton.module.methods.put(yield_sym, .{ .builtin = &builtinFiberYield });

    const resume_sym = try vm.intern("resume");
    try vm.fiber_class.module.methods.put(resume_sym, .{ .builtin = &builtinFiberResume });

    const alive_sym = try vm.intern("alive?");
    try vm.fiber_class.module.methods.put(alive_sym, .{ .builtin = &builtinFiberAlive });

    const inspect_sym = try vm.intern("inspect");
    try vm.fiber_class.module.methods.put(inspect_sym, .{ .builtin = &builtinFiberInspect });
}

fn argsToValue(vm: *VM, args: []Value) VMError!Value {
    return switch (args.len) {
        0 => Value.nil(),
        1 => args[0],
        else => blk: {
            const array_obj = try vm.createArray();
            for (args) |arg| {
                array_obj.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
            }
            break :blk Value{ .data = .{ .array = array_obj } };
        },
    };
}

fn raiseFiberError(vm: *VM, msg: []const u8) VMError!Value {
    const exc = try vm.createException(vm.fiber_error_class, msg);
    vm.pending_exception = exc;
    return error.Unwind;
}

pub fn builtinFiberNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(vm.argument_error_class, "no block given");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const class_ptr = receiver.data.class;
    return try vm.newFiber(class_ptr, blk);
}

pub fn builtinFiberCurrent(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value{ .data = .{ .fiber = vm.current_fiber } };
}

pub fn builtinFiberYield(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (vm.current_fiber == vm.main_fiber) {
        return raiseFiberError(vm, "can't yield from root fiber");
    }

    const yield_value = try argsToValue(vm, args);
    vm.current_fiber.yielded_value = yield_value;
    vm.current_fiber.awaiting_resume_value = true;
    vm.current_fiber.state = .suspended;
    return error.FiberYield;
}

pub fn builtinFiberResume(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const fiber = receiver.data.fiber;

    if (fiber == vm.current_fiber) {
        return raiseFiberError(vm, "attempt to resume the current fiber");
    }
    switch (fiber.state) {
        .terminated => return raiseFiberError(vm, "dead fiber called"),
        .running => return raiseFiberError(vm, "attempt to resume a running fiber"),
        else => {},
    }

    const resume_value = try argsToValue(vm, args);
    fiber.pending_resume_value = resume_value;

    const caller = vm.current_fiber;
    vm.saveFiberState(caller);
    fiber.caller = caller;
    vm.current_fiber = fiber;
    vm.restoreFiberState(fiber);

    errdefer {
        vm.saveFiberState(fiber);
        vm.current_fiber = caller;
        vm.restoreFiberState(caller);
        fiber.caller = null;
    }

    const result = try vm.runFiberUntilYieldOrTerminate(fiber, args);

    vm.saveFiberState(fiber);
    vm.current_fiber = caller;
    vm.restoreFiberState(caller);
    fiber.caller = null;

    return result;
}

pub fn builtinFiberAlive(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const fiber = receiver.data.fiber;
    return Value.boolean(fiber.state != .terminated);
}

pub fn builtinFiberInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const fiber = receiver.data.fiber;
    const state_str = switch (fiber.state) {
        .created => "created",
        .running => "resumed",
        .suspended => "suspended",
        .terminated => "terminated",
    };
    const msg = std.fmt.allocPrint(
        vm.gc_allocator,
        "#<Fiber:0x{x} ({s})>",
        .{ @intFromPtr(fiber), state_str },
    ) catch return error.Fatal;
    return try vm.newString(msg, false);
}
