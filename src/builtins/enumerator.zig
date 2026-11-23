const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const class_builtin = @import("class.zig");
const kernel_builtin = @import("kernel.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodEntry = value.MethodEntry;

pub fn register(vm: *VM) !void {
    // Enumerator singleton methods (class methods)
    const enum_class_val = Value.fromObject(&vm.enumerator_class.module.object);
    const enum_singleton = try vm.getOrCreateSingletonClass(enum_class_val);

    const new_sym = try vm.intern("new");
    try enum_singleton.module.methods.put(new_sym, MethodEntry.builtin(&builtinEnumeratorNew, .{ .variadic = 0 }));

    // Enumerator instance methods
    const each_sym = try vm.intern("each");
    try vm.enumerator_class.module.methods.put(each_sym, MethodEntry.builtin(&builtinEnumeratorEach, .{ .variadic = 0 }));

    const each_with_index_sym = try vm.intern("each_with_index");
    try vm.enumerator_class.module.methods.put(each_with_index_sym, MethodEntry.builtin(&builtinEnumeratorEachWithIndex, .{ .exact = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.enumerator_class.module.methods.put(to_a_sym, MethodEntry.builtin(&builtinEnumeratorToA, .{ .variadic = 0 }));

    const next_sym = try vm.intern("next");
    try vm.enumerator_class.module.methods.put(next_sym, MethodEntry.builtin(&builtinEnumeratorNext, .{ .exact = 0 }));

    const next_values_sym = try vm.intern("next_values");
    try vm.enumerator_class.module.methods.put(next_values_sym, MethodEntry.builtin(&builtinEnumeratorNextValues, .{ .exact = 0 }));

    const peek_sym = try vm.intern("peek");
    try vm.enumerator_class.module.methods.put(peek_sym, MethodEntry.builtin(&builtinEnumeratorPeek, .{ .exact = 0 }));

    const peek_values_sym = try vm.intern("peek_values");
    try vm.enumerator_class.module.methods.put(peek_values_sym, MethodEntry.builtin(&builtinEnumeratorPeekValues, .{ .exact = 0 }));

    const rewind_sym = try vm.intern("rewind");
    try vm.enumerator_class.module.methods.put(rewind_sym, MethodEntry.builtin(&builtinEnumeratorRewind, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.enumerator_class.module.methods.put(inspect_sym, MethodEntry.builtin(&builtinEnumeratorInspect, .{ .exact = 0 }));
    try vm.enumerator_arithmetic_sequence_class.module.methods.put(inspect_sym, MethodEntry.builtin(&builtinArithmeticSequenceInspect, .{ .exact = 0 }));
    try vm.enumerator_arithmetic_sequence_class.module.methods.put(try vm.intern("begin"), MethodEntry.builtin(&builtinArithmeticSequenceBegin, .{ .exact = 0 }));
    try vm.enumerator_arithmetic_sequence_class.module.methods.put(try vm.intern("end"), MethodEntry.builtin(&builtinArithmeticSequenceEnd, .{ .exact = 0 }));
    try vm.enumerator_arithmetic_sequence_class.module.methods.put(try vm.intern("step"), MethodEntry.builtin(&builtinArithmeticSequenceStep, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.enumerator_class.module.methods.put(size_sym, MethodEntry.builtin(&builtinEnumeratorSize, .{ .exact = 0 }));

    const with_index_sym = try vm.intern("with_index");
    try vm.enumerator_class.module.methods.put(with_index_sym, MethodEntry.builtin(&builtinEnumeratorWithIndex, .{ .variadic = 0 }));

    const enumerable_sym = try vm.intern("Enumerable");
    const enumerable = vm.object_class.module.constants.get(enumerable_sym) orelse return error.Fatal;
    const each_with_object_sym = try vm.intern("each_with_object");
    const each_with_object_entry = enumerable.value.toModuleObject().methods.get(each_with_object_sym) orelse return error.Fatal;
    try vm.enumerator_class.module.methods.put(each_with_object_sym, each_with_object_entry);
    const with_object_sym = try vm.intern("with_object");
    try vm.enumerator_class.module.methods.put(with_object_sym, each_with_object_entry);

    vm.enumerator_chain_class.builtin_alloc_func = &builtinChainAllocate;
    const chain_singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.enumerator_chain_class.module.object));
    try chain_singleton.module.methods.put(new_sym, MethodEntry.keywordBuiltin(&class_builtin.builtinClassNew, .{ .variadic = 0 }));
    try vm.enumerator_chain_class.module.methods.put(try vm.intern("initialize"), MethodEntry.builtinWithVisibility(&builtinChainInitialize, .{ .variadic = 0 }, .private));

    const product_value = try vm.newClass(try vm.intern("Product"), vm.enumerator_class);
    const product_class = product_value.toClassObject();
    try vm.setConstant(&vm.enumerator_class.module, try vm.intern("Product"), product_value);
    product_class.builtin_alloc_func = &builtinProductAllocate;
    const product_singleton = try vm.getOrCreateSingletonClass(product_value);
    try product_singleton.module.methods.put(new_sym, MethodEntry.keywordBuiltin(&class_builtin.builtinClassNew, .{ .variadic = 0 }));
    try product_class.module.methods.put(try vm.intern("initialize"), MethodEntry.keywordBuiltinWithVisibility(&builtinProductInitialize, .{ .variadic = 0 }, .private));
    try product_class.module.methods.put(try vm.intern("initialize_copy"), MethodEntry.builtinWithVisibility(&builtinProductInitializeCopy, .{ .exact = 1 }, .private));
    try product_class.module.methods.put(each_sym, MethodEntry.builtin(&builtinProductEach, .{ .exact = 0 }));
    try product_class.module.methods.put(size_sym, MethodEntry.builtin(&builtinProductSize, .{ .exact = 0 }));
    try product_class.module.methods.put(rewind_sym, MethodEntry.builtin(&builtinProductRewind, .{ .exact = 0 }));
    try product_class.module.methods.put(to_a_sym, enumerable.value.toModuleObject().methods.get(to_a_sym) orelse return error.Fatal);
    for ([_][]const u8{ "feed", "next", "next_values", "peek", "peek_values" }) |name| {
        try product_class.module.methods.put(try vm.intern(name), .{ .method = .{ .undefined = {} } });
    }

    // Yielder instance methods
    const yield_push_sym = try vm.intern("<<");
    try vm.yielder_class.module.methods.put(yield_push_sym, MethodEntry.builtin(&builtinYielderPush, .{ .exact = 1 }));

    const yield_sym = try vm.intern("yield");
    try vm.yielder_class.module.methods.put(yield_sym, MethodEntry.builtin(&builtinYielderYield, .{ .variadic = 0 }));
}

// --- Enumerator class methods ---

fn builtinEnumeratorNew(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = try vm.requireBlock(block);

    // Wrap the block as a ProcObject
    const proc_val = try vm.newProc(blk);
    return vm.newEnumerator(.{ .generator = .{ .proc = proc_val.toProcObject() } }, null, null, null);
}

fn builtinChainAllocate(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return vm.newEnumeratorOfClass(receiver.toClassObject(), .{ .chain = .{ .sources = null } }, null, null, null);
}

fn builtinChainInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.guardNotFrozen(receiver);
    const sources = try vm.createArray();
    sources.elements.appendSlice(vm.gc_allocator, args) catch return error.Fatal;
    receiver.toEnumeratorObject().kind = .{ .chain = .{ .sources = sources } };
    return receiver;
}

fn chainSources(vm: *VM, receiver: Value) VMError!*value.ArrayObject {
    return receiver.toEnumeratorObject().kind.chain.sources orelse
        vm.raiseExceptionFmt(vm.argument_error_class, "uninitialized chain", .{});
}

fn enumerateChain(vm: *VM, receiver: Value, args: []Value, block: Block) VMError!Value {
    const sources = try chainSources(vm, receiver);
    for (sources.elements.items, 0..) |source, index| {
        receiver.toEnumeratorObject().kind.chain.iterated_count = index + 1;
        _ = try vm.callMethodByName(source, "each", args, block);
    }
    return receiver;
}

fn builtinProductAllocate(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return vm.newEnumeratorOfClass(receiver.toClassObject(), .{ .product = .{ .sources = null } }, null, null, null);
}

fn builtinProductInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.validateKeywordArgsConsumed();
    try vm.guardNotFrozen(receiver);
    const sources = try vm.createArray();
    sources.elements.appendSlice(vm.gc_allocator, args) catch return error.Fatal;
    var sources_value = Value.fromObject(&sources.object);
    sources_value.freeze();
    receiver.toEnumeratorObject().kind = .{ .product = .{ .sources = sources } };
    return receiver;
}

fn productSources(vm: *VM, receiver: Value) VMError!*value.ArrayObject {
    return receiver.toEnumeratorObject().kind.product.sources orelse
        vm.raiseExceptionFmt(vm.argument_error_class, "uninitialized product", .{});
}

fn builtinProductInitializeCopy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = try kernel_builtin.builtinKernelInitializeCopy(vm, receiver, args, block);
    if (receiver.raw == args[0].raw) return receiver;
    receiver.toEnumeratorObject().kind = .{ .product = .{ .sources = try productSources(vm, args[0]) } };
    return receiver;
}

fn productSize(vm: *VM, receiver: Value, _: ?*value.ArrayObject) VMError!Value {
    return builtinProductSize(vm, receiver, &.{}, null);
}

fn builtinProductSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sources = try productSources(vm, receiver);
    const sizes = try vm.createArray();
    for (sources.elements.items) |source| {
        const size = (try vm.checkCallMethodByName(source, "size", false, &.{}, null)) orelse Value.nil();
        if (size.isInteger() and size.toInteger() == 0) return size;
        sizes.elements.append(vm.gc_allocator, size) catch return error.Fatal;
    }
    var total = Value.integer(1);
    for (sizes.elements.items) |size| {
        if (size.isNil() or (size.isFloat() and std.math.isInf(size.toFloatObject().val))) return size;
        if (!size.isInteger() and !size.isBigInteger()) return Value.nil();
        var multiply_args = [_]Value{size};
        total = try vm.callMethodByName(total, "*", &multiply_args, null);
    }
    return total;
}

fn builtinProductRewind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sources = try productSources(vm, receiver);
    for (sources.elements.items) |source| {
        _ = try vm.checkCallMethodByName(source, "rewind", false, &.{}, null);
    }
    return receiver;
}

const ProductContext = struct {
    product: Value,
    sources: *value.ArrayObject,
    values: []Value,
    block: Block,
    index: usize = 0,
};

fn builtinProductEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse return vm.createMethodEnumeratorWithSizeFn(receiver, try vm.intern("each"), &.{}, &productSize);
    const sources = try productSources(vm, receiver);
    const context = vm.gc_allocator.create(ProductContext) catch return error.Fatal;
    const values = vm.gc_allocator.alloc(Value, sources.elements.items.len) catch return error.Fatal;
    @memset(values, Value.nil());
    context.* = .{
        .product = receiver,
        .sources = sources,
        .values = values,
        .block = (try vm.procValueForBlock(blk)).toProcObject().block,
    };
    try iterateProduct(vm, context);
    return receiver;
}

fn iterateProduct(vm: *VM, context: *ProductContext) VMError!void {
    if (context.index == context.values.len) {
        const tuple = try vm.createArray();
        tuple.elements.appendSlice(vm.gc_allocator, context.values) catch return error.Fatal;
        _ = try vm.yieldToBlock(context.block, &.{Value.fromObject(&tuple.object)});
        return;
    }
    const callback = Block{ .kind = .{ .receiver_builtin = .{
        .receiver = .{ .raw = @intFromPtr(context) },
        .func = &productEachEntry,
        .arity = -1,
    } } };
    _ = try vm.callMethodByName(context.sources.elements.items[context.index], "each_entry", &.{}, callback);
}

fn productEachEntry(vm: *VM, receiver: Value, args: []Value) VMError!Value {
    const context: *ProductContext = @ptrFromInt(receiver.raw);
    // each_entry normally packs values itself. A custom implementation that
    // yields multiple arguments contributes only its first argument, like MRI.
    context.values[context.index] = if (args.len == 0) Value.nil() else args[0];
    context.index += 1;
    defer context.index -= 1;
    try iterateProduct(vm, context);
    return context.product;
}

fn inspectComposite(vm: *VM, receiver: Value, sources: ?*value.ArrayObject) VMError!Value {
    const description = if (sources) |array| blk: {
        if (try vm.enterRecursionGuard(.enumerator_inspect, receiver, Value.nil())) break :blk "...";
        defer vm.leaveRecursionGuard(.enumerator_inspect, receiver, Value.nil());
        const inspected = try Value.fromObject(&array.object).inspect(vm);
        break :blk inspected.toStringObject().str;
    } else "uninitialized";
    const message = std.fmt.allocPrint(vm.gc_allocator, "#<{s}: {s}>", .{ vm.className(receiver), description }) catch return error.Fatal;
    return vm.newString(message, false);
}

// --- Enumerator instance methods ---

fn builtinEnumeratorEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const enum_obj = receiver.toEnumeratorObject();

    const blk = block orelse {
        if (args.len == 0) {
            return receiver;
        }

        switch (enum_obj.kind) {
            .method => {
                var merged_args = try vm.createArray();
                if (enum_obj.method_args) |method_args| {
                    for (method_args.elements.items) |arg| {
                        merged_args.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
                    }
                }
                for (args) |arg| {
                    merged_args.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
                }
                return vm.newEnumerator(enum_obj.kind, merged_args, enum_obj.size, enum_obj.size_fn);
            },
            .generator => {
                return vm.newEnumerator(enum_obj.kind, null, enum_obj.size, enum_obj.size_fn);
            },
            .product => return builtinProductEach(vm, receiver, args, null),
            .chain => {
                return vm.newEnumeratorOfClass(enum_obj.object.class.?, enum_obj.kind, null, enum_obj.size, enum_obj.size_fn);
            },
            .chunk_while => {
                return vm.newEnumerator(enum_obj.kind, null, enum_obj.size, enum_obj.size_fn);
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
            return vm.callProcObject(g.proc, &proc_args, null, null, null, null);
        },
        .chain => return enumerateChain(vm, receiver, args, blk),
        .product => return builtinProductEach(vm, receiver, args, blk),
        .chunk_while => |chunk_while| return enumerateChunkWhile(vm, receiver, chunk_while.receiver, chunk_while.predicate, blk),
    }
}

fn coerceEnumeratorIndexOffset(vm: *VM, args: []Value) VMError!i64 {
    if (args.len == 0 or args[0].isNil()) return 0;
    return args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion to Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long`",
    );
}

fn enumeratorWithIndexYieldBlock(vm: *VM, args: []Value) VMError!Value {
    var yield_ctx = vm.indexed_yield_ctx orelse return error.Fatal;
    var yield_args_buf: [2]Value = undefined;
    yield_args_buf[0] = switch (args.len) {
        0 => Value.nil(),
        1 => args[0],
        else => blk: {
            const values = try vm.createArray();
            for (args) |arg| {
                values.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
            }
            break :blk Value.fromObject(&values.object);
        },
    };
    yield_args_buf[1] = Value.integer(yield_ctx.index);
    yield_ctx.index += 1;

    vm.indexed_yield_ctx = yield_ctx.previous;
    defer vm.indexed_yield_ctx = yield_ctx;

    const yielded = try vm.yieldToBlock(yield_ctx.block, &yield_args_buf);
    return yielded;
}

fn enumeratorWithIndexImpl(vm: *VM, receiver: Value, args: []Value, block: ?Block, method_name: []const u8) VMError!Value {
    const blk = block orelse {
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, try vm.intern(method_name), args, size);
        }
        return vm.createMethodEnumerator(receiver, try vm.intern(method_name), args);
    };

    const start_index = try coerceEnumeratorIndexOffset(vm, args);
    var yield_ctx = vm_mod.IndexedYieldContext{
        .block = blk,
        .index = start_index,
        .previous = vm.indexed_yield_ctx,
    };
    vm.indexed_yield_ctx = &yield_ctx;
    defer vm.indexed_yield_ctx = yield_ctx.previous;

    return vm.callMethodByName(receiver, "each", &.{}, .{ .kind = .{ .builtin = &enumeratorWithIndexYieldBlock } });
}

fn builtinEnumeratorEachWithIndex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return enumeratorWithIndexImpl(vm, receiver, &.{}, block, "each_with_index");
}

fn builtinEnumeratorWithIndex(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    return enumeratorWithIndexImpl(vm, receiver, args, block, "with_index");
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
    return Value.fromObject(&yield_values.object);
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
    return Value.fromObject(&yield_values.object);
}

fn builtinEnumeratorRewind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const enum_obj = receiver.toEnumeratorObject();
    if (enum_obj.kind == .method) {
        _ = try vm.checkCallMethodByName(enum_obj.kind.method.receiver, "rewind", false, &.{}, null);
    }
    if (enum_obj.kind == .product) return builtinProductRewind(vm, receiver, args, null);
    if (enum_obj.kind == .chain) {
        const sources = try chainSources(vm, receiver);
        while (enum_obj.kind.chain.iterated_count > 0 and enum_obj.kind.chain.iterated_count <= sources.elements.items.len) {
            const index = enum_obj.kind.chain.iterated_count - 1;
            _ = try vm.checkCallMethodByName(sources.elements.items[index], "rewind", false, &.{}, null);
            enum_obj.kind.chain.iterated_count = index;
        }
    }
    enum_obj.fiber = null;
    enum_obj.has_lookahead_values = false;
    enum_obj.lookahead_values = null;
    return receiver;
}

fn arithmeticSequenceRange(vm: *VM, receiver: Value) VMError!*value.RangeObject {
    const method = switch (receiver.toEnumeratorObject().kind) {
        .method => |method| method,
        else => return vm.raiseExceptionFmt(vm.type_error_class, "invalid arithmetic sequence", .{}),
    };
    if (!method.receiver.isRange()) return vm.raiseExceptionFmt(vm.type_error_class, "invalid arithmetic sequence", .{});
    return method.receiver.toRangeObject();
}

fn builtinArithmeticSequenceBegin(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return (try arithmeticSequenceRange(vm, receiver)).begin;
}

fn builtinArithmeticSequenceEnd(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return (try arithmeticSequenceRange(vm, receiver)).end;
}

fn builtinArithmeticSequenceStep(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    if (receiver.toEnumeratorObject().method_args) |args| {
        if (args.elements.items.len > 0) return args.elements.items[0];
    }
    return Value.integer(1);
}

fn builtinArithmeticSequenceInspect(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const sequence = receiver.toEnumeratorObject();
    const method = switch (sequence.kind) {
        .method => |method| method,
        else => return builtinEnumeratorInspect(vm, receiver, &.{}, null),
    };
    const inspected = try method.receiver.inspect(vm);
    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    writer.print("(({s}).{s}", .{ inspected.toStringObject().str, method.method_name.name }) catch return error.Fatal;
    if (sequence.method_args) |args| {
        writer.writeAll("(") catch return error.Fatal;
        for (args.elements.items, 0..) |arg, i| {
            if (i > 0) writer.writeAll(", ") catch return error.Fatal;
            const arg_inspected = try arg.inspect(vm);
            writer.writeAll(arg_inspected.toStringObject().str) catch return error.Fatal;
        }
        writer.writeAll(")") catch return error.Fatal;
    }
    writer.writeAll(")") catch return error.Fatal;
    return vm.newString(buf.written(), false);
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
        .chain => |chain| return inspectComposite(vm, receiver, chain.sources),
        .product => |product| return inspectComposite(vm, receiver, product.sources),
        .chunk_while => {
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

    if (enum_obj.kind == .chain) {
        const sources = try chainSources(vm, receiver);
        var total = Value.integer(0);
        for (sources.elements.items) |source| {
            const size = (try vm.checkCallMethodByName(source, "size", false, &.{}, null)) orelse return Value.nil();
            if (size.isNil() or (size.isFloat() and std.math.isInf(size.toFloatObject().val))) return size;
            if (!size.isInteger() and !size.isBigInteger()) return Value.nil();
            var sum_args = [_]Value{size};
            total = try vm.callMethodByName(total, "+", &sum_args, null);
        }
        return total;
    }

    if (enum_obj.size) |size| {
        if (size.isProc()) {
            return vm.callProcObject(size.toProcObject(), &[_]Value{}, null, null, null, null);
        }
        return size;
    }
    if (enum_obj.size_fn) |size_fn| {
        switch (enum_obj.kind) {
            .method => |m| return size_fn(vm, m.receiver, enum_obj.method_args),
            .generator => return Value.nil(),
            .chain, .product => return Value.nil(),
            .chunk_while => return Value.nil(),
        }
    }

    return Value.nil();
}

fn builtinEnumeratorToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const out = try vm.createArray();

    while (true) {
        const next_val = builtinEnumeratorNext(vm, receiver, &[_]Value{}, null) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };
        out.elements.append(vm.gc_allocator, next_val) catch return error.Fatal;
    }

    return Value.fromObject(&out.object);
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
    return result;
}

// --- Helper functions ---

fn ensureEnumeratorFiber(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.FiberObject {
    if (enum_obj.fiber) |fiber| {
        return fiber;
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
    const yield_block = Block{ .kind = .{ .receiver_builtin = .{
        .receiver = Value.nil(),
        .func = &enumeratorFiberYieldBlock,
        .arity = -1,
    } } };

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
            return vm.callProcObject(g.proc, &proc_args, null, null, null, null);
        },
        .chain => return enumerateChain(vm, enum_val, &.{}, yield_block),
        .product => return builtinProductEach(vm, enum_val, &.{}, yield_block),
        .chunk_while => |chunk_while| return enumerateChunkWhile(vm, enum_val, chunk_while.receiver, chunk_while.predicate, yield_block),
    }
}

fn enumerateChunkWhile(
    vm: *VM,
    enum_value: Value,
    source: Value,
    predicate: *value.ProcObject,
    block: Block,
) VMError!Value {
    const source_enum = try vm.createMethodEnumerator(source, try vm.intern("each"), &.{});
    const first_values = fetchNextYieldValues(vm, source_enum.toEnumeratorObject()) catch |err| {
        if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
            vm.setPendingException(null);
            return enum_value;
        }
        return err;
    };

    var previous = collapseYieldValues(first_values);
    var chunk = try vm.createArray();
    chunk.elements.append(vm.gc_allocator, previous) catch return error.Fatal;

    while (true) {
        const next_values = fetchNextYieldValues(vm, source_enum.toEnumeratorObject()) catch |err| {
            if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.stop_iteration_class) {
                vm.setPendingException(null);
                break;
            }
            return err;
        };
        const current = collapseYieldValues(next_values);
        var predicate_args = [_]Value{ previous, current };
        const keep = try vm.callProcObject(predicate, &predicate_args, null, null, null, null);
        if (!keep.isTruthy()) {
            _ = try vm.yieldToBlock(block, &.{Value.fromObject(&chunk.object)});
            chunk = try vm.createArray();
        }
        chunk.elements.append(vm.gc_allocator, current) catch return error.Fatal;
        previous = current;
    }

    _ = try vm.yieldToBlock(block, &.{Value.fromObject(&chunk.object)});
    return enum_value;
}

fn enumeratorFiberYieldBlock(vm: *VM, _: Value, args: []Value) VMError!Value {
    const arr = try vm.createArray();
    for (args) |arg| {
        arr.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    }
    return vm.fiberYield(Value.fromObject(&arr.object));
}

fn raiseStopIteration(vm: *VM) VMError {
    return vm.raiseExceptionFmt(vm.stop_iteration_class, "StopIteration", .{});
}

fn collapseYieldValues(yield_values: *value.ArrayObject) Value {
    return switch (yield_values.elements.items.len) {
        0 => Value.nil(),
        1 => yield_values.elements.items[0],
        else => Value.fromObject(&yield_values.object),
    };
}

fn fetchNextYieldValues(vm: *VM, enum_obj: *value.EnumeratorObject) VMError!*value.ArrayObject {
    // Ensure we have a fiber for external iteration
    const fiber = try ensureEnumeratorFiber(vm, enum_obj);

    if (fiber.state == .terminated) {
        return raiseStopIteration(vm);
    }

    var resume_args: [1]Value = .{Value.fromObject(&enum_obj.object)};
    const result = vm.resumeFiber(
        fiber,
        if (fiber.state == .created) resume_args[0..1] else &[_]Value{},
        Value.nil(),
    ) catch |err| {
        // The fiber died abnormally. A StopIteration leaves the enumerator
        // stopped until rewind, but any other exception is transient, so drop
        // the dead fiber and let the next call restart iteration.
        if (err == error.Unwind) {
            const stopped = if (vm.pendingException()) |pending|
                pending.object.class == vm.stop_iteration_class
            else
                false;
            if (!stopped) {
                enum_obj.fiber = null;
            }
        }
        return err;
    };

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
