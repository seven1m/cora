const std = @import("std");
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

    const trap_sym = try vm.intern("trap");
    try signal_singleton.module.methods.put(trap_sym, value.MethodEntry.builtin(&builtinSignalTrap, .{ .variadic = 1 }));
}

fn signalNumberFromName(name: []const u8) ?c_int {
    const trimmed = if (std.mem.startsWith(u8, name, "SIG")) name[3..] else name;

    if (std.mem.eql(u8, trimmed, "HUP") and @hasField(std.posix.SIG, "HUP")) return @intCast(@intFromEnum(std.posix.SIG.HUP));
    if (std.mem.eql(u8, trimmed, "INT")) return @intCast(@intFromEnum(std.posix.SIG.INT));
    if (std.mem.eql(u8, trimmed, "QUIT") and @hasField(std.posix.SIG, "QUIT")) return @intCast(@intFromEnum(std.posix.SIG.QUIT));
    if (std.mem.eql(u8, trimmed, "KILL") and @hasField(std.posix.SIG, "KILL")) return @intCast(@intFromEnum(std.posix.SIG.KILL));
    if (std.mem.eql(u8, trimmed, "TERM") and @hasField(std.posix.SIG, "TERM")) return @intCast(@intFromEnum(std.posix.SIG.TERM));
    if (std.mem.eql(u8, trimmed, "ALRM") and @hasField(std.posix.SIG, "ALRM")) return @intCast(@intFromEnum(std.posix.SIG.ALRM));
    if (std.mem.eql(u8, trimmed, "USR1") and @hasField(std.posix.SIG, "USR1")) return @intCast(@intFromEnum(std.posix.SIG.USR1));
    if (std.mem.eql(u8, trimmed, "USR2") and @hasField(std.posix.SIG, "USR2")) return @intCast(@intFromEnum(std.posix.SIG.USR2));
    return null;
}

fn signalArgToNumber(vm: *VM, signal_value: Value) VMError!c_int {
    if (signal_value.isInteger()) {
        return @intCast(try signal_value.integerArgToI64(vm, "no implicit conversion into Integer", "signal out of range"));
    }

    if (signal_value.isSymbol() or signal_value.isString()) {
        const name = if (signal_value.isSymbol())
            signal_value.toSymbolObject().name
        else
            signal_value.toStringObject().str;
        return signalNumberFromName(name) orelse vm.raiseExceptionFmt(vm.argument_error_class, "unsupported signal name", .{});
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into String", .{});
}

fn signalTrapActionValue(vm: *VM, mode: SignalTrapMode, callable: Value) VMError!Value {
    return switch (mode) {
        .default => vm.newString("DEFAULT", false),
        .ignore => vm.newString("IGNORE", false),
        .callable => callable,
    };
}

fn parseTrapAction(vm: *VM, args: []Value, block: ?Block) VMError!struct {
    mode: SignalTrapMode,
    callable: Value,
} {
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
    if (action.isProc()) {
        return .{ .mode = .callable, .callable = action };
    }

    if (action.isSymbol() or action.isString()) {
        const name = if (action.isSymbol())
            action.toSymbolObject().name
        else
            action.toStringObject().str;
        if (std.mem.eql(u8, name, "DEFAULT") or std.mem.eql(u8, name, "SYSTEM_DEFAULT") or std.mem.eql(u8, name, "SIG_DFL")) {
            return .{ .mode = .default, .callable = Value.nil() };
        }
        if (std.mem.eql(u8, name, "IGNORE") or std.mem.eql(u8, name, "SIG_IGN")) {
            return .{ .mode = .ignore, .callable = Value.nil() };
        }
        return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported signal handler", .{});
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "handler must be String, Symbol, or Proc", .{});
}

pub fn builtinSignalTrap(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const signo = try signalArgToNumber(vm, args[0]);
    const previous_mode = vm.signalTrapMode(signo);
    const previous_callable = vm.signalTrapCallable(signo);
    const next = try parseTrapAction(vm, args, block);

    try vm.setSignalTrap(signo, next.mode, next.callable);
    return signalTrapActionValue(vm, previous_mode, previous_callable);
}
