const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.exception_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinExceptionInitialize, .{ .variadic = 0 }));

    const message_sym = try vm.intern("message");
    try vm.exception_class.module.methods.put(message_sym, value.MethodEntry.builtin(&builtinExceptionMessage, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.exception_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinExceptionMessage, .{ .exact = 0 }));

    const backtrace_sym = try vm.intern("backtrace");
    try vm.exception_class.module.methods.put(backtrace_sym, value.MethodEntry.builtin(&builtinExceptionBacktrace, .{ .exact = 0 }));

    const full_message_sym = try vm.intern("full_message");
    try vm.exception_class.module.methods.put(full_message_sym, value.MethodEntry.builtin(&builtinExceptionFullMessage, .{ .variadic = 0 }));

    try vm.system_exit_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinSystemExitInitialize, .{ .variadic = 0 }));

    const signo_sym = try vm.intern("signo");
    try vm.signal_exception_class.module.methods.put(signo_sym, value.MethodEntry.builtin(&builtinSignalExceptionSigno, .{ .exact = 0 }));

    const signm_sym = try vm.intern("signm");
    try vm.signal_exception_class.module.methods.put(signm_sym, value.MethodEntry.builtin(&builtinSignalExceptionSignm, .{ .exact = 0 }));

    const status_sym = try vm.intern("status");
    try vm.system_exit_class.module.methods.put(status_sym, value.MethodEntry.builtin(&builtinSystemExitStatus, .{ .exact = 0 }));

    const receiver_sym = try vm.intern("receiver");
    try vm.key_error_class.module.methods.put(receiver_sym, value.MethodEntry.builtin(&builtinKeyErrorReceiver, .{ .exact = 0 }));

    const key_sym = try vm.intern("key");
    try vm.key_error_class.module.methods.put(key_sym, value.MethodEntry.builtin(&builtinKeyErrorKey, .{ .exact = 0 }));

    const name_sym = try vm.intern("name");
    try vm.name_error_class.module.methods.put(name_sym, value.MethodEntry.builtin(&builtinNameErrorName, .{ .exact = 0 }));

    const path_sym = try vm.intern("path");
    try vm.load_error_class.module.methods.put(path_sym, value.MethodEntry.builtin(&builtinLoadErrorPath, .{ .exact = 0 }));

    const tag_sym = try vm.intern("tag");
    try vm.uncaught_throw_error_class.module.methods.put(tag_sym, value.MethodEntry.builtin(&builtinUncaughtThrowErrorTag, .{ .exact = 0 }));

    const value_sym = try vm.intern("value");
    try vm.uncaught_throw_error_class.module.methods.put(value_sym, value.MethodEntry.builtin(&builtinUncaughtThrowErrorValue, .{ .exact = 0 }));
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

pub fn builtinSignalExceptionSigno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const signo = try vm.getInstanceVariable(receiver, "@signo");
    if (!signo.isNil()) return signo;
    if (receiver.toExceptionObject().object.class == vm.interrupt_class) {
        return Value.integer(@intCast(@intFromEnum(std.posix.SIG.INT)));
    }
    return Value.nil();
}

pub fn builtinSignalExceptionSignm(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinExceptionMessage(vm, receiver, args, null);
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

pub fn builtinLoadErrorPath(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const exc = receiver.toExceptionObject();
    if (exc.path) |p| {
        return Value.fromObject(p);
    }
    return Value.nil();
}

pub fn builtinUncaughtThrowErrorTag(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@tag");
}

pub fn builtinUncaughtThrowErrorValue(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@value");
}
