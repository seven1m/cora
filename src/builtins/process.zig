const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const process_obj = Value{ .data = .{ .module = vm.process_module } };
    const process_singleton = try vm.getOrCreateSingletonClass(process_obj);

    const uid_sym = try vm.intern("uid");
    try process_singleton.module.methods.put(uid_sym, .{ .method = .{ .builtin = &builtinProcessUid } });

    const euid_sym = try vm.intern("euid");
    try process_singleton.module.methods.put(euid_sym, .{ .method = .{ .builtin = &builtinProcessEuid } });
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
