const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const mutex_class_val = Value.fromObject(&vm.mutex_class.module.object);
    const mutex_singleton = try vm.getOrCreateSingletonClass(mutex_class_val);

    // Class methods
    const new_sym = try vm.intern("new");
    try mutex_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinMutexNew, .{ .variadic = 0 }));

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
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }
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
    _ = try vm.ensureMainThread();
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
    _ = try vm.ensureMainThread();
    const mutex = receiver.toMutexObject();

    if (mutex.state != .locked) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to unlock a mutex which is not locked", .{});
    }

    if (!isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Attempt to unlock a mutex which is locked by another thread/fiber", .{});
    }

    releaseMutex(vm, mutex);
    return receiver;
}

fn builtinMutexLockedQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();
    const mutex = receiver.toMutexObject();
    return Value.boolean(mutex.state == .locked);
}

fn builtinMutexTryLock(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();
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
    _ = try vm.ensureMainThread();
    const mutex = receiver.toMutexObject();

    if (mutex.state != .locked) return Value.boolean(false);

    return Value.boolean(isOwnedByCurrentFiber(vm, mutex));
}

fn builtinMutexSynchronize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();
    const blk = block orelse {
        return vm.raiseExceptionFmt(vm.argument_error_class, "no block given", .{});
    };

    const mutex = receiver.toMutexObject();

    if (mutex.state == .locked and isOwnedByCurrentFiber(vm, mutex)) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "deadlock; recursive locking", .{});
    }

    if (mutex.state == .locked) {
        try waitForMutex(vm, mutex);
    }
    try acquireMutex(vm, mutex);

    const yield_result = vm.yieldToBlock(blk, &[_]Value{}) catch |err| {
        releaseMutex(vm, mutex);
        return err;
    };
    releaseMutex(vm, mutex);

    return yield_result.controlFlowValue() orelse yield_result.value;
}

fn builtinMutexSleep(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    _ = try vm.ensureMainThread();
    const mutex = receiver.toMutexObject();

    var timeout: ?f64 = null;
    if (args.len == 1) {
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

    releaseMutex(vm, mutex);

    if (vm.current_thread == null) {
        try acquireMutex(vm, mutex);
        return Value.integer(0);
    }

    if (timeout == null) {
        try vm.sleepCurrentThreadForever();
    } else {
        const duration_ms = @as(i64, @intFromFloat(@ceil(timeout.? * 1000.0)));
        try vm.timedSleepCurrentThread(duration_ms);
    }

    if (mutex.state == .locked) {
        try waitForMutex(vm, mutex);
    }
    try acquireMutex(vm, mutex);

    return Value.integer(0);
}

// =============================================================================
// Helpers
// =============================================================================

pub fn isOwnedByCurrentFiber(vm: *VM, mutex: *value.MutexObject) bool {
    const current_thread = vm.current_thread;
    const current_fiber = vm.current_fiber;

    if (mutex.owner_thread != current_thread) return false;
    if (mutex.owner_fiber) |owner_fiber| {
        return owner_fiber == current_fiber;
    }
    return true;
}

pub fn acquireMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    mutex.state = .locked;
    mutex.owner_thread = vm.current_thread;
    mutex.owner_fiber = vm.current_fiber;
    if (vm.current_thread) |thread| {
        const gop = vm.thread_owned_mutexes.getOrPut(thread) catch return error.Fatal;
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }
        for (gop.value_ptr.items) |owned_mutex| {
            if (owned_mutex == mutex) return;
        }
        gop.value_ptr.append(vm.allocator, mutex) catch return error.Fatal;
    }
}

pub fn releaseMutex(vm: *VM, mutex: *value.MutexObject) void {
    if (mutex.owner_thread) |owner_thread| {
        if (vm.thread_owned_mutexes.getPtr(owner_thread)) |owned_mutexes| {
            var i: usize = 0;
            while (i < owned_mutexes.items.len) {
                if (owned_mutexes.items[i] == mutex) {
                    _ = owned_mutexes.orderedRemove(i);
                    break;
                }
                i += 1;
            }
        }
    }
    mutex.state = .unlocked;
    mutex.owner_thread = null;
    mutex.owner_fiber = null;
    vm.wakeNextMutexWaiter(mutex);
}

pub fn waitForMutex(vm: *VM, mutex: *value.MutexObject) VMError!void {
    const current_thread = vm.current_thread;
    const main_thread = vm.main_thread;

    if (current_thread != null and main_thread != null and current_thread.? != main_thread.?) {
        const gop = vm.mutex_waiters.getOrPut(mutex) catch return error.Fatal;
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }

        while (mutex.state == .locked) {
            var found = false;
            for (gop.value_ptr.items) |waiter| {
                if (waiter == current_thread.?) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                gop.value_ptr.append(vm.allocator, current_thread.?) catch return error.Fatal;
            }
            current_thread.?.state = .sleeping;
            try vm.threadYield();
        }
        current_thread.?.state = .running;
        return;
    }

    while (mutex.state == .locked) {
        try vm.threadYield();
    }
}
