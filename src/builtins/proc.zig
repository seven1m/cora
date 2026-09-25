const std = @import("std");
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
    try proc_singleton.module.methods.put(proc_new_sym, value.MethodEntry.keywordBuiltin(&builtinProcNew, .{ .variadic = 0 }));

    const call_entry = value.MethodEntry.keywordBuiltin(&builtinProcCall, .{ .variadic = 0 });
    const call_sym = try vm.intern("call");
    try vm.proc_class.module.methods.put(call_sym, call_entry);

    const bracket_sym = try vm.intern("[]");
    try vm.proc_class.module.methods.put(bracket_sym, call_entry);

    const case_equal_sym = try vm.intern("===");
    try vm.proc_class.module.methods.put(case_equal_sym, call_entry);

    const yield_sym = try vm.intern("yield");
    try vm.proc_class.module.methods.put(yield_sym, call_entry);

    const lambda_query_sym = try vm.intern("lambda?");
    try vm.proc_class.module.methods.put(lambda_query_sym, value.MethodEntry.builtin(&builtinProcIsLambda, .{ .exact = 0 }));

    const arity_sym = try vm.intern("arity");
    try vm.proc_class.module.methods.put(arity_sym, value.MethodEntry.builtin(&builtinProcArity, .{ .exact = 0 }));

    const parameters_sym = try vm.intern("parameters");
    try vm.proc_class.module.methods.put(parameters_sym, value.MethodEntry.builtin(&builtinProcParameters, .{ .exact = 0 }));

    const source_location_sym = try vm.intern("source_location");
    try vm.proc_class.module.methods.put(source_location_sym, value.MethodEntry.builtin(&builtinProcSourceLocation, .{ .exact = 0 }));

    const binding_sym = try vm.intern("binding");
    try vm.proc_class.module.methods.put(binding_sym, value.MethodEntry.builtin(&builtinProcBinding, .{ .exact = 0 }));

    const inspect_entry = value.MethodEntry.builtin(&builtinProcInspect, .{ .exact = 0 });
    const inspect_sym = try vm.intern("inspect");
    try vm.proc_class.module.methods.put(inspect_sym, inspect_entry);
    const to_s_sym = try vm.intern("to_s");
    try vm.proc_class.module.methods.put(to_s_sym, inspect_entry);

    const to_proc_sym = try vm.intern("to_proc");
    try vm.proc_class.module.methods.put(to_proc_sym, value.MethodEntry.builtin(&builtinProcToProc, .{ .exact = 0 }));

    const ruby2_keywords_sym = try vm.intern("ruby2_keywords");
    try vm.proc_class.module.methods.put(ruby2_keywords_sym, value.MethodEntry.builtin(&builtinProcRuby2Keywords, .{ .exact = 0 }));

    const equal_entry = value.MethodEntry.builtin(&builtinProcEqual, .{ .exact = 1 });
    const equal_sym = try vm.intern("==");
    try vm.proc_class.module.methods.put(equal_sym, equal_entry);
    const eql_sym = try vm.intern("eql?");
    try vm.proc_class.module.methods.put(eql_sym, equal_entry);
}

pub fn builtinProcEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isProc()) return Value.boolean(false);
    if (vm.getClass(receiver) != vm.getClass(args[0])) return Value.boolean(false);

    const lhs = receiver.toProcObject().block;
    const rhs = args[0].toProcObject().block;
    const equal = switch (lhs.kind) {
        .chunk => |lhs_chunk| switch (rhs.kind) {
            .chunk => |rhs_chunk| lhs_chunk.chunk == rhs_chunk.chunk and lhs_chunk.defining_ep == rhs_chunk.defining_ep,
            else => false,
        },
        .receiver_builtin => |lhs_builtin| switch (rhs.kind) {
            .receiver_builtin => |rhs_builtin| lhs_builtin.receiver.raw == rhs_builtin.receiver.raw and
                lhs_builtin.func == rhs_builtin.func and
                lhs_builtin.arity == rhs_builtin.arity,
            else => false,
        },
        .symbol => |lhs_symbol| switch (rhs.kind) {
            .symbol => |rhs_symbol| lhs_symbol == rhs_symbol,
            else => false,
        },
        .builtin => |lhs_builtin| switch (rhs.kind) {
            .builtin => |rhs_builtin| lhs_builtin == rhs_builtin,
            else => false,
        },
        .callable => |lhs_callable| switch (rhs.kind) {
            .callable => |rhs_callable| lhs_callable.raw == rhs_callable.raw,
            else => false,
        },
    };
    return Value.boolean(equal);
}

pub fn builtinProcNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const blk = block orelse {
        return vm.raiseExceptionFmt(vm.argument_error_class, "tried to create Proc object without a block", .{});
    };

    const proc_val = try vm.newProc(blk);
    proc_val.toProcObject().object.class = receiver.toClassObject();
    _ = try vm.callMethodByNameForwardingKeywords(proc_val, "initialize", args, block);
    return proc_val;
}

pub fn builtinProcCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    return vm.callProcObject(proc_obj, args, block, null, null, null);
}

pub fn builtinProcBinding(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const chunk_block = switch (receiver.toProcObject().block.kind) {
        .chunk => |chunk_block| chunk_block,
        else => return vm.raiseExceptionFmt(vm.argument_error_class, "Can't create Binding from C level Proc", .{}),
    };
    const binding = try vm.createBinding(chunk_block.defining_self, chunk_block.defining_ep, chunk_block.chunk.lexical_scope);
    for (chunk_block.defining_local_names) |name| {
        binding.local_names.append(vm.gc_allocator, name) catch return error.Fatal;
    }
    binding.real_local_count = binding.local_names.items.len;
    return Value.fromObject(&binding.object);
}

pub fn builtinProcIsLambda(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(switch (receiver.toProcObject().block.kind) {
        .chunk => |chunk_blk| chunk_blk.chunk.is_lambda,
        .receiver_builtin, .symbol, .builtin, .callable => true,
    });
}

pub fn builtinProcArity(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.integer(try vm.blockArity(receiver.toProcObject().block));
}

pub fn builtinProcParameters(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    switch (proc_obj.block.kind) {
        .receiver_builtin => |builtin_data| {
            const result = try vm.createArray();
            var index: i64 = 0;
            while (index < builtin_data.arity) : (index += 1) {
                const param = try vm.createArray();
                param.elements.append(vm.gc_allocator, Value.fromObject(&(try vm.intern("req")).object)) catch return error.Fatal;
                result.elements.append(vm.gc_allocator, Value.fromObject(&param.object)) catch return error.Fatal;
            }
            return Value.fromObject(&result.object);
        },
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
        .receiver_builtin, .symbol, .builtin, .callable => return Value.nil(),
        .chunk => |chunk_blk| {
            if (chunk_blk.chunk.source_file) |source| {
                const line = chunk_blk.chunk.declaration_line;
                const array = try vm.createArray();
                array.elements.append(vm.gc_allocator, try vm.newString(source, false)) catch return error.Fatal;
                array.elements.append(vm.gc_allocator, Value.integer(line)) catch return error.Fatal;
                return Value.fromObject(&array.object);
            }
            return Value.nil();
        },
    }
}

pub fn builtinProcInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const object_id = receiver.objectId();
    const proc_obj = receiver.toProcObject();
    const inspected = switch (proc_obj.block.kind) {
        .chunk => |chunk_blk| if (chunk_blk.chunk.source_file) |source|
            if (chunk_blk.chunk.is_lambda)
                std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x} {s}:{d} (lambda)>", .{ object_id, source, chunk_blk.chunk.declaration_line }) catch return error.Fatal
            else
                std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x} {s}:{d}>", .{ object_id, source, chunk_blk.chunk.declaration_line }) catch return error.Fatal
        else if (chunk_blk.chunk.is_lambda)
            std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x} (lambda)>", .{object_id}) catch return error.Fatal
        else
            std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x}>", .{object_id}) catch return error.Fatal,
        .symbol => |symbol| std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x}(&:{s}) (lambda)>", .{ object_id, symbol.name }) catch return error.Fatal,
        .receiver_builtin, .builtin, .callable => std.fmt.allocPrint(vm.gc_allocator, "#<Proc:0x{x} (lambda)>", .{object_id}) catch return error.Fatal,
    };
    return vm.newString(inspected, false);
}

pub fn builtinProcToProc(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return receiver;
}

pub fn builtinProcRuby2Keywords(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    receiver.toProcObject().ruby2_keywords = true;
    return receiver;
}
