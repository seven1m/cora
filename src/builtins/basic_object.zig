const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.basic_object_class.module.methods.put(initialize_sym, .{
        .method = .{ .builtin = &builtinBasicObjectInitialize },
        .visibility = .private,
    });

    const op_equal_sym = try vm.intern("==");
    try vm.basic_object_class.module.methods.put(op_equal_sym, .{ .method = .{ .builtin = &builtinBasicObjectEqual } });

    const equal_sym = try vm.intern("equal?");
    try vm.basic_object_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinBasicObjectEqual } });

    const not_equal_sym = try vm.intern("!=");
    try vm.basic_object_class.module.methods.put(not_equal_sym, .{ .method = .{ .builtin = &builtinBasicObjectNotEqual } });

    const not_sym = try vm.intern("!");
    try vm.basic_object_class.module.methods.put(not_sym, .{ .method = .{ .builtin = &builtinBasicObjectNot } });

    const method_missing_sym = try vm.intern("method_missing");
    try vm.basic_object_class.module.methods.put(method_missing_sym, .{
        .method = .{ .builtin = &builtinBasicObjectMethodMissing },
        .visibility = .private,
    });
}

pub fn builtinBasicObjectInitialize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.nil();
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
        return vm.raiseExceptionFmt(
            vm.no_method_error_class,
            "undefined method '{s}' for {s}",
            .{ sym.name, vm.getClass(receiver).module.name.name },
        );
    }
    unreachable;
}
