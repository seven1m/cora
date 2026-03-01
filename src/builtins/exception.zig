const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.exception_class.module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinExceptionInitialize } });

    const message_sym = try vm.intern("message");
    try vm.exception_class.module.methods.put(message_sym, .{ .method = .{ .builtin = &builtinExceptionMessage } });
}

pub fn builtinExceptionInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const exc = receiver.toExceptionObject();
    const message = if (args.len == 1) try args[0].coerceToStr(vm, "no implicit conversion into String") else "";
    const msg_val = try vm.newString(message, false);
    exc.message = msg_val.toStringObject();
    return receiver;
}

pub fn builtinExceptionMessage(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.toExceptionObject();
    return Value.fromObject(exc.message);
}
