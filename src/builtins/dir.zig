const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ArrayObject = value.ArrayObject;

const FNM_NOESCAPE: i64 = 0x01;
const FNM_DOTMATCH: i64 = 0x04;

const GlobFlags = struct {
    dotmatch: bool = false,
    noescape: bool = false,
};

const GlobKeywords = struct {
    base: ?[]const u8 = null,
    sort: bool = true,
};

const GlobContext = struct {
    vm: *VM,
    matches: *std.ArrayList([]u8),
    flags: GlobFlags,
    base_abs: []const u8,
    return_relative: bool,
};

fn passwdDir(passwd: *const std.c.passwd) ?[]const u8 {
    const dir_z = passwd.dir orelse return null;
    return std.mem.span(dir_z);
}

fn homeFromPasswdByUid(vm: *VM) VMError!?[]const u8 {
    const passwd = std.c.getpwuid(std.c.getuid()) orelse return null;
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
    const home_z = std.c.getenv("HOME") orelse {
        return (try homeFromPasswdByUid(vm)) orelse vm.raiseExceptionFmt(
            vm.argument_error_class,
            "couldn't find HOME environment -- expanding `~'",
            .{},
        );
    };
    const home = std.mem.span(home_z);
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
    try dir_singleton.module.methods.put(pwd_sym, value.MethodEntry.builtin(&builtinDirPwd, .{ .exact = 0 }));

    const home_sym = try vm.intern("home");
    try dir_singleton.module.methods.put(home_sym, value.MethodEntry.builtin(&builtinDirHome, .{ .variadic = 0 }));

    const chdir_sym = try vm.intern("chdir");
    try dir_singleton.module.methods.put(chdir_sym, value.MethodEntry.builtin(&builtinDirChdir, .{ .variadic = 0 }));

    const mkdir_sym = try vm.intern("mkdir");
    try dir_singleton.module.methods.put(mkdir_sym, value.MethodEntry.builtin(&builtinDirMkdir, .{ .variadic = 0 }));

    const glob_sym = try vm.intern("glob");
    try dir_singleton.module.methods.put(glob_sym, value.MethodEntry.builtin(&builtinDirGlob, .{ .variadic = 1 }));

    const bracket_sym = try vm.intern("[]");
    try dir_singleton.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinDirGlob, .{ .variadic = 0 }));
}

pub fn builtinDirPwd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.pwd is not implemented on Windows", .{});
    }

    const cwd = std.process.currentPathAlloc(vm.io, vm.allocator) catch return error.Fatal;
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
    const previous = std.process.currentPathAlloc(vm.io, vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(previous);
    const target_z = try vm.allocCStringZ(target);
    defer vm.allocator.free(target_z);

    const result = std.c.chdir(target_z.ptr);
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "No such file or directory @ dir_s_chdir - {s}", .{target});
    }

    if (block) |blk| {
        const previous_z = try vm.allocCStringZ(previous);
        defer vm.allocator.free(previous_z);
        defer _ = std.c.chdir(previous_z.ptr);
        const yielded = try vm.yieldToBlock(blk, &[_]Value{});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }

    return Value.integer(0);
}

pub fn builtinDirMkdir(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.mkdir is not implemented on Windows", .{});
    }

    const target = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const permissions: std.Io.File.Permissions = if (args.len == 2) blk: {
        const missing_msg = std.fmt.allocPrint(
            vm.gc_allocator,
            "no implicit conversion of {s} into Integer",
            .{vm.className(args[1])},
        ) catch return error.Fatal;
        const raw_mode = try args[1].coerceToI64ViaToInt(
            vm,
            missing_msg,
            "can't convert to Integer (to_int gives non-Integer)",
            "integer out of range",
        );
        if (raw_mode < 0) {
            return vm.raiseExceptionFmt(vm.range_error_class, "integer out of range", .{});
        }
        break :blk std.Io.File.Permissions.fromMode(@intCast(raw_mode));
    } else .default_dir;

    const target_z = try vm.allocCStringZ(target);
    defer vm.allocator.free(target_z);
    const result = std.c.mkdir(target_z.ptr, @as(std.c.mode_t, permissions.toMode()));
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "failed to create directory: {s}", .{target});
    }

    return Value.integer(0);
}

fn joinPathAlloc(allocator: std.mem.Allocator, left: []const u8, right: []const u8) ![]u8 {
    if (left.len == 0) return allocator.dupe(u8, right);
    if (right.len == 0) return allocator.dupe(u8, left);
    if (std.mem.eql(u8, left, "/")) return std.fmt.allocPrint(allocator, "/{s}", .{right});
    if (left[left.len - 1] == '/') return std.fmt.allocPrint(allocator, "{s}{s}", .{ left, right });
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ left, right });
}

fn currentWorkingDir(vm: *VM) VMError![]u8 {
    const cwd = std.process.currentPathAlloc(vm.io, vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(cwd);
    return vm.allocator.dupe(u8, cwd) catch return error.Fatal;
}

fn normalizeAbsolutePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or path[0] != '/') return error.InvalidArgument;

    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(allocator);

    var start: usize = 1;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and path[end] != '/') : (end += 1) {}
        const segment = path[start..end];
        if (segment.len != 0 and !std.mem.eql(u8, segment, ".")) {
            if (std.mem.eql(u8, segment, "..")) {
                if (segments.items.len > 0) _ = segments.pop();
            } else {
                segments.append(allocator, segment) catch return error.OutOfMemory;
            }
        }
        start = end + 1;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    out.append(allocator, '/') catch return error.OutOfMemory;
    for (segments.items, 0..) |segment, idx| {
        if (idx != 0) out.append(allocator, '/') catch return error.OutOfMemory;
        out.appendSlice(allocator, segment) catch return error.OutOfMemory;
    }
    return allocator.dupe(u8, out.items);
}

fn absolutePathAlloc(vm: *VM, path: []const u8) VMError![]u8 {
    if (path.len != 0 and path[0] == '/') {
        return normalizeAbsolutePathAlloc(vm.allocator, path) catch return error.Fatal;
    }

    const cwd = try currentWorkingDir(vm);
    defer vm.allocator.free(cwd);
    const joined = joinPathAlloc(vm.allocator, cwd, path) catch return error.Fatal;
    defer vm.allocator.free(joined);
    return normalizeAbsolutePathAlloc(vm.allocator, joined) catch return error.Fatal;
}

fn hasMeta(pattern: []const u8, noescape: bool) bool {
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        if (!noescape and pattern[i] == '\\' and i + 1 < pattern.len) {
            i += 1;
            continue;
        }
        switch (pattern[i]) {
            '*', '?', '[', '{' => return true,
            else => {},
        }
    }
    return false;
}

fn splitPatternSegmentsAlloc(allocator: std.mem.Allocator, pattern: []const u8) !std.ArrayList([]const u8) {
    var segments: std.ArrayList([]const u8) = .empty;
    errdefer segments.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;
    while (i <= pattern.len) : (i += 1) {
        if (i == pattern.len or pattern[i] == '/') {
            try segments.append(allocator, pattern[start..i]);
            start = i + 1;
        }
    }
    return segments;
}

fn compactRecursiveSegmentsAlloc(allocator: std.mem.Allocator, segments: []const []const u8) !std.ArrayList([]const u8) {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);

    var previous_recursive = false;
    for (segments) |segment| {
        const recursive = std.mem.eql(u8, segment, "**");
        if (recursive and previous_recursive) continue;
        try out.append(allocator, segment);
        previous_recursive = recursive;
    }
    return out;
}

fn containsNul(bytes: []const u8) bool {
    return std.mem.indexOfScalar(u8, bytes, 0) != null;
}

fn isDotLike(name: []const u8) bool {
    return std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..");
}

fn shouldRejectLeadingDot(name: []const u8, pattern: []const u8, flags: GlobFlags) bool {
    if (flags.dotmatch or name.len == 0 or name[0] != '.') return false;
    if (pattern.len != 0 and pattern[0] == '.') return false;
    if (std.mem.eql(u8, pattern, "**")) return true;
    return true;
}

fn matchCharClass(pattern: []const u8, index: *usize, byte: u8, noescape: bool) bool {
    var i = index.*;
    if (i >= pattern.len or pattern[i] != '[') return false;
    i += 1;

    var negate = false;
    if (i < pattern.len and (pattern[i] == '^' or pattern[i] == '!')) {
        negate = true;
        i += 1;
    }

    var matched = false;
    while (i < pattern.len and pattern[i] != ']') {
        var first = pattern[i];
        if (!noescape and first == '\\' and i + 1 < pattern.len) {
            i += 1;
            first = pattern[i];
        }

        if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
            var last = pattern[i + 2];
            if (!noescape and last == '\\' and i + 3 < pattern.len) {
                last = pattern[i + 3];
                i += 1;
            }
            if (first <= byte and byte <= last) matched = true;
            i += 3;
            continue;
        }

        if (first == byte) matched = true;
        i += 1;
    }

    if (i >= pattern.len or pattern[i] != ']') {
        index.* += 1;
        return pattern[index.* - 1] == byte;
    }

    index.* = i + 1;
    return if (negate) !matched else matched;
}

fn matchSegment(name: []const u8, pattern: []const u8, flags: GlobFlags) bool {
    if (shouldRejectLeadingDot(name, pattern, flags)) return false;

    return matchSegmentAt(name, 0, pattern, 0, flags);
}

fn matchSegmentAt(name: []const u8, name_idx: usize, pattern: []const u8, pattern_idx: usize, flags: GlobFlags) bool {
    var n = name_idx;
    var p = pattern_idx;

    while (true) {
        if (p == pattern.len) return n == name.len;
        const ch = pattern[p];

        switch (ch) {
            '*' => {
                var next_p = p + 1;
                while (next_p < pattern.len and pattern[next_p] == '*') : (next_p += 1) {}
                if (next_p == pattern.len) return true;
                var scan = n;
                while (scan <= name.len) : (scan += 1) {
                    if (matchSegmentAt(name, scan, pattern, next_p, flags)) return true;
                }
                return false;
            },
            '?' => {
                if (n == name.len) return false;
                n += 1;
                p += 1;
            },
            '[' => {
                if (n == name.len) return false;
                var class_idx = p;
                if (!matchCharClass(pattern, &class_idx, name[n], flags.noescape)) return false;
                n += 1;
                p = class_idx;
            },
            '\\' => {
                if (!flags.noescape and p + 1 < pattern.len) {
                    if (n == name.len or name[n] != pattern[p + 1]) return false;
                    n += 1;
                    p += 2;
                } else {
                    if (n == name.len or name[n] != '\\') return false;
                    n += 1;
                    p += 1;
                }
            },
            else => {
                if (n == name.len or name[n] != ch) return false;
                n += 1;
                p += 1;
            },
        }
    }
}

fn findClosingBrace(pattern: []const u8, open_idx: usize, noescape: bool) ?usize {
    var depth: usize = 0;
    var i = open_idx;
    while (i < pattern.len) : (i += 1) {
        const ch = pattern[i];
        if (!noescape and ch == '\\' and i + 1 < pattern.len) {
            i += 1;
            continue;
        }
        if (ch == '{') {
            depth += 1;
        } else if (ch == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn splitBraceAlternativesAlloc(allocator: std.mem.Allocator, inner: []const u8, noescape: bool) !std.ArrayList([]const u8) {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (parts.items) |part| allocator.free(part);
        parts.deinit(allocator);
    }

    var depth: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= inner.len) : (i += 1) {
        if (i == inner.len) {
            try parts.append(allocator, try allocator.dupe(u8, inner[start..i]));
            break;
        }

        const ch = inner[i];
        if (!noescape and ch == '\\' and i + 1 < inner.len) {
            i += 1;
            continue;
        }
        if (ch == '{') {
            depth += 1;
        } else if (ch == '}') {
            if (depth > 0) depth -= 1;
        } else if (ch == ',' and depth == 0) {
            try parts.append(allocator, try allocator.dupe(u8, inner[start..i]));
            start = i + 1;
        }
    }
    return parts;
}

fn expandBracesRec(allocator: std.mem.Allocator, pattern: []const u8, noescape: bool, out: *std.ArrayList([]u8)) !void {
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        if (!noescape and pattern[i] == '\\' and i + 1 < pattern.len) {
            i += 1;
            continue;
        }
        if (pattern[i] != '{') continue;

        const close_idx = findClosingBrace(pattern, i, noescape) orelse break;
        const prefix = pattern[0..i];
        const inner = pattern[i + 1 .. close_idx];
        const suffix = pattern[close_idx + 1 ..];
        var options = try splitBraceAlternativesAlloc(allocator, inner, noescape);
        defer {
            for (options.items) |opt| allocator.free(opt);
            options.deinit(allocator);
        }

        for (options.items) |opt| {
            const combined = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, opt, suffix });
            defer allocator.free(combined);
            try expandBracesRec(allocator, combined, noescape, out);
        }
        return;
    }

    try out.append(allocator, try allocator.dupe(u8, pattern));
}

fn expandBracesAlloc(allocator: std.mem.Allocator, pattern: []const u8, noescape: bool) !std.ArrayList([]u8) {
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }
    try expandBracesRec(allocator, pattern, noescape, &out);
    return out;
}

fn appendMatch(ctx: *GlobContext, rel_path: []const u8, absolute: bool, append_slash: bool) VMError!void {
    var out = if (absolute or !ctx.return_relative)
        ctx.vm.allocator.dupe(u8, rel_path) catch return error.Fatal
    else
        ctx.vm.allocator.dupe(u8, rel_path) catch return error.Fatal;

    if (append_slash and (out.len == 0 or out[out.len - 1] != '/')) {
        const with_slash = std.fmt.allocPrint(ctx.vm.allocator, "{s}/", .{out}) catch return error.Fatal;
        ctx.vm.allocator.free(out);
        out = with_slash;
    }
    ctx.matches.append(ctx.vm.allocator, out) catch return error.Fatal;
}

fn collectRecursiveDirs(ctx: *GlobContext, dir_abs: []const u8, rel_prefix: []const u8, segments: []const []const u8, next_idx: usize, directory_only: bool) VMError!void {
    try globWalk(ctx, dir_abs, rel_prefix, segments, next_idx, directory_only);

    var dir = std.Io.Dir.cwd().openDir(ctx.vm.io, dir_abs, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir or err == error.AccessDenied) return;
        return error.Fatal;
    };
    defer dir.close(ctx.vm.io);

    var iter = dir.iterate();
    while (iter.next(ctx.vm.io) catch return error.Fatal) |entry| {
        if (entry.kind != .directory) continue;
        if (isDotLike(entry.name)) continue;
        if (!ctx.flags.dotmatch and entry.name.len > 0 and entry.name[0] == '.') continue;

        const child_abs = joinPathAlloc(ctx.vm.allocator, dir_abs, entry.name) catch return error.Fatal;
        defer ctx.vm.allocator.free(child_abs);
        const child_rel = if (rel_prefix.len == 0)
            ctx.vm.allocator.dupe(u8, entry.name) catch return error.Fatal
        else
            joinPathAlloc(ctx.vm.allocator, rel_prefix, entry.name) catch return error.Fatal;
        defer ctx.vm.allocator.free(child_rel);
        try collectRecursiveDirs(ctx, child_abs, child_rel, segments, next_idx, directory_only);
    }
}

fn globWalk(ctx: *GlobContext, dir_abs: []const u8, rel_prefix: []const u8, segments: []const []const u8, seg_idx: usize, directory_only: bool) VMError!void {
    if (seg_idx >= segments.len) {
        if (directory_only) {
            const display = if (ctx.return_relative) rel_prefix else dir_abs;
            try appendMatch(ctx, display, !ctx.return_relative, true);
            return;
        }

        const display = if (ctx.return_relative) rel_prefix else dir_abs;
        if (display.len != 0) try appendMatch(ctx, display, !ctx.return_relative, false);
        return;
    }

    const segment = segments[seg_idx];
    if (segment.len == 0) {
        try globWalk(ctx, dir_abs, rel_prefix, segments, seg_idx + 1, directory_only);
        return;
    }

    if (std.mem.eql(u8, segment, "**")) {
        try collectRecursiveDirs(ctx, dir_abs, rel_prefix, segments, seg_idx + 1, directory_only);
        return;
    }

    var dir = std.Io.Dir.cwd().openDir(ctx.vm.io, dir_abs, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir or err == error.AccessDenied) return;
        return error.Fatal;
    };
    defer dir.close(ctx.vm.io);

    var iter = dir.iterate();
    while (iter.next(ctx.vm.io) catch return error.Fatal) |entry| {
        if (isDotLike(entry.name)) continue;
        if (!matchSegment(entry.name, segment, ctx.flags)) continue;

        const child_abs = joinPathAlloc(ctx.vm.allocator, dir_abs, entry.name) catch return error.Fatal;
        defer ctx.vm.allocator.free(child_abs);
        const child_rel = if (rel_prefix.len == 0)
            ctx.vm.allocator.dupe(u8, entry.name) catch return error.Fatal
        else
            joinPathAlloc(ctx.vm.allocator, rel_prefix, entry.name) catch return error.Fatal;
        defer ctx.vm.allocator.free(child_rel);

        if (seg_idx + 1 == segments.len) {
            if (directory_only and entry.kind != .directory) continue;
            const display = if (ctx.return_relative) child_rel else child_abs;
            try appendMatch(ctx, display, !ctx.return_relative, directory_only and entry.kind == .directory);
            continue;
        }

        if (entry.kind == .directory) {
            try globWalk(ctx, child_abs, child_rel, segments, seg_idx + 1, directory_only);
        }
    }
}

fn processPattern(ctx: *GlobContext, pattern: []const u8) VMError!void {
    if (pattern.len == 0) return;
    if (containsNul(pattern)) {
        return ctx.vm.raiseExceptionFmt(ctx.vm.argument_error_class, "nul-separated glob pattern", .{});
    }

    const absolute = pattern[0] == '/';
    const directory_only = pattern[pattern.len - 1] == '/';
    const trimmed = if (directory_only) pattern[0 .. pattern.len - 1] else pattern;
    if (trimmed.len == 0 and directory_only) return;

    const base_abs = if (absolute)
        ctx.vm.allocator.dupe(u8, "/") catch return error.Fatal
    else
        ctx.vm.allocator.dupe(u8, ctx.base_abs) catch return error.Fatal;
    defer ctx.vm.allocator.free(base_abs);

    const pattern_body = if (absolute) trimmed[1..] else trimmed;
    if (!hasMeta(pattern_body, ctx.flags.noescape) and std.mem.indexOfScalar(u8, pattern_body, '/') == null) {
        const candidate_abs = joinPathAlloc(ctx.vm.allocator, base_abs, pattern_body) catch return error.Fatal;
        defer ctx.vm.allocator.free(candidate_abs);
        const stat = std.Io.Dir.cwd().statFile(ctx.vm.io, candidate_abs, .{}) catch return;
        if (directory_only and stat.kind != .directory) return;
        if (!directory_only and stat.kind != .file and stat.kind != .directory) return;

        const display = if (absolute) candidate_abs else pattern_body;
        try appendMatch(ctx, display, absolute, directory_only and stat.kind == .directory);
        return;
    }

    var segments_list = splitPatternSegmentsAlloc(ctx.vm.allocator, pattern_body) catch return error.Fatal;
    defer segments_list.deinit(ctx.vm.allocator);
    var compact_segments = compactRecursiveSegmentsAlloc(ctx.vm.allocator, segments_list.items) catch return error.Fatal;
    defer compact_segments.deinit(ctx.vm.allocator);
    try globWalk(ctx, base_abs, "", compact_segments.items, 0, directory_only);
}

fn parseGlobFlags(vm: *VM, flags_value: ?Value) VMError!GlobFlags {
    if (flags_value == null) return .{};
    const val = flags_value.?;
    if (!val.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const bits = val.toInteger();
    return .{
        .dotmatch = (bits & FNM_DOTMATCH) != 0,
        .noescape = (bits & FNM_NOESCAPE) != 0,
    };
}

fn parseGlobKeywords(vm: *VM) VMError!GlobKeywords {
    var keywords: GlobKeywords = .{};
    if (try vm.consumeKeywordArg("base")) |base_val| {
        if (!base_val.isNil()) {
            keywords.base = try vm.coerceToPath(base_val, "no implicit conversion into String");
        }
    }
    if (try vm.consumeKeywordArg("sort")) |sort_val| {
        if (!sort_val.isBool()) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "expected true or false as sort: argument", .{});
        }
        keywords.sort = sort_val.toBool();
    }
    try vm.validateKeywordArgsConsumed();
    return keywords;
}

fn buildGlobResult(vm: *VM, matches: *ArrayObject, block: ?Block) VMError!Value {
    if (block) |blk| {
        for (matches.elements.items) |entry| {
            const yielded = try vm.yieldToBlock(blk, &[_]Value{entry});
            if (yielded.controlFlowValue()) |return_value| return return_value;
        }
        return Value.nil();
    }
    return Value.fromObject(matches);
}

pub fn builtinDirGlob(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "Dir.glob is not implemented on Windows", .{});
    }

    const keywords = try parseGlobKeywords(vm);
    const flags = try parseGlobFlags(vm, if (args.len == 2) args[1] else null);

    const base_abs = if (keywords.base) |base|
        absolutePathAlloc(vm, base) catch return error.Fatal
    else
        try currentWorkingDir(vm);
    defer vm.allocator.free(base_abs);

    var raw_matches: std.ArrayList([]u8) = .empty;
    defer {
        for (raw_matches.items) |entry| vm.allocator.free(entry);
        raw_matches.deinit(vm.allocator);
    }

    var ctx = GlobContext{
        .vm = vm,
        .matches = &raw_matches,
        .flags = flags,
        .base_abs = base_abs,
        .return_relative = true,
    };

    if (args[0].isArray()) {
        for (args[0].toArrayObject().elements.items) |pattern_val| {
            const pattern = try vm.coerceToPath(pattern_val, "no implicit conversion into String");
            var expanded = expandBracesAlloc(vm.allocator, pattern, flags.noescape) catch return error.Fatal;
            defer {
                for (expanded.items) |item| vm.allocator.free(item);
                expanded.deinit(vm.allocator);
            }
            for (expanded.items) |expanded_pattern| {
                try processPattern(&ctx, expanded_pattern);
            }
        }
    } else {
        const pattern = try vm.coerceToPath(args[0], "no implicit conversion into String");
        var expanded = expandBracesAlloc(vm.allocator, pattern, flags.noescape) catch return error.Fatal;
        defer {
            for (expanded.items) |item| vm.allocator.free(item);
            expanded.deinit(vm.allocator);
        }
        for (expanded.items) |expanded_pattern| {
            try processPattern(&ctx, expanded_pattern);
        }
    }

    if (keywords.sort) {
        std.sort.block([]u8, raw_matches.items, {}, struct {
            fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
                return std.mem.order(u8, lhs, rhs) == .lt;
            }
        }.lessThan);
    }

    const result = try vm.createArray();
    for (raw_matches.items) |entry| {
        result.elements.append(vm.gc_allocator, try vm.newString(entry, false)) catch return error.Fatal;
    }
    return buildGlobResult(vm, result, block);
}
