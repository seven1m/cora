const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodEntry = value.MethodEntry;

fn evalFilename(vm: *VM, source_file_arg: ?Value) VMError![]const u8 {
    if (source_file_arg) |arg| {
        return arg.coerceToStr(vm, "no implicit conversion into String");
    }

    if (vm.currentRubyCallerFrame()) |frame| {
        const caller_source = frame.chunk.source_file orelse "(eval)";
        const caller_line = vm.backtraceLineForFrame(frame);
        return std.fmt.allocPrint(vm.gc_allocator, "(eval at {s}:{d})", .{ caller_source, caller_line }) catch return error.Fatal;
    }

    return "(eval)";
}

fn evalLineOffset(vm: *VM, lineno_arg: ?Value) VMError!u32 {
    if (lineno_arg == null or lineno_arg.?.isNil()) return 0;
    const lineno = try lineno_arg.?.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );
    if (lineno <= 1) return 0;
    return @intCast(lineno - 1);
}

fn instanceEvalLexicalScope(vm: *VM, receiver: Value) VMError!*value.LexicalScope {
    const caller_scope = vm.current_lexical_scope;
    const receiver_class = vm.getClass(receiver);

    const receiver_class_scope = try vm.createLexicalScope(
        Value.fromObject(&receiver_class.module.object),
        caller_scope,
    );

    if (receiver.isModule() or receiver.isClass()) {
        return receiver_class_scope;
    }

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    return vm.createLexicalScope(
        Value.fromObject(&singleton_class.module.object),
        receiver_class_scope,
    );
}

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.basic_object_class.module.methods.put(initialize_sym, MethodEntry.builtinWithVisibility(&builtinBasicObjectInitialize, .{ .exact = 0 }, .private));

    const send_sym = try vm.intern("__send__");
    try vm.basic_object_class.module.methods.put(send_sym, MethodEntry.builtin(&builtinBasicObjectSend, .{ .variadic = 0 }));

    const instance_eval_sym = try vm.intern("instance_eval");
    try vm.basic_object_class.module.methods.put(instance_eval_sym, MethodEntry.builtin(&builtinBasicObjectInstanceEval, .{ .variadic = 0 }));

    const instance_exec_sym = try vm.intern("instance_exec");
    try vm.basic_object_class.module.methods.put(instance_exec_sym, MethodEntry.builtin(&builtinBasicObjectInstanceExec, .{ .variadic = 0 }));

    const id_sym = try vm.intern("__id__");
    try vm.basic_object_class.module.methods.put(id_sym, MethodEntry.builtin(&builtinBasicObjectId, .{ .exact = 0 }));

    const op_equal_sym = try vm.intern("==");
    try vm.basic_object_class.module.methods.put(op_equal_sym, MethodEntry.builtin(&builtinBasicObjectEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.basic_object_class.module.methods.put(eql_sym, MethodEntry.builtin(&builtinBasicObjectEqual, .{ .exact = 1 }));

    const equal_sym = try vm.intern("equal?");
    try vm.basic_object_class.module.methods.put(equal_sym, MethodEntry.builtin(&builtinBasicObjectEqual, .{ .exact = 1 }));

    const not_equal_sym = try vm.intern("!=");
    try vm.basic_object_class.module.methods.put(not_equal_sym, MethodEntry.builtin(&builtinBasicObjectNotEqual, .{ .exact = 1 }));

    const not_sym = try vm.intern("!");
    try vm.basic_object_class.module.methods.put(not_sym, MethodEntry.builtin(&builtinBasicObjectNot, .{ .exact = 0 }));

    const method_missing_sym = try vm.intern("method_missing");
    try vm.basic_object_class.module.methods.put(method_missing_sym, MethodEntry.builtinWithVisibility(&builtinBasicObjectMethodMissing, .{ .variadic = 0 }, .private));
}

pub fn builtinBasicObjectInitialize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.nil();
}

pub fn builtinBasicObjectSend(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const name_str = try vm.coerceToMethodNameString(args[0]);
    const call_args = args[1..];
    return vm.callMethodByNameForwardingKeywords(receiver, name_str, call_args, block);
}

pub fn builtinBasicObjectInstanceEval(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (block) |blk| {
        try vm.requireArgCount(args, 0);
        const proc_obj = (try vm.newProc(blk)).toProcObject();
        var block_args = [_]Value{receiver};
        return vm.callProcObject(proc_obj, block_args[0..], null, receiver, receiver);
    }

    try vm.requireArgCountRange(args, 1, 3);
    const source_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const caller_frame = vm.currentRubyCallerFrame();
    const lexical_scope = try instanceEvalLexicalScope(vm, receiver);
    return vm.evalSourceWithEncodingAndContext(
        source_value.toStringObject().str,
        try evalFilename(vm, if (args.len >= 2) args[1] else null),
        source_value.toStringObject().encoding,
        .{
            .self_value = receiver,
            .parent_ep = if (caller_frame) |frame| frame.ep else null,
            .lexical_scope = lexical_scope,
            .class_variable_scope = vm.currentRubyCallerLexicalScope(),
            .method_definition_target = receiver,
            .parent_local_names = vm.currentEvalParentLocalNames(),
            .line_offset = try evalLineOffset(vm, if (args.len >= 3) args[2] else null),
        },
    );
}

pub fn builtinBasicObjectInstanceExec(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const blk = block orelse {
        return vm.raiseExceptionFmt(vm.local_jump_error_class, "no block given", .{});
    };

    const proc_obj = (try vm.newProc(blk)).toProcObject();
    return vm.callProcObject(proc_obj, args, null, receiver, receiver);
}

pub fn builtinBasicObjectId(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.objectIdValue(receiver);
}

pub fn builtinBasicObjectEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(receiver.objectId() == args[0].objectId());
}

pub fn builtinBasicObjectNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const equal = try vm.callMethodByName(receiver, "==", args[0..1], null);
    return Value.boolean(equal.isFalsey());
}

pub fn builtinBasicObjectNot(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.isFalsey());
}

pub fn builtinBasicObjectMethodMissing(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        return vm.raiseExceptionFmt(vm.no_method_error_class, "undefined method", .{});
    }
    if (args[0].isSymbol()) {
        const sym = args[0].toSymbolObject();
        return vm.raiseNoMethod(receiver, sym.name);
    }
    unreachable;
}
