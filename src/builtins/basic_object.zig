const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodEntry = value.MethodEntry;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.basic_object_class.module.methods.put(initialize_sym, MethodEntry.builtinWithVisibility(&builtinBasicObjectInitialize, .{ .exact = 0 }, .private));

    const send_sym = try vm.intern("__send__");
    try vm.basic_object_class.module.methods.put(send_sym, MethodEntry.builtin(&builtinBasicObjectSend, .{ .variadic = 0 }));

    const instance_eval_sym = try vm.intern("instance_eval");
    try vm.basic_object_class.module.methods.put(instance_eval_sym, MethodEntry.builtin(&builtinBasicObjectInstanceEval, .{ .variadic = 0 }));

    const id_sym = try vm.intern("__id__");
    try vm.basic_object_class.module.methods.put(id_sym, MethodEntry.builtin(&builtinBasicObjectId, .{ .exact = 0 }));

    const op_equal_sym = try vm.intern("==");
    try vm.basic_object_class.module.methods.put(op_equal_sym, MethodEntry.builtin(&builtinBasicObjectEqual, .{ .exact = 1 }));

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
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);
    const proc_obj = (try vm.newProc(blk)).toProcObject();
    return vm.callProcObject(proc_obj, &.{}, null, receiver);
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
    return Value.boolean(!equal.is_truthy());
}

pub fn builtinBasicObjectNot(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(!receiver.is_truthy());
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
