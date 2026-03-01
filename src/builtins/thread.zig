const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const thread_class_val = Value.fromObject(vm.thread_class);
    const thread_singleton = try vm.getOrCreateSingletonClass(thread_class_val);

    // Class methods
    const new_sym = try vm.intern("new");
    try thread_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinThreadNew } });

    const start_sym = try vm.intern("start");
    try thread_singleton.module.methods.put(start_sym, .{ .method = .{ .builtin = &builtinThreadNew } });

    const fork_sym = try vm.intern("fork");
    try thread_singleton.module.methods.put(fork_sym, .{ .method = .{ .builtin = &builtinThreadNew } });

    const current_sym = try vm.intern("current");
    try thread_singleton.module.methods.put(current_sym, .{ .method = .{ .builtin = &builtinThreadCurrent } });

    const main_sym = try vm.intern("main");
    try thread_singleton.module.methods.put(main_sym, .{ .method = .{ .builtin = &builtinThreadMain } });

    const list_sym = try vm.intern("list");
    try thread_singleton.module.methods.put(list_sym, .{ .method = .{ .builtin = &builtinThreadList } });

    const pass_sym = try vm.intern("pass");
    try thread_singleton.module.methods.put(pass_sym, .{ .method = .{ .builtin = &builtinThreadPass } });

    const stop_sym = try vm.intern("stop");
    try thread_singleton.module.methods.put(stop_sym, .{ .method = .{ .builtin = &builtinThreadStop } });

    const kill_class_sym = try vm.intern("kill");
    try thread_singleton.module.methods.put(kill_class_sym, .{ .method = .{ .builtin = &builtinThreadKillClass } });

    // Instance methods
    const join_sym = try vm.intern("join");
    try vm.thread_class.module.methods.put(join_sym, .{ .method = .{ .builtin = &builtinThreadJoin } });

    const value_sym = try vm.intern("value");
    try vm.thread_class.module.methods.put(value_sym, .{ .method = .{ .builtin = &builtinThreadValue } });

    const alive_sym = try vm.intern("alive?");
    try vm.thread_class.module.methods.put(alive_sym, .{ .method = .{ .builtin = &builtinThreadAlive } });

    const status_sym = try vm.intern("status");
    try vm.thread_class.module.methods.put(status_sym, .{ .method = .{ .builtin = &builtinThreadStatus } });

    const kill_sym = try vm.intern("kill");
    try vm.thread_class.module.methods.put(kill_sym, .{ .method = .{ .builtin = &builtinThreadKill } });

    const exit_sym = try vm.intern("exit");
    try vm.thread_class.module.methods.put(exit_sym, .{ .method = .{ .builtin = &builtinThreadKill } });

    const terminate_sym = try vm.intern("terminate");
    try vm.thread_class.module.methods.put(terminate_sym, .{ .method = .{ .builtin = &builtinThreadKill } });

    const raise_sym = try vm.intern("raise");
    try vm.thread_class.module.methods.put(raise_sym, .{ .method = .{ .builtin = &builtinThreadRaise } });

    const run_sym = try vm.intern("run");
    try vm.thread_class.module.methods.put(run_sym, .{ .method = .{ .builtin = &builtinThreadRun } });

    const wakeup_sym = try vm.intern("wakeup");
    try vm.thread_class.module.methods.put(wakeup_sym, .{ .method = .{ .builtin = &builtinThreadWakeup } });

    const get_sym = try vm.intern("[]");
    try vm.thread_class.module.methods.put(get_sym, .{ .method = .{ .builtin = &builtinThreadGetFiberLocal } });

    const set_sym = try vm.intern("[]=");
    try vm.thread_class.module.methods.put(set_sym, .{ .method = .{ .builtin = &builtinThreadSetFiberLocal } });

    const key_sym = try vm.intern("key?");
    try vm.thread_class.module.methods.put(key_sym, .{ .method = .{ .builtin = &builtinThreadKey } });

    const keys_sym = try vm.intern("keys");
    try vm.thread_class.module.methods.put(keys_sym, .{ .method = .{ .builtin = &builtinThreadKeys } });

    const tv_get_sym = try vm.intern("thread_variable_get");
    try vm.thread_class.module.methods.put(tv_get_sym, .{ .method = .{ .builtin = &builtinThreadVarGet } });

    const tv_set_sym = try vm.intern("thread_variable_set");
    try vm.thread_class.module.methods.put(tv_set_sym, .{ .method = .{ .builtin = &builtinThreadVarSet } });

    const tv_has_sym = try vm.intern("thread_variable?");
    try vm.thread_class.module.methods.put(tv_has_sym, .{ .method = .{ .builtin = &builtinThreadVarHas } });

    const tv_list_sym = try vm.intern("thread_variables");
    try vm.thread_class.module.methods.put(tv_list_sym, .{ .method = .{ .builtin = &builtinThreadVarList } });

    const name_get_sym = try vm.intern("name");
    try vm.thread_class.module.methods.put(name_get_sym, .{ .method = .{ .builtin = &builtinThreadNameGet } });

    const name_set_sym = try vm.intern("name=");
    try vm.thread_class.module.methods.put(name_set_sym, .{ .method = .{ .builtin = &builtinThreadNameSet } });

    const priority_get_sym = try vm.intern("priority");
    try vm.thread_class.module.methods.put(priority_get_sym, .{ .method = .{ .builtin = &builtinThreadPriorityGet } });

    const priority_set_sym = try vm.intern("priority=");
    try vm.thread_class.module.methods.put(priority_set_sym, .{ .method = .{ .builtin = &builtinThreadPrioritySet } });

    const inspect_sym = try vm.intern("inspect");
    try vm.thread_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinThreadInspect } });

    const stop_q_sym = try vm.intern("stop?");
    try vm.thread_class.module.methods.put(stop_q_sym, .{ .method = .{ .builtin = &builtinThreadStopQ } });

    const initialize_sym = try vm.intern("initialize");
    try vm.thread_class.module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinThreadInitialize } });

    const report_on_exception_sym = try vm.intern("report_on_exception");
    try vm.thread_class.module.methods.put(report_on_exception_sym, .{ .method = .{ .builtin = &builtinThreadReportOnException } });

    const report_on_exception_set_sym = try vm.intern("report_on_exception=");
    try vm.thread_class.module.methods.put(report_on_exception_set_sym, .{ .method = .{ .builtin = &builtinThreadReportOnExceptionSet } });
}

// =============================================================================
// Class methods
// =============================================================================

fn builtinThreadNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }
    const class_obj = receiver.toClassObject();
    const thread = try vm.newThreadUnstarted(class_obj);
    const thread_val = Value.fromObject(thread);
    _ = try vm.callMethodByName(thread_val, "initialize", args, block);

    if (thread.block == null) {
        const exc = try vm.createException(vm.thread_error_class, "must be called with a block");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    try vm.startThread(thread);

    // Immediately yield to give the new thread a chance to start
    try vm.schedulerYield();

    return thread_val;
}

fn builtinThreadCurrent(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mt = try vm.ensureMainThread();
    return Value.fromObject(vm.current_thread orelse mt);
}

fn builtinThreadMain(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(try vm.ensureMainThread());
}

fn builtinThreadList(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    _ = try vm.ensureMainThread();
    const arr = try vm.createArray();
    for (vm.thread_list.items) |thread| {
        if (thread.state != .terminated) {
            arr.elements.append(vm.gc_allocator, Value.fromObject(thread)) catch return error.Fatal;
        }
    }
    return Value.fromObject(arr);
}

fn builtinThreadPass(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    try vm.threadYield();
    return Value.nil();
}

fn builtinThreadStop(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = vm.current_thread orelse {
        const exc = try vm.createException(vm.thread_error_class, "stopping main thread");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    if (thread == vm.main_thread orelse thread) {
        const exc = try vm.createException(vm.thread_error_class, "stopping main thread");
        vm.pending_exception = exc;
        return error.Unwind;
    }
    thread.state = .sleeping;
    try vm.threadYield();
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
            vm.runnable_queue.append(vm.allocator, thread) catch return error.Fatal;
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
        const exc = try vm.createException(vm.thread_error_class, "must be called with a block");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    try vm.configureThread(thread, blk, args);
    return receiver;
}

fn builtinThreadJoin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const thread = receiver.toThreadObject();

    if (vm.current_thread != null and thread == vm.current_thread.?) {
        const exc = try vm.createException(vm.thread_error_class, "Target thread must not be current thread");
        vm.pending_exception = exc;
        return error.Unwind;
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
            vm.pending_exception = exc;
            return error.Unwind;
        }
    }

    return receiver;
}

fn builtinThreadValue(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();

    if (vm.current_thread != null and thread == vm.current_thread.?) {
        const exc = try vm.createException(vm.thread_error_class, "Target thread must not be current thread");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    // Wait for thread to finish
    while (thread.state != .terminated) {
        try vm.threadYield();
    }

    // Re-raise exception if thread died with one
    if (!thread.terminated_normally) {
        if (thread.exception) |exc| {
            vm.pending_exception = exc;
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
        // Kill self: terminate immediately
        thread.state = .terminated;
        thread.result = Value.nil();
        thread.terminated_normally = true;
        // Remove from runnable queue
        removeFromRunnable(vm, thread);
        const is_main = vm.main_thread != null and thread == vm.main_thread.?;
        if (!is_main) {
            if (thread.coro) |c| c.yield();
        }
        return receiver;
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

    // Create exception
    const exc = if (args.len == 0)
        try vm.createException(vm.runtime_error_class, "")
    else if (args[0].isString())
        try vm.createException(vm.runtime_error_class, args[0].toStringObject().str)
    else if (args[0].isException())
        args[0].toExceptionObject()
    else if (args[0].isClass()) blk: {
        const msg = if (args.len > 1 and args[1].isString()) args[1].toStringObject().str else "";
        break :blk try vm.createException(args[0].toClassObject(), msg);
    } else try vm.createException(vm.runtime_error_class, "");

    thread.exception = exc;
    thread.terminated_normally = false;
    thread.state = .terminated;
    removeFromRunnable(vm, thread);
    return Value.nil();
}

fn builtinThreadRun(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    if (thread.state == .terminated) {
        const exc = try vm.createException(vm.thread_error_class, "killed thread");
        vm.pending_exception = exc;
        return error.Unwind;
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
        const exc = try vm.createException(vm.thread_error_class, "killed thread");
        vm.pending_exception = exc;
        return error.Unwind;
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
            arr.elements.append(vm.gc_allocator, Value.fromObject(key.*)) catch return error.Fatal;
        }
    }
    return Value.fromObject(arr);
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
            arr.elements.append(vm.gc_allocator, Value.fromObject(key.*)) catch return error.Fatal;
        }
    }
    return Value.fromObject(arr);
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
    const state_str = switch (thread.state) {
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

fn builtinThreadStopQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const thread = receiver.toThreadObject();
    return Value.boolean(thread.state == .sleeping or thread.state == .terminated);
}

fn builtinThreadReportOnException(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toThreadObject().report_on_exception);
}

fn builtinThreadReportOnExceptionSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    receiver.toThreadObject().report_on_exception = args[0].is_truthy();
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
    if (arg.isString()) return try vm.intern(arg.toStringObject().str);

    const to_str_sym = try vm.intern("to_str");
    if ((try vm.findMethod(arg, to_str_sym)) != null) {
        const coerced = try vm.callMethodByName(arg, "to_str", &[_]Value{}, null);
        if (coerced.isString()) return try vm.intern(coerced.toStringObject().str);
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
    vm.runnable_queue.append(vm.allocator, thread) catch {};
}
