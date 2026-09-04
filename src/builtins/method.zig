const std = @import("std");
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

pub fn register(vm: *VM) !void {
    const inspect_sym = try vm.intern("inspect");
    const to_s_sym = try vm.intern("to_s");
    const inspect_entry = common.MethodEntry.builtin(&builtinMethodInspect, .{ .exact = 0 });
    try vm.method_class.module.methods.put(inspect_sym, inspect_entry);
    try vm.method_class.module.methods.put(to_s_sym, inspect_entry);
}

fn builtinMethodInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const text = std.fmt.allocPrint(vm.gc_allocator, "#<Method:0x{x}>", .{receiver.raw}) catch return error.Fatal;
    return vm.newString(text, false);
}

fn builtinMethodCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const method_obj = boundMethodObject(receiver);

    const resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
    };
    return vm.invokeResolvedMethod(resolved, method_obj.receiver, args, block);
}

fn builtinMethodEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isMethodObject()) return Value.boolean(false);

    return Value.boolean(common.boundMethodsEqual(boundMethodObject(receiver), boundMethodObject(other)));
}

fn builtinMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return boundMethodObject(receiver).owner;
}

fn builtinMethodReceiver(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return boundMethodObject(receiver).receiver;
}

fn builtinMethodName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(&boundMethodObject(receiver).name.object);
}

fn builtinMethodOriginalName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const method_obj = boundMethodObject(receiver);
    const original_name = method_obj.entry.original_name orelse method_obj.name;
    return Value.fromObject(&original_name.object);
}

fn builtinMethodToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return boundMethodObject(receiver).arity;
}

fn builtinMethodParameters(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = boundMethodObject(receiver);
    const resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
    };
    return common.parametersForResolvedMethod(vm, resolved);
}

fn builtinMethodUnbind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = boundMethodObject(receiver);
    const resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
    };
    return unbound_method.createUnboundMethodObject(vm, method_obj.name, resolved, method_obj.owner);
}

fn builtinMethodSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = boundMethodObject(receiver);
    const resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .owner_class = if (method_obj.owner.isClass()) method_obj.owner.toClassObject() else vm.getClass(method_obj.owner),
        .entry = method_obj.entry,
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
        .equal = &builtinMethodEqual,
        .name = &builtinMethodName,
        .original_name = &builtinMethodOriginalName,
        .owner = &builtinMethodOwner,
        .receiver = &builtinMethodReceiver,
        .to_proc = &builtinMethodToProc,
        .arity = &builtinMethodArity,
        .parameters = &builtinMethodParameters,
        .unbind = &builtinMethodUnbind,
        .source_location = &builtinMethodSourceLocation,
    });
}
