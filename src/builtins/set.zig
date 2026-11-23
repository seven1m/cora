const array_builtin = @import("array.zig");
const string_builtin = @import("string.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;
const Block = vm_mod.Block;

pub fn register(vm: *VM) !void {
    const entry = vm.object_class.module.constants.get(try vm.intern("Set")) orelse return error.Fatal;
    if (!entry.value.isClass()) return error.Fatal;
    const class = entry.value.toClassObject();
    const inspect = value.MethodEntry.builtin(&builtinSetInspect, .{ .exact = 0 });
    try class.module.methods.put(try vm.intern("inspect"), inspect);
    try class.module.methods.put(try vm.intern("to_s"), inspect);
    vm.bumpMethodStateVersion();
}

fn builtinSetInspect(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const result = try vm.newString(vm.className(receiver), false);
    if (try vm.enterRecursionGuard(.set_inspect, receiver, Value.nil())) {
        try string_builtin.appendEncodedBytes(vm, result.toStringObject(), "[...]", .{ .us_ascii = .{} });
        return result;
    }
    defer vm.leaveRecursionGuard(.set_inspect, receiver, Value.nil());

    const elements = try vm.callMethodByName(receiver, "to_a", &.{}, null);
    if (!elements.isArray()) return vm.raiseExceptionFmt(vm.type_error_class, "to_a did not return Array", .{});
    const inspected = (try array_builtin.builtinArrayInspect(vm, elements, &.{}, null)).toStringObject();
    try string_builtin.appendEncodedBytes(vm, result.toStringObject(), inspected.str, inspected.encoding);
    return result;
}
