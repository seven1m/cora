const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const mutex_builtin = @import("mutex.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const cv_class_val = Value.fromObject(&vm.condition_variable_class.module.object);
    const cv_singleton = try vm.getOrCreateSingletonClass(cv_class_val);

    const new_sym = try vm.intern("new");
    try cv_singleton.module.methods.put(new_sym, value.MethodEntry.keywordBuiltin(&builtinConditionVariableNew, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.condition_variable_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinConditionVariableInitialize, .{ .exact = 0 }));

    const wait_sym = try vm.intern("wait");
    try vm.condition_variable_class.module.methods.put(wait_sym, value.MethodEntry.builtin(&builtinConditionVariableWait, .{ .variadic = 1 }));

    const signal_sym = try vm.intern("signal");
    try vm.condition_variable_class.module.methods.put(signal_sym, value.MethodEntry.builtin(&builtinConditionVariableSignal, .{ .exact = 0 }));

    const marshal_dump_sym = try vm.intern("marshal_dump");
    try vm.condition_variable_class.module.methods.put(marshal_dump_sym, value.MethodEntry.builtin(&builtinConditionVariableMarshalDump, .{ .exact = 0 }));

    const broadcast_sym = try vm.intern("broadcast");
    try vm.condition_variable_class.module.methods.put(broadcast_sym, value.MethodEntry.builtin(&builtinConditionVariableBroadcast, .{ .exact = 0 }));
}

fn builtinConditionVariableNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    const cv_obj = try vm.newConditionVariable(receiver);
    const cv_val = Value.fromObject(&cv_obj.object);
    _ = try vm.callMethodByNameForwardingKeywords(cv_val, "initialize", args, block);
    return cv_val;
}

fn builtinConditionVariableInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    VM.clearThreadList(&receiver.toConditionVariableObject().waiters);
    return receiver;
}

fn builtinConditionVariableWait(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const current_thread = vm.current_thread orelse return error.Fatal;
    const cv = receiver.toConditionVariableObject();
    try appendWaiter(vm, cv, current_thread);
    defer removeWaiter(cv, current_thread);

    if (!args[0].isMutex()) {
        var sleep_args = [_]Value{if (args.len == 2) args[1] else Value.nil()};
        _ = try vm.callMethodByName(args[0], "sleep", &sleep_args, null);
        return receiver;
    }
    const mutex = args[0].toMutexObject();
    if (mutex.state != .locked or !mutex_builtin.isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to unlock a mutex which is not locked", .{});
    }

    var timeout_ms: ?i64 = null;
    if (args.len == 2 and !args[1].isNil()) {
        if (args[1].isInteger() or args[1].isFloat()) {
            const timeout = if (args[1].isInteger()) args[1].integerToF64() else args[1].toFloatObject().val;
            if (timeout < 0) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must not be negative", .{});
            }
            timeout_ms = @intFromFloat(timeout * 1000.0);
        } else {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Float", .{});
        }
    }

    try mutex_builtin.releaseMutex(vm, mutex);
    const wait_result: VMError!void = wait: {
        if (timeout_ms) |limit| {
            vm.timedSleepCurrentThread(limit) catch |err| break :wait err;
        } else {
            const was_deadlockable = current_thread.deadlockable_wait;
            current_thread.deadlockable_wait = true;
            defer {
                current_thread.deadlockable_wait = was_deadlockable;
                if (current_thread.state != .terminated) current_thread.state = .running;
            }
            current_thread.state = .sleeping;
            while (current_thread.state == .sleeping) {
                vm.threadYield() catch |err| break :wait err;
            }
        }

        break :wait;
    };
    try mutex_builtin.reacquireMutex(vm, mutex);
    try wait_result;
    return receiver;
}

fn builtinConditionVariableSignal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const cv = receiver.toConditionVariableObject();
    while (cv.waiters.items.len > 0) {
        const waiter = VM.removeThreadListEntry(&cv.waiters, 0);
        if (waiter.state == .terminated) continue;
        waiter.state = .running;
        enqueueRunnable(vm, waiter);
        break;
    }
    return receiver;
}

fn builtinConditionVariableBroadcast(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const cv = receiver.toConditionVariableObject();
    while (cv.waiters.items.len > 0) {
        const waiter = VM.removeThreadListEntry(&cv.waiters, 0);
        if (waiter.state == .terminated) continue;
        waiter.state = .running;
        enqueueRunnable(vm, waiter);
    }
    return receiver;
}

fn builtinConditionVariableMarshalDump(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.raiseExceptionFmt(vm.type_error_class, "can't dump ConditionVariable", .{});
}

fn appendWaiter(vm: *VM, cv: *value.ConditionVariableObject, thread: *value.ThreadObject) VMError!void {
    for (cv.waiters.items) |waiter| {
        if (waiter == thread) return;
    }
    cv.waiters.append(vm.gc_allocator, thread) catch return error.Fatal;
}

fn removeWaiter(cv: *value.ConditionVariableObject, thread: *value.ThreadObject) void {
    var i: usize = 0;
    while (i < cv.waiters.items.len) {
        if (cv.waiters.items[i] == thread) {
            _ = VM.removeThreadListEntry(&cv.waiters, i);
            return;
        }
        i += 1;
    }
}

fn enqueueRunnable(vm: *VM, waiter: *value.ThreadObject) void {
    vm.addRunnableThreadIfAbsent(waiter);
}
