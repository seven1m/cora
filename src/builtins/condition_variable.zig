const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const mutex_builtin = @import("mutex.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;

pub fn register(vm: *VM) !void {
    const cv_class_val = Value.fromObject(&vm.condition_variable_class.module.object);
    const cv_singleton = try vm.getOrCreateSingletonClass(cv_class_val);

    const new_sym = try vm.intern("new");
    try cv_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinConditionVariableNew, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.condition_variable_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinConditionVariableInitialize, .{ .exact = 0 }));

    const wait_sym = try vm.intern("wait");
    try vm.condition_variable_class.module.methods.put(wait_sym, value.MethodEntry.builtin(&builtinConditionVariableWait, .{ .variadic = 1 }));

    const signal_sym = try vm.intern("signal");
    try vm.condition_variable_class.module.methods.put(signal_sym, value.MethodEntry.builtin(&builtinConditionVariableSignal, .{ .exact = 0 }));

    const broadcast_sym = try vm.intern("broadcast");
    try vm.condition_variable_class.module.methods.put(broadcast_sym, value.MethodEntry.builtin(&builtinConditionVariableBroadcast, .{ .exact = 0 }));
}

fn builtinConditionVariableNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }
    const cv_obj = try vm.newConditionVariable(receiver);
    const cv_val = Value.fromObject(&cv_obj.object);
    _ = try vm.callMethodByNameForwardingKeywords(cv_val, "initialize", args, block);
    return cv_val;
}

fn builtinConditionVariableInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    receiver.toConditionVariableObject().waiters.clearRetainingCapacity();
    return receiver;
}

fn builtinConditionVariableWait(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    _ = try vm.ensureMainThread();
    try vm.requireArgType(args, 0, .mutex, "Mutex");

    const current_thread = vm.current_thread orelse {
        return vm.raiseExceptionFmt(vm.thread_error_class, "no current thread", .{});
    };
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

    const cv = receiver.toConditionVariableObject();
    appendWaiter(vm, cv, current_thread);
    mutex_builtin.releaseMutex(vm, mutex);
    defer {
        removeWaiter(cv, current_thread);
        if (mutex.state == .locked) {
            mutex_builtin.waitForMutex(vm, mutex) catch {};
        }
        mutex_builtin.acquireMutex(vm, mutex) catch {};
    }

    if (timeout_ms) |limit| {
        const deadline = monotonicMilliseconds() + limit;
        while (containsWaiter(cv, current_thread) and monotonicMilliseconds() < deadline) {
            try vm.threadYield();
        }
    } else {
        while (containsWaiter(cv, current_thread)) {
            try vm.threadYield();
        }
    }

    return receiver;
}

fn builtinConditionVariableSignal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();

    const cv = receiver.toConditionVariableObject();
    while (cv.waiters.items.len > 0) {
        const waiter = cv.waiters.orderedRemove(0);
        if (waiter.state == .terminated) continue;
        waiter.state = .running;
        enqueueRunnable(vm, waiter);
        break;
    }
    return receiver;
}

fn builtinConditionVariableBroadcast(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();

    const cv = receiver.toConditionVariableObject();
    while (cv.waiters.items.len > 0) {
        const waiter = cv.waiters.orderedRemove(0);
        if (waiter.state == .terminated) continue;
        waiter.state = .running;
        enqueueRunnable(vm, waiter);
    }
    return receiver;
}

fn monotonicMilliseconds() i64 {
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(std.posix.CLOCK.MONOTONIC, &timespec) != 0) return 0;

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);
    return seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000);
}

fn appendWaiter(vm: *VM, cv: *value.ConditionVariableObject, thread: *value.ThreadObject) void {
    for (cv.waiters.items) |waiter| {
        if (waiter == thread) return;
    }
    cv.waiters.append(vm.gc_allocator, thread) catch {};
}

fn containsWaiter(cv: *value.ConditionVariableObject, thread: *value.ThreadObject) bool {
    for (cv.waiters.items) |waiter| {
        if (waiter == thread) return true;
    }
    return false;
}

fn removeWaiter(cv: *value.ConditionVariableObject, thread: *value.ThreadObject) void {
    var i: usize = 0;
    while (i < cv.waiters.items.len) {
        if (cv.waiters.items[i] == thread) {
            _ = cv.waiters.orderedRemove(i);
            return;
        }
        i += 1;
    }
}

fn enqueueRunnable(vm: *VM, waiter: *value.ThreadObject) void {
    for (vm.runnable_queue.items) |thread| {
        if (thread == waiter) return;
    }
    vm.runnable_queue.append(vm.gc_allocator, waiter) catch {};
}
