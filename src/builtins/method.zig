const vm_mod = @import("../vm.zig");
const common = @import("method_common.zig");
const unbound_method = @import("unbound_method.zig");

const VM = common.VM;
const VMError = common.VMError;
const Block = common.Block;
const Value = common.Value;
const MethodObject = common.MethodObject;
const SymbolObject = common.SymbolObject;

fn boundMethodObject(receiver: Value) *MethodObject {
    return receiver.toMethodObject();
}

fn builtinMethodCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const method_obj = boundMethodObject(receiver);

    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };
    return vm.invokeResolvedMethod(resolved, method_obj.receiver, args, block);
}

fn builtinMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return boundMethodObject(receiver).owner;
}

fn builtinMethodToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return boundMethodObject(receiver).arity;
}

fn builtinMethodUnbind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = boundMethodObject(receiver);
    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };

    return unbound_method.createUnboundMethodObject(vm, method_obj.name, resolved, method_obj.owner);
}

fn builtinMethodSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = boundMethodObject(receiver);
    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };
    return common.sourceLocationForResolvedMethod(vm, resolved);
}

pub fn createBoundMethodObject(
    vm: *VM,
    receiver: Value,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
) VMError!Value {
    return common.createBoundMethodObject(vm, receiver, method_name, resolved, owner, .{
        .call = &builtinMethodCall,
        .owner = &builtinMethodOwner,
        .to_proc = &builtinMethodToProc,
        .arity = &builtinMethodArity,
        .unbind = &builtinMethodUnbind,
        .source_location = &builtinMethodSourceLocation,
    });
}
