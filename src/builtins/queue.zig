const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const queue_class_val = Value.fromObject(vm.queue_class);
    const queue_singleton = try vm.getOrCreateSingletonClass(queue_class_val);

    const new_sym = try vm.intern("new");
    try queue_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinQueueNew, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.queue_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinQueueInitialize, .{ .variadic = 0 }, .private));

    const append_sym = try vm.intern("<<");
    try vm.queue_class.module.methods.put(append_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const push_sym = try vm.intern("push");
    try vm.queue_class.module.methods.put(push_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const enq_sym = try vm.intern("enq");
    try vm.queue_class.module.methods.put(enq_sym, value.MethodEntry.builtin(&builtinQueuePush, .{ .exact = 1 }));

    const pop_sym = try vm.intern("pop");
    try vm.queue_class.module.methods.put(pop_sym, value.MethodEntry.builtin(&builtinQueuePop, .{ .variadic = 0 }));

    const deq_sym = try vm.intern("deq");
    try vm.queue_class.module.methods.put(deq_sym, value.MethodEntry.builtin(&builtinQueuePop, .{ .variadic = 0 }));

    const shift_sym = try vm.intern("shift");
    try vm.queue_class.module.methods.put(shift_sym, value.MethodEntry.builtin(&builtinQueuePop, .{ .variadic = 0 }));

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
}

fn builtinQueueNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }
    const queue_obj = try vm.newQueue(receiver);
    const queue_val = Value.fromObject(queue_obj);
    _ = try vm.callMethodByNameForwardingKeywords(queue_val, "initialize", args, block);
    return queue_val;
}

fn builtinQueueInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    _ = try vm.ensureMainThread();

    const queue = receiver.toQueueObject();
    queue.items.clearRetainingCapacity();
    queue.read_index = 0;
    queue.closed = false;

    if (args.len == 0) return receiver;

    const source = if (args[0].isArray()) args[0] else blk: {
        const coerced = try vm.checkCallMethodByName(args[0], "to_a", false, &[_]Value{}, null) orelse {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Array", .{vm.className(args[0])});
        };
        if (!coerced.isArray()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} to Array ({s}#to_a gives {s})",
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
    _ = try vm.ensureMainThread();

    const queue = receiver.toQueueObject();
    if (queue.closed) {
        return vm.raiseExceptionFmt(vm.closed_queue_error_class, "queue closed", .{});
    }

    queue.items.append(vm.gc_allocator, args[0]) catch return error.Fatal;
    wakeNextWaiter(queue);
    return receiver;
}

fn builtinQueuePop(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    _ = try vm.ensureMainThread();

    var keyword_timeout: ?Value = null;
    try vm.consumeKeywordArgs(.{"timeout"}, .{&keyword_timeout});
    try vm.validateKeywordArgsConsumed();

    const queue = receiver.toQueueObject();
    const non_block = args.len == 1 and args[0].is_truthy();
    const timeout = try timeoutFromKeyword(vm, keyword_timeout);

    if (non_block and timeout != null) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "can't set a timeout if non_block is enabled", .{});
    }

    if (dequeueAvailable(queue)) |item| {
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

    const current_thread = vm.current_thread orelse {
        while (true) {
            try vm.threadYield();
            if (dequeueAvailable(queue)) |item| return item;
            if (queue.closed) return Value.nil();
        }
    };

    addWaiter(queue, current_thread);
    defer removeWaiter(queue, current_thread);

    current_thread.state = .sleeping;
    defer {
        if (current_thread.state != .terminated) current_thread.state = .running;
    }

    if (timeout) |seconds| {
        var spin_budget: u32 = @intFromFloat(@min(seconds * 1000.0, 1000.0));
        if (spin_budget == 0) spin_budget = 1;
        while (spin_budget > 0) : (spin_budget -= 1) {
            try vm.schedulerYield();
            if (dequeueAvailable(queue)) |item| return item;
            if (queue.closed) return Value.nil();
        }
        return Value.nil();
    }

    while (true) {
        try vm.threadYield();
        if (dequeueAvailable(queue)) |item| return item;
        if (queue.closed) return Value.nil();
    }
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
    wakeAllWaiters(queue);
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

fn timeoutFromKeyword(vm: *VM, timeout: ?Value) VMError!?f64 {
    const raw = timeout orelse return null;
    if (raw.isNil()) return null;
    if (raw.isInteger()) return raw.integerToF64();
    if (raw.isFloat()) return raw.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion to float from {s}", .{timeoutTypeName(raw)});
}

fn timeoutTypeName(raw: Value) []const u8 {
    if (raw.isString()) return "string";
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

fn addWaiter(queue: *value.QueueObject, thread: *value.ThreadObject) void {
    for (queue.waiters.items) |waiter| {
        if (waiter == thread) return;
    }
    queue.waiters.append(thread.owner_vm.gc_allocator, thread) catch {};
}

fn removeWaiter(queue: *value.QueueObject, thread: *value.ThreadObject) void {
    var i: usize = 0;
    while (i < queue.waiters.items.len) {
        if (queue.waiters.items[i] == thread) {
            _ = queue.waiters.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn wakeNextWaiter(queue: *value.QueueObject) void {
    while (queue.waiters.items.len > 0) {
        const waiter = queue.waiters.orderedRemove(0);
        if (waiter.state == .terminated) {
            continue;
        }
        waiter.state = .running;
        return;
    }
}

fn wakeAllWaiters(queue: *value.QueueObject) void {
    for (queue.waiters.items) |waiter| {
        if (waiter.state != .terminated) {
            waiter.state = .running;
        }
    }
    queue.waiters.clearRetainingCapacity();
}

fn countWaiting(queue: *value.QueueObject) usize {
    var count: usize = 0;
    for (queue.waiters.items) |waiter| {
        if (waiter.state == .sleeping) count += 1;
    }
    return count;
}
