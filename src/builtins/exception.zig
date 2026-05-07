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

    const backtrace_sym = try vm.intern("backtrace");
    try vm.exception_class.module.methods.put(backtrace_sym, .{ .method = .{ .builtin = &builtinExceptionBacktrace } });

    const full_message_sym = try vm.intern("full_message");
    try vm.exception_class.module.methods.put(full_message_sym, .{ .method = .{ .builtin = &builtinExceptionFullMessage } });

    try vm.system_exit_class.module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinSystemExitInitialize } });

    const status_sym = try vm.intern("status");
    try vm.system_exit_class.module.methods.put(status_sym, .{ .method = .{ .builtin = &builtinSystemExitStatus } });

    const receiver_sym = try vm.intern("receiver");
    try vm.key_error_class.module.methods.put(receiver_sym, .{ .method = .{ .builtin = &builtinKeyErrorReceiver } });

    const key_sym = try vm.intern("key");
    try vm.key_error_class.module.methods.put(key_sym, .{ .method = .{ .builtin = &builtinKeyErrorKey } });

    const name_sym = try vm.intern("name");
    try vm.name_error_class.module.methods.put(name_sym, .{ .method = .{ .builtin = &builtinNameErrorName } });
}

pub fn builtinExceptionInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const exc = receiver.toExceptionObject();
    const message = if (args.len == 1)
        try args[0].coerceToStr(vm, "no implicit conversion into String")
    else
        vm.className(receiver);
    const msg_val = try vm.newString(message, false);
    exc.message = msg_val.toStringObject();
    return receiver;
}

pub fn builtinSystemExitInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    const exc = receiver.toExceptionObject();
    var status: i64 = 0;
    var message: []const u8 = vm.className(receiver);

    switch (args.len) {
        0 => {},
        1 => {
            if (args[0].isString()) {
                message = try args[0].coerceToStr(vm, "no implicit conversion into String");
            } else if (args[0].isBool()) {
                status = if (args[0].toBool()) 0 else 1;
            } else {
                status = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range");
            }
        },
        2 => {
            if (args[0].isBool()) {
                status = if (args[0].toBool()) 0 else 1;
            } else {
                status = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "integer out of range");
            }
            message = try args[1].coerceToStr(vm, "no implicit conversion into String");
        },
        else => unreachable,
    }

    const msg_val = try vm.newString(message, false);
    exc.message = msg_val.toStringObject();
    try vm.setInstanceVariable(receiver, "@status", Value.integer(status));
    return receiver;
}

pub fn builtinExceptionMessage(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.toExceptionObject();
    return Value.fromObject(exc.message);
}

pub fn builtinExceptionBacktrace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.toExceptionObject();
    if (exc.backtrace) |backtrace| {
        return Value.fromObject(backtrace);
    }
    return Value.nil();
}

pub fn builtinExceptionFullMessage(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.exceptionFullMessage(receiver.toExceptionObject());
}

pub fn builtinSystemExitStatus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const status = try vm.getInstanceVariable(receiver, "@status");
    if (status.isNil()) return Value.integer(0);
    return status;
}

pub fn builtinKeyErrorReceiver(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.toExceptionObject();
    return exc.receiver orelse Value.nil();
}

pub fn builtinKeyErrorKey(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const exc = receiver.toExceptionObject();
    return exc.key orelse Value.nil();
}

pub fn builtinNameErrorName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@name");
}
