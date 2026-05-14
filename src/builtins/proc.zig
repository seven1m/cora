const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const proc_new_sym = try vm.intern("new");
    const proc_class_val = Value.fromObject(&vm.proc_class.module.object);
    const proc_singleton = try vm.getOrCreateSingletonClass(proc_class_val);
    try proc_singleton.module.methods.put(proc_new_sym, value.MethodEntry.builtin(&builtinProcNew, .{ .variadic = 0 }));

    const call_sym = try vm.intern("call");
    try vm.proc_class.module.methods.put(call_sym, value.MethodEntry.builtin(&builtinProcCall, .{ .variadic = 0 }));

    const lambda_query_sym = try vm.intern("lambda?");
    try vm.proc_class.module.methods.put(lambda_query_sym, value.MethodEntry.builtin(&builtinProcIsLambda, .{ .exact = 0 }));

    const arity_sym = try vm.intern("arity");
    try vm.proc_class.module.methods.put(arity_sym, value.MethodEntry.builtin(&builtinProcArity, .{ .exact = 0 }));

    const parameters_sym = try vm.intern("parameters");
    try vm.proc_class.module.methods.put(parameters_sym, value.MethodEntry.builtin(&builtinProcParameters, .{ .exact = 0 }));

    const source_location_sym = try vm.intern("source_location");
    try vm.proc_class.module.methods.put(source_location_sym, value.MethodEntry.builtin(&builtinProcSourceLocation, .{ .exact = 0 }));

    const to_proc_sym = try vm.intern("to_proc");
    try vm.proc_class.module.methods.put(to_proc_sym, value.MethodEntry.builtin(&builtinProcToProc, .{ .exact = 0 }));
}

pub fn builtinProcNew(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Proc object without a block",
        );
        vm.setPendingException(exc);
        return error.Unwind;
    };

    return try vm.newProc(blk);
}

pub fn builtinProcCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    return vm.callProcObject(proc_obj, args, block, null);
}

pub fn builtinProcIsLambda(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(switch (receiver.toProcObject().block.kind) {
        .chunk => |chunk_blk| chunk_blk.chunk.is_lambda,
        .symbol, .builtin, .callable => true,
    });
}

pub fn builtinProcArity(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return switch (receiver.toProcObject().block.kind) {
        .chunk => |chunk_blk| blk: {
            const required = chunk_blk.chunk.arity + chunk_blk.chunk.post_required_count;
            if (chunk_blk.chunk.rest_param_index != null or chunk_blk.chunk.optional_params.items.len > 0) {
                break :blk Value.integer(-@as(i64, @intCast(required)) - 1);
            }
            break :blk Value.integer(@intCast(required));
        },
        .symbol, .builtin, .callable => Value.integer(-2),
    };
}

pub fn builtinProcParameters(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    switch (proc_obj.block.kind) {
        .symbol, .builtin, .callable => {
            const req_array = try vm.createArray();
            req_array.elements.append(vm.gc_allocator, Value.fromObject(&(try vm.intern("req")).object)) catch return error.Fatal;
            const rest_array = try vm.createArray();
            rest_array.elements.append(vm.gc_allocator, Value.fromObject(&(try vm.intern("rest")).object)) catch return error.Fatal;
            const result = try vm.createArray();
            result.elements.append(vm.gc_allocator, Value.fromObject(&req_array.object)) catch return error.Fatal;
            result.elements.append(vm.gc_allocator, Value.fromObject(&rest_array.object)) catch return error.Fatal;
            return Value.fromObject(&result.object);
        },
        .chunk => |chunk_blk| {
            return try vm.getChunkParameters(chunk_blk.chunk);
        },
    }
}

pub fn builtinProcSourceLocation(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    switch (proc_obj.block.kind) {
        .symbol, .builtin, .callable => return Value.nil(),
        .chunk => |chunk_blk| {
            if (chunk_blk.chunk.source_file) |source| {
                const line = if (chunk_blk.chunk.line_info.items.len > 0 and chunk_blk.chunk.line_info.items[0].line != 0)
                    chunk_blk.chunk.line_info.items[0].line
                else
                    1;
                const array = try vm.createArray();
                array.elements.append(vm.gc_allocator, try vm.newString(source, false)) catch return error.Fatal;
                array.elements.append(vm.gc_allocator, Value.integer(line)) catch return error.Fatal;
                return Value.fromObject(&array.object);
            }
            return Value.nil();
        },
    }
}

pub fn builtinProcToProc(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return receiver;
}
