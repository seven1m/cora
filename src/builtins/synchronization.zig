const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub const Waiters = std.ArrayList(*value.SynchronizationWaiter);

fn removeWaiter(waiters: *Waiters, index: usize) *value.SynchronizationWaiter {
    const waiter = waiters.orderedRemove(index);
    @memset(std.mem.asBytes(&waiters.unusedCapacitySlice()[0]), 0);
    return waiter;
}

pub fn removeWaiterIfPresent(waiters: *Waiters, waiter: *value.SynchronizationWaiter) void {
    for (waiters.items, 0..) |entry, index| {
        if (entry == waiter) {
            _ = removeWaiter(waiters, index);
            return;
        }
    }
}

pub fn clearWaiters(waiters: *Waiters) void {
    @memset(std.mem.sliceAsBytes(waiters.items), 0);
    waiters.clearRetainingCapacity();
}

pub fn addThreadWaiter(vm: *VM, waiters: *Waiters, thread: *value.ThreadObject) VMError!*value.SynchronizationWaiter {
    const waiter = vm.gc_allocator.create(value.SynchronizationWaiter) catch return error.Fatal;
    waiter.* = .{ .thread = thread };
    waiters.append(vm.gc_allocator, waiter) catch return error.Fatal;
    return waiter;
}

pub fn waiterIsLive(waiter: *value.SynchronizationWaiter) bool {
    return switch (waiter.*) {
        .thread => |thread| thread.state != .terminated,
        .fiber => |fiber_waiter| fiber_waiter.thread.state != .terminated and fiber_waiter.fiber.state != .terminated,
    };
}

fn wakeWaiter(vm: *VM, blocker: Value, waiter: *value.SynchronizationWaiter) VMError!void {
    switch (waiter.*) {
        .thread => |thread| {
            thread.state = .running;
            vm.addRunnableThreadIfAbsent(thread);
        },
        .fiber => |fiber_waiter| try vm.notifyFiberSchedulerWaiter(fiber_waiter, blocker),
    }
}

pub fn wakeNextWaiter(vm: *VM, blocker: Value, waiters: *Waiters) VMError!void {
    while (waiters.items.len > 0) {
        const waiter = removeWaiter(waiters, 0);
        if (!waiterIsLive(waiter)) continue;
        try wakeWaiter(vm, blocker, waiter);
        return;
    }
}

pub fn wakeAllWaiters(vm: *VM, blocker: Value, waiters: *Waiters) VMError!void {
    // Unblock callbacks can yield, cancel waits, or register new waits. Only
    // notify the registrations that existed when this wakeup began.
    const snapshot = vm.gc_allocator.dupe(*value.SynchronizationWaiter, waiters.items) catch return error.Fatal;
    for (snapshot) |waiter| {
        for (waiters.items, 0..) |entry, index| {
            if (entry == waiter) {
                _ = removeWaiter(waiters, index);
                if (waiterIsLive(waiter)) try wakeWaiter(vm, blocker, waiter);
                break;
            }
        }
    }
}

pub fn blockFiber(vm: *VM, receiver: Value, waiters: *Waiters, scheduler: Value, timeout: ?f64) VMError!void {
    try vm.deliverThreadInterrupt(true);
    const fiber_waiter = vm.gc_allocator.create(value.FiberSchedulerWaiter) catch return error.Fatal;
    fiber_waiter.* = .{ .thread = vm.current_thread orelse return error.Fatal, .fiber = vm.current_fiber, .scheduler = scheduler };
    const waiter = vm.gc_allocator.create(value.SynchronizationWaiter) catch return error.Fatal;
    waiter.* = .{ .fiber = fiber_waiter };
    waiters.append(vm.gc_allocator, waiter) catch return error.Fatal;
    defer removeWaiterIfPresent(waiters, waiter);
    var args = [_]Value{ receiver, if (timeout) |seconds| try vm.newFloat(seconds) else Value.nil() };
    _ = try vm.callMethodByName(scheduler, "block", &args, null);
    try vm.deliverThreadInterrupt(true);
}
