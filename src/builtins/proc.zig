const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const proc_new_sym = try vm.intern("new");
    const proc_class_val = Value.fromObject(vm.proc_class);
    const proc_singleton = try vm.getOrCreateSingletonClass(proc_class_val);
    try proc_singleton.module.methods.put(proc_new_sym, value.MethodEntry.builtin(&builtinProcNew, .{ .variadic = 0 }));

    const call_sym = try vm.intern("call");
    try vm.proc_class.module.methods.put(call_sym, value.MethodEntry.builtin(&builtinProcCall, .{ .variadic = 0 }));

    const lambda_query_sym = try vm.intern("lambda?");
    try vm.proc_class.module.methods.put(lambda_query_sym, value.MethodEntry.builtin(&builtinProcIsLambda, .{ .exact = 0 }));
}

pub fn builtinProcNew(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Proc object without a block",
        );
        vm.pending_exception = exc;
        return error.Unwind;
    };

    return try vm.newProc(blk);
}

pub fn builtinProcCall(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const proc_obj = receiver.toProcObject();
    return vm.callProcObject(proc_obj, args, null, null);
}

pub fn builtinProcIsLambda(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(switch (receiver.toProcObject().block.kind) {
        .chunk => |chunk_blk| chunk_blk.chunk.is_lambda,
        .symbol, .builtin, .callable => true,
    });
}
