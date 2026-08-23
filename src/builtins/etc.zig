const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const etc_name_sym = try vm.intern("Etc");
    const etc_val = try vm.newModule(etc_name_sym);
    const etc_singleton = try vm.getOrCreateSingletonClass(etc_val);
    vm.object_class.module.constants.put(etc_name_sym, .{ .value = etc_val }) catch return error.Fatal;

    const nprocessors_sym = try vm.intern("nprocessors");
    try etc_singleton.module.methods.put(nprocessors_sym, value.MethodEntry.builtin(&builtinEtcNprocessors, .{ .exact = 0 }));

    const getlogin_sym = try vm.intern("getlogin");
    try etc_singleton.module.methods.put(getlogin_sym, value.MethodEntry.builtin(&builtinEtcGetlogin, .{ .exact = 0 }));

    const uname_sym = try vm.intern("uname");
    try etc_singleton.module.methods.put(uname_sym, value.MethodEntry.builtin(&builtinEtcUname, .{ .exact = 0 }));
}

fn builtinEtcNprocessors(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    // Use sysconf(_SC_NPROCESSORS_ONLN) on POSIX or GetSystemInfo on Windows
    const count: i64 = @intCast(std.Thread.getCpuCount() catch 1);
    return Value.integer(count);
}

extern "c" fn getlogin() ?[*:0]u8;

fn builtinEtcGetlogin(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const login = getlogin() orelse return Value.nil();
    const name = std.mem.span(login);
    return vm.newString(name, false);
}

fn builtinEtcUname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Etc.uname is not implemented on Windows", .{});
    }

    const uts = std.posix.uname();
    const fields = [_]struct { key: []const u8, bytes: []const u8 }{
        .{ .key = "sysname", .bytes = std.mem.sliceTo(&uts.sysname, 0) },
        .{ .key = "nodename", .bytes = std.mem.sliceTo(&uts.nodename, 0) },
        .{ .key = "release", .bytes = std.mem.sliceTo(&uts.release, 0) },
        .{ .key = "version", .bytes = std.mem.sliceTo(&uts.version, 0) },
        .{ .key = "machine", .bytes = std.mem.sliceTo(&uts.machine, 0) },
    };

    const hash = try vm.createHash();
    for (fields) |field| {
        const key = Value.fromObject(&(try vm.intern(field.key)).object);
        try vm.hashSetEntry(hash, key, try vm.newString(field.bytes, false));
    }
    return Value.fromObject(&hash.object);
}
