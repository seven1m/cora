const std = @import("std");
const signal_support = @import("../signal_support.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const SignalTrapMode = vm_mod.SignalTrapMode;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const signal_obj = Value.fromObject(&vm.signal_module.object);
    const signal_singleton = try vm.getOrCreateSingletonClass(signal_obj);

    const list_sym = try vm.intern("list");
    try signal_singleton.module.methods.put(list_sym, value.MethodEntry.builtin(&builtinSignalList, .{ .exact = 0 }));

    const signame_sym = try vm.intern("signame");
    try signal_singleton.module.methods.put(signame_sym, value.MethodEntry.builtin(&builtinSignalSigname, .{ .exact = 1 }));

    const trap_sym = try vm.intern("trap");
    try signal_singleton.module.methods.put(trap_sym, value.MethodEntry.builtin(&builtinSignalTrap, .{ .variadic = 1 }));
}

fn trapSignalTypeError(vm: *VM, signal_value: Value) VMError!c_int {
    return vm.raiseExceptionFmt(vm.argument_error_class, "bad signal type {s}", .{vm.className(signal_value)});
}

fn coerceSignalName(vm: *VM, signal_value: Value) VMError!?[]const u8 {
    if (signal_value.isSymbol()) return signal_value.toSymbolObject().name;
    if (signal_value.isString()) return signal_value.toStringObject().str;

    if (try vm.checkCallMethodByName(signal_value, "to_str", false, &.{}, null)) |coerced| {
        if (!coerced.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into String", .{vm.className(signal_value)});
        }
        return coerced.toStringObject().str;
    }

    return null;
}

fn unsupportedSignalName(vm: *VM, name: []const u8) VMError!c_int {
    const prefixed = if (std.mem.startsWith(u8, name, "SIG"))
        name
    else
        std.fmt.allocPrint(vm.gc_allocator, "SIG{s}", .{name}) catch return error.Fatal;
    return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported signal '{s}'", .{prefixed});
}

fn signalArgToNumber(vm: *VM, signal_value: Value) VMError!c_int {
    if (signal_value.isInteger()) {
        return @intCast(try signal_value.integerArgToI64(vm, "no implicit conversion into Integer", "signal out of range"));
    }

    const name = (try coerceSignalName(vm, signal_value)) orelse return trapSignalTypeError(vm, signal_value);
    return if (signal_support.infoByName(name)) |info|
        info.signo
    else
        unsupportedSignalName(vm, name);
}

fn signalTrapActionValue(vm: *VM, previous_mode: SignalTrapMode, previous_callable: Value, next_mode: SignalTrapMode) VMError!Value {
    if (previous_mode == .system_default) {
        return if (next_mode == .system_default)
            Value.nil()
        else
            vm.newString("SYSTEM_DEFAULT", false);
    }

    return switch (previous_mode) {
        .default => vm.newString("DEFAULT", false),
        .ignore => vm.newString("IGNORE", false),
        .ignore_nil => Value.nil(),
        .callable => previous_callable,
        .system_default => unreachable,
    };
}

fn parseTrapAction(vm: *VM, signo: c_int, args: []Value, block: ?Block) VMError!struct {
    mode: SignalTrapMode,
    callable: Value,
} {
    if (signo == 0) {
        if (block) |blk| {
            if (args.len != 1) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "signal handler argument conflicts with block", .{});
            }
            return .{ .mode = .callable, .callable = try vm.newProc(blk) };
        }

        if (args.len != 2) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "missing signal handler", .{});
        }

        if (args[1].isNil()) return .{ .mode = .system_default, .callable = Value.nil() };

        const name = try coerceSignalName(vm, args[1]);
        if (name) |handler_name| {
            if (std.mem.eql(u8, handler_name, "DEFAULT") or std.mem.eql(u8, handler_name, "SIG_DFL") or std.mem.eql(u8, handler_name, "SYSTEM_DEFAULT")) {
                return .{ .mode = .system_default, .callable = Value.nil() };
            }
            return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported signal handler", .{});
        }

        return .{ .mode = .callable, .callable = args[1] };
    }

    if (block) |blk| {
        if (args.len != 1) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "signal handler argument conflicts with block", .{});
        }
        return .{ .mode = .callable, .callable = try vm.newProc(blk) };
    }

    if (args.len != 2) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "missing signal handler", .{});
    }

    const action = args[1];
    if (action.isNil()) return .{ .mode = .ignore_nil, .callable = Value.nil() };

    const action_name = try coerceSignalName(vm, action);
    if (action_name) |name| {
        if (std.mem.eql(u8, name, "DEFAULT") or std.mem.eql(u8, name, "SYSTEM_DEFAULT") or std.mem.eql(u8, name, "SIG_DFL")) {
            return .{
                .mode = if (std.mem.eql(u8, name, "SYSTEM_DEFAULT")) .system_default else if (signal_support.isVmDefaultSignal(signo)) .default else .default,
                .callable = Value.nil(),
            };
        }
        if (std.mem.eql(u8, name, "IGNORE") or std.mem.eql(u8, name, "SIG_IGN")) {
            return .{ .mode = .ignore, .callable = Value.nil() };
        }
    }

    return .{ .mode = .callable, .callable = action };
}

fn signalListPut(vm: *VM, hash_obj: *value.HashObject, key: []const u8, number: c_int) VMError!void {
    const key_value = try vm.newString(key, false);
    try vm.hashSetEntry(hash_obj, key_value, Value.integer(number));
}

pub fn builtinSignalList(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const hash_obj = try vm.createHash();
    try signalListPut(vm, hash_obj, "EXIT", 0);
    if (signal_support.infoByCanonicalName("HUP")) |info| try signalListPut(vm, hash_obj, "HUP", info.signo);
    if (signal_support.infoByCanonicalName("INT")) |info| try signalListPut(vm, hash_obj, "INT", info.signo);
    if (signal_support.infoByCanonicalName("QUIT")) |info| try signalListPut(vm, hash_obj, "QUIT", info.signo);
    if (signal_support.infoByCanonicalName("ILL")) |info| try signalListPut(vm, hash_obj, "ILL", info.signo);
    if (signal_support.infoByCanonicalName("ABRT")) |info| {
        try signalListPut(vm, hash_obj, "ABRT", info.signo);
        try signalListPut(vm, hash_obj, "IOT", info.signo);
    }
    if (signal_support.infoByCanonicalName("FPE")) |info| try signalListPut(vm, hash_obj, "FPE", info.signo);
    if (signal_support.infoByCanonicalName("KILL")) |info| try signalListPut(vm, hash_obj, "KILL", info.signo);
    if (signal_support.infoByCanonicalName("BUS")) |info| try signalListPut(vm, hash_obj, "BUS", info.signo);
    if (signal_support.infoByCanonicalName("SEGV")) |info| try signalListPut(vm, hash_obj, "SEGV", info.signo);
    if (signal_support.infoByCanonicalName("PIPE")) |info| try signalListPut(vm, hash_obj, "PIPE", info.signo);
    if (signal_support.infoByCanonicalName("ALRM")) |info| try signalListPut(vm, hash_obj, "ALRM", info.signo);
    if (signal_support.infoByCanonicalName("TERM")) |info| try signalListPut(vm, hash_obj, "TERM", info.signo);
    if (signal_support.infoByCanonicalName("STOP")) |info| try signalListPut(vm, hash_obj, "STOP", info.signo);
    if (signal_support.infoByCanonicalName("CHLD")) |info| {
        try signalListPut(vm, hash_obj, "CHLD", info.signo);
        try signalListPut(vm, hash_obj, "CLD", info.signo);
    }
    if (signal_support.infoByCanonicalName("VTALRM")) |info| try signalListPut(vm, hash_obj, "VTALRM", info.signo);
    if (signal_support.infoByCanonicalName("PROF")) |info| try signalListPut(vm, hash_obj, "PROF", info.signo);
    if (signal_support.infoByCanonicalName("USR1")) |info| try signalListPut(vm, hash_obj, "USR1", info.signo);
    if (signal_support.infoByCanonicalName("USR2")) |info| try signalListPut(vm, hash_obj, "USR2", info.signo);
    return Value.fromObject(&hash_obj.object);
}

pub fn builtinSignalSigname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const signo = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "signal number out of range",
    );
    if (signo < std.math.minInt(c_int) or signo > std.math.maxInt(c_int)) return Value.nil();
    return if (signal_support.shortName(@intCast(signo))) |name|
        vm.newString(name, false)
    else
        Value.nil();
}

pub fn builtinSignalTrap(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const signo = try signalArgToNumber(vm, args[0]);
    const previous_mode = vm.signalTrapMode(signo);
    const previous_callable = vm.signalTrapCallable(signo);
    const next = try parseTrapAction(vm, signo, args, block);

    try vm.setSignalTrap(signo, next.mode, next.callable);
    return signalTrapActionValue(vm, previous_mode, previous_callable, next.mode);
}
