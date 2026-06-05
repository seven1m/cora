const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const thread_class_val = Value.fromObject(&vm.thread_class.module.object);
    const thread_singleton = try vm.getOrCreateSingletonClass(thread_class_val);

    // Class methods
    const new_sym = try vm.intern("new");
    try thread_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinThreadNew, .{ .variadic = 0 }));

    const start_sym = try vm.intern("start");
    try thread_singleton.module.methods.put(start_sym, value.MethodEntry.builtin(&builtinThreadNew, .{ .variadic = 0 }));

    const fork_sym = try vm.intern("fork");
    try thread_singleton.module.methods.put(fork_sym, value.MethodEntry.builtin(&builtinThreadNew, .{ .variadic = 0 }));

    const current_sym = try vm.intern("current");
    try thread_singleton.module.methods.put(current_sym, value.MethodEntry.builtin(&builtinThreadCurrent, .{ .exact = 0 }));

    const main_sym = try vm.intern("main");
    try thread_singleton.module.methods.put(main_sym, value.MethodEntry.builtin(&builtinThreadMain, .{ .exact = 0 }));

    const list_sym = try vm.intern("list");
    try thread_singleton.module.methods.put(list_sym, value.MethodEntry.builtin(&builtinThreadList, .{ .exact = 0 }));

    const pass_sym = try vm.intern("pass");
    try thread_singleton.module.methods.put(pass_sym, value.MethodEntry.builtin(&builtinThreadPass, .{ .exact = 0 }));

    const stop_sym = try vm.intern("stop");
    try thread_singleton.module.methods.put(stop_sym, value.MethodEntry.builtin(&builtinThreadStop, .{ .exact = 0 }));

    const kill_class_sym = try vm.intern("kill");
    try thread_singleton.module.methods.put(kill_class_sym, value.MethodEntry.builtin(&builtinThreadKillClass, .{ .exact = 1 }));

    // Instance methods
    const join_sym = try vm.intern("join");
    try vm.thread_class.module.methods.put(join_sym, value.MethodEntry.builtin(&builtinThreadJoin, .{ .variadic = 0 }));

    const value_sym = try vm.intern("value");
    try vm.thread_class.module.methods.put(value_sym, value.MethodEntry.builtin(&builtinThreadValue, .{ .exact = 0 }));

    const alive_sym = try vm.intern("alive?");
    try vm.thread_class.module.methods.put(alive_sym, value.MethodEntry.builtin(&builtinThreadAlive, .{ .exact = 0 }));

    const status_sym = try vm.intern("status");
    try vm.thread_class.module.methods.put(status_sym, value.MethodEntry.builtin(&builtinThreadStatus, .{ .exact = 0 }));

    const group_sym = try vm.intern("group");
    try vm.thread_class.module.methods.put(group_sym, value.MethodEntry.builtin(&builtinThreadGroup, .{ .exact = 0 }));

    const kill_sym = try vm.intern("kill");
    try vm.thread_class.module.methods.put(kill_sym, value.MethodEntry.builtin(&builtinThreadKill, .{ .exact = 0 }));

    const exit_sym = try vm.intern("exit");
    try vm.thread_class.module.methods.put(exit_sym, value.MethodEntry.builtin(&builtinThreadKill, .{ .exact = 0 }));

    const terminate_sym = try vm.intern("terminate");
    try vm.thread_class.module.methods.put(terminate_sym, value.MethodEntry.builtin(&builtinThreadKill, .{ .exact = 0 }));

    const raise_sym = try vm.intern("raise");
    try vm.thread_class.module.methods.put(raise_sym, value.MethodEntry.builtin(&builtinThreadRaise, .{ .variadic = 0 }));

    const run_sym = try vm.intern("run");
    try vm.thread_class.module.methods.put(run_sym, value.MethodEntry.builtin(&builtinThreadRun, .{ .exact = 0 }));

    const wakeup_sym = try vm.intern("wakeup");
    try vm.thread_class.module.methods.put(wakeup_sym, value.MethodEntry.builtin(&builtinThreadWakeup, .{ .exact = 0 }));

    const get_sym = try vm.intern("[]");
    try vm.thread_class.module.methods.put(get_sym, value.MethodEntry.builtin(&builtinThreadGetFiberLocal, .{ .exact = 1 }));

    const set_sym = try vm.intern("[]=");
    try vm.thread_class.module.methods.put(set_sym, value.MethodEntry.builtin(&builtinThreadSetFiberLocal, .{ .exact = 2 }));

    const key_sym = try vm.intern("key?");
    try vm.thread_class.module.methods.put(key_sym, value.MethodEntry.builtin(&builtinThreadKey, .{ .exact = 1 }));

    const keys_sym = try vm.intern("keys");
    try vm.thread_class.module.methods.put(keys_sym, value.MethodEntry.builtin(&builtinThreadKeys, .{ .exact = 0 }));

    const tv_get_sym = try vm.intern("thread_variable_get");
    try vm.thread_class.module.methods.put(tv_get_sym, value.MethodEntry.builtin(&builtinThreadVarGet, .{ .exact = 1 }));

    const tv_set_sym = try vm.intern("thread_variable_set");
    try vm.thread_class.module.methods.put(tv_set_sym, value.MethodEntry.builtin(&builtinThreadVarSet, .{ .exact = 2 }));

    const tv_has_sym = try vm.intern("thread_variable?");
    try vm.thread_class.module.methods.put(tv_has_sym, value.MethodEntry.builtin(&builtinThreadVarHas, .{ .exact = 1 }));

    const tv_list_sym = try vm.intern("thread_variables");
    try vm.thread_class.module.methods.put(tv_list_sym, value.MethodEntry.builtin(&builtinThreadVarList, .{ .exact = 0 }));

    const name_get_sym = try vm.intern("name");
    try vm.thread_class.module.methods.put(name_get_sym, value.MethodEntry.builtin(&builtinThreadNameGet, .{ .exact = 0 }));

    const name_set_sym = try vm.intern("name=");
    try vm.thread_class.module.methods.put(name_set_sym, value.MethodEntry.builtin(&builtinThreadNameSet, .{ .exact = 1 }));

    const priority_get_sym = try vm.intern("priority");
    try vm.thread_class.module.methods.put(priority_get_sym, value.MethodEntry.builtin(&builtinThreadPriorityGet, .{ .exact = 0 }));

    const priority_set_sym = try vm.intern("priority=");
    try vm.thread_class.module.methods.put(priority_set_sym, value.MethodEntry.builtin(&builtinThreadPrioritySet, .{ .exact = 1 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.thread_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinThreadInspect, .{ .exact = 0 }));

    const backtrace_sym = try vm.intern("backtrace");
    try vm.thread_class.module.methods.put(backtrace_sym, value.MethodEntry.builtin(&builtinThreadBacktrace, .{ .exact = 0 }));

    const path_sym = try vm.intern("path");
    try vm.thread_backtrace_location_class.module.methods.put(path_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationPath, .{ .exact = 0 }));

    const absolute_path_sym = try vm.intern("absolute_path");
    try vm.thread_backtrace_location_class.module.methods.put(absolute_path_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationAbsolutePath, .{ .exact = 0 }));

    const label_sym = try vm.intern("label");
    try vm.thread_backtrace_location_class.module.methods.put(label_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationLabel, .{ .exact = 0 }));

    const base_label_sym = try vm.intern("base_label");
    try vm.thread_backtrace_location_class.module.methods.put(base_label_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationBaseLabel, .{ .exact = 0 }));

    const lineno_sym = try vm.intern("lineno");
    try vm.thread_backtrace_location_class.module.methods.put(lineno_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationLineno, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.thread_backtrace_location_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationToS, .{ .exact = 0 }));

    const location_inspect_sym = try vm.intern("inspect");
    try vm.thread_backtrace_location_class.module.methods.put(location_inspect_sym, value.MethodEntry.builtin(&builtinThreadBacktraceLocationToS, .{ .exact = 0 }));

    const stop_q_sym = try vm.intern("stop?");
    try vm.thread_class.module.methods.put(stop_q_sym, value.MethodEntry.builtin(&builtinThreadStopQ, .{ .exact = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.thread_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinThreadInitialize, .{ .variadic = 0 }));

    const report_on_exception_sym = try vm.intern("report_on_exception");
    try vm.thread_class.module.methods.put(report_on_exception_sym, value.MethodEntry.builtin(&builtinThreadReportOnException, .{ .exact = 0 }));

    const report_on_exception_set_sym = try vm.intern("report_on_exception=");
    try vm.thread_class.module.methods.put(report_on_exception_set_sym, value.MethodEntry.builtin(&builtinThreadReportOnExceptionSet, .{ .exact = 1 }));

    const add_sym = try vm.intern("add");
    try vm.thread_group_class.module.methods.put(add_sym, value.MethodEntry.builtin(&builtinThreadGroupAdd, .{ .exact = 1 }));

    const list_group_sym = try vm.intern("list");
    try vm.thread_group_class.module.methods.put(list_group_sym, value.MethodEntry.builtin(&builtinThreadGroupList, .{ .exact = 0 }));

    const enclosed_sym = try vm.intern("enclosed?");
    try vm.thread_group_class.module.methods.put(enclosed_sym, value.MethodEntry.builtin(&builtinThreadGroupEnclosed, .{ .exact = 0 }));
}

// =============================================================================
// Class methods
// =============================================================================

fn builtinThreadNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    const class_obj = receiver.toClassObject();
    const thread = try vm.newThreadUnstarted(class_obj);
    const thread_val = Value.fromObject(&thread.object);
    _ = try vm.callMethodByNameForwardingKeywords(thread_val, "initialize", args, block);

    if (thread.block == null) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "must be called with a block", .{});
    }

    try vm.startThread(thread);

    // Immediately yield to give the new thread a chance to start
    try vm.schedulerYield();

    return thread_val;
}

fn builtinThreadCurrent(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mt = try vm.ensureMainThread();
    return Value.fromObject(&(vm.current_thread orelse mt).object);
}

fn builtinThreadMain(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(&(try vm.ensureMainThread()).object);
}

fn builtinThreadList(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();
    const arr = try vm.createArray();
    for (vm.thread_list.items) |thread| {
        if (thread.state != .terminated) {
            arr.elements.append(vm.gc_allocator, Value.fromObject(&thread.object)) catch return error.Fatal;
        }
    }
    return Value.fromObject(&arr.object);
}

fn builtinThreadPass(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try vm.threadYield();
    return Value.nil();
}

fn builtinThreadStop(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = vm.current_thread orelse {
        return vm.raiseExceptionFmt(vm.thread_error_class, "stopping main thread", .{});
    };
    if (thread == vm.main_thread orelse thread) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "stopping main thread", .{});
    }
    thread.state = .sleeping;
    try vm.threadYield();
    if (vm.pendingException()) |exc| {
        if (exc.object.class == vm.thread_kill_exception_class and thread.state != .terminated) {
            thread.state = .aborting;
        }
    }
    return Value.nil();
}

fn builtinThreadKillClass(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isThread()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type (expected Thread)", .{});
    }
    const thread = args[0].toThreadObject();
    thread.kill_requested = true;
    if (thread.state == .sleeping) {
        thread.state = .running;
        // Add back to runnable queue if not there
        for (vm.runnable_queue.items) |t| {
            if (t == thread) break;
        } else {
            vm.runnable_queue.append(vm.gc_allocator, thread) catch return error.Fatal;
        }
    }
    return args[0];
}

// =============================================================================
// Instance methods
// =============================================================================

fn builtinThreadInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const thread = receiver.toThreadObject();
    const blk = block orelse {
        return vm.raiseExceptionFmt(vm.thread_error_class, "must be called with a block", .{});
    };

    try vm.configureThread(thread, blk, args);
    return receiver;
}

fn builtinThreadJoin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const thread = receiver.toThreadObject();

    if (vm.current_thread != null and thread == vm.current_thread.?) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Target thread must not be current thread", .{});
    }

    const timeout = try optionalTimeoutArg(vm, args);
    if (timeout) |seconds| {
        if (thread.state == .terminated) {
            return receiver;
        }

        if (seconds <= 0.0) {
            return Value.nil();
        }

        var spin_budget: u32 = @intFromFloat(@min(seconds * 1000.0, 1000.0));
        if (spin_budget == 0) spin_budget = 1;
        while (thread.state != .terminated and spin_budget > 0) : (spin_budget -= 1) {
            try vm.threadYield();
        }

        if (thread.state != .terminated) {
            return Value.nil();
        }
    } else {
        // Wait for thread to finish.
        while (thread.state != .terminated) {
            try vm.threadYield();
        }
    }

    // Re-raise exception if thread died with one
    if (!thread.terminated_normally) {
        if (thread.exception) |exc| {
            vm.setPendingException(exc);
            return error.Unwind;
        }
    }

    return receiver;
}

fn builtinThreadGroup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = if (receiver.isThread())
        receiver.toThreadObject()
    else
        (vm.current_thread orelse try vm.ensureMainThread());
    return try threadGroupForThread(vm, thread);
}

fn builtinThreadGroupAdd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isThread()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type (expected Thread)", .{});
    }

    const thread = args[0].toThreadObject();
    const previous_group = try threadGroupForThread(vm, thread);
    try removeThreadFromGroup(vm, previous_group, thread);
    try appendThreadToGroup(vm, receiver, thread);
    try vm.setInstanceVariable(args[0], "@thread_group", receiver);
    return receiver;
}

fn builtinThreadGroupList(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const threads = try threadGroupThreads(vm, receiver);
    const out = try vm.createArray();
    for (threads.elements.items) |thread_value| {
        out.elements.append(vm.gc_allocator, thread_value) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

fn builtinThreadGroupEnclosed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean((try vm.getInstanceVariable(receiver, "@enclosed")).isTruthy());
}

fn threadGroupForThread(vm: *VM, thread: *value.ThreadObject) VMError!Value {
    const group = try vm.getInstanceVariable(Value.fromObject(&thread.object), "@thread_group");
    return if (group.isNil()) vm.default_thread_group else group;
}

fn threadGroupThreads(vm: *VM, receiver: Value) VMError!*value.ArrayObject {
    const threads_value = try vm.getInstanceVariable(receiver, "@threads");
    if (threads_value.isNil()) {
        const threads = try vm.createArray();
        try vm.setInstanceVariable(receiver, "@threads", Value.fromObject(&threads.object));
        return threads;
    }
    return threads_value.toArrayObject();
}

fn appendThreadToGroup(vm: *VM, receiver: Value, thread: *value.ThreadObject) VMError!void {
    const threads = try threadGroupThreads(vm, receiver);
    const thread_value = Value.fromObject(&thread.object);
    for (threads.elements.items) |entry| {
        if (entry.isThread() and entry.toThreadObject() == thread) return;
    }
    threads.elements.append(vm.gc_allocator, thread_value) catch return error.Fatal;
}

fn removeThreadFromGroup(vm: *VM, receiver: Value, thread: *value.ThreadObject) VMError!void {
    const threads = try threadGroupThreads(vm, receiver);
    for (threads.elements.items, 0..) |entry, i| {
        if (entry.isThread() and entry.toThreadObject() == thread) {
            _ = threads.elements.orderedRemove(i);
            return;
        }
    }
}

fn builtinThreadValue(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();

    if (vm.current_thread != null and thread == vm.current_thread.?) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "Target thread must not be current thread", .{});
    }

    // Wait for thread to finish
    while (thread.state != .terminated) {
        try vm.threadYield();
    }

    // Re-raise exception if thread died with one
    if (!thread.terminated_normally) {
        if (thread.exception) |exc| {
            vm.setPendingException(exc);
            return error.Unwind;
        }
    }

    return thread.result;
}

fn builtinThreadAlive(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    return Value.boolean(thread.state != .terminated);
}

fn builtinThreadStatus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    if (thread.waiting_on_queue) return try vm.newString("sleep", false);
    return switch (thread.state) {
        .created, .running => try vm.newString("run", false),
        .sleeping => try vm.newString("sleep", false),
        .aborting => try vm.newString("aborting", false),
        .terminated => if (thread.terminated_normally) Value.boolean(false) else Value.nil(),
    };
}

fn builtinThreadKill(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();

    const is_current = vm.current_thread != null and thread == vm.current_thread.?;
    if (is_current) {
        thread.state = .aborting;
        return vm.raiseExceptionFmt(vm.thread_kill_exception_class, "", .{});
    }

    thread.kill_requested = true;
    if (thread.state == .sleeping) {
        thread.state = .running;
        addToRunnableIfAbsent(vm, thread);
    }
    return receiver;
}

fn builtinThreadRaise(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const thread = receiver.toThreadObject();
    if (thread.state == .terminated) return Value.nil();

    // Validate and create the exception
    const exc = blk: {
        if (args.len == 0) {
            break :blk try vm.createExceptionWithoutBacktrace(vm.runtime_error_class, "");
        }

        if (args[0].isString()) {
            break :blk try vm.createExceptionWithoutBacktrace(vm.runtime_error_class, args[0].toStringObject().str);
        }

        if (args[0].isException()) {
            if (args.len > 1) {
                // Call exception#exception(message) to create a copy, matching MRI semantics
                const exc_val = args[0];
                const copy_val = try vm.callMethodByName(exc_val, "exception", args[1..], null);
                break :blk copy_val.toExceptionObject();
            } else {
                break :blk args[0].toExceptionObject();
            }
        }

        if (args[0].isClass()) {
            const class_obj = args[0].toClassObject();
            if (!vm.isClassOrSubclassOf(class_obj, vm.exception_class)) {
                return vm.raiseExceptionFmt(vm.type_error_class, "exception class/object expected", .{});
            }
            const msg = if (args.len > 1 and args[1].isString()) args[1].toStringObject().str else "";
            break :blk try vm.createExceptionWithoutBacktrace(class_obj, msg);
        }

        // Non-Exception object: raise TypeError
        return vm.raiseExceptionFmt(vm.type_error_class, "exception class/object expected", .{});
    };

    // Self-raise: deliver synchronously
    const is_current = vm.current_thread != null and thread == vm.current_thread.?;
    if (is_current) {
        try vm.captureAndSetExceptionBacktrace(exc);
        vm.setPendingException(exc);
        return error.Unwind;
    }

    // Deliver exception asynchronously to the target thread
    thread.async_exception = exc;
    if (thread.state == .sleeping) {
        thread.state = .running;
        addToRunnableIfAbsent(vm, thread);
    }
    return Value.nil();
}

fn builtinThreadRun(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    if (thread.state == .terminated) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "killed thread", .{});
    }
    if (thread.state == .sleeping) {
        thread.state = .running;
        addToRunnableIfAbsent(vm, thread);
    }
    try vm.threadYield();
    return receiver;
}

fn builtinThreadWakeup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    if (thread.state == .terminated) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "killed thread", .{});
    }
    if (thread.state == .sleeping) {
        thread.state = .running;
        addToRunnableIfAbsent(vm, thread);
    }
    return receiver;
}

// =============================================================================
// Fiber-local variables (Thread#[] / Thread#[]=)
// =============================================================================

fn builtinThreadGetFiberLocal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    const fiber = try fiberLocalTarget(vm, thread);
    const key = try symbolArg(vm, args[0]);
    if (fiber.fiber_locals) |locals| {
        if (locals.get(key)) |val| return val;
    }
    return Value.nil();
}

fn builtinThreadSetFiberLocal(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen thread locals", .{});
    }
    const thread = receiver.toThreadObject();
    const fiber = try fiberLocalTarget(vm, thread);
    const key = try symbolArg(vm, args[0]);
    if (args[1].isNil()) {
        if (fiber.fiber_locals) |*locals| {
            _ = locals.remove(key);
        }
        return Value.nil();
    }
    if (fiber.fiber_locals == null) {
        fiber.fiber_locals = std.AutoHashMap(*value.SymbolObject, Value).init(vm.gc_allocator);
    }
    fiber.fiber_locals.?.put(key, args[1]) catch return error.Fatal;
    return args[1];
}

fn builtinThreadKey(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    const fiber = try fiberLocalTarget(vm, thread);
    const key = try symbolArg(vm, args[0]);
    if (fiber.fiber_locals) |locals| {
        return Value.boolean(locals.contains(key));
    }
    return Value.boolean(false);
}

fn builtinThreadKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    const fiber = try fiberLocalTarget(vm, thread);
    const arr = try vm.createArray();
    if (fiber.fiber_locals) |locals| {
        var it = locals.keyIterator();
        while (it.next()) |key| {
            arr.elements.append(vm.gc_allocator, Value.fromObject(&key.*.object)) catch return error.Fatal;
        }
    }
    return Value.fromObject(&arr.object);
}

// =============================================================================
// Thread variables (thread_variable_get / thread_variable_set)
// =============================================================================

fn builtinThreadVarGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    const key = try symbolArg(vm, args[0]);
    if (thread.thread_variables) |vars| {
        if (vars.get(key)) |val| return val;
    }
    return Value.nil();
}

fn builtinThreadVarSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen thread locals", .{});
    }
    const thread = receiver.toThreadObject();
    const key = try symbolArg(vm, args[0]);
    if (args[1].isNil()) {
        if (thread.thread_variables) |*vars| {
            _ = vars.remove(key);
        }
        return Value.nil();
    }
    if (thread.thread_variables == null) {
        thread.thread_variables = std.AutoHashMap(*value.SymbolObject, Value).init(vm.gc_allocator);
    }
    thread.thread_variables.?.put(key, args[1]) catch return error.Fatal;
    return args[1];
}

fn builtinThreadVarHas(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    const key = try symbolArg(vm, args[0]);
    if (thread.thread_variables) |vars| {
        return Value.boolean(vars.contains(key));
    }
    return Value.boolean(false);
}

fn builtinThreadVarList(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    const arr = try vm.createArray();
    if (thread.thread_variables) |vars| {
        var it = vars.keyIterator();
        while (it.next()) |key| {
            arr.elements.append(vm.gc_allocator, Value.fromObject(&key.*.object)) catch return error.Fatal;
        }
    }
    return Value.fromObject(&arr.object);
}

// =============================================================================
// Metadata
// =============================================================================

fn builtinThreadNameGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    if (thread.name) |n| return try vm.newString(n, false);
    return Value.nil();
}

fn builtinThreadNameSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    if (args[0].isNil()) {
        thread.name = null;
    } else {
        const name = try args[0].coerceToStr(vm, "no implicit conversion into String");
        if (std.mem.indexOfScalar(u8, name, 0) != null) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "thread name must not contain null bytes", .{});
        }
        thread.name = vm.gc_allocator_atomic.dupe(u8, name) catch return error.Fatal;
    }
    return args[0];
}

fn builtinThreadPriorityGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    return Value.integer(@intCast(thread.priority));
}

fn builtinThreadPrioritySet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const thread = receiver.toThreadObject();
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const prio = args[0].toInteger();
    thread.priority = @intCast(std.math.clamp(prio, -3, 3));
    return args[0];
}

fn builtinThreadInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    const state_str = if (thread.waiting_on_queue)
        "sleep"
    else switch (thread.state) {
        .created, .running => "run",
        .sleeping => "sleep",
        .aborting => "aborting",
        .terminated => if (thread.terminated_normally) "dead" else "dead",
    };
    const msg = std.fmt.allocPrint(
        vm.gc_allocator,
        "#<Thread:0x{x} {s}>",
        .{ @intFromPtr(thread), state_str },
    ) catch return error.Fatal;
    return try vm.newString(msg, false);
}

fn builtinThreadBacktrace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();

    if (thread.waiting_on_require) {
        const arr = try vm.createArray();
        arr.elements.append(vm.gc_allocator, try vm.newString("require", false)) catch return error.Fatal;
        if (try vm.captureThreadBacktrace(thread)) |backtrace| {
            for (backtrace.elements.items) |entry| {
                arr.elements.append(vm.gc_allocator, entry) catch return error.Fatal;
            }
        }
        return Value.fromObject(&arr.object);
    }

    if (thread.state == .terminated) {
        if (thread.exception) |exc| {
            if (exc.backtrace) |backtrace| return Value.fromObject(&backtrace.object);
        }
        return Value.nil();
    }

    if (try vm.captureThreadBacktrace(thread)) |backtrace| {
        return Value.fromObject(&backtrace.object);
    }
    return Value.nil();
}

fn builtinThreadBacktraceLocationPath(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@path");
}

fn builtinThreadBacktraceLocationAbsolutePath(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@absolute_path");
}

fn builtinThreadBacktraceLocationLabel(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@label");
}

fn builtinThreadBacktraceLocationBaseLabel(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const label = try vm.getInstanceVariable(receiver, "@label");
    const label_string = label.toStringObject().str;
    const stripped = if (std.mem.startsWith(u8, label_string, "block in "))
        label_string["block in ".len..]
    else
        label_string;
    const hash_idx = std.mem.lastIndexOfScalar(u8, stripped, '#');
    const dot_idx = std.mem.lastIndexOfScalar(u8, stripped, '.');
    const split_idx = if (hash_idx != null and dot_idx != null)
        @max(hash_idx.?, dot_idx.?)
    else
        hash_idx orelse dot_idx;
    const base = if (split_idx) |idx| stripped[idx + 1 ..] else stripped;
    return try vm.newString(base, false);
}

fn builtinThreadBacktraceLocationLineno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@lineno");
}

fn builtinThreadBacktraceLocationToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@to_s");
}

fn builtinThreadStopQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    return Value.boolean(thread.waiting_on_queue or thread.waiting_on_require or thread.state == .sleeping or thread.state == .terminated);
}

fn builtinThreadReportOnException(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toThreadObject().report_on_exception);
}

fn builtinThreadReportOnExceptionSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    receiver.toThreadObject().report_on_exception = args[0].isTruthy();
    return args[0];
}

// =============================================================================
// Helpers
// =============================================================================

fn optionalTimeoutArg(vm: *VM, args: []Value) VMError!?f64 {
    if (args.len == 0 or args[0].isNil()) return null;

    const timeout = args[0];
    if (timeout.isInteger()) return timeout.integerToF64();
    if (timeout.isFloat()) return timeout.toFloatObject().val;

    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Float", .{});
}

fn symbolArg(vm: *VM, arg: Value) VMError!*value.SymbolObject {
    if (arg.isSymbol()) return arg.toSymbolObject();
    switch (try vm.probeToStringValue(arg)) {
        .string => |coerced| return try vm.intern(coerced.toStringObject().str),
        .missing, .nil_result => {},
    }

    return raiseNotSymbolTypeError(vm, arg);
}

fn raiseNotSymbolTypeError(vm: *VM, arg: Value) VMError!*value.SymbolObject {
    if (arg.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "{d} is not a symbol", .{arg.toInteger()});
    }
    if (arg.isBigInteger()) {
        const value_str = arg.toBigIntegerObject().value.toString(vm.allocator, 10, .lower) catch return error.Fatal;
        defer vm.allocator.free(value_str);
        return vm.raiseExceptionFmt(vm.type_error_class, "{s} is not a symbol", .{value_str});
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "is not a symbol", .{});
}

fn fiberLocalTarget(vm: *VM, thread: *value.ThreadObject) VMError!*value.FiberObject {
    if (vm.current_thread != null and vm.current_thread.? == thread) {
        return vm.current_fiber;
    }
    if (thread.current_fiber) |fiber| return fiber;
    if (thread.main_fiber) |fiber| return fiber;
    return error.Fatal;
}

fn removeFromRunnable(vm: *VM, thread: *value.ThreadObject) void {
    var i: usize = 0;
    while (i < vm.runnable_queue.items.len) {
        if (vm.runnable_queue.items[i] == thread) {
            _ = vm.runnable_queue.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn addToRunnableIfAbsent(vm: *VM, thread: *value.ThreadObject) void {
    for (vm.runnable_queue.items) |t| {
        if (t == thread) return;
    }
    vm.runnable_queue.append(vm.gc_allocator, thread) catch {};
}
