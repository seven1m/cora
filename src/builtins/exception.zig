const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const message_sym = try vm.intern("message");
    try vm.exception_class.module.methods.put(message_sym, .{ .method = .{ .builtin = &builtinExceptionMessage } });
}

pub fn builtinExceptionMessage(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.data.exception;
    return .{ .data = .{ .string = exc.message } };
}
