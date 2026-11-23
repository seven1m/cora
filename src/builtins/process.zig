const std = @import("std");
const builtin = @import("builtin");
const signal_support = @import("../signal_support.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const struct_builtin = @import("struct.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn clock_getres(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn getpgrp() std.c.pid_t;
extern "c" fn getpgid(pid: std.c.pid_t) std.c.pid_t;
extern "c" fn getpriority(which: c_int, who: c_int) c_int;
extern "c" fn setsid() std.c.pid_t;
extern "c" fn chdir(path: [*:0]const u8) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;

pub fn register(vm: *VM) !void {
    const process_obj = Value.fromObject(&vm.process_module.object);
    const process_singleton = try vm.getOrCreateSingletonClass(process_obj);

    try vm.setConstant(vm.process_module, try vm.intern("Status"), Value.fromObject(&vm.process_status_class.module.object));
    inline for (.{
        .{ "exitstatus", &statusExitstatus }, .{ "success?", &statusSuccess }, .{ "exited?", &statusExited },
        .{ "signaled?", &statusSignaled },    .{ "termsig", &statusTermsig },  .{ "pid", &statusPid },
        .{ "to_i", &statusToI },              .{ "to_s", &statusToS },         .{ "inspect", &statusInspect },
        .{ "stopped?", &statusStopped },      .{ "stopsig", &statusStopsig },  .{ "coredump?", &statusCoredump },
    }) |entry| try vm.process_status_class.module.methods.put(try vm.intern(entry[0]), value.MethodEntry.builtin(entry[1], .{ .exact = 0 }));
    try vm.process_status_class.module.methods.put(try vm.intern("=="), value.MethodEntry.builtin(&statusEqual, .{ .exact = 1 }));
    const status_singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.process_status_class.module.object));
    try status_singleton.module.methods.put(try vm.intern("wait"), value.MethodEntry.builtin(&statusWait, .{ .variadic = 0 }));
    try process_singleton.module.methods.put(try vm.intern("waitall"), value.MethodEntry.builtin(&processWaitall, .{ .exact = 0 }));

    var tms_members: [4]Value = undefined;
    for ([_][]const u8{ "utime", "stime", "cutime", "cstime" }, 0..) |name, index| {
        tms_members[index] = Value.fromObject(&(try vm.intern(name)).object);
    }
    const tms_class = try struct_builtin.builtinStructNew(vm, Value.fromObject(&vm.struct_class.module.object), &tms_members, null);
    try vm.setConstant(vm.process_module, try vm.intern("Tms"), tms_class);

    const uid_sym = try vm.intern("uid");
    try process_singleton.module.methods.put(uid_sym, value.MethodEntry.builtin(&builtinProcessUid, .{ .exact = 0 }));

    const euid_sym = try vm.intern("euid");
    try process_singleton.module.methods.put(euid_sym, value.MethodEntry.builtin(&builtinProcessEuid, .{ .exact = 0 }));

    const gid_sym = try vm.intern("gid");
    try process_singleton.module.methods.put(gid_sym, value.MethodEntry.builtin(&builtinProcessGid, .{ .exact = 0 }));

    const pid_sym = try vm.intern("pid");
    try process_singleton.module.methods.put(pid_sym, value.MethodEntry.builtin(&builtinProcessPid, .{ .exact = 0 }));

    const ppid_sym = try vm.intern("ppid");
    try process_singleton.module.methods.put(ppid_sym, value.MethodEntry.builtin(&builtinProcessPpid, .{ .exact = 0 }));

    const fork_sym = try vm.intern("_fork");
    try process_singleton.module.methods.put(fork_sym, value.MethodEntry.builtin(&builtinProcessForkRaw, .{ .exact = 0 }));

    const daemon_sym = try vm.intern("daemon");
    try process_singleton.module.methods.put(daemon_sym, value.MethodEntry.builtin(&builtinProcessDaemon, .{ .variadic = 0 }));

    const getpgrp_sym = try vm.intern("getpgrp");
    try process_singleton.module.methods.put(getpgrp_sym, value.MethodEntry.builtin(&builtinProcessGetpgrp, .{ .exact = 0 }));

    const getpgid_sym = try vm.intern("getpgid");
    try process_singleton.module.methods.put(getpgid_sym, value.MethodEntry.builtin(&builtinProcessGetpgid, .{ .exact = 1 }));

    const getpriority_sym = try vm.intern("getpriority");
    try process_singleton.module.methods.put(getpriority_sym, value.MethodEntry.builtin(&builtinProcessGetpriority, .{ .exact = 2 }));

    const warmup_sym = try vm.intern("warmup");
    try process_singleton.module.methods.put(warmup_sym, value.MethodEntry.builtin(&builtinProcessWarmup, .{ .exact = 0 }));

    const clock_gettime_sym = try vm.intern("clock_gettime");
    try process_singleton.module.methods.put(clock_gettime_sym, value.MethodEntry.builtin(&builtinProcessClockGettime, .{ .variadic = 1 }));

    const clock_getres_sym = try vm.intern("clock_getres");
    try process_singleton.module.methods.put(clock_getres_sym, value.MethodEntry.builtin(&builtinProcessClockGetres, .{ .variadic = 1 }));

    const wait_sym = try vm.intern("wait");
    const waitpid_sym = try vm.intern("waitpid");
    const wait_entry = value.MethodEntry.builtin(&builtinProcessWait, .{ .variadic = 0 });
    try process_singleton.module.methods.put(wait_sym, wait_entry);
    try process_singleton.module.methods.put(waitpid_sym, wait_entry);

    const last_status_sym = try vm.intern("last_status");
    try process_singleton.module.methods.put(last_status_sym, value.MethodEntry.builtin(&builtinProcessLastStatus, .{ .exact = 0 }));

    const kill_sym = try vm.intern("kill");
    try process_singleton.module.methods.put(kill_sym, value.MethodEntry.builtin(&builtinProcessKill, .{ .variadic = 1 }));

    const detach_sym = try vm.intern("detach");
    try process_singleton.module.methods.put(detach_sym, value.MethodEntry.builtin(&builtinProcessDetach, .{ .exact = 1 }));

    const spawn_sym = try vm.intern("spawn");
    try process_singleton.module.methods.put(spawn_sym, value.MethodEntry.keywordBuiltin(&builtinProcessSpawn, .{ .variadic = 1 }));

    const clock_realtime_sym = try vm.intern("CLOCK_REALTIME");
    try vm.process_module.constants.put(clock_realtime_sym, .{ .value = Value.integer(@intCast(@backingInt(std.posix.CLOCK.REALTIME))) });

    const clock_monotonic_sym = try vm.intern("CLOCK_MONOTONIC");
    try vm.process_module.constants.put(clock_monotonic_sym, .{ .value = Value.integer(@intCast(@backingInt(std.posix.CLOCK.MONOTONIC))) });

    const wnohang_sym = try vm.intern("WNOHANG");
    try vm.process_module.constants.put(wnohang_sym, .{ .value = Value.integer(std.posix.W.NOHANG) });

    const prio_process_sym = try vm.intern("PRIO_PROCESS");
    try vm.process_module.constants.put(prio_process_sym, .{ .value = Value.integer(0) });

    const prio_pgrp_sym = try vm.intern("PRIO_PGRP");
    try vm.process_module.constants.put(prio_pgrp_sym, .{ .value = Value.integer(1) });

    const prio_user_sym = try vm.intern("PRIO_USER");
    try vm.process_module.constants.put(prio_user_sym, .{ .value = Value.integer(2) });
}

pub fn builtinProcessForkRaw(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "fork is not implemented on Windows", .{});
    }
    const pid = std.c.fork();
    if (pid < 0) return vm.raiseErrnoFmt(std.posix.errno(pid), "fork failed", .{});
    return Value.integer(@intCast(pid));
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

pub fn builtinProcessGid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.gid is not implemented on Windows", .{});
    }

    const gid = std.c.getgid();
    return Value.integer(@intCast(gid));
}

pub fn builtinProcessPid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.pid is not implemented on Windows", .{});
    }

    return Value.integer(@intCast(std.c.getpid()));
}

pub fn builtinProcessPpid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.ppid is not implemented on Windows", .{});
    }

    return Value.integer(@intCast(std.c.getppid()));
}

pub fn builtinProcessDaemon(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.daemon is not implemented on Windows", .{});
    }

    vm.setupOutput();
    if (vm.stdout) |out| _ = out.flush() catch {};
    if (vm.stderr) |err_out| _ = err_out.flush() catch {};

    const stay_in_dir = args.len >= 1 and args[0].isTruthy();
    const keep_stdio_open = args.len >= 2 and args[1].isTruthy();

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

pub fn builtinProcessGetpgid(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.getpgid is not implemented on Windows", .{});
    }

    const pid_value = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "pid out of range");
    const pid: std.c.pid_t = @intCast(try pid_value.integerToI64(vm, "pid out of range"));
    const pgid = getpgid(pid);
    if (pgid < 0) return vm.raiseErrnoFmt(std.posix.errno(pgid), "getpgid failed", .{});
    return Value.integer(@intCast(pgid));
}

pub fn builtinProcessGetpriority(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.getpriority is not implemented on Windows", .{});
    }

    const which_value = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "which out of range");
    const who_value = try args[1].coerceToIntegerValue(vm, "no implicit conversion into Integer", "who out of range");
    const which: c_int = @intCast(try which_value.integerToI64(vm, "which out of range"));
    const who: c_int = @intCast(try who_value.integerToI64(vm, "who out of range"));

    std.c._errno().* = 0;
    const priority = getpriority(which, who);
    if (priority == -1 and std.c._errno().* != 0) {
        return vm.raiseErrnoFmt(@fromBackingInt(@intCast(std.c._errno().*)), "getpriority failed", .{});
    }
    return Value.integer(@intCast(priority));
}

pub fn builtinProcessWarmup(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return Value.boolean(true);
}

pub fn builtinProcessClockGettime(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.clock_gettime is not implemented on Windows", .{});
    }

    const clock_id_raw = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "clock id out of range");
    const clock_id: std.posix.CLOCK = if (clock_id_raw == @backingInt(std.posix.CLOCK.REALTIME))
        .REALTIME
    else if (clock_id_raw == @backingInt(std.posix.CLOCK.MONOTONIC))
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
    if (unit.isNil()) {
        const as_float = @as(f64, @floatFromInt(seconds)) + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
        return vm.newFloat(as_float);
    }
    if (!unit.isSymbol()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
    }

    const unit_name = unit.toSymbolObject().name;
    if (std.mem.eql(u8, unit_name, "float_second")) {
        const as_float = @as(f64, @floatFromInt(seconds)) + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
        return vm.newFloat(as_float);
    }
    if (std.mem.eql(u8, unit_name, "float_millisecond")) {
        const as_float = @as(f64, @floatFromInt(seconds)) * 1_000.0 + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000.0;
        return vm.newFloat(as_float);
    }
    if (std.mem.eql(u8, unit_name, "float_microsecond")) {
        const as_float = @as(f64, @floatFromInt(seconds)) * 1_000_000.0 + @as(f64, @floatFromInt(nanoseconds)) / 1_000.0;
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

pub fn builtinProcessClockGetres(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "Process.clock_getres is not implemented on Windows", .{});
    }

    const clock_id_raw = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "clock id out of range");
    const clock_id: std.posix.CLOCK = if (clock_id_raw == @backingInt(std.posix.CLOCK.REALTIME))
        .REALTIME
    else if (clock_id_raw == @backingInt(std.posix.CLOCK.MONOTONIC))
        .MONOTONIC
    else
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid clock id", .{});

    var timespec: std.posix.timespec = undefined;
    if (clock_getres(clock_id, &timespec) != 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "clock_getres failed", .{});
    }

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);
    const as_float = @as(f64, @floatFromInt(seconds)) + @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
    if (args.len == 1 or args[1].isNil()) return vm.newFloat(as_float);

    const unit = args[1];
    if (!unit.isSymbol()) return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
    const unit_name = unit.toSymbolObject().name;
    if (std.mem.eql(u8, unit_name, "float_second")) return vm.newFloat(as_float);
    if (std.mem.eql(u8, unit_name, "float_millisecond")) return vm.newFloat(as_float * 1_000.0);
    if (std.mem.eql(u8, unit_name, "float_microsecond")) return vm.newFloat(as_float * 1_000_000.0);
    if (std.mem.eql(u8, unit_name, "hertz")) return vm.newFloat(1.0 / as_float);
    if (std.mem.eql(u8, unit_name, "second")) return Value.integer(seconds);
    if (std.mem.eql(u8, unit_name, "millisecond")) return Value.integer(seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000));
    if (std.mem.eql(u8, unit_name, "microsecond")) return Value.integer(seconds * 1_000_000 + @divTrunc(nanoseconds, 1_000));
    if (std.mem.eql(u8, unit_name, "nanosecond")) return Value.integer(seconds * 1_000_000_000 + nanoseconds);
    return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected unit", .{});
}

pub const WaitResult = union(enum) {
    child: struct { pid: i64, status: c_int },
    not_ready,
    no_children,
};

pub fn waitForChild(vm: *VM, pid: i32, flags: c_int) VMError!WaitResult {
    var status: c_int = 0;
    while (true) {
        try vm.checkAsyncEvents();
        const rc = std.c.waitpid(pid, &status, flags);
        if (rc > 0) return .{ .child = .{ .pid = rc, .status = status } };
        if (rc == 0) return .not_ready;
        switch (std.posix.errno(rc)) {
            .INTR => {
                try vm.checkAsyncEvents();
                continue;
            },
            .CHILD => return .no_children,
            else => |errno_code| return vm.raiseErrnoFmt(errno_code, "waitpid failed", .{}),
        }
    }
}

fn waitArguments(vm: *VM, args: []Value) VMError!struct { pid: i32, flags: c_int } {
    try vm.requireArgCountRange(args, 0, 2);
    const pid = if (args.len > 0 and !args[0].isNil()) try args[0].coerceToI64ViaToInt(vm, "no implicit conversion into Integer", "to_int did not return Integer", "pid out of range") else -1;
    const flags = if (args.len > 1) try args[1].coerceToI64ViaToInt(vm, "no implicit conversion into Integer", "to_int did not return Integer", "flags out of range") else 0;
    return .{
        .pid = std.math.cast(i32, pid) orelse return vm.raiseExceptionFmt(vm.range_error_class, "pid out of range", .{}),
        .flags = std.math.cast(c_int, flags) orelse return vm.raiseExceptionFmt(vm.range_error_class, "flags out of range", .{}),
    };
}

pub fn builtinProcessWait(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try waitArguments(vm, args);
    return switch (try waitForChild(vm, options.pid, options.flags)) {
        .child => |child| blk: {
            try vm.setLastProcessStatusFromWaitStatus(child.status, child.pid);
            break :blk Value.integer(child.pid);
        },
        .not_ready => Value.nil(),
        .no_children => vm.raiseErrnoFmt(.CHILD, "No child processes", .{}),
    };
}

fn statusWait(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try waitArguments(vm, args);
    return switch (try waitForChild(vm, options.pid, options.flags)) {
        .child => |child| vm.newProcessStatus(child.status, child.pid),
        .not_ready => Value.nil(),
        // Ruby represents wait's ECHILD result with a status whose PID is -1.
        .no_children => vm.newProcessStatus(0, -1),
    };
}

fn processWaitall(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const results = try vm.createArray();
    while (true) {
        switch (try waitForChild(vm, -1, 0)) {
            .no_children => break,
            .not_ready => return error.Fatal,
            .child => |child| {
                const status = try vm.newProcessStatus(child.status, child.pid);
                try vm.setGlobal("$?", status);
                const pair = try vm.createArray();
                pair.elements.appendSlice(vm.gc_allocator, &.{ Value.integer(child.pid), status }) catch return error.Fatal;
                results.elements.append(vm.gc_allocator, Value.fromObject(&pair.object)) catch return error.Fatal;
            },
        }
    }
    return Value.fromObject(&results.object);
}

fn rawStatus(vm: *VM, receiver: Value) VMError!*value.ProcessStatusObject {
    if (!receiver.isProcessStatus()) return vm.raiseExceptionFmt(vm.type_error_class, "uninitialized Process::Status", .{});
    return receiver.toProcessStatusObject();
}

fn statusExitstatus(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const status = (try rawStatus(vm, receiver)).status;
    return if (processExited(status)) Value.integer((status >> 8) & 255) else Value.nil();
}
fn statusSuccess(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const result = try statusExitstatus(vm, receiver, &.{}, null);
    return if (result.isNil()) result else Value.boolean(result.toInteger() == 0);
}
fn statusExited(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(processExited((try rawStatus(vm, receiver)).status));
}
fn statusSignaled(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(processSignaled((try rawStatus(vm, receiver)).status));
}
fn statusTermsig(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const status = (try rawStatus(vm, receiver)).status;
    return if (processSignaled(status)) Value.integer(status & 127) else Value.nil();
}
fn statusPid(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.integer((try rawStatus(vm, receiver)).pid);
}
fn statusToI(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.integer((try rawStatus(vm, receiver)).status);
}
fn statusStopped(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(((try rawStatus(vm, receiver)).status & 255) == 127);
}
fn statusStopsig(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const status = (try rawStatus(vm, receiver)).status;
    return if ((status & 255) == 127) Value.integer((status >> 8) & 255) else Value.nil();
}
fn statusCoredump(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return Value.boolean(((try rawStatus(vm, receiver)).status & 128) != 0);
}
fn statusEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const status = (try rawStatus(vm, receiver)).status;
    const other = args[0];
    return Value.boolean(if (other.isProcessStatus()) status == other.toProcessStatusObject().status else other.isInteger() and status == other.toInteger());
}

pub fn builtinProcessLastStatus(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.getGlobalValue("$?");
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

    return thread_val;
}

const RedirectAction = struct {
    target_fd: i32,
    source_fd: i32, // -1 means close
};

pub fn builtinProcessSpawn(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountAtLeast(args, 1);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Process.spawn is not implemented on Windows", .{});
    }

    var chdir_value: ?Value = null;
    var pgroup_value: ?Value = null;
    try vm.consumeKeywordArgs(.{ "chdir", "pgroup" }, .{ &chdir_value, &pgroup_value });
    try vm.validateKeywordArgsConsumed();

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var arg_index: usize = 0;
    if (args.len > 0 and args[0].isHash()) {
        for (args[0].toHashObject().entries.items) |entry| {
            const key = try entry.key.coerceToStr(vm, "no implicit conversion into String");
            const value_bytes = try entry.value.coerceToStr(vm, "no implicit conversion into String");
            env_map.put(key, value_bytes) catch return error.Fatal;
        }
        arg_index = 1;
    }
    if (arg_index >= args.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given 0, expected 1+)", .{});
    }

    // Parse options hash from last positional arg if it's a hash and not the env hash
    var redirects: std.ArrayList(RedirectAction) = .empty;
    defer redirects.deinit(vm.allocator);

    const last_arg = args[args.len - 1];
    if (last_arg.isHash() and arg_index < args.len - 1) {
        const opts_hash = last_arg.toHashObject();
        for (opts_hash.entries.items) |entry| {
            const key = entry.key;
            const val = entry.value;

            // Extract chdir from positional options hash (also handled via keyword args)
            if (chdir_value == null and key.isSymbol()) {
                if (std.mem.eql(u8, key.toSymbolObject().name, "chdir")) {
                    chdir_value = val;
                    continue;
                }
            }

            if (key.isSymbol() and std.mem.eql(u8, key.toSymbolObject().name, "pgroup")) {
                pgroup_value = val;
                continue;
            }
            // Determine target fd(s) from key
            var targets: [2]i32 = .{ -1, -1 };
            var target_count: usize = 0;
            if (key.isSymbol()) {
                const name = key.toSymbolObject().name;
                if (std.mem.eql(u8, name, "in")) {
                    targets[0] = 0;
                    target_count = 1;
                } else if (std.mem.eql(u8, name, "out")) {
                    targets[0] = 1;
                    target_count = 1;
                } else if (std.mem.eql(u8, name, "err")) {
                    targets[0] = 2;
                    target_count = 1;
                }
            } else if (key.isArray()) {
                const arr = key.toArrayObject().elements.items;
                if (arr.len == 2 and arr[0].isSymbol() and arr[1].isSymbol()) {
                    const n0 = arr[0].toSymbolObject().name;
                    const n1 = arr[1].toSymbolObject().name;
                    if (std.mem.eql(u8, n0, "out") and std.mem.eql(u8, n1, "err")) {
                        targets[0] = 1;
                        targets[1] = 2;
                        target_count = 2;
                    }
                }
            }

            if (target_count == 0) continue;

            // Determine source fd from value
            var source_fd: i32 = -2; // -2 = not set, -1 = close
            if (val.isSymbol()) {
                const vname = val.toSymbolObject().name;
                if (std.mem.eql(u8, vname, "close")) {
                    source_fd = -1;
                } else if (std.mem.eql(u8, vname, "out")) {
                    source_fd = 1;
                } else if (std.mem.eql(u8, vname, "in")) {
                    source_fd = 0;
                } else if (std.mem.eql(u8, vname, "err")) {
                    source_fd = 2;
                }
            } else if (val.isIo()) {
                source_fd = val.toIoObject().fd;
            } else if (val.isArray()) {
                const arr = val.toArrayObject().elements.items;
                if (arr.len == 2 and arr[0].isSymbol() and arr[1].isSymbol() and
                    std.mem.eql(u8, arr[0].toSymbolObject().name, "child") and
                    std.mem.eql(u8, arr[1].toSymbolObject().name, "out"))
                {
                    source_fd = 1;
                }
            }

            if (source_fd == -2) continue;

            for (0..target_count) |ti| {
                redirects.append(vm.allocator, .{ .target_fd = targets[ti], .source_fd = source_fd }) catch return error.Fatal;
            }
        }
    }

    // Build command args
    var exec_path_str: []const u8 = undefined;
    var argv_builder: std.ArrayList([]const u8) = .empty;
    defer argv_builder.deinit(vm.allocator);

    const cmd_val = args[arg_index];
    if (cmd_val.isArray()) {
        const arr = cmd_val.toArrayObject();
        const end = if (arr.elements.items.len > 0 and arr.elements.items[arr.elements.items.len - 1].isHash())
            arr.elements.items.len - 1
        else
            arr.elements.items.len;
        for (0..end) |i| {
            argv_builder.append(vm.allocator, try arr.elements.items[i].coerceToStr(vm, "no implicit conversion into String")) catch return error.Fatal;
        }
        exec_path_str = argv_builder.items[0];
    } else {
        const command = try cmd_val.coerceToStr(vm, "no implicit conversion into String");
        // Determine positional arg count (excluding trailing options hash)
        var cmd_end = args.len;
        if (cmd_end > arg_index + 1 and args[cmd_end - 1].isHash()) {
            cmd_end -= 1;
        }
        if (arg_index + 1 == cmd_end) {
            // Single command string → shell mode
            exec_path_str = "/bin/sh";
            argv_builder.append(vm.allocator, "/bin/sh") catch return error.Fatal;
            argv_builder.append(vm.allocator, "-c") catch return error.Fatal;
            argv_builder.append(vm.allocator, command) catch return error.Fatal;
        } else {
            // Multiple positional args → array mode
            exec_path_str = command;
            var i = arg_index;
            while (i < cmd_end) : (i += 1) {
                argv_builder.append(vm.allocator, try args[i].coerceToStr(vm, "no implicit conversion into String")) catch return error.Fatal;
            }
        }
    }

    // Build null-terminated argv
    var arg_z_strings: std.ArrayList([:0]u8) = .empty;
    defer {
        for (arg_z_strings.items) |item| vm.allocator.free(item);
        arg_z_strings.deinit(vm.allocator);
    }
    var argv_ptrs: std.ArrayList(?[*:0]const u8) = .empty;
    defer argv_ptrs.deinit(vm.allocator);
    for (argv_builder.items) |arg| {
        const arg_z = try vm.allocCStringZ(arg);
        arg_z_strings.append(vm.allocator, arg_z) catch return error.Fatal;
        argv_ptrs.append(vm.allocator, arg_z.ptr) catch return error.Fatal;
    }
    argv_ptrs.append(vm.allocator, null) catch return error.Fatal;

    // Build null-terminated envp
    var env_strings: std.ArrayList([:0]u8) = .empty;
    defer {
        for (env_strings.items) |item| vm.allocator.free(item);
        env_strings.deinit(vm.allocator);
    }
    var envp_ptrs: std.ArrayList(?[*:0]const u8) = .empty;
    defer envp_ptrs.deinit(vm.allocator);
    {
        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const combined = std.fmt.allocPrint(vm.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch return error.Fatal;
            defer vm.allocator.free(combined);
            const z = try vm.allocCStringZ(combined);
            env_strings.append(vm.allocator, z) catch return error.Fatal;
            envp_ptrs.append(vm.allocator, z.ptr) catch return error.Fatal;
        }
    }
    envp_ptrs.append(vm.allocator, null) catch return error.Fatal;

    // Prepare chdir path for child
    var chdir_path: ?[]const u8 = null;
    if (chdir_value) |cd_val| {
        chdir_path = try vm.coerceToPath(cd_val, "no implicit conversion into String");
    }

    const path_z = try vm.resolveExecPathFromEnvMap(&env_map, exec_path_str);
    defer vm.allocator.free(path_z);

    vm.setupOutput();
    if (vm.stdout) |out| _ = out.flush() catch {};
    if (vm.stderr) |err_out| _ = err_out.flush() catch {};

    const process_group: ?i32 = if (pgroup_value) |group| blk: {
        if (!group.isTruthy()) break :blk null;
        if (group.isTrue()) break :blk 0;
        const integer = try group.coerceToI64ViaToInt(vm, "no implicit conversion into Integer", "to_int did not return Integer", "process group out of range");
        break :blk std.math.cast(i32, integer) orelse return vm.raiseExceptionFmt(vm.range_error_class, "process group out of range", .{});
    } else null;
    const pid = std.c.fork();
    if (pid < 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "fork failed", .{});
    }

    if (pid == 0) {
        if (process_group) |group| {
            if (std.c.setpgid(0, group) != 0) std.c._exit(127);
        }

        // Apply fd redirections
        for (redirects.items) |r| {
            if (r.source_fd == -1) {
                _ = std.c.close(@intCast(r.target_fd));
            } else if (r.source_fd != r.target_fd) {
                _ = dup2(r.source_fd, r.target_fd);
            }
        }

        if (chdir_path) |cp| {
            const cp_z = @as([*:0]u8, @ptrCast(std.c.malloc(cp.len + 1) orelse std.c._exit(127)));
            @memcpy(cp_z, cp);
            cp_z[cp.len] = 0;
            _ = std.c.chdir(cp_z);
            std.c.free(cp_z);
        }

        _ = execve(path_z.ptr, @ptrCast(argv_ptrs.items.ptr), @ptrCast(&envp_ptrs.items[0]));
        std.c._exit(127);
    }

    return Value.integer(@intCast(pid));
}

fn detachFunction(vm: *VM, args: []Value) VMError!Value {
    const pid = try args[0].integerArgToI64(vm, "no implicit conversion into Integer", "pid out of range");

    var status: c_int = 0;
    while (true) {
        const rc = std.c.waitpid(@intCast(pid), &status, std.posix.W.NOHANG);
        if (rc > 0) {
            try vm.setLastProcessStatusFromWaitStatus(status, rc);
            return vm.getGlobalValue("$?");
        }
        if (rc == 0) {
            // Park the waiter so an idle scheduler can sleep, while bounding
            // child-exit detection latency and still delivering async events.
            try vm.timedSleepCurrentThread(10);
            continue;
        }

        switch (std.posix.errno(rc)) {
            .INTR => {
                try vm.checkAsyncEvents();
                continue;
            },
            .CHILD => return Value.nil(),
            else => |errno_code| return vm.raiseErrnoFmt(errno_code, "waitpid failed", .{}),
        }
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
        const rc = std.c.kill(pid, @fromBackingInt(@intCast(signo)));
        if (rc != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(rc), "kill failed", .{});
        }
        delivered += 1;
    }

    try vm.checkAsyncEvents();
    return Value.integer(delivered);
}

fn processExited(wait_status: c_int) bool {
    return (wait_status & 0x7f) == 0;
}

fn processSignaled(wait_status: c_int) bool {
    const signal_bits = wait_status & 0x7f;
    return signal_bits != 0 and signal_bits != 0x7f;
}

fn statusDescription(vm: *VM, receiver: Value, inspect: bool) VMError!Value {
    const data = try rawStatus(vm, receiver);
    var output: std.Io.Writer.Allocating = .init(vm.allocator);
    defer output.deinit();
    if (inspect) output.writer.writeAll("#<Process::Status: ") catch return error.Fatal;
    output.writer.print("pid {d}", .{data.pid}) catch return error.Fatal;
    if ((data.status & 255) == 127) {
        const signal = (data.status >> 8) & 255;
        output.writer.writeAll(" stopped") catch return error.Fatal;
        if (signal_support.fullName(signal)) |name| output.writer.print(" {s}", .{name}) catch return error.Fatal;
        output.writer.print(" (signal {d})", .{signal}) catch return error.Fatal;
    } else if (processSignaled(data.status)) {
        const signal = data.status & 127;
        if (signal_support.fullName(signal)) |name| output.writer.print(" {s}", .{name}) catch return error.Fatal;
        output.writer.print(" (signal {d})", .{signal}) catch return error.Fatal;
    } else if (processExited(data.status)) output.writer.print(" exit {d}", .{(data.status >> 8) & 255}) catch return error.Fatal;
    if ((data.status & 128) != 0) output.writer.writeAll(" (core dumped)") catch return error.Fatal;
    if (inspect) output.writer.writeByte('>') catch return error.Fatal;
    return vm.newString(output.written(), false);
}
fn statusToS(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return statusDescription(vm, receiver, false);
}
fn statusInspect(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return statusDescription(vm, receiver, true);
}
