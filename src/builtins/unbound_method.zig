const std = @import("std");
const vm_mod = @import("../vm.zig");
const common = @import("method_common.zig");

const VM = common.VM;
const VMError = common.VMError;
const Block = common.Block;
const Value = common.Value;
const SymbolObject = common.SymbolObject;
const UnboundMethodObject = common.UnboundMethodObject;

fn unboundMethodObject(receiver: Value) *UnboundMethodObject {
    return receiver.toUnboundMethodObject();
}

fn builtinMethodCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const method_obj = receiver.toMethodObject();

    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };
    return vm.invokeResolvedMethod(resolved, method_obj.receiver, args, block);
}

fn builtinMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toMethodObject().owner;
}

fn builtinMethodToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toMethodObject().arity;
}

fn builtinMethodParameters(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = receiver.toMethodObject();
    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };
    return common.parametersForResolvedMethod(vm, resolved);
}

fn builtinMethodUnbind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = receiver.toMethodObject();
    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };

    return createUnboundMethodObject(vm, method_obj.name, resolved, method_obj.owner);
}

fn builtinMethodSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = receiver.toMethodObject();
    const resolved = (try common.resolveExactMethodForReceiver(vm, method_obj.receiver, method_obj.owner, method_obj.name)) orelse {
        return common.raiseUndefinedMethodName(vm, method_obj.name);
    };
    return common.sourceLocationForResolvedMethod(vm, resolved);
}

fn createBoundMethodObject(
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
        .parameters = &builtinMethodParameters,
        .unbind = &builtinMethodUnbind,
        .source_location = &builtinMethodSourceLocation,
    });
}

fn builtinUnboundMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return unboundMethodObject(receiver).owner;
}

fn builtinUnboundMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return unboundMethodObject(receiver).arity;
}

fn builtinUnboundMethodParameters(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = unboundMethodObject(receiver);
    const resolved = common.methodEntryForOwner(method_obj.owner, method_obj.name) orelse return Value.nil();
    return common.parametersForResolvedMethod(vm, .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = resolved,
    });
}

fn builtinUnboundMethodBind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const method_obj = unboundMethodObject(receiver);
    const bind_target = args[0];

    if (!common.isCompatibleBindTarget(vm, bind_target, method_obj.owner)) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "bind argument must be an instance of {s}",
            .{common.ownerDisplayName(method_obj.owner)},
        );
    }

    // Use the captured entry so the bound method invokes the original
    // implementation even if the method was removed/redefined since capture.
    const captured_resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
    };
    return createBoundMethodObject(vm, bind_target, method_obj.name, captured_resolved, method_obj.owner);
}

fn builtinUnboundMethodBindCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const method_obj = unboundMethodObject(receiver);
    const bind_target = args[0];
    const call_args = args[1..];

    if (!common.isCompatibleBindTarget(vm, bind_target, method_obj.owner)) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "bind argument must be an instance of {s}",
            .{common.ownerDisplayName(method_obj.owner)},
        );
    }

    // Use the captured entry so we invoke the original implementation
    // even if the method was removed/redefined since the UnboundMethod was created.
    const captured_resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
    };
    return vm.invokeResolvedMethod(captured_resolved, bind_target, @constCast(call_args), block);
}

fn builtinUnboundMethodInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = unboundMethodObject(receiver);
    const owner_name = try common.ownerDisplayNameFull(vm, method_obj.owner);
    const text = std.fmt.allocPrint(
        vm.gc_allocator,
        "#<UnboundMethod: {s}#{s}>",
        .{ owner_name, method_obj.name.name },
    ) catch return error.Fatal;
    return try vm.newString(text, false);
}

fn builtinUnboundMethodEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isObject() or vm.getClass(other) != vm.unbound_method_class) {
        return Value.boolean(false);
    }

    const lhs = unboundMethodObject(receiver);
    const rhs = unboundMethodObject(other);

    return Value.boolean(lhs.owner.raw == rhs.owner.raw and lhs.name == rhs.name);
}

fn builtinUnboundMethodSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = unboundMethodObject(receiver);
    const resolved = common.methodEntryForOwner(method_obj.owner, method_obj.name) orelse return Value.nil();
    return common.sourceLocationForResolvedMethod(vm, .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = resolved,
    });
}

pub fn createUnboundMethodObject(
    vm: *VM,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
) VMError!Value {
    return common.createUnboundMethodObject(vm, method_name, resolved, owner, .{
        .owner = &builtinUnboundMethodOwner,
        .arity = &builtinUnboundMethodArity,
        .parameters = &builtinUnboundMethodParameters,
        .bind = &builtinUnboundMethodBind,
        .bind_call = &builtinUnboundMethodBindCall,
        .inspect = &builtinUnboundMethodInspect,
        .equal = &builtinUnboundMethodEqual,
        .source_location = &builtinUnboundMethodSourceLocation,
    });
}
