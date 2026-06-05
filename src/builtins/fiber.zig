const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const fiber_class_val = Value.fromObject(&vm.fiber_class.module.object);
    const fiber_singleton = try vm.getOrCreateSingletonClass(fiber_class_val);

    const new_sym = try vm.intern("new");
    try fiber_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinFiberNew, .{ .variadic = 0 }));

    const current_sym = try vm.intern("current");
    try fiber_singleton.module.methods.put(current_sym, value.MethodEntry.builtin(&builtinFiberCurrent, .{ .exact = 0 }));

    const yield_sym = try vm.intern("yield");
    try fiber_singleton.module.methods.put(yield_sym, value.MethodEntry.builtin(&builtinFiberYield, .{ .variadic = 0 }));

    const resume_sym = try vm.intern("resume");
    try vm.fiber_class.module.methods.put(resume_sym, value.MethodEntry.builtin(&builtinFiberResume, .{ .variadic = 0 }));

    const alive_sym = try vm.intern("alive?");
    try vm.fiber_class.module.methods.put(alive_sym, value.MethodEntry.builtin(&builtinFiberAlive, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.fiber_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinFiberInspect, .{ .exact = 0 }));
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
            break :blk Value.fromObject(&array_obj.object);
        },
    };
}

fn raiseFiberError(vm: *VM, msg: []const u8) VMError!Value {
    return vm.raiseExceptionFmt(vm.fiber_error_class, "{s}", .{msg});
}

pub fn builtinFiberNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = try vm.requireBlock(block);

    const class_ptr = receiver.toClassObject();
    return try vm.newFiber(class_ptr, blk);
}

pub fn builtinFiberCurrent(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(&vm.current_fiber.object);
}

pub fn builtinFiberYield(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const yield_value = try argsToValue(vm, args);
    return vm.fiberYield(yield_value);
}

pub fn builtinFiberResume(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const fiber = receiver.toFiberObject();
    const current_thread = vm.current_thread orelse try vm.ensureMainThread();
    if (fiber.owner_thread) |owner_thread| {
        if (owner_thread != current_thread) {
            return raiseFiberError(vm, "fiber called across threads");
        }
    }

    if (fiber == vm.current_fiber) {
        return raiseFiberError(vm, "attempt to resume the current fiber");
    }
    switch (fiber.state) {
        .terminated => return raiseFiberError(vm, "dead fiber called"),
        .running => return raiseFiberError(vm, "attempt to resume a running fiber"),
        else => {},
    }

    const resume_value = try argsToValue(vm, args);
    return vm.resumeFiber(fiber, args, resume_value);
}

pub fn builtinFiberAlive(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const fiber = receiver.toFiberObject();
    return Value.boolean(fiber.state != .terminated);
}

pub fn builtinFiberInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const fiber = receiver.toFiberObject();
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
