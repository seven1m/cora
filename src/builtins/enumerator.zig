const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const integer_builtin = @import("integer.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    // Enumerator singleton methods (class methods)
    const enum_class_val = Value.fromObject(vm.enumerator_class);
    const enum_singleton = try vm.getOrCreateSingletonClass(enum_class_val);

    const new_sym = try vm.intern("new");
    try enum_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinEnumeratorNew } });

    // Enumerator instance methods
    const each_sym = try vm.intern("each");
    try vm.enumerator_class.module.methods.put(each_sym, .{ .method = .{ .builtin = &builtinEnumeratorEach } });

    const map_sym = try vm.intern("map");
    try vm.enumerator_class.module.methods.put(map_sym, .{ .method = .{ .builtin = &builtinEnumeratorMap } });

    const to_a_sym = try vm.intern("to_a");
    try vm.enumerator_class.module.methods.put(to_a_sym, .{ .method = .{ .builtin = &builtinEnumeratorToA } });

    const next_sym = try vm.intern("next");
    try vm.enumerator_class.module.methods.put(next_sym, .{ .method = .{ .builtin = &builtinEnumeratorNext } });

    const next_values_sym = try vm.intern("next_values");
    try vm.enumerator_class.module.methods.put(next_values_sym, .{ .method = .{ .builtin = &builtinEnumeratorNextValues } });

    const peek_sym = try vm.intern("peek");
    try vm.enumerator_class.module.methods.put(peek_sym, .{ .method = .{ .builtin = &builtinEnumeratorPeek } });

    const peek_values_sym = try vm.intern("peek_values");
    try vm.enumerator_class.module.methods.put(peek_values_sym, .{ .method = .{ .builtin = &builtinEnumeratorPeekValues } });

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
    return vm.newEnumerator(.{ .generator = .{ .proc = proc_val.toProcObject() } }, null, null);
}

// --- Enumerator instance methods ---

fn builtinEnumeratorEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const enum_obj = receiver.toEnumeratorObject();

    const blk = block orelse {
        if (args.len == 0) {
            return receiver;
        }

        switch (enum_obj.kind) {
            .method => |_| {
                var merged_args = try vm.createArray();
                if (enum_obj.method_args) |method_args| {
                    for (method_args.elements.items) |arg| {
                        merged_args.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
                    }
                }
                for (args) |arg| {
                    merged_args.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
                }
                return vm.newEnumerator(enum_obj.kind, merged_args, enum_obj.size);
            },
            .generator => {
                return vm.newEnumerator(enum_obj.kind, null, enum_obj.size);
            },
        }
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
            for (args) |arg| {
                call_args_buf[call_argc] = arg;
                call_argc += 1;
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
    const enum_obj = receiver.toEnumeratorObject();

    const yield_values = try takeNextYieldValues(vm, enum_obj);
    return collapseYieldValues(yield_values);
}

fn builtinEnumeratorNextValues(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();
    const yield_values = try takeNextYieldValues(vm, enum_obj);
    return Value.fromObject(yield_values);
}

fn builtinEnumeratorPeek(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();
    const yield_values = try peekNextYieldValues(vm, enum_obj);
    return collapseYieldValues(yield_values);
}

fn builtinEnumeratorPeekValues(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();
    const yield_values = try peekNextYieldValues(vm, enum_obj);
    return Value.fromObject(yield_values);
}

fn builtinEnumeratorRewind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();
    enum_obj.fiber = null;
    enum_obj.has_lookahead_values = false;
    enum_obj.lookahead_values = null;
    return receiver;
}

fn builtinEnumeratorInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();

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
    const enum_obj = receiver.toEnumeratorObject();

    if (enum_obj.size) |size| {
        if (size.isProc()) {
            return vm.callProcObject(size.toProcObject(), &[_]Value{}, null, null);
        }
        return size;
    }

    switch (enum_obj.kind) {
        .method => |m| {
            if ((m.receiver.isInteger() or m.receiver.isBigInteger()) and std.mem.eql(u8, m.method_name.name, "upto")) {
                const method_args = enum_obj.method_args orelse return Value.nil();
                if (method_args.elements.items.len != 1) return Value.nil();

                const start = try m.receiver.integerToI64(vm, "integer is too large to iterate");
                const stop = try integer_builtin.uptoStopToI64(vm, method_args.elements.items[0]);
                if (start > stop) return Value.integer(0);
                return Value.integer(stop - start + 1);
            }
            if ((m.receiver.isInteger() or m.receiver.isBigInteger()) and std.mem.eql(u8, m.method_name.name, "downto")) {
                const method_args = enum_obj.method_args orelse return Value.nil();
                if (method_args.elements.items.len != 1) return Value.nil();

                const start = try m.receiver.integerToI64(vm, "integer is too large to iterate");
                const stop = try integer_builtin.downtoStopToI64(vm, method_args.elements.items[0]);
                if (start < stop) return Value.integer(0);
                return Value.integer(start - stop + 1);
            }
        },
        .generator => {},
    }

    return Value.nil();
}

fn builtinEnumeratorToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const out = try vm.createArray();

    while (true) {
        const next_val = builtinEnumeratorNext(vm, receiver, &[_]Value{}, null) catch |err| {
            if (err == error.Unwind and vm.pending_exception != null and vm.pending_exception.?.object.class == vm.stop_iteration_class) {
                vm.pending_exception = null;
                break;
            }
            return err;
        };
        out.elements.append(vm.gc_allocator, next_val) catch return error.Fatal;
    }

    return Value.fromObject(out);
}

fn builtinEnumeratorMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        return vm.createMethodEnumerator(receiver, try vm.intern("map"), &.{});
    };

    const out = try vm.createArray();
    while (true) {
        const next_val = builtinEnumeratorNext(vm, receiver, &[_]Value{}, null) catch |err| {
            if (err == error.Unwind and vm.pending_exception != null and vm.pending_exception.?.object.class == vm.stop_iteration_class) {
                vm.pending_exception = null;
                break;
            }
            return err;
        };

        const mapped = try vm.yieldToBlock(blk, &[_]Value{next_val});
        if (mapped.break_occurred) return mapped.value;
        out.elements.append(vm.gc_allocator, mapped.value) catch return error.Fatal;
    }

    return Value.fromObject(out);
}

// --- Yielder instance methods ---

fn builtinYielderPush(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const yielder_obj = receiver.toYielderObject();

    const yield_args = [_]Value{args[0]};
    _ = try vm.yieldToBlock(yielder_obj.block, &yield_args);

    // Return self for chaining (y << 1 << 2 << 3)
    return receiver;
}

fn builtinYielderYield(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const yielder_obj = receiver.toYielderObject();
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
    const fiber = fiber_val.toFiberObject();

    enum_obj.fiber = fiber;
    return fiber;
}

fn enumeratorFiberBody(vm: *VM, args: []Value) VMError!Value {
    // args[0] is the enumerator value passed as first resume arg
    const enum_val = if (args.len > 0) args[0] else return error.Fatal;
    const enum_obj = enum_val.toEnumeratorObject();

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
    const arr = try vm.createArray();
    for (args) |arg| {
        arr.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    }
    return vm.fiberYield(Value.fromObject(arr));
}

fn raiseStopIteration(vm: *VM) VMError {
    const exc = try vm.createException(vm.stop_iteration_class, "StopIteration");
    vm.pending_exception = exc;
    return error.Unwind;
}

fn collapseYieldValues(yield_values: *value.ArrayObject) Value {
    return switch (yield_values.elements.items.len) {
        0 => Value.nil(),
        1 => yield_values.elements.items[0],
        else => Value.fromObject(yield_values),
    };
}

fn fetchNextYieldValues(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.ArrayObject {
    // Ensure we have a fiber for external iteration
    const fiber = try ensureEnumeratorFiber(vm, enum_obj);

    if (fiber.state == .terminated) {
        return raiseStopIteration(vm);
    }

    var resume_args: [1]Value = .{Value.fromObject(enum_obj)};
    const result = try vm.resumeFiber(
        fiber,
        if (fiber.state == .created) resume_args[0..1] else &[_]Value{},
        Value.nil(),
    );

    if (fiber.state == .terminated) {
        return raiseStopIteration(vm);
    }
    if (!result.isArray()) return error.Fatal;
    return result.toArrayObject();
}

fn takeNextYieldValues(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.ArrayObject {
    if (enum_obj.has_lookahead_values) {
        const val = enum_obj.lookahead_values orelse return error.Fatal;
        enum_obj.has_lookahead_values = false;
        enum_obj.lookahead_values = null;
        return val;
    }
    return fetchNextYieldValues(vm, enum_obj);
}

fn peekNextYieldValues(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.ArrayObject {
    if (enum_obj.has_lookahead_values) {
        return enum_obj.lookahead_values orelse return error.Fatal;
    }
    const val = try fetchNextYieldValues(vm, enum_obj);
    enum_obj.lookahead_values = val;
    enum_obj.has_lookahead_values = true;
    return val;
}
