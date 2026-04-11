const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

fn passwdDir(passwd: *const std.c.passwd) ?[]const u8 {
    const dir_z = passwd.dir orelse return null;
    return std.mem.span(dir_z);
}

fn homeFromPasswdByUid(vm: *VM) VMError!?[]const u8 {
    const passwd = std.c.getpwuid(std.posix.getuid()) orelse return null;
    const dir = passwdDir(passwd) orelse return null;
    if (!std.fs.path.isAbsolute(dir)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return dir;
}

fn homeFromPasswdByName(vm: *VM, username: []const u8) VMError!?[]const u8 {
    const username_z = try vm.allocCStringZ(username);
    defer vm.allocator.free(username_z);

    const passwd = std.c.getpwnam(username_z.ptr) orelse return null;
    const dir = passwdDir(passwd) orelse return null;
    if (!std.fs.path.isAbsolute(dir)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return dir;
}

fn currentHome(vm: *VM) VMError![]const u8 {
    const home_z = std.posix.getenv("HOME") orelse {
        return (try homeFromPasswdByUid(vm)) orelse vm.raiseExceptionFmt(
            vm.argument_error_class,
            "couldn't find HOME environment -- expanding `~'",
            .{},
        );
    };
    const home = home_z[0..home_z.len];
    if (home.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "couldn't find HOME environment -- expanding `~'", .{});
    }
    if (!std.fs.path.isAbsolute(home)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "non-absolute home", .{});
    }
    return home;
}

pub fn register(vm: *VM) !void {
    const dir_val = Value.fromObject(vm.dir_class);
    const dir_singleton = try vm.getOrCreateSingletonClass(dir_val);

    const pwd_sym = try vm.intern("pwd");
    try dir_singleton.module.methods.put(pwd_sym, .{ .method = .{ .builtin = &builtinDirPwd } });

    const home_sym = try vm.intern("home");
    try dir_singleton.module.methods.put(home_sym, .{ .method = .{ .builtin = &builtinDirHome } });

    const chdir_sym = try vm.intern("chdir");
    try dir_singleton.module.methods.put(chdir_sym, .{ .method = .{ .builtin = &builtinDirChdir } });
}

pub fn builtinDirPwd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.pwd is not implemented on Windows", .{});
    }

    const cwd = std.process.getCwdAlloc(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(cwd);
    return try vm.newString(cwd, false);
}

pub fn builtinDirHome(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.home is not implemented on Windows", .{});
    }

    if (args.len == 1) {
        const requested_user = try args[0].coerceToStr(vm, "no implicit conversion into String");
        const home = (try homeFromPasswdByName(vm, requested_user)) orelse {
            return vm.raiseExceptionFmt(vm.argument_error_class, "user {s} doesn't exist", .{requested_user});
        };
        return try vm.newString(home, false);
    }

    return try vm.newString(try currentHome(vm), false);
}

pub fn builtinDirChdir(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.chdir is not implemented on Windows", .{});
    }

    const target = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const previous = std.process.getCwdAlloc(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(previous);

    std.posix.chdir(target) catch {
        return vm.raiseExceptionFmt(vm.io_error_class, "No such file or directory @ dir_s_chdir - {s}", .{target});
    };

    if (block) |blk| {
        defer std.posix.chdir(previous) catch {};
        const yielded = try vm.yieldToBlock(blk, &[_]Value{});
        if (yielded.break_occurred) return yielded.value;
        return yielded.value;
    }

    return Value.integer(0);
}
