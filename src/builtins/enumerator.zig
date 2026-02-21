const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    // Enumerator singleton methods (class methods)
    const enum_class_val = Value{ .data = .{ .class = vm.enumerator_class } };
    const enum_singleton = try vm.getOrCreateSingletonClass(enum_class_val);

    const new_sym = try vm.intern("new");
    try enum_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinEnumeratorNew } });

    // Enumerator instance methods
    const each_sym = try vm.intern("each");
    try vm.enumerator_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinEnumeratorEach } });

    const next_sym = try vm.intern("next");
    try vm.enumerator_class.module.methods.put(next_sym, .{ .method = .{ .builtin = &builtinEnumeratorNext } });

    const peek_sym = try vm.intern("peek");
    try vm.enumerator_class.module.methods.put(peek_sym, .{ .method = .{ .builtin = &builtinEnumeratorPeek } });

    const rewind_sym = try vm.intern("rewind");
    try vm.enumerator_class.module.methods.put(rewind_sym, .{ .method = .{ .builtin = &builtinEnumeratorRewind } });

    const inspect_sym = try vm.intern("inspect");
    try vm.enumerator_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinEnumeratorInspect } });

    const size_sym = try vm.intern("size");
    try vm.enumerator_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinEnumeratorSize } });

    // Yielder instance methods
    const yield_push_sym = try vm.intern("<<");
    try vm.yielder_class.module.methods.put(yield_push_sym, .{ .method = .{ .builtin = &builtinYielderPush } });

    const yield_sym = try vm.intern("yield");
    try vm.yielder_class.module.methods.put(yield_sym, .{ .method = .{ .builtin = &builtinYielderYield } });
}

// --- Enumerator class methods ---

fn builtinEnumeratorNew(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(vm.argument_error_class, "no block given");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    // Wrap the block as a ProcObject
    const proc_val = try vm.newProc(blk);
    return vm.newEnumerator(.{ .generator = .{ .proc = proc_val.data.proc } }, null, null);
}

// --- Enumerator instance methods ---

fn builtinEnumeratorEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;

    const blk = block orelse {
        // No block: return self
        return receiver;
    };

    switch (enum_obj.kind) {
        .method => |m| {
            // Method-based: call receiver.method_name(args, &blk)
            var call_args_buf: [256]Value = undefined;
            var call_argc: usize = 0;
            if (enum_obj.method_args) |method_args| {
                for (method_args.elements.items) |arg| {
                    call_args_buf[call_argc] = arg;
                    call_argc += 1;
                }
            }
            return vm.callMethodByName(m.receiver, m.method_name.name, call_args_buf[0..call_argc], blk);
        },
        .generator => |g| {
            // Generator-based: create Yielder wrapping the user's block, call proc(yielder)
            const yielder_val = try vm.newYielder(blk);
            var proc_args = [_]Value{yielder_val};
            return vm.callProcObject(g.proc, &proc_args, null, null);
        },
    }
}

fn builtinEnumeratorNext(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;

    // If we have a lookahead value from peek, consume it
    if (enum_obj.has_lookahead) {
        const val = enum_obj.lookahead;
        enum_obj.has_lookahead = false;
        enum_obj.lookahead = Value.nil();
        return val;
    }

    // Ensure we have a fiber for external iteration
    const fiber = try ensureEnumeratorFiber(vm, enum_obj);

    // If fiber is terminated, raise StopIteration
    if (fiber.state == .terminated) {
        return raiseStopIteration(vm);
    }

    // On first resume, pass the enumerator as arg so the fiber body can access it
    // On subsequent resumes, the fiber is already running and just resumes from yield
    var resume_args: [1]Value = .{Value{ .data = .{ .enumerator = enum_obj } }};
    const result = try vm.resumeFiber(
        fiber,
        if (fiber.state == .created) resume_args[0..1] else &[_]Value{},
        Value.nil(),
    );

    // If fiber terminated after resuming (returned rather than yielded), iteration is done
    if (fiber.state == .terminated) {
        return raiseStopIteration(vm);
    }

    return result;
}

fn builtinEnumeratorPeek(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;

    if (enum_obj.has_lookahead) {
        return enum_obj.lookahead;
    }

    // Call next - if StopIteration, let it propagate
    const val = try builtinEnumeratorNext(vm, receiver, args, null);
    enum_obj.lookahead = val;
    enum_obj.has_lookahead = true;
    return val;
}

fn builtinEnumeratorRewind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;
    enum_obj.fiber = null;
    enum_obj.has_lookahead = false;
    enum_obj.lookahead = Value.nil();
    return receiver;
}

fn builtinEnumeratorInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;

    switch (enum_obj.kind) {
        .method => |m| {
            const class_name = vm.getClass(m.receiver).module.name.name;
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "#<Enumerator: {s}:{s}>",
                .{ class_name, m.method_name.name },
            ) catch return error.Fatal;
            return try vm.newString(msg, false);
        },
        .generator => {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "#<Enumerator:0x{x}>",
                .{@intFromPtr(enum_obj)},
            ) catch return error.Fatal;
            return try vm.newString(msg, false);
        },
    }
}

fn builtinEnumeratorSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.data.enumerator;

    if (enum_obj.size_proc) |size_proc| {
        return vm.callProcObject(size_proc, &[_]Value{}, null, null);
    }

    return Value.nil();
}

// --- Yielder instance methods ---

fn builtinYielderPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const yielder_obj = receiver.data.yielder;

    const yield_args = [_]Value{args[0]};
    _ = try vm.yieldToBlock(yielder_obj.block, &yield_args);

    // Return self for chaining (y << 1 << 2 << 3)
    return receiver;
}

fn builtinYielderYield(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const yielder_obj = receiver.data.yielder;
    const result = try vm.yieldToBlock(yielder_obj.block, args);
    return result.value;
}

// --- Helper functions ---

fn ensureEnumeratorFiber(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.FiberObject {
    if (enum_obj.fiber) |fiber| {
        if (fiber.state != .terminated) {
            return fiber;
        }
    }

    // Create a new fiber with a builtin block that calls enum.each { |v| Fiber.yield(v) }
    const fiber_block = Block{ .kind = .{ .builtin = &enumeratorFiberBody } };
    const fiber_val = try vm.newFiber(vm.fiber_class, fiber_block);
    const fiber = fiber_val.data.fiber;

    enum_obj.fiber = fiber;
    return fiber;
}

fn enumeratorFiberBody(vm: *VM, args: []Value) VMError!Value {
    // args[0] is the enumerator value passed as first resume arg
    const enum_val = if (args.len > 0) args[0] else return error.Fatal;
    const enum_obj = enum_val.data.enumerator;

    // Create a block that fiber-yields each value
    const yield_block = Block{ .kind = .{ .builtin = &enumeratorFiberYieldBlock } };

    switch (enum_obj.kind) {
        .method => |m| {
            var call_args_buf: [256]Value = undefined;
            var call_argc: usize = 0;
            if (enum_obj.method_args) |method_args| {
                for (method_args.elements.items) |arg| {
                    call_args_buf[call_argc] = arg;
                    call_argc += 1;
                }
            }
            return vm.callMethodByName(m.receiver, m.method_name.name, call_args_buf[0..call_argc], yield_block);
        },
        .generator => |g| {
            // Create a yielder that fiber-yields
            const yielder_val = try vm.newYielder(yield_block);
            var proc_args = [_]Value{yielder_val};
            return vm.callProcObject(g.proc, &proc_args, null, null);
        },
    }
}

fn enumeratorFiberYieldBlock(vm: *VM, args: []Value) VMError!Value {
    const yield_value = switch (args.len) {
        0 => Value.nil(),
        1 => args[0],
        else => blk: {
            const arr = try vm.createArray();
            for (args) |arg| {
                arr.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
            }
            break :blk Value{ .data = .{ .array = arr } };
        },
    };
    return vm.fiberYield(yield_value);
}

fn raiseStopIteration(vm: *VM) VMError!Value {
    const exc = try vm.createException(vm.stop_iteration_class, "StopIteration");
    vm.pending_exception = exc;
    return error.Unwind;
}
