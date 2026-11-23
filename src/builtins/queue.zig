const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const synchronization = @import("synchronization.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const queue_class_val = Value.fromObject(&vm.queue_class.module.object);
    const queue_singleton = try vm.getOrCreateSingletonClass(queue_class_val);
    const sized_queue_class_val = Value.fromObject(&vm.sized_queue_class.module.object);

    const new_sym = try vm.intern("new");
    try queue_singleton.module.methods.put(new_sym, value.MethodEntry.keywordBuiltin(&builtinQueueNew, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.queue_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinQueueInitialize, .{ .variadic = 0 }, .private));

    const append_sym = try vm.intern("<<");
    try vm.queue_class.module.methods.put(append_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const push_sym = try vm.intern("push");
    try vm.queue_class.module.methods.put(push_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const enq_sym = try vm.intern("enq");
    try vm.queue_class.module.methods.put(enq_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const clear_sym = try vm.intern("clear");
    try vm.queue_class.module.methods.put(clear_sym, value.MethodEntry.builtin(&builtinQueueClear, .{ .exact = 0 }));

    const pop_sym = try vm.intern("pop");
    try vm.queue_class.module.methods.put(pop_sym, value.MethodEntry.keywordBuiltin(&builtinQueuePop, .{ .variadic = 0 }));

    const deq_sym = try vm.intern("deq");
    try vm.queue_class.module.methods.put(deq_sym, value.MethodEntry.keywordBuiltin(&builtinQueuePop, .{ .variadic = 0 }));

    const shift_sym = try vm.intern("shift");
    try vm.queue_class.module.methods.put(shift_sym, value.MethodEntry.keywordBuiltin(&builtinQueuePop, .{ .variadic = 0 }));

    const size_sym = try vm.intern("size");
    try vm.queue_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinQueueSize, .{ .exact = 0 }));

    const length_sym = try vm.intern("length");
    try vm.queue_class.module.methods.put(length_sym, value.MethodEntry.builtin(&builtinQueueSize, .{ .exact = 0 }));

    const empty_sym = try vm.intern("empty?");
    try vm.queue_class.module.methods.put(empty_sym, value.MethodEntry.builtin(&builtinQueueEmpty, .{ .exact = 0 }));

    const close_sym = try vm.intern("close");
    try vm.queue_class.module.methods.put(close_sym, value.MethodEntry.builtin(&builtinQueueClose, .{ .exact = 0 }));

    const closed_sym = try vm.intern("closed?");
    try vm.queue_class.module.methods.put(closed_sym, value.MethodEntry.builtin(&builtinQueueClosed, .{ .exact = 0 }));

    const num_waiting_sym = try vm.intern("num_waiting");
    try vm.queue_class.module.methods.put(num_waiting_sym, value.MethodEntry.builtin(&builtinQueueNumWaiting, .{ .exact = 0 }));

    const freeze_sym = try vm.intern("freeze");
    try vm.queue_class.module.methods.put(freeze_sym, value.MethodEntry.builtin(&builtinQueueFreeze, .{ .exact = 0 }));

    const sized_queue_initialize_sym = try vm.intern("initialize");
    try vm.sized_queue_class.module.methods.put(sized_queue_initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinSizedQueueInitialize, .{ .exact = 1 }, .private));

    try vm.sized_queue_class.module.methods.put(append_sym, value.MethodEntry.keywordBuiltin(&builtinSizedQueuePush, .{ .variadic = 1 }));
    try vm.sized_queue_class.module.methods.put(push_sym, value.MethodEntry.keywordBuiltin(&builtinSizedQueuePush, .{ .variadic = 1 }));
    try vm.sized_queue_class.module.methods.put(enq_sym, value.MethodEntry.keywordBuiltin(&builtinSizedQueuePush, .{ .variadic = 1 }));

    const max_sym = try vm.intern("max");
    try vm.sized_queue_class.module.methods.put(max_sym, value.MethodEntry.builtin(&builtinSizedQueueMax, .{ .exact = 0 }));

    const max_set_sym = try vm.intern("max=");
    try vm.sized_queue_class.module.methods.put(max_set_sym, value.MethodEntry.builtin(&builtinSizedQueueMaxSet, .{ .exact = 1 }));

    _ = sized_queue_class_val;
}

fn builtinQueueNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());
    const queue_obj = try vm.newQueue(receiver);
    const queue_val = Value.fromObject(&queue_obj.object);
    _ = try vm.callMethodByNameForwardingKeywords(queue_val, "initialize", args, block);
    return queue_val;
}

fn builtinQueueInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const queue = receiver.toQueueObject();
    resetQueue(queue);
    queue.max_size = null;

    if (args.len == 0) return receiver;

    const source = if (args[0].isArray()) args[0] else blk: {
        const coerced = try vm.checkCallMethodByName(args[0], "to_a", false, &[_]Value{}, null) orelse {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Array", .{vm.className(args[0])});
        };
        if (!coerced.isArray()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} into Array ({s}#to_a gives {s})",
                .{ vm.className(args[0]), vm.className(args[0]), vm.className(coerced) },
            );
        }
        break :blk coerced;
    };

    for (source.toArrayObject().elements.items) |item| {
        queue.items.append(vm.gc_allocator, item) catch return error.Fatal;
    }
    return receiver;
}

fn builtinQueuePush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const queue = receiver.toQueueObject();
    if (queue.closed) {
        return vm.raiseExceptionFmt(vm.closed_queue_error_class, "queue closed", .{});
    }

    queue.items.append(vm.gc_allocator, args[0]) catch return error.Fatal;
    try wakeNextDequeueWaiter(vm, queue);
    return receiver;
}

fn builtinQueueClear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const queue = receiver.toQueueObject();
    queue.items.clearRetainingCapacity();
    queue.read_index = 0;
    try wakeAllEnqueueWaiters(vm, queue);
    return receiver;
}

fn builtinQueueFreeze(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const message = std.fmt.allocPrint(
        vm.gc_allocator,
        "cannot freeze #<{s}:0x{x}>",
        .{ vm.className(receiver), receiver.raw },
    ) catch return error.Fatal;
    return vm.raiseExceptionFmt(vm.type_error_class, "{s}", .{message});
}

fn builtinSizedQueueInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const queue = receiver.toQueueObject();
    resetQueue(queue);
    queue.max_size = try sizedQueueCapacity(vm, args[0]);
    return receiver;
}

fn builtinSizedQueuePush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    var keyword_timeout: ?Value = null;
    try vm.consumeKeywordArgs(.{"timeout"}, .{&keyword_timeout});
    try vm.validateKeywordArgsConsumed();

    const queue = receiver.toQueueObject();
    const non_block = args.len == 2 and args[1].isTruthy();
    const timeout = try timeoutFromKeyword(vm, keyword_timeout);

    if (non_block and timeout != null) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "can't set a timeout if non_block is enabled", .{});
    }
    if (queue.closed) {
        return vm.raiseExceptionFmt(vm.closed_queue_error_class, "queue closed", .{});
    }
    if (queueHasCapacity(queue)) {
        queue.items.append(vm.gc_allocator, args[0]) catch return error.Fatal;
        try wakeNextDequeueWaiter(vm, queue);
        return receiver;
    }
    if (non_block) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "queue full", .{});
    }
    if (timeout) |seconds| {
        if (seconds <= 0) return Value.nil();
    }

    return waitForQueue(vm, receiver, queue, .enqueue, args[0], timeout);
}

fn builtinSizedQueueMax(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const queue = receiver.toQueueObject();
    return Value.integer(@intCast(queue.max_size orelse 0));
}

fn builtinSizedQueueMaxSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const queue = receiver.toQueueObject();
    queue.max_size = try sizedQueueCapacity(vm, args[0]);
    try wakeAllEnqueueWaiters(vm, queue);
    return receiver;
}

fn builtinQueuePop(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    var keyword_timeout: ?Value = null;
    try vm.consumeKeywordArgs(.{"timeout"}, .{&keyword_timeout});
    try vm.validateKeywordArgsConsumed();

    const queue = receiver.toQueueObject();
    const non_block = args.len == 1 and args[0].isTruthy();
    const timeout = try timeoutFromKeyword(vm, keyword_timeout);

    if (non_block and timeout != null) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "can't set a timeout if non_block is enabled", .{});
    }

    if (dequeueAvailable(queue)) |item| {
        if (queue.max_size != null) try wakeNextEnqueueWaiter(vm, queue);
        return item;
    }

    if (queue.closed) {
        if (non_block) return vm.raiseExceptionFmt(vm.thread_error_class, "queue empty", .{});
        return Value.nil();
    }

    if (non_block) {
        return vm.raiseExceptionFmt(vm.thread_error_class, "queue empty", .{});
    }

    if (timeout) |seconds| {
        if (seconds <= 0) return Value.nil();
    }

    return waitForQueue(vm, receiver, queue, .dequeue, Value.nil(), timeout);
}

fn builtinQueueSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const queue = receiver.toQueueObject();
    return Value.integer(@intCast(queue.items.items.len - queue.read_index));
}

fn builtinQueueEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const queue = receiver.toQueueObject();
    return Value.boolean(queue.items.items.len == queue.read_index);
}

fn builtinQueueClose(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const queue = receiver.toQueueObject();
    queue.closed = true;
    try wakeAllDequeueWaiters(vm, queue);
    try wakeAllEnqueueWaiters(vm, queue);
    return receiver;
}

fn builtinQueueClosed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toQueueObject().closed);
}

fn builtinQueueNumWaiting(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(countWaiting(receiver.toQueueObject())));
}

fn sizedQueueCapacity(vm: *VM, raw: Value) VMError!usize {
    const max_i64 = try raw.coerceToI64ViaToInt(
        vm,
        "can't convert into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long long'",
    );
    if (max_i64 <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "queue size must be positive", .{});
    }
    return @intCast(max_i64);
}

fn timeoutFromKeyword(vm: *VM, timeout: ?Value) VMError!?f64 {
    const raw = timeout orelse return null;
    if (raw.isNil()) return null;
    if (raw.isInteger()) return raw.integerToF64();
    if (raw.isFloat()) return raw.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into Float", .{timeoutTypeName(raw)});
}

fn timeoutTypeName(raw: Value) []const u8 {
    if (raw.isString()) return "String";
    if (raw.isTrue()) return "true";
    if (raw.isFalse()) return "false";
    if (raw.isNil()) return "nil";
    return "object";
}

fn dequeueAvailable(queue: *value.QueueObject) ?Value {
    if (queue.read_index >= queue.items.items.len) return null;
    const item = queue.items.items[queue.read_index];
    queue.read_index += 1;
    if (queue.read_index == queue.items.items.len) {
        queue.items.clearRetainingCapacity();
        queue.read_index = 0;
    }
    return item;
}

fn resetQueue(queue: *value.QueueObject) void {
    queue.items.clearRetainingCapacity();
    queue.read_index = 0;
    clearWaiters(&queue.dequeue_waiters);
    clearWaiters(&queue.enqueue_waiters);
    queue.closed = false;
}

fn queueLength(queue: *value.QueueObject) usize {
    return queue.items.items.len - queue.read_index;
}

fn queueHasCapacity(queue: *value.QueueObject) bool {
    const max_size = queue.max_size orelse return true;
    return queueLength(queue) < max_size;
}

const Waiters = synchronization.Waiters;
const removeWaiterIfPresent = synchronization.removeWaiterIfPresent;
const clearWaiters = synchronization.clearWaiters;
const addThreadWaiter = synchronization.addThreadWaiter;
const waiterIsLive = synchronization.waiterIsLive;
const blockFiberOnQueue = synchronization.blockFiber;

fn wakeNextDequeueWaiter(vm: *VM, queue: *value.QueueObject) VMError!void {
    try synchronization.wakeNextWaiter(vm, Value.fromObject(&queue.object), &queue.dequeue_waiters);
}

fn wakeAllDequeueWaiters(vm: *VM, queue: *value.QueueObject) VMError!void {
    try synchronization.wakeAllWaiters(vm, Value.fromObject(&queue.object), &queue.dequeue_waiters);
}

fn wakeNextEnqueueWaiter(vm: *VM, queue: *value.QueueObject) VMError!void {
    try synchronization.wakeNextWaiter(vm, Value.fromObject(&queue.object), &queue.enqueue_waiters);
}

fn wakeAllEnqueueWaiters(vm: *VM, queue: *value.QueueObject) VMError!void {
    try synchronization.wakeAllWaiters(vm, Value.fromObject(&queue.object), &queue.enqueue_waiters);
}

fn countWaiting(queue: *value.QueueObject) usize {
    var count: usize = 0;
    for ([_][]*value.SynchronizationWaiter{ queue.dequeue_waiters.items, queue.enqueue_waiters.items }) |waiters| {
        for (waiters) |waiter| {
            switch (waiter.*) {
                .thread => |thread| if (thread.state == .sleeping or thread.waiting_on_queue) {
                    count += 1;
                },
                .fiber => if (waiterIsLive(waiter)) {
                    count += 1;
                },
            }
        }
    }
    return count;
}

fn blockThreadOnQueue(vm: *VM, waiters: *Waiters, timeout: ?f64) VMError!void {
    try vm.deliverThreadInterrupt(true);
    const thread = vm.current_thread orelse return error.Fatal;
    const waiter = try addThreadWaiter(vm, waiters, thread);
    defer removeWaiterIfPresent(waiters, waiter);
    const was_deadlockable = thread.deadlockable_wait;
    thread.deadlockable_wait = timeout == null;
    thread.waiting_on_queue = true;
    defer {
        thread.deadlockable_wait = was_deadlockable;
        thread.waiting_on_queue = false;
        if (thread.state != .terminated) thread.state = .running;
    }
    if (timeout) |seconds| {
        // Short sleeps bound the native deadline conversion for very large
        // timeouts. The caller retains the absolute deadline across wakeups.
        try vm.timedSleepCurrentThread(@intFromFloat(@ceil(@min(seconds * 1000, 100))));
    } else {
        thread.state = .sleeping;
        while (thread.state == .sleeping) try vm.threadYield();
    }
}

fn waitForQueue(vm: *VM, receiver: Value, queue: *value.QueueObject, mode: enum { enqueue, dequeue }, item: Value, timeout: ?f64) VMError!Value {
    const scheduler = vm.currentFiberScheduler();
    const deadline: ?f64 = if (timeout) |seconds| @as(f64, @floatFromInt(vm_mod.monotonicMilliseconds())) + seconds * 1000 else null;
    while (true) {
        if (mode == .dequeue) {
            if (dequeueAvailable(queue)) |available| {
                if (queue.max_size != null) try wakeNextEnqueueWaiter(vm, queue);
                return available;
            }
            if (queue.closed) return Value.nil();
        } else {
            if (queue.closed) return vm.raiseExceptionFmt(vm.closed_queue_error_class, "queue closed", .{});
            if (queueHasCapacity(queue)) {
                queue.items.append(vm.gc_allocator, item) catch return error.Fatal;
                try wakeNextDequeueWaiter(vm, queue);
                return receiver;
            }
        }
        const remaining: ?f64 = if (deadline) |end| (end - @as(f64, @floatFromInt(vm_mod.monotonicMilliseconds()))) / 1000 else null;
        if (remaining) |seconds| {
            if (seconds <= 0) return Value.nil();
        }
        const waiters = if (mode == .enqueue) &queue.enqueue_waiters else &queue.dequeue_waiters;
        if (scheduler) |fiber_scheduler| {
            try blockFiberOnQueue(vm, receiver, waiters, fiber_scheduler, remaining);
        } else {
            try blockThreadOnQueue(vm, waiters, remaining);
        }
        if (mode == .enqueue) {
            if (deadline) |end| {
                if (@as(f64, @floatFromInt(vm_mod.monotonicMilliseconds())) >= end) return Value.nil();
            }
        }
    }
}
