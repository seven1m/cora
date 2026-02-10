const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const CallFrame = vm_mod.CallFrame;

pub fn register(vm: *VM) !void {
    const proc_new_sym = try vm.intern("new");
    const proc_class_val = Value{ .data = .{ .class = vm.proc_class } };
    const proc_singleton = try vm.getOrCreateSingletonClass(proc_class_val);
    try proc_singleton.module.methods.put(proc_new_sym, .{ .method = .{ .builtin = &builtinProcNew } });

    const call_sym = try vm.intern("call");
    try vm.proc_class.module.methods.put(call_sym, .{ .method = .{ .builtin = &builtinProcCall } });

    const lambda_query_sym = try vm.intern("lambda?");
    try vm.proc_class.module.methods.put(lambda_query_sym, .{ .method = .{ .builtin = &builtinProcIsLambda } });
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
    const proc_obj = receiver.data.proc;

    const real_defining_ep = VM.derefEnvironment(proc_obj.block.defining_ep);

    const proc_env = vm.createStackEnvironment(real_defining_ep, proc_obj.block.chunk.lexical_scope orelse vm.current_lexical_scope) catch return error.Fatal;

    const proc_chunk = proc_obj.block.chunk;
    const mode: VM.ArityMode = if (proc_chunk.is_lambda) .strict else .lenient;

    // Copy arguments with rest parameter handling
    try vm.copyArgumentsWithRestParam(proc_chunk, proc_env, args, mode);

    if (proc_obj.block.chunk.lexical_scope) |scope| {
        vm.current_lexical_scope = scope;
    }

    vm.frames.append(vm.gc_allocator, CallFrame{
        .chunk = proc_obj.block.chunk,
        .ip = 0,
        .stack_base = vm.stack.items.len,
        .self_value = proc_obj.block.defining_self,
        .ep = proc_env,
        .block = null,
        .frame_type = if (proc_obj.block.chunk.is_lambda) .lambda else .proc,
    }) catch return error.Fatal;

    // Execute the proc/lambda until it returns
    const saved_frame_count = vm.frames.items.len - 1;
    try vm.executeInstructionsUntilFrameLength(saved_frame_count + 1);

    // The return value is already on the stack from the RETURN instruction
    return vm.pop();
}

pub fn builtinProcIsLambda(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(receiver.data.proc.block.chunk.is_lambda);
}
