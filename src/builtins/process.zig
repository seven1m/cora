const std = @import("std");
const builtin = @import("builtin");
const signal_support = @import("../signal_support.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn getpgrp() std.c.pid_t;
extern "c" fn setsid() std.c.pid_t;
extern "c" fn chdir(path: [*:0]const u8) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;

pub fn register(vm: *VM) !void {
    const process_obj = Value.fromObject(&vm.process_module.object);
    const process_singleton = try vm.getOrCreateSingletonClass(process_obj);

    const uid_sym = try vm.intern("uid");
    try process_singleton.module.methods.put(uid_sym, value.MethodEntry.builtin(&builtinProcessUid, .{ .exact = 0 }));

    const euid_sym = try vm.intern("euid");
    try process_singleton.module.methods.put(euid_sym, value.MethodEntry.builtin(&builtinProcessEuid, .{ .exact = 0 }));

    const pid_sym = try vm.intern("pid");
    try process_singleton.module.methods.put(pid_sym, value.MethodEntry.builtin(&builtinProcessPid, .{ .exact = 0 }));

    const daemon_sym = try vm.intern("daemon");
    try process_singleton.module.methods.put(daemon_sym, value.MethodEntry.builtin(&builtinProcessDaemon, .{ .variadic = 0 }));

    const getpgrp_sym = try vm.intern("getpgrp");
    try process_singleton.module.methods.put(getpgrp_sym, value.MethodEntry.builtin(&builtinProcessGetpgrp, .{ .exact = 0 }));

    const clock_gettime_sym = try vm.intern("clock_gettime");
    try process_singleton.module.methods.put(clock_gettime_sym, value.MethodEntry.builtin(&builtinProcessClockGettime, .{ .variadic = 1 }));

    const wait_sym = try vm.intern("wait");
    try process_singleton.module.methods.put(wait_sym, value.MethodEntry.builtin(&builtinProcessWait, .{ .variadic = 0 }));

    const kill_sym = try vm.intern("kill");
    try process_singleton.module.methods.put(kill_sym, value.MethodEntry.builtin(&builtinProcessKill, .{ .variadic = 1 }));

    const detach_sym = try vm.intern("detach");
    try process_singleton.module.methods.put(detach_sym, value.MethodEntry.builtin(&builtinProcessDetach, .{ .exact = 1 }));

    const clock_realtime_sym = try vm.intern("CLOCK_REALTIME");
    try vm.process_module.constants.put(clock_realtime_sym, .{ .value = Value.integer(@intCast(@intFromEnum(std.posix.CLOCK.REALTIME))) });

    const clock_monotonic_sym = try vm.intern("CLOCK_MONOTONIC");
    try vm.process_module.constants.put(clock_monotonic_sym, .{ .value = Value.integer(@intCast(@intFromEnum(std.posix.CLOCK.MONOTONIC))) });

    const wnohang_sym = try vm.intern("WNOHANG");
    try vm.process_module.constants.put(wnohang_sym, .{ .value = Value.integer(std.posix.W.NOHANG) });
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
        const prefixed = if (std.mem.startsWith(u8, name, "SIG"))
            name
        else
            std.fmt.allocPrint(vm.gc_allocator, "SIG{s}", .{name}) catch return error.Fatal;
        return if (signal_support.infoByName(name)) |info|
            info.signo
        else
            vm.raiseExceptionFmt(vm.argument_error_class, "unsupported signal '{s}'", .{prefixed});
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into String", .{});
}

pub fn builtinProcessUid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.uid is not implemented on Windows", .{});
    }

    const uid = std.c.getuid();
    return Value.integer(@intCast(uid));
}

pub fn builtinProcessEuid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.euid is not implemented on Windows", .{});
    }

    const euid = std.c.geteuid();
    return Value.integer(@intCast(euid));
}

pub fn builtinProcessPid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.pid is not implemented on Windows", .{});
    }

    return Value.integer(@intCast(std.c.getpid()));
}

pub fn builtinProcessDaemon(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.daemon is not implemented on Windows", .{});
    }

    vm.setupOutput();
    if (vm.stdout) |out| _ = out.flush() catch {};
    if (vm.stderr) |err_out| _ = err_out.flush() catch {};

    const stay_in_dir = args.len >= 1 and args[0].is_truthy();
    const keep_stdio_open = args.len >= 2 and args[1].is_truthy();

    const fork_rc = std.c.fork();
    if (fork_rc < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "fork failed", .{});
    }
    if (fork_rc > 0) {
        std.c._exit(0);
    }

    if (setsid() < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "setsid failed", .{});
    }

    if (!stay_in_dir) {
        const root_path = try vm.allocCStringZ("/");
        defer vm.allocator.free(root_path);
        if (chdir(root_path.ptr) != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "chdir failed", .{});
        }
    }

    if (!keep_stdio_open) {
        const devnull_path = try vm.allocCStringZ("/dev/null");
        defer vm.allocator.free(devnull_path);
        const open_flags: std.c.O = .{ .ACCMODE = .RDWR };
        const devnull_fd = open(devnull_path.ptr, @bitCast(open_flags), @as(c_uint, 0));
        if (devnull_fd < 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "open failed", .{});
        }
        defer {
            if (devnull_fd > 2) _ = close(devnull_fd);
        }

        if (dup2(devnull_fd, 0) < 0 or dup2(devnull_fd, 1) < 0 or dup2(devnull_fd, 2) < 0) {
            return vm.raiseErrnoFmt(std.posix.errno(-1), "dup2 failed", .{});
        }
    }

    return Value.integer(0);
}

pub fn builtinProcessGetpgrp(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.getpgrp is not implemented on Windows", .{});
    }

    return Value.integer(@intCast(getpgrp()));
}

pub fn builtinProcessClockGettime(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.clock_gettime is not implemented on Windows", .{});
    }

    const clock_id_raw = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "clock id out of range");
    const clock_id: std.posix.CLOCK = if (clock_id_raw == @intFromEnum(std.posix.CLOCK.REALTIME))
        .REALTIME
    else if (clock_id_raw == @intFromEnum(std.posix.CLOCK.MONOTONIC))
        .MONOTONIC
    else
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid clock id", .{});

    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(clock_id, &timespec) != 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "clock_gettime failed", .{});
    }

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);

    if (args.len == 1) {
        const as_float = @as(f64, @floatFromInt(seconds)) + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
        return vm.newFloat(as_float);
    }

    const unit = args[1];
    if (!unit.isSymbol()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
    }

    const unit_name = unit.toSymbolObject().name;
    if (std.mem.eql(u8, unit_name, "float_second")) {
        const as_float = @as(f64, @floatFromInt(seconds)) + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
        return vm.newFloat(as_float);
    }
    if (std.mem.eql(u8, unit_name, "second")) {
        return Value.integer(seconds);
    }
    if (std.mem.eql(u8, unit_name, "millisecond")) {
        return Value.integer(seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000));
    }
    if (std.mem.eql(u8, unit_name, "microsecond")) {
        return Value.integer(seconds * 1_000_000 + @divTrunc(nanoseconds, 1_000));
    }
    if (std.mem.eql(u8, unit_name, "nanosecond")) {
        return Value.integer(seconds * 1_000_000_000 + nanoseconds);
    }

    return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
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
        return vm.raiseErrnoFmt(std.posix.errno(rc), "waitpid failed", .{});
    }
    if (rc == 0) return Value.nil();
    if (rc > 0) {
        try vm.setLastProcessStatusFromWaitStatus(status, rc);
    }
    return Value.integer(@intCast(rc));
}

pub fn builtinProcessDetach(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.detach is not implemented on Windows", .{});
    }

    const pid = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "pid out of range");

    const thread = try vm.newThreadUnstarted(vm.thread_class);
    const thread_val = Value.fromObject(&thread.object);

    const pid_value = Value.integer(pid);
    const block = Block{ .kind = .{ .builtin = &detachFunction } };
    var thread_args = [_]Value{pid_value};
    try vm.configureThread(thread, block, thread_args[0..]);
    try vm.startThread(thread);
    try vm.schedulerYield();

    return thread_val;
}

fn detachFunction(vm: *VM, args: []Value) VMError!Value {
    const pid = args[0];
    const process_val = Value.fromObject(&vm.process_module.object);
    var wait_args = [_]Value{pid};
    const wait_result = vm.callMethodByNameForwardingKeywords(process_val, "wait", wait_args[0..], null);
    if (wait_result) |_| {
        return vm.getGlobalValue("$?");
    } else |err| {
        if (err == error.Unwind and vm.pendingException() != null) {
            // ECHILD means no child to wait for; just return nil
            vm.setPendingException(null);
        }
        return Value.nil();
    }
}

pub fn builtinProcessKill(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.kill is not implemented on Windows", .{});
    }

    const signo = try signalArgToNumber(vm, args[0]);
    var delivered: i64 = 0;

    for (args[1..]) |pid_value| {
        const pid: i32 = @intCast(try pid_value.integerArgToI64(vm, "no implicit conversion into Integer", "pid out of range"));
        const rc = std.c.kill(pid, @enumFromInt(signo));
        if (rc != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(rc), "kill failed", .{});
        }
        delivered += 1;
    }

    return Value.integer(delivered);
}
