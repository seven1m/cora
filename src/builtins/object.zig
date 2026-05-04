const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const new_sym = try vm.intern("new");
    try vm.object_class.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinObjectNew } });

    const object_id_sym = try vm.intern("object_id");
    try vm.object_class.module.methods.put(object_id_sym, .{ .method = .{ .builtin = &builtinObjectObjectId } });

    const class_sym = try vm.intern("class");
    try vm.object_class.module.methods.put(class_sym, .{ .method = .{ .builtin = &builtinObjectClass } });

    const case_equal_sym = try vm.intern("===");
    try vm.object_class.module.methods.put(case_equal_sym, .{ .method = .{ .builtin = &builtinObjectCaseEqual } });
}

pub fn builtinObjectNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }
    const class_ptr = receiver.toClassObject();

    if (vm.isClassOrSubclassOf(class_ptr, vm.exception_class)) {
        return try vm.newExceptionInstance(class_ptr, args, block);
    }

    const instance = try vm.newObjectForClass(class_ptr);

    _ = try vm.callMethodByNameForwardingKeywords(instance, "initialize", args, block);

    return instance;
}

pub fn builtinObjectObjectId(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.objectIdValue(receiver);
}

pub fn builtinObjectClass(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.fromObject(vm.getClass(receiver));
}

pub fn builtinObjectCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return vm.callMethodByName(receiver, "==", args[0..1], null);
}
