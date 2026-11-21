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

fn boundOwnerClass(vm: *VM, bind_target: Value, owner: Value) *common.ClassObject {
    if (owner.isModule()) return bind_target.getSingletonClass() orelse vm.getClass(bind_target);
    if (owner.isClass()) return owner.toClassObject();
    return vm.getClass(owner);
}

fn requireCompatibleBindTarget(vm: *VM, bind_target: Value, owner: Value) VMError!void {
    if (common.isCompatibleBindTarget(vm, bind_target, owner)) return;
    return vm.raiseExceptionFmt(
        vm.type_error_class,
        "bind argument must be an instance of {s}",
        .{common.ownerDisplayName(owner)},
    );
}

pub fn register(vm: *VM) !void {
    try common.registerUnboundMethodBuiltins(vm, .{
        .name = &builtinUnboundMethodName,
        .original_name = &builtinUnboundMethodOriginalName,
        .owner = &builtinUnboundMethodOwner,
        .arity = &builtinUnboundMethodArity,
        .parameters = &builtinUnboundMethodParameters,
        .bind = &builtinUnboundMethodBind,
        .bind_call = &builtinUnboundMethodBindCall,
        .inspect = &builtinUnboundMethodInspect,
        .equal = &builtinUnboundMethodEqual,
        .source_location = &builtinUnboundMethodSourceLocation,
    });
    try vm.unbound_method_class.module.methods.put(try vm.intern("super_method"), common.MethodEntry.builtin(&builtinUnboundMethodSuperMethod, .{ .exact = 0 }));
    const to_s_sym = try vm.intern("to_s");
    const inspect_entry = common.MethodEntry.builtin(&builtinUnboundMethodInspect, .{ .exact = 0 });
    try vm.unbound_method_class.module.methods.put(to_s_sym, inspect_entry);
}

fn createBoundMethodObject(
    vm: *VM,
    receiver: Value,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
) VMError!Value {
    return common.createBoundMethodObject(vm, receiver, method_name, resolved, owner);
}

fn builtinUnboundMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return unboundMethodObject(receiver).owner;
}

fn builtinUnboundMethodName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(&unboundMethodObject(receiver).name.object);
}

fn builtinUnboundMethodOriginalName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const method_obj = unboundMethodObject(receiver);
    const original_name = method_obj.entry.original_name orelse method_obj.name;
    return Value.fromObject(&original_name.object);
}

fn builtinUnboundMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return unboundMethodObject(receiver).arity;
}

fn builtinUnboundMethodParameters(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return common.parametersForMethod(vm, unboundMethodObject(receiver).entry.method);
}

fn builtinUnboundMethodBind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const method_obj = unboundMethodObject(receiver);
    const bind_target = args[0];

    try requireCompatibleBindTarget(vm, bind_target, method_obj.owner);

    // Use the captured entry so the bound method invokes the original
    // implementation even if the method was removed/redefined since capture.
    const captured_resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .defining_node = method_obj.defining_node,
        .owner_class = boundOwnerClass(vm, bind_target, method_obj.owner),
        .entry = method_obj.entry,
    };
    return createBoundMethodObject(vm, bind_target, method_obj.name, captured_resolved, method_obj.owner);
}

fn builtinUnboundMethodBindCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const method_obj = unboundMethodObject(receiver);
    const bind_target = args[0];
    const call_args = args[1..];

    try requireCompatibleBindTarget(vm, bind_target, method_obj.owner);
    const captured_resolved: vm_mod.ResolvedMethod = .{
        .name = method_obj.name,
        .defining_node = common.definingNodeForBind(vm, bind_target, method_obj.defining_node),
        .owner_class = boundOwnerClass(vm, bind_target, method_obj.owner),
        .entry = method_obj.entry,
    };
    return vm.invokeResolvedMethodWithKeywords(captured_resolved, bind_target, @constCast(call_args), block, vm.builtin_keyword_ctx);
}

fn builtinUnboundMethodInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const method_obj = unboundMethodObject(receiver);
    const owner_name = try common.ownerDisplayNameFull(vm, method_obj.owner);
    const original_name = method_obj.entry.original_name;
    const text = if (original_name != null and original_name.? != method_obj.name)
        std.fmt.allocPrint(
            vm.gc_allocator,
            "#<UnboundMethod: {s}#{s}({s})>",
            .{ owner_name, method_obj.name.name, original_name.?.name },
        ) catch return error.Fatal
    else
        std.fmt.allocPrint(
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

    return Value.boolean(lhs.owner.raw == rhs.owner.raw and common.entriesHaveSameImplementation(lhs.entry, rhs.entry));
}

fn builtinUnboundMethodSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return common.sourceLocationForMethod(vm, unboundMethodObject(receiver).entry.method);
}

pub fn createUnboundMethodObject(
    vm: *VM,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
) VMError!Value {
    return common.createUnboundMethodObject(vm, method_name, resolved, owner);
}

fn builtinUnboundMethodSuperMethod(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const method_obj = receiver.toUnboundMethodObject();
    const node = method_obj.defining_node orelse return Value.nil();
    const name = method_obj.entry.original_name orelse method_obj.name;
    const resolved = vm.lookupMethodAfterNode(node, name) orelse return Value.nil();
    const owner = common.methodOwnerForResolved(resolved);
    return createUnboundMethodObject(vm, name, resolved, owner);
}
