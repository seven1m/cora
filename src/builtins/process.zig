const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const process_obj = Value.fromObject(vm.process_module);
    const process_singleton = try vm.getOrCreateSingletonClass(process_obj);

    const uid_sym = try vm.intern("uid");
    try process_singleton.module.methods.put(uid_sym, .{ .method = .{ .builtin = &builtinProcessUid } });

    const euid_sym = try vm.intern("euid");
    try process_singleton.module.methods.put(euid_sym, .{ .method = .{ .builtin = &builtinProcessEuid } });

    const pid_sym = try vm.intern("pid");
    try process_singleton.module.methods.put(pid_sym, .{ .method = .{ .builtin = &builtinProcessPid } });

    const wait_sym = try vm.intern("wait");
    try process_singleton.module.methods.put(wait_sym, .{ .method = .{ .builtin = &builtinProcessWait } });
}

pub fn builtinProcessUid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.uid is not implemented on Windows", .{});
    }

    const uid = std.posix.getuid();
    return Value.integer(@intCast(uid));
}

pub fn builtinProcessEuid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.euid is not implemented on Windows", .{});
    }

    const euid = std.posix.geteuid();
    return Value.integer(@intCast(euid));
}

pub fn builtinProcessPid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.pid is not implemented on Windows", .{});
    }

    return Value.integer(@intCast(std.c.getpid()));
}

pub fn builtinProcessWait(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.wait is not implemented on Windows", .{});
    }

    const wait_pid: i32 = if (args.len >= 1 and !args[0].isNil())
        @intCast(try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "pid out of range"))
    else
        -1;
    const flags: c_int = if (args.len >= 2)
        @intCast(try args[1].integerArgToI64(vm, "no implicit conversion into Integer", "flags out of range"))
    else
        0;

    var status: c_int = 0;
    const rc = std.c.waitpid(wait_pid, &status, flags);
    if (rc < 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "waitpid failed", .{});
    }
    return Value.integer(@intCast(rc));
}
