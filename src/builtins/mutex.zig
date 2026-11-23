const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const synchronization = @import("synchronization.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const mutex_class_val = Value.fromObject(&vm.mutex_class.module.object);
    const mutex_singleton = try vm.getOrCreateSingletonClass(mutex_class_val);

    // Class methods
    const new_sym = try vm.intern("new");
    try mutex_singleton.module.methods.put(new_sym, value.MethodEntry.keywordBuiltin(&builtinMutexNew, .{ .variadic = 0 }));

    // Instance methods
    const initialize_sym = try vm.intern("initialize");
    try vm.mutex_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinMutexInitialize, .{ .exact = 0 }));

    const lock_sym = try vm.intern("lock");
    try vm.mutex_class.module.methods.put(lock_sym, value.MethodEntry.builtin(&builtinMutexLock, .{ .exact = 0 }));

    const unlock_sym = try vm.intern("unlock");
    try vm.mutex_class.module.methods.put(unlock_sym, value.MethodEntry.builtin(&builtinMutexUnlock, .{ .exact = 0 }));

    const locked_q_sym = try vm.intern("locked?");
    try vm.mutex_class.module.methods.put(locked_q_sym, value.MethodEntry.builtin(&builtinMutexLockedQ, .{ .exact = 0 }));

    const try_lock_sym = try vm.intern("try_lock");
    try vm.mutex_class.module.methods.put(try_lock_sym, value.MethodEntry.builtin(&builtinMutexTryLock, .{ .exact = 0 }));

    const owned_q_sym = try vm.intern("owned?");
    try vm.mutex_class.module.methods.put(owned_q_sym, value.MethodEntry.builtin(&builtinMutexOwnedQ, .{ .exact = 0 }));

    const synchronize_sym = try vm.intern("synchronize");
    try vm.mutex_class.module.methods.put(synchronize_sym, value.MethodEntry.builtin(&builtinMutexSynchronize, .{ .exact = 0 }));

    const sleep_sym = try vm.intern("sleep");
    try vm.mutex_class.module.methods.put(sleep_sym, value.MethodEntry.builtin(&builtinMutexSleep, .{ .variadic = 0 }));
}

// =============================================================================
// Class methods
// =============================================================================

fn builtinMutexNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    const mutex_obj = try vm.newMutex(Value.fromObject(&vm.mutex_class.module.object));
    const mutex_val = Value.fromObject(&mutex_obj.object);
    _ = try vm.callMethodByNameForwardingKeywords(mutex_val, "initialize", args, block);
    return mutex_val;
}

// =============================================================================
// Instance methods
// =============================================================================

fn builtinMutexInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinMutexLock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mutex = receiver.toMutexObject();

    if (mutex.state == .locked) {
        if (isOwnedByCurrentFiber(vm, mutex)) {
            return vm.raiseExceptionFmt(vm.thread_error_class, "deadlock; recursive locking", .{});
        }
        try waitForMutex(vm, mutex);
    }

    try acquireMutex(vm, mutex);
    return receiver;
}

fn builtinMutexUnlock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mutex = receiver.toMutexObject();

    if (mutex.state != .locked) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to unlock a mutex which is not locked", .{});
    }

    if (!isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to unlock a mutex which is locked by another thread/fiber", .{});
    }

    try releaseMutex(vm, mutex);
    return receiver;
}

fn builtinMutexLockedQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mutex = receiver.toMutexObject();
    return Value.boolean(mutex.state == .locked);
}

fn builtinMutexTryLock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mutex = receiver.toMutexObject();

    if (mutex.state == .locked) {
        if (isOwnedByCurrentFiber(vm, mutex)) {
            return Value.boolean(false);
        }
        return Value.boolean(false);
    }

    try acquireMutex(vm, mutex);
    return Value.boolean(true);
}

fn builtinMutexOwnedQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mutex = receiver.toMutexObject();

    if (mutex.state != .locked) return Value.boolean(false);

    return Value.boolean(isOwnedByCurrentFiber(vm, mutex));
}

fn builtinMutexSynchronize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);

    const mutex = receiver.toMutexObject();

    if (mutex.state == .locked and isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "deadlock; recursive locking", .{});
    }

    if (mutex.state == .locked) {
        try waitForMutex(vm, mutex);
    }
    try acquireMutex(vm, mutex);

    const yield_result = vm.yieldToBlock(blk, &[_]Value{}) catch |err| {
        try releaseMutex(vm, mutex);
        return err;
    };
    try releaseMutex(vm, mutex);

    return yield_result;
}

fn builtinMutexSleep(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const mutex = receiver.toMutexObject();

    var timeout: ?f64 = null;
    if (args.len == 1 and !args[0].isNil()) {
        const duration = args[0];
        if (duration.isInteger() or duration.isFloat()) {
            const dur_val = if (duration.isInteger()) duration.integerToF64() else duration.toFloatObject().val;
            if (dur_val < 0) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must not be negative", .{});
            }
            timeout = dur_val;
        } else {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Float", .{});
        }
    }

    if (mutex.state != .locked or !isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to sleep with a mutex not locked by the current thread", .{});
    }

    try releaseMutex(vm, mutex);

    const started = vm_mod.monotonicMilliseconds();
    const sleep_result: VMError!void = sleeping: {
        vm.deliverThreadInterrupt(true) catch |err| break :sleeping err;
        if (vm.currentFiberScheduler()) |scheduler| {
            var sleep_args = [_]Value{if (args.len == 1) args[0] else Value.nil()};
            _ = vm.callMethodByName(scheduler, "kernel_sleep", &sleep_args, null) catch |err| break :sleeping err;
        } else if (timeout) |seconds| {
            const duration_ms: i64 = @intFromFloat(@ceil(seconds * 1000.0));
            vm.timedSleepCurrentThread(duration_ms) catch |err| break :sleeping err;
        } else {
            vm.sleepCurrentThreadForever() catch |err| break :sleeping err;
        }
        vm.deliverThreadInterrupt(true) catch |err| break :sleeping err;
        break :sleeping;
    };
    try reacquireMutex(vm, mutex);
    try sleep_result;
    return Value.integer(@divTrunc(vm_mod.monotonicMilliseconds() - started + 500, 1000));
}

// =============================================================================
// Helpers
// =============================================================================

pub fn isOwnedByCurrentFiber(vm: *VM, mutex: *value.MutexObject) bool {
    return mutex.owner_thread != null and mutex.owner_thread == vm.current_thread and mutex.owner_fiber == vm.current_fiber;
}

pub fn acquireMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    const thread = vm.current_thread orelse return error.Fatal;
    std.debug.assert(mutex.state == .unlocked);
    thread.owned_mutexes.append(vm.gc_allocator, mutex) catch return error.Fatal;
    mutex.state = .locked;
    mutex.owner_thread = thread;
    mutex.owner_fiber = vm.current_fiber;
}

pub fn releaseMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    const owner = mutex.owner_thread orelse return error.Fatal;
    for (owner.owned_mutexes.items, 0..) |owned, index| {
        if (owned == mutex) {
            _ = owner.owned_mutexes.orderedRemove(index);
            @memset(std.mem.asBytes(&owner.owned_mutexes.unusedCapacitySlice()[0]), 0);
            break;
        }
    }
    mutex.state = .unlocked;
    mutex.owner_thread = null;
    mutex.owner_fiber = null;
    const pending = vm.pending_unwind;
    vm.pending_unwind = null;
    try vm.wakeNextMutexWaiter(mutex);
    vm.pending_unwind = pending;
}

// A sleeping waiter must own the lock again before an interrupt reaches Ruby.
// Keep waiting after interrupts, preserving their unwind until acquisition.
pub fn reacquireMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    var pending_unwind = vm.pending_unwind;
    vm.pending_unwind = null;
    defer vm.pending_unwind = pending_unwind;
    var interrupted = false;
    while (mutex.state == .locked) {
        waitForMutex(vm, mutex) catch |err| switch (err) {
            error.Unwind => {
                pending_unwind = vm.pending_unwind;
                vm.pending_unwind = null;
                interrupted = true;
            },
            else => return err,
        };
    }
    try acquireMutex(vm, mutex);
    if (interrupted) return error.Unwind;
}

pub fn waitForMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    const thread = vm.current_thread orelse return error.Fatal;
    const scheduler = vm.currentFiberScheduler();
    while (mutex.state == .locked) {
        if (isOwnedByCurrentFiber(vm, mutex)) return vm.raiseExceptionFmt(vm.thread_error_class, "deadlock; recursive locking", .{});
        if (scheduler) |fiber_scheduler| {
            try synchronization.blockFiber(vm, Value.fromObject(&mutex.object), &mutex.waiters, fiber_scheduler, null);
        } else {
            if (mutex.owner_thread == thread and !vm.thread_ignore_deadlock) {
                return vm.raiseExceptionFmt(vm.thread_error_class, "deadlock; lock already owned by another fiber belonging to the same thread", .{});
            }
            try vm.deliverThreadInterrupt(true);
            const waiter = try synchronization.addThreadWaiter(vm, &mutex.waiters, thread);
            defer synchronization.removeWaiterIfPresent(&mutex.waiters, waiter);
            const was_deadlockable = thread.deadlockable_wait;
            thread.deadlockable_wait = true;
            defer {
                thread.deadlockable_wait = was_deadlockable;
                if (thread.state != .terminated) thread.state = .running;
            }
            thread.state = .sleeping;
            while (thread.state == .sleeping) try vm.threadYield();
        }
    }
}
