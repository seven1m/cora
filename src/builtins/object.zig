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
}

pub fn builtinObjectNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const class_ptr = receiver.data.class;
    const instance = try vm.newObjectForClass(class_ptr);

    // Call initialize if it exists
    const init_sym = try vm.intern("initialize");
    if (try vm.findMethod(instance, init_sym)) |_| {
        // Use callMethodByName which handles dispatch properly
        _ = try vm.callMethodByName(instance, "initialize", args, block);
    } else if (args.len != 0) {
        // No initialize method but arguments were passed
        try vm.requireArgCount(args, 0);
    }

    return instance;
}

pub fn builtinObjectObjectId(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const object_id: i64 = receiver.objectId();

    return Value{ .data = .{ .integer = object_id } };
}
