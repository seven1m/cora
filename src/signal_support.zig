const std = @import("std");

pub const SignalInfo = struct {
    short_name: []const u8,
    full_name: []const u8,
    signo: c_int,
    can_trap: bool = true,
    ruby_reserved: bool = false,
    vm_default: bool = false,
};

fn signalInfo(
    comptime short_name: []const u8,
    comptime full_name: []const u8,
    comptime field_name: []const u8,
    comptime options: struct {
        can_trap: bool = true,
        ruby_reserved: bool = false,
        vm_default: bool = false,
    },
) ?SignalInfo {
    if (!@hasField(std.posix.SIG, field_name)) return null;
    return .{
        .short_name = short_name,
        .full_name = full_name,
        .signo = @intCast(@intFromEnum(@field(std.posix.SIG, field_name))),
        .can_trap = options.can_trap,
        .ruby_reserved = options.ruby_reserved,
        .vm_default = options.vm_default,
    };
}

pub fn infoByCanonicalName(name: []const u8) ?SignalInfo {
    if (std.mem.eql(u8, name, "EXIT")) {
        return .{
            .short_name = "EXIT",
            .full_name = "EXIT",
            .signo = 0,
            .vm_default = false,
        };
    }
    if (std.mem.eql(u8, name, "HUP")) return signalInfo("HUP", "SIGHUP", "HUP", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "INT")) return signalInfo("INT", "SIGINT", "INT", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "QUIT")) return signalInfo("QUIT", "SIGQUIT", "QUIT", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "ILL")) return signalInfo("ILL", "SIGILL", "ILL", .{ .ruby_reserved = true });
    if (std.mem.eql(u8, name, "ABRT")) return signalInfo("ABRT", "SIGABRT", "ABRT", .{});
    if (std.mem.eql(u8, name, "FPE")) return signalInfo("FPE", "SIGFPE", "FPE", .{ .ruby_reserved = true });
    if (std.mem.eql(u8, name, "KILL")) return signalInfo("KILL", "SIGKILL", "KILL", .{ .can_trap = false });
    if (std.mem.eql(u8, name, "BUS")) return signalInfo("BUS", "SIGBUS", "BUS", .{ .ruby_reserved = true });
    if (std.mem.eql(u8, name, "SEGV")) return signalInfo("SEGV", "SIGSEGV", "SEGV", .{ .ruby_reserved = true });
    if (std.mem.eql(u8, name, "PIPE")) return signalInfo("PIPE", "SIGPIPE", "PIPE", .{});
    if (std.mem.eql(u8, name, "ALRM")) return signalInfo("ALRM", "SIGALRM", "ALRM", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "TERM")) return signalInfo("TERM", "SIGTERM", "TERM", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "STOP")) return signalInfo("STOP", "SIGSTOP", "STOP", .{ .can_trap = false });
    if (std.mem.eql(u8, name, "CHLD")) return signalInfo("CHLD", "SIGCHLD", "CHLD", .{});
    if (std.mem.eql(u8, name, "VTALRM")) return signalInfo("VTALRM", "SIGVTALRM", "VTALRM", .{ .ruby_reserved = true });
    if (std.mem.eql(u8, name, "PROF")) return signalInfo("PROF", "SIGPROF", "PROF", .{});
    if (std.mem.eql(u8, name, "USR1")) return signalInfo("USR1", "SIGUSR1", "USR1", .{ .vm_default = true });
    if (std.mem.eql(u8, name, "USR2")) return signalInfo("USR2", "SIGUSR2", "USR2", .{ .vm_default = true });
    return null;
}

pub fn infoByName(name: []const u8) ?SignalInfo {
    const trimmed = if (std.mem.startsWith(u8, name, "SIG")) name[3..] else name;
    if (std.mem.eql(u8, trimmed, "IOT")) return infoByCanonicalName("ABRT");
    if (std.mem.eql(u8, trimmed, "CLD")) return infoByCanonicalName("CHLD");
    return infoByCanonicalName(trimmed);
}

pub fn infoByNumber(signo: c_int) ?SignalInfo {
    if (signo == 0) return infoByCanonicalName("EXIT");

    if (infoByCanonicalName("HUP")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("INT")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("QUIT")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("ILL")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("ABRT")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("FPE")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("KILL")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("BUS")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("SEGV")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("PIPE")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("ALRM")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("TERM")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("STOP")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("CHLD")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("VTALRM")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("PROF")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("USR1")) |info| if (info.signo == signo) return info;
    if (infoByCanonicalName("USR2")) |info| if (info.signo == signo) return info;
    return null;
}

pub fn fullName(signo: c_int) ?[]const u8 {
    return if (infoByNumber(signo)) |info| info.full_name else null;
}

pub fn shortName(signo: c_int) ?[]const u8 {
    return if (infoByNumber(signo)) |info| info.short_name else null;
}

pub fn isVmDefaultSignal(signo: c_int) bool {
    return if (infoByNumber(signo)) |info| info.vm_default else false;
}
