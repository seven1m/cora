const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const hash_builtin = @import("hash.zig");
const thread_builtin = @import("thread.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const fiber_class_val = Value.fromObject(&vm.fiber_class.module.object);
    const fiber_singleton = try vm.getOrCreateSingletonClass(fiber_class_val);

    const new_sym = try vm.intern("new");
    try fiber_singleton.module.methods.put(new_sym, value.MethodEntry.keywordBuiltin(&builtinFiberNew, .{ .variadic = 0 }));

    const current_sym = try vm.intern("current");
    try fiber_singleton.module.methods.put(current_sym, value.MethodEntry.builtin(&builtinFiberCurrent, .{ .exact = 0 }));

    const yield_sym = try vm.intern("yield");
    try fiber_singleton.module.methods.put(yield_sym, value.MethodEntry.builtin(&builtinFiberYield, .{ .variadic = 0 }));

    const get_sym = try vm.intern("[]");
    try fiber_singleton.module.methods.put(get_sym, value.MethodEntry.builtin(&builtinFiberStorageGet, .{ .exact = 1 }));
    const set_sym = try vm.intern("[]=");
    try fiber_singleton.module.methods.put(set_sym, value.MethodEntry.builtin(&builtinFiberStorageSet, .{ .exact = 2 }));

    try vm.fiber_class.module.methods.put(try vm.intern("storage"), value.MethodEntry.builtin(&builtinFiberStorage, .{ .exact = 0 }));
    try vm.fiber_class.module.methods.put(try vm.intern("storage="), value.MethodEntry.builtin(&builtinFiberStorageReplace, .{ .exact = 1 }));

    const resume_sym = try vm.intern("resume");
    try vm.fiber_class.module.methods.put(resume_sym, value.MethodEntry.builtin(&builtinFiberResume, .{ .variadic = 0 }));

    try vm.fiber_class.module.methods.put(try vm.intern("transfer"), value.MethodEntry.builtin(&builtinFiberTransfer, .{ .variadic = 0 }));

    try vm.fiber_class.module.methods.put(try vm.intern("raise"), value.MethodEntry.keywordBuiltin(&builtinFiberRaise, .{ .variadic = 0 }));

    try vm.fiber_class.module.methods.put(try vm.intern("kill"), value.MethodEntry.builtin(&builtinFiberKill, .{ .exact = 0 }));

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

    const storage = try vm.consumeKeywordArg("storage");
    try vm.validateKeywordArgsConsumed();
    const blk = try vm.requireBlock(block);
    return vm.newFiberWithStorage(receiver.toClassObject(), blk, storage);
}

pub fn builtinFiberCurrent(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(&vm.current_fiber.object);
}

fn builtinFiberStorageGet(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const key = try thread_builtin.symbolArg(vm, args[0]);
    const storage = vm.current_fiber.storage orelse return Value.nil();
    var key_args = [_]Value{Value.fromObject(&key.object)};
    return hash_builtin.builtinHashBracket(vm, Value.fromObject(&storage.object), &key_args, null);
}

fn builtinFiberStorageSet(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const symbol = try thread_builtin.symbolArg(vm, args[0]);
    const key = Value.fromObject(&symbol.object);
    const fiber = vm.current_fiber;
    if (args[1].isNil()) {
        const storage = fiber.storage orelse return Value.nil();
        return try vm.hashDeleteEntry(storage, key) orelse Value.nil();
    }
    if (fiber.storage == null) fiber.storage = try vm.createHash();
    try vm.hashSetEntry(fiber.storage.?, key, args[1]);
    return args[1];
}

fn requireStorageOwner(vm: *VM, receiver: Value) VMError!void {
    if (receiver.toFiberObject() != vm.current_fiber) return vm.raiseExceptionFmt(vm.argument_error_class, "Fiber storage can only be accessed from the Fiber it belongs to", .{});
}

fn builtinFiberStorage(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    try requireStorageOwner(vm, receiver);
    const storage = receiver.toFiberObject().storage orelse return Value.nil();
    const snapshot = try vm.copyHashObject(storage);
    return Value.fromObject(&snapshot.object);
}

fn builtinFiberStorageReplace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try requireStorageOwner(vm, receiver);
    receiver.toFiberObject().storage = try vm.copyValidatedFiberStorage(args[0]);
    return args[0];
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
    if (fiber.resuming_fiber != null) return raiseFiberError(vm, "attempt to resume a resuming fiber");
    if (fiber.caller != null) return raiseFiberError(vm, "attempt to resume a resumed fiber (double resume)");
    if (fiber.state == .suspended and !fiber.yielding) return raiseFiberError(vm, "attempt to resume a transferring fiber");
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

fn builtinFiberTransfer(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const fiber = receiver.toFiberObject();
    const thread = vm.current_thread orelse try vm.ensureMainThread();
    if (fiber.owner_thread) |owner| {
        if (owner != thread) return raiseFiberError(vm, "fiber called across threads");
    }
    if (fiber.resuming_fiber != null) return raiseFiberError(vm, "attempt to transfer to a resuming fiber");
    if (fiber.yielding) return raiseFiberError(vm, "attempt to transfer to a yielding fiber");
    if (fiber.state == .terminated) return raiseFiberError(vm, "dead fiber called");
    return vm.transferFiber(fiber, args, try argsToValue(vm, args));
}

fn builtinFiberRaise(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const exception = try vm.prepareRaisedException(args);
    return vm.raiseInFiber(receiver.toFiberObject(), exception);
}

fn builtinFiberKill(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return vm.killFiber(receiver.toFiberObject());
}
