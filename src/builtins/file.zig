const std = @import("std");
const builtin = @import("builtin");
const enc = @import("../encoding.zig");
const encoding_builtin = @import("encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const Encoding = enc.Encoding;

const null_device_path = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

fn openFlagValue(flags: std.posix.O) i64 {
    return @intCast(@as(c_int, @bitCast(flags)));
}

// ─── Native fnmatch ───────────────────────────────────────────────────────────
//
// Ported from MRI's dir.c.  Ruby defines its own stable FNM_* flag values and
// implements matching without calling the OS fnmatch(3), which avoids all
// platform-specific flag-value differences.
//
//   FNM_NOESCAPE = 0x01  disable '\' escaping
//   FNM_PATHNAME = 0x02  '*' and '?' do not match '/'
//   FNM_DOTMATCH = 0x04  '*'/'?' match a leading '.'
//   FNM_CASEFOLD = 0x08  case-insensitive (ASCII range)
//   FNM_EXTGLOB  = 0x10  enable {a,b,...} brace expansion
//
// These are the values Ruby exposes in File::FNM_* and expects back as flags.

/// Decode one UTF-8 codepoint at position i.  Invalid sequences fall back to
/// treating the byte as a Latin-1 codepoint (matches MRI's behaviour).
fn fnmDecodeChar(bytes: []const u8, i: usize) struct { cp: u21, len: usize } {
    if (i >= bytes.len) return .{ .cp = 0, .len = 0 };
    const seq_len = std.unicode.utf8ByteSequenceLength(bytes[i]) catch return .{ .cp = bytes[i], .len = 1 };
    if (i + seq_len > bytes.len) return .{ .cp = bytes[i], .len = 1 };
    const cp = std.unicode.utf8Decode(bytes[i .. i + seq_len]) catch return .{ .cp = bytes[i], .len = 1 };
    return .{ .cp = cp, .len = seq_len };
}

/// Advance past one UTF-8 character at position i.
fn fnmInc(bytes: []const u8, i: usize) usize {
    return i + fnmDecodeChar(bytes, i).len;
}

/// Apply FNM_CASEFOLD to a codepoint (ASCII range; non-ASCII passes through).
fn fnmUpper(cp: u21, nocase: bool) u21 {
    if (!nocase or cp > 127) return cp;
    return std.ascii.toUpper(@intCast(cp));
}

/// True if position i is "at the end" of s (end of string, or '/' in pathname mode).
inline fn fnmIsEnd(s: []const u8, i: usize, pathname: bool) bool {
    return i >= s.len or (pathname and s[i] == '/');
}

/// If escape mode is on and p[i] == '\\', return i+1; otherwise return i.
inline fn fnmUnescape(p: []const u8, i: usize, escape: bool) usize {
    if (escape and i < p.len and p[i] == '\\') return i + 1;
    return i;
}

/// Match string s[si..] against a bracket expression p[0..] where p starts
/// immediately after the opening '['.
/// Returns the index in p just past the closing ']' on a match, null otherwise.
fn fnmBracket(p: []const u8, s: []const u8, si: usize, flags: i64) ?usize {
    const nocase = (flags & 0x08) != 0;
    const escape = (flags & 0x01) == 0;
    var ok = false;
    var negate = false;
    var pi: usize = 0;

    if (pi >= p.len) return null;
    if (p[pi] == '!' or p[pi] == '^') {
        negate = true;
        pi += 1;
    }

    while (pi < p.len and p[pi] != ']') {
        // t1i: start of the pattern character (after any escape backslash)
        var t1i = pi;
        if (escape and t1i < p.len and p[t1i] == '\\') t1i += 1;
        if (t1i >= p.len) return null;

        const t1 = fnmDecodeChar(p, t1i);
        pi = t1i + t1.len;
        if (pi >= p.len) return null;

        if (p[pi] == '-' and pi + 1 < p.len and p[pi + 1] != ']') {
            // Range: [t1-t2]
            var t2i = pi + 1;
            if (escape and t2i < p.len and p[t2i] == '\\') t2i += 1;
            if (t2i >= p.len) return null;
            const t2 = fnmDecodeChar(p, t2i);
            pi = t2i + t2.len;

            if (ok) continue;

            // Byte-exact endpoint match (MRI checks this first)
            if (t1.len <= s.len - si and std.mem.eql(u8, p[t1i .. t1i + t1.len], s[si .. si + t1.len])) {
                ok = true;
                continue;
            }
            if (t2.len <= s.len - si and std.mem.eql(u8, p[t2i .. t2i + t2.len], s[si .. si + t2.len])) {
                ok = true;
                continue;
            }

            // Codepoint range check
            const sc = fnmUpper(fnmDecodeChar(s, si).cp, nocase);
            if (sc < fnmUpper(t1.cp, nocase)) continue;
            if (sc > fnmUpper(t2.cp, nocase)) continue;
        } else {
            if (ok) continue;

            // Byte-exact match
            if (t1.len <= s.len - si and std.mem.eql(u8, p[t1i .. t1i + t1.len], s[si .. si + t1.len])) {
                ok = true;
                continue;
            }
            if (!nocase) continue;

            // Case-insensitive codepoint match
            const sc = fnmUpper(fnmDecodeChar(s, si).cp, true);
            const pc = fnmUpper(t1.cp, true);
            if (sc != pc) continue;
        }
        ok = true;
    }

    if (pi >= p.len) return null; // unclosed '['
    return if (ok != negate) pi + 1 else null;
}

const FnmHelperResult = struct { pi: usize, si: usize, matched: bool };

/// Match string s[s_start..] against pattern p[p_start..] for one path segment.
/// Handles '*', '?', '[...]', ordinary chars, and backtracking across '*'.
/// Ported from MRI's fnmatch_helper().
fn fnmHelper(p: []const u8, p_start: usize, s: []const u8, s_start: usize, flags: i64) FnmHelperResult {
    const period = (flags & 0x04) == 0; // !FNM_DOTMATCH → leading '.' must match literally
    const pathname = (flags & 0x02) != 0;
    const escape = (flags & 0x01) == 0;
    const nocase = (flags & 0x08) != 0;

    var pi = p_start;
    var si = s_start;
    var ptmp: ?usize = null; // saved pattern position after last '*'
    var stmp: ?usize = null; // saved string position at last '*'

    // Leading period: if string starts with '.' the pattern must too.
    if (period and !fnmIsEnd(s, si, pathname) and s[si] == '.') {
        const ui = fnmUnescape(p, pi, escape);
        if (ui >= p.len or p[ui] != '.') {
            return .{ .pi = pi, .si = si, .matched = false };
        }
    }

    while (true) {
        // Each iteration tries to match one pattern element.  On success, `continue`
        // loops back to the top.  `break :step` falls through to backtracking.
        step: {
            const at_end = pi >= p.len or fnmIsEnd(p, pi, pathname);

            if (at_end) {
                // Pattern segment is done: match iff string segment is also done.
                if (fnmIsEnd(s, si, pathname)) {
                    return .{ .pi = pi, .si = si, .matched = true };
                }
                // String has more — try backtracking to last '*'.
                break :step;
            }

            switch (p[pi]) {
                '*' => {
                    // Consume all consecutive '*'.
                    while (pi < p.len and p[pi] == '*') pi += 1;
                    // '*' at end of segment matches the rest unconditionally.
                    const ui = fnmUnescape(p, pi, escape);
                    if (fnmIsEnd(p, ui, pathname)) {
                        pi = ui;
                        return .{ .pi = pi, .si = si, .matched = true };
                    }
                    if (fnmIsEnd(s, si, pathname)) break :step;
                    ptmp = pi;
                    stmp = si;
                    continue;
                },
                '?' => {
                    if (fnmIsEnd(s, si, pathname)) break :step;
                    pi += 1;
                    si = fnmInc(s, si);
                    continue;
                },
                '[' => {
                    if (fnmIsEnd(s, si, pathname)) break :step;
                    if (fnmBracket(p[pi + 1 ..], s, si, flags)) |bracket_end| {
                        pi = pi + 1 + bracket_end;
                        si = fnmInc(s, si);
                        continue;
                    }
                    break :step;
                },
                else => {
                    // Ordinary character (with possible backslash escape).
                    // MRI checks ISEND(s) first, then ISEND(p).
                    const ui = fnmUnescape(p, pi, escape);
                    if (fnmIsEnd(s, si, pathname)) {
                        // String ended: match iff pattern also ended here.
                        return .{ .pi = ui, .si = si, .matched = fnmIsEnd(p, ui, pathname) };
                    }
                    if (fnmIsEnd(p, ui, pathname)) break :step;
                    const pc = fnmDecodeChar(p, ui);
                    const sc = fnmDecodeChar(s, si);
                    if (pc.len <= s.len - si and
                        std.mem.eql(u8, p[ui .. ui + pc.len], s[si .. si + pc.len]))
                    {
                        pi = ui + pc.len;
                        si += pc.len;
                        continue;
                    }
                    if (nocase and fnmUpper(pc.cp, true) == fnmUpper(sc.cp, true)) {
                        pi = ui + pc.len;
                        si += sc.len;
                        continue;
                    }
                    break :step;
                },
            }
        }

        // `failed`: backtrack to the most recently saved '*' position.
        if (ptmp) |sp| {
            if (stmp) |ss| {
                pi = sp;
                si = fnmInc(s, ss);
                stmp = si;
                continue;
            }
        }
        return .{ .pi = pi, .si = si, .matched = false };
    }
}

/// Top-level match: handles FNM_PATHNAME (segment-by-segment) and `**/`.
/// Ported from MRI's fnmatch().
fn fnmMatch(pattern: []const u8, string: []const u8, flags: i64) bool {
    const pathname = (flags & 0x02) != 0;
    const period = (flags & 0x04) == 0;

    if (!pathname) {
        // Non-pathname mode: one call covers the whole string.
        // Note: fnmHelper returns matched=true when '*' exhausts the pattern even
        // if si hasn't reached string.len (because '*' matches the rest).  The
        // ordinary-character and bracket paths return matched based on fnmIsEnd(s),
        // so false positives from those paths are not possible.
        const r = fnmHelper(pattern, 0, string, 0, flags);
        return r.matched;
    }

    // Pathname mode: match segment by segment, with `**/` support.
    var pi: usize = 0;
    var si: usize = 0;
    var ptmp: ?usize = null; // pattern pos saved after last `**/`
    var stmp: ?usize = null; // string pos saved at last `**/`

    while (true) {
        // Consume any leading `**/` sequences and save as backtrack point.
        if (pi + 2 < pattern.len and
            pattern[pi] == '*' and pattern[pi + 1] == '*' and pattern[pi + 2] == '/')
        {
            while (pi + 2 < pattern.len and
                pattern[pi] == '*' and pattern[pi + 1] == '*' and pattern[pi + 2] == '/')
            {
                pi += 3;
            }
            ptmp = pi;
            stmp = si;
        }

        const r = fnmHelper(pattern, pi, string, si, flags);
        if (r.matched) {
            // Advance si to the segment boundary (in case '*' consumed past it)
            var new_si = r.si;
            while (new_si < string.len and string[new_si] != '/') {
                new_si = fnmInc(string, new_si);
            }
            const new_pi = r.pi;
            if (new_pi < pattern.len and new_si < string.len) {
                // Both have more segments: skip the '/' separators and continue.
                pi = new_pi + 1;
                si = new_si + 1;
                continue;
            }
            if (new_pi >= pattern.len and new_si >= string.len) {
                return true;
            }
            // One side ended but not the other → fall through to backtrack.
        }

        // Try backtracking to the last `**/` save point.
        if (ptmp != null and stmp != null) {
            var new_stmp = stmp.?;
            if (period and new_stmp < string.len and string[new_stmp] == '.') {
                return false;
            }
            // Advance stmp past the current path segment.
            while (new_stmp < string.len and string[new_stmp] != '/') {
                new_stmp = fnmInc(string, new_stmp);
            }
            if (new_stmp < string.len) {
                pi = ptmp.?;
                stmp = new_stmp + 1;
                si = new_stmp + 1;
                continue;
            }
        }
        return false;
    }
}

/// Expand `{a,b,...}` brace alternatives and return true if any expanded pattern
/// matches.  Handles nested braces via recursion.  Ported from MRI's
/// ruby_brace_expand() + fnmatch_brace().
fn fnmBraceMatch(pattern: []const u8, string: []const u8, flags: i64, allocator: std.mem.Allocator) std.mem.Allocator.Error!bool {
    const escape = (flags & 0x01) == 0;

    // Locate the outermost balanced { }.
    var lbrace: ?usize = null;
    var rbrace: ?usize = null;
    var nest: i32 = 0;
    var i: usize = 0;
    while (i < pattern.len) {
        if (pattern[i] == '{') {
            if (nest == 0) lbrace = i;
            nest += 1;
        } else if (pattern[i] == '}' and lbrace != null) {
            nest -= 1;
            if (nest == 0) {
                rbrace = i;
                break;
            }
        } else if (escape and pattern[i] == '\\') {
            i += 1;
            if (i >= pattern.len) break;
        }
        i = fnmInc(pattern, i);
    }

    if (lbrace == null or rbrace == null) {
        // No braces: plain match.
        return fnmMatch(pattern, string, flags);
    }

    const lb = lbrace.?;
    const rb = rbrace.?;
    const prefix = pattern[0..lb];
    const suffix = pattern[rb + 1 ..];

    // Iterate through comma-separated alternatives inside { }.
    var p: usize = lb + 1;
    while (p <= rb) {
        // Find the end of this alternative (next ',' or the closing '}').
        var end = p;
        var inner_nest: i32 = 0;
        while (end < rb) {
            if (pattern[end] == '{') inner_nest += 1;
            if (pattern[end] == '}') {
                if (inner_nest == 0) break;
                inner_nest -= 1;
            }
            if (pattern[end] == ',' and inner_nest == 0) break;
            if (escape and pattern[end] == '\\') {
                end += 1;
                if (end >= rb) break;
            }
            end = fnmInc(pattern, end);
        }

        const alt = pattern[p..end];
        const expanded = try std.mem.concat(allocator, u8, &.{ prefix, alt, suffix });
        defer allocator.free(expanded);

        // Recurse to handle nested braces in the expanded pattern.
        if (try fnmBraceMatch(expanded, string, flags, allocator)) return true;

        if (end >= rb) break;
        p = end + 1; // skip ','
    }

    return false;
}

const PosixStatMetadata = struct {
    uid: i64,
    gid: i64,
    mode: i64,
};

const linux_statx_request: std.os.linux.STATX = .{
    .MODE = true,
    .UID = true,
    .GID = true,
};

const linux_identical_statx_request: std.os.linux.STATX = .{
    .INO = true,
    .MNT_ID = true,
};

const FileIdentity = struct {
    inode: u64,
    mount_id: ?u64,
};

// callStat: thin wrapper around fstatat(AT_FDCWD, path, ..., 0) for non-Linux platforms.
// We use fstatat because std.c.stat isn't universally available in Zig 0.16.
fn callStat(path: [*:0]const u8, buf: *std.posix.Stat) c_int {
    const rc = std.posix.system.fstatat(std.posix.AT.FDCWD, path, buf, 0);
    // fstatat returns -1 on error (errno set) or 0 on success; return as c_int
    return @intCast(rc);
}

// fnmatch is implemented natively below; no OS fnmatch(3) needed.
extern fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;

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

const FileMode = struct {
    read: bool,
    write: bool,
    append: bool,
    create: bool,
    truncate: bool,
};

pub fn register(vm: *VM) !void {
    const file_class_val = Value.fromObject(&vm.file_class.module.object);
    const file_singleton = try vm.getOrCreateSingletonClass(file_class_val);
    const stat_name_sym = try vm.intern("Stat");
    const file_stat_class_val = try vm.newClass(stat_name_sym, vm.object_class);
    vm.file_stat_class = file_stat_class_val.toClassObject();
    try vm.file_class.module.constants.put(stat_name_sym, .{ .value = file_stat_class_val });

    const separator_sym = try vm.intern("SEPARATOR");
    try vm.file_class.module.constants.put(separator_sym, .{ .value = try vm.newString("/", false) });

    const null_sym = try vm.intern("NULL");
    try vm.file_class.module.constants.put(null_sym, .{ .value = try vm.newString(null_device_path, false) });

    // File::Constants module — open-mode flag constants shared with IO
    const constants_name_sym = try vm.intern("Constants");
    const file_constants_val = try vm.newModule(constants_name_sym);
    const file_constants_module = file_constants_val.toModuleObject();
    try vm.file_class.module.constants.put(constants_name_sym, .{ .value = file_constants_val });
    const shared_file_constants = [_]struct { []const u8, i64 }{
        .{ "RDONLY", 0 },
        .{ "WRONLY", 1 },
        .{ "RDWR", 2 },
        .{ "APPEND", openFlagValue(.{ .APPEND = true }) },
        .{ "TRUNC", openFlagValue(.{ .TRUNC = true }) },
        .{ "CREAT", openFlagValue(.{ .CREAT = true }) },
        .{ "EXCL", openFlagValue(.{ .EXCL = true }) },
        .{ "NONBLOCK", openFlagValue(.{ .NONBLOCK = true }) },
        .{ "NOCTTY", openFlagValue(.{ .NOCTTY = true }) },
        .{ "SYNC", openFlagValue(.{ .SYNC = true }) },
        .{ "BINARY", 0 },
        .{ "SHARE_DELETE", 0 },
        .{ "FNM_NOESCAPE", 0x01 },
        .{ "FNM_PATHNAME", 0x02 },
        .{ "FNM_DOTMATCH", 0x04 },
        .{ "FNM_CASEFOLD", 0x08 },
        .{ "FNM_EXTGLOB", 0x10 },
        .{ "FNM_SYSCASE", 0x00 },
        .{ "LOCK_SH", 1 },
        .{ "LOCK_EX", 2 },
        .{ "LOCK_NB", 4 },
        .{ "LOCK_UN", 8 },
    };
    for (shared_file_constants) |entry| {
        const sym = try vm.intern(entry[0]);
        try file_constants_module.constants.put(sym, .{ .value = Value.integer(entry[1]) });
        try vm.file_class.module.constants.put(sym, .{ .value = Value.integer(entry[1]) });
    }

    const alt_separator_sym = try vm.intern("ALT_SEPARATOR");
    try vm.file_class.module.constants.put(alt_separator_sym, .{ .value = Value.nil() });

    const path_separator_sym = try vm.intern("PATH_SEPARATOR");
    try vm.file_class.module.constants.put(path_separator_sym, .{ .value = try vm.newString(":", false) });

    const new_sym = try vm.intern("new");
    try file_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinFileNew, .{ .variadic = 0 }));

    const open_sym = try vm.intern("open");
    try file_singleton.module.methods.put(open_sym, value.MethodEntry.builtin(&builtinFileOpen, .{ .variadic = 0 }));

    const read_sym = try vm.intern("read");
    try file_singleton.module.methods.put(read_sym, value.MethodEntry.builtin(&builtinFileRead, .{ .variadic = 0 }));

    const write_sym = try vm.intern("write");
    try file_singleton.module.methods.put(write_sym, value.MethodEntry.builtin(&builtinFileWrite, .{ .variadic = 0 }));

    const binread_sym = try vm.intern("binread");
    try file_singleton.module.methods.put(binread_sym, value.MethodEntry.builtin(&builtinFileBinread, .{ .variadic = 0 }));

    const expand_path_sym = try vm.intern("expand_path");
    try file_singleton.module.methods.put(expand_path_sym, value.MethodEntry.builtin(&builtinFileExpandPath, .{ .variadic = 0 }));

    const realpath_sym = try vm.intern("realpath");
    try file_singleton.module.methods.put(realpath_sym, value.MethodEntry.builtin(&builtinFileRealpath, .{ .variadic = 0 }));

    const join_sym = try vm.intern("join");
    try file_singleton.module.methods.put(join_sym, value.MethodEntry.builtin(&builtinFileJoin, .{ .variadic = 0 }));

    const dirname_sym = try vm.intern("dirname");
    try file_singleton.module.methods.put(dirname_sym, value.MethodEntry.builtin(&builtinFileDirname, .{ .variadic = 0 }));

    const basename_sym = try vm.intern("basename");
    try file_singleton.module.methods.put(basename_sym, value.MethodEntry.builtin(&builtinFileBasename, .{ .variadic = 0 }));

    const extname_sym = try vm.intern("extname");
    try file_singleton.module.methods.put(extname_sym, value.MethodEntry.builtin(&builtinFileExtname, .{ .exact = 1 }));

    const split_sym = try vm.intern("split");
    try file_singleton.module.methods.put(split_sym, value.MethodEntry.builtin(&builtinFileSplit, .{ .exact = 1 }));

    const directory_sym = try vm.intern("directory?");
    try file_singleton.module.methods.put(directory_sym, value.MethodEntry.builtin(&builtinFileDirectory, .{ .exact = 1 }));

    const file_sym = try vm.intern("file?");
    try file_singleton.module.methods.put(file_sym, value.MethodEntry.builtin(&builtinFileFile, .{ .exact = 1 }));

    const stat_sym = try vm.intern("stat");
    try file_singleton.module.methods.put(stat_sym, value.MethodEntry.builtin(&builtinFileStat, .{ .exact = 1 }));
    const lstat_sym = try vm.intern("lstat");
    try file_singleton.module.methods.put(lstat_sym, value.MethodEntry.builtin(&builtinFileLstat, .{ .exact = 1 }));
    try vm.io_class.module.methods.put(stat_sym, value.MethodEntry.builtin(&builtinIoStat, .{ .exact = 0 }));

    const exist_sym = try vm.intern("exist?");
    try file_singleton.module.methods.put(exist_sym, value.MethodEntry.builtin(&builtinFileExist, .{ .exact = 1 }));

    const writable_sym = try vm.intern("writable?");
    try file_singleton.module.methods.put(writable_sym, value.MethodEntry.builtin(&builtinFileWritable, .{ .exact = 1 }));

    const executable_sym = try vm.intern("executable?");
    try file_singleton.module.methods.put(executable_sym, value.MethodEntry.builtin(&builtinFileExecutable, .{ .exact = 1 }));

    const identical_sym = try vm.intern("identical?");
    try file_singleton.module.methods.put(identical_sym, value.MethodEntry.builtin(&builtinFileIdentical, .{ .exact = 2 }));

    const symlink_sym = try vm.intern("symlink");
    try file_singleton.module.methods.put(symlink_sym, value.MethodEntry.builtin(&builtinFileSymlink, .{ .exact = 2 }));
    const symlink_q_singleton_sym = try vm.intern("symlink?");
    try file_singleton.module.methods.put(symlink_q_singleton_sym, value.MethodEntry.builtin(&builtinFileSymlinkQ, .{ .exact = 1 }));

    const chmod_sym = try vm.intern("chmod");
    try file_singleton.module.methods.put(chmod_sym, value.MethodEntry.builtin(&builtinFileChmod, .{ .variadic = 1 }));

    const chown_sym = try vm.intern("chown");
    try file_singleton.module.methods.put(chown_sym, value.MethodEntry.builtin(&builtinFileChown, .{ .variadic = 2 }));
    try vm.file_class.module.methods.put(chown_sym, value.MethodEntry.builtin(&builtinFileInstanceChown, .{ .exact = 2 }));

    const umask_sym = try vm.intern("umask");
    try file_singleton.module.methods.put(umask_sym, value.MethodEntry.builtin(&builtinFileUmask, .{ .variadic = 0 }));

    const utime_sym = try vm.intern("utime");
    try file_singleton.module.methods.put(utime_sym, value.MethodEntry.builtin(&builtinFileUtime, .{ .variadic = 2 }));

    const fnmatch_sym = try vm.intern("fnmatch");
    try file_singleton.module.methods.put(fnmatch_sym, value.MethodEntry.builtin(&builtinFileFnmatch, .{ .variadic = 2 }));
    const fnmatch_q_sym = try vm.intern("fnmatch?");
    try file_singleton.module.methods.put(fnmatch_q_sym, value.MethodEntry.builtin(&builtinFileFnmatch, .{ .variadic = 2 }));

    const rename_sym = try vm.intern("rename");
    try file_singleton.module.methods.put(rename_sym, value.MethodEntry.builtin(&builtinFileRename, .{ .exact = 2 }));

    const delete_sym = try vm.intern("delete");
    try file_singleton.module.methods.put(delete_sym, value.MethodEntry.builtin(&builtinFileDelete, .{ .variadic = 0 }));

    const unlink_sym = try vm.intern("unlink");
    try file_singleton.module.methods.put(unlink_sym, value.MethodEntry.builtin(&builtinFileDelete, .{ .variadic = 0 }));

    const path_sym = try vm.intern("path");
    try file_singleton.module.methods.put(path_sym, value.MethodEntry.builtin(&builtinFilePath, .{ .variadic = 0 }));

    const size_sym_file = try vm.intern("size");
    try file_singleton.module.methods.put(size_sym_file, value.MethodEntry.builtin(&builtinFileSize, .{ .exact = 1 }));

    const size_q_sym_file = try vm.intern("size?");
    try file_singleton.module.methods.put(size_q_sym_file, value.MethodEntry.builtin(&builtinFileSizeQ, .{ .exact = 1 }));

    const zero_q_sym_file = try vm.intern("zero?");
    try file_singleton.module.methods.put(zero_q_sym_file, value.MethodEntry.builtin(&builtinFileZeroQ, .{ .exact = 1 }));

    const mtime_sym_file = try vm.intern("mtime");
    try file_singleton.module.methods.put(mtime_sym_file, value.MethodEntry.builtin(&builtinFileMtime, .{ .exact = 1 }));
    try vm.file_class.module.methods.put(mtime_sym_file, value.MethodEntry.builtin(&builtinFileInstanceMtime, .{ .exact = 0 }));

    try vm.file_stat_class.module.methods.put(file_sym, value.MethodEntry.builtin(&builtinFileStatFileQ, .{ .exact = 0 }));

    const directory_q_sym = try vm.intern("directory?");
    try vm.file_stat_class.module.methods.put(directory_q_sym, value.MethodEntry.builtin(&builtinFileStatDirectoryQ, .{ .exact = 0 }));

    const symlink_q_sym = try vm.intern("symlink?");
    try vm.file_stat_class.module.methods.put(symlink_q_sym, value.MethodEntry.builtin(&builtinFileStatSymlinkQ, .{ .exact = 0 }));

    const zero_q_sym = try vm.intern("zero?");
    try vm.file_stat_class.module.methods.put(zero_q_sym, value.MethodEntry.builtin(&builtinFileStatZeroQ, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.file_stat_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinFileStatSize, .{ .exact = 0 }));

    const size_q_sym = try vm.intern("size?");
    try vm.file_stat_class.module.methods.put(size_q_sym, value.MethodEntry.builtin(&builtinFileStatSizeQ, .{ .exact = 0 }));

    const blksize_sym = try vm.intern("blksize");
    try vm.file_stat_class.module.methods.put(blksize_sym, value.MethodEntry.builtin(&builtinFileStatBlksize, .{ .exact = 0 }));

    const ino_sym = try vm.intern("ino");
    try vm.file_stat_class.module.methods.put(ino_sym, value.MethodEntry.builtin(&builtinFileStatIno, .{ .exact = 0 }));

    const atime_sym = try vm.intern("atime");
    try vm.file_stat_class.module.methods.put(atime_sym, value.MethodEntry.builtin(&builtinFileStatAtime, .{ .exact = 0 }));

    const ctime_sym = try vm.intern("ctime");
    try vm.file_stat_class.module.methods.put(ctime_sym, value.MethodEntry.builtin(&builtinFileStatCtime, .{ .exact = 0 }));

    const mtime_sym = try vm.intern("mtime");
    try vm.file_stat_class.module.methods.put(mtime_sym, value.MethodEntry.builtin(&builtinFileStatMtime, .{ .exact = 0 }));

    const mode_sym = try vm.intern("mode");
    try vm.file_stat_class.module.methods.put(mode_sym, value.MethodEntry.builtin(&builtinFileStatMode, .{ .exact = 0 }));

    const uid_sym = try vm.intern("uid");
    try vm.file_stat_class.module.methods.put(uid_sym, value.MethodEntry.builtin(&builtinFileStatUid, .{ .exact = 0 }));

    const gid_sym = try vm.intern("gid");
    try vm.file_stat_class.module.methods.put(gid_sym, value.MethodEntry.builtin(&builtinFileStatGid, .{ .exact = 0 }));

    const executable_q_sym = try vm.intern("executable?");
    try vm.file_stat_class.module.methods.put(executable_q_sym, value.MethodEntry.builtin(&builtinFileStatExecutableQ, .{ .exact = 0 }));

    const world_writable_q_sym = try vm.intern("world_writable?");
    try vm.file_stat_class.module.methods.put(world_writable_q_sym, value.MethodEntry.builtin(&builtinFileStatWorldWritableQ, .{ .exact = 0 }));

    const sticky_q_sym = try vm.intern("sticky?");
    try vm.file_stat_class.module.methods.put(sticky_q_sym, value.MethodEntry.builtin(&builtinFileStatStickyQ, .{ .exact = 0 }));

    const readable_q_sym = try vm.intern("readable?");
    try vm.file_stat_class.module.methods.put(readable_q_sym, value.MethodEntry.builtin(&builtinFileStatReadableQ, .{ .exact = 0 }));

    const writable_q_sym = try vm.intern("writable?");
    try vm.file_stat_class.module.methods.put(writable_q_sym, value.MethodEntry.builtin(&builtinFileStatWritableQ, .{ .exact = 0 }));
}

fn parseMode(vm: *VM, mode_str: []const u8) VMError!FileMode {
    if (mode_str.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode", .{});
    }

    const plus = std.mem.indexOfScalar(u8, mode_str, '+') != null;
    return switch (mode_str[0]) {
        'r' => .{ .read = true, .write = plus, .append = false, .create = false, .truncate = false },
        'w' => .{ .read = plus, .write = true, .append = false, .create = true, .truncate = true },
        'a' => .{ .read = plus, .write = true, .append = true, .create = true, .truncate = false },
        else => vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode {s}", .{mode_str}),
    };
}

fn parseModeBits(vm: *VM, raw_mode: i64) VMError!FileMode {
    if (raw_mode < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid access mode {d}", .{raw_mode});
    }

    // Decode using OS-native flag layout by bitcasting back to the posix.O struct.
    // This is the reverse of openFlagValue() and handles platform differences
    // (e.g. O_CREAT=512 on macOS vs O_CREAT=64 on Linux).
    const flags: std.posix.O = @bitCast(@as(c_int, @truncate(raw_mode)));
    const read = flags.ACCMODE == .RDONLY or flags.ACCMODE == .RDWR;
    const write = flags.ACCMODE == .WRONLY or flags.ACCMODE == .RDWR;
    const append = flags.APPEND;
    const truncate = flags.TRUNC;
    const create = flags.CREAT or append;

    return .{
        .read = read,
        .write = write or append,
        .append = append,
        .create = create,
        .truncate = truncate,
    };
}

fn openFileWithMode(vm: *VM, path: Value, mode: FileMode, create_mode: std.c.mode_t) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "File is not implemented on Windows", .{});
    }

    const path_obj = path.toStringObject();
    const path_bytes = path_obj.str;

    const flags: std.c.O = .{
        .ACCMODE = if (mode.read and mode.write) .RDWR else if (mode.write) .WRONLY else .RDONLY,
        .CLOEXEC = true,
        .CREAT = mode.create,
        .TRUNC = mode.truncate,
        .APPEND = mode.append,
    };

    const path_z = try vm.allocCStringZ(path_bytes);
    defer vm.allocator.free(path_z);
    const fd = std.c.open(path_z.ptr, flags, create_mode);
    if (fd < 0) {
        return vm.raiseErrnoFmt(std.posix.errno(fd), "failed to open file: {s}", .{path_bytes});
    }

    const path_copy = vm.gc_allocator.dupe(u8, path_bytes) catch return error.Fatal;
    return vm.newIo(vm.file_class, @intCast(fd), .{
        .owns_fd = true,
        .readable = mode.read,
        .writable = mode.write,
        .append = mode.append,
        .path = path_copy,
        .path_encoding = path_obj.encoding,
    });
}

fn pathAndMode(vm: *VM, args: []Value) VMError!struct { path: Value, mode: FileMode, create_mode: std.c.mode_t } {
    try vm.requireArgCountRange(args, 1, 3);
    const path = try vm.coerceToPathValue(args[0], "no implicit conversion into String");

    const mode = if (args.len >= 2 and !args[1].isNil()) blk: {
        if (args[1].isInteger()) {
            break :blk try parseModeBits(vm, args[1].toInteger());
        }
        const mode_str = try args[1].coerceToStr(vm, "no implicit conversion into String");
        break :blk try parseMode(vm, mode_str);
    } else try parseMode(vm, "r");
    const create_mode: std.c.mode_t = if (args.len == 3 and !args[2].isNil())
        try coerceModeBits(vm, args[2])
    else
        0o666;
    return .{ .path = path, .mode = mode, .create_mode = create_mode };
}

const FileOpenConfig = struct {
    path: Value,
    mode: FileMode,
    create_mode: std.c.mode_t,
    external_encoding: ?Value = null,
    internal_encoding: ?Value = null,
};

fn resolveEncodingValue(vm: *VM, arg: Value) VMError!Value {
    if (arg.isEncoding()) return arg;
    var find_args = [_]Value{arg};
    return encoding_builtin.builtinEncodingFind(vm, Value.nil(), find_args[0..], null);
}

fn fileOpenConfig(vm: *VM, args: []Value) VMError!FileOpenConfig {
    var external_encoding: ?Value = null;
    var internal_encoding: ?Value = null;
    var autoclose: ?Value = null;
    var path: ?Value = null;
    var perm: ?Value = null;
    try vm.consumeKeywordArgs(.{ "external_encoding", "internal_encoding", "autoclose", "path", "perm" }, .{ &external_encoding, &internal_encoding, &autoclose, &path, &perm });
    try vm.validateKeywordArgsConsumed();

    const parsed = try pathAndMode(vm, args);
    var config = FileOpenConfig{
        .path = parsed.path,
        .mode = parsed.mode,
        .create_mode = parsed.create_mode,
    };

    if (perm) |perm_val| {
        config.create_mode = try coerceModeBits(vm, perm_val);
    }

    if (external_encoding) |encoding_arg| {
        config.external_encoding = try resolveEncodingValue(vm, encoding_arg);
    }
    if (internal_encoding) |encoding_arg| {
        config.internal_encoding = try resolveEncodingValue(vm, encoding_arg);
    }
    if (config.external_encoding != null and config.internal_encoding != null and config.external_encoding.?.raw == config.internal_encoding.?.raw) {
        config.internal_encoding = null;
    }
    return config;
}

fn applyIoEncodingConfig(vm: *VM, io_value: Value, config: FileOpenConfig) VMError!void {
    if (config.external_encoding) |encoding| {
        try vm.setInstanceVariable(io_value, "@external_encoding", encoding);
    }
    if (config.internal_encoding) |encoding| {
        try vm.setInstanceVariable(io_value, "@internal_encoding", encoding);
    }
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

fn coerceModeBits(vm: *VM, arg: Value) VMError!std.c.mode_t {
    const missing_msg = std.fmt.allocPrint(
        vm.gc_allocator,
        "no implicit conversion of {s} into Integer",
        .{vm.className(arg)},
    ) catch return error.Fatal;
    const raw_mode = try arg.coerceToI64ViaToInt(
        vm,
        missing_msg,
        "can't convert to Integer (to_int gives non-Integer)",
        "integer out of range",
    );
    if (raw_mode < 0) {
        return vm.raiseExceptionFmt(vm.range_error_class, "integer out of range", .{});
    }
    return @intCast(raw_mode);
}

fn currentWorkingDir(vm: *VM) VMError![]u8 {
    const cwd_z = std.process.currentPathAlloc(vm.io, vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(cwd_z);
    return vm.dupeCStringZAsSlice(cwd_z);
}

fn joinPathPartsAlloc(allocator: std.mem.Allocator, base: []const u8, tail: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    if (base.len == 0) {
        out.appendSlice(allocator, tail) catch return error.OutOfMemory;
    } else if (tail.len == 0) {
        out.appendSlice(allocator, base) catch return error.OutOfMemory;
    } else {
        out.appendSlice(allocator, base) catch return error.OutOfMemory;
        if (out.items[out.items.len - 1] != '/') {
            out.append(allocator, '/') catch return error.OutOfMemory;
        }
        var start: usize = 0;
        while (start < tail.len and tail[start] == '/') : (start += 1) {}
        out.appendSlice(allocator, tail[start..]) catch return error.OutOfMemory;
    }

    return allocator.dupe(u8, out.items);
}

fn normalizeAbsolutePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var leading_slashes: usize = 0;
    while (leading_slashes < path.len and path[leading_slashes] == '/') : (leading_slashes += 1) {}
    if (leading_slashes == 0) return error.InvalidArgument;

    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(allocator);

    var i: usize = leading_slashes;
    while (i <= path.len) {
        const start = i;
        while (i < path.len and path[i] != '/') : (i += 1) {}
        const segment = path[start..i];
        if (segment.len > 0 and !std.mem.eql(u8, segment, ".")) {
            if (std.mem.eql(u8, segment, "..")) {
                if (segments.items.len > 0) _ = segments.pop();
            } else {
                segments.append(allocator, segment) catch return error.OutOfMemory;
            }
        }
        i += 1;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (0..leading_slashes) |_| {
        out.append(allocator, '/') catch return error.OutOfMemory;
    }

    for (segments.items, 0..) |segment, idx| {
        if (idx > 0) out.append(allocator, '/') catch return error.OutOfMemory;
        out.appendSlice(allocator, segment) catch return error.OutOfMemory;
    }

    return allocator.dupe(u8, out.items);
}

fn expandUserPathAlloc(vm: *VM, path: []const u8) VMError![]u8 {
    std.debug.assert(path.len > 0 and path[0] == '~');
    var split: usize = 1;
    while (split < path.len and path[split] != '/') : (split += 1) {}
    const username = path[1..split];
    const rest = path[split..];

    const home = if (username.len == 0)
        try currentHome(vm)
    else
        (try homeFromPasswdByName(vm, username)) orelse {
            return vm.raiseExceptionFmt(vm.argument_error_class, "user {s} doesn't exist", .{username});
        };
    if (rest.len == 0 or (rest.len == 1 and rest[0] == '/')) {
        return vm.allocator.dupe(u8, home) catch return error.Fatal;
    }

    return joinPathPartsAlloc(vm.allocator, home, rest[1..]) catch return error.Fatal;
}

fn expandBaseDirAlloc(vm: *VM, base_opt: ?[]const u8) VMError![]u8 {
    const base = base_opt orelse {
        return currentWorkingDir(vm);
    };

    if (base.len > 0 and base[0] == '~') {
        const expanded = try expandUserPathAlloc(vm, base);
        defer vm.allocator.free(expanded);
        return normalizeAbsolutePathAlloc(vm.allocator, expanded) catch return error.Fatal;
    }

    if (base.len > 0 and base[0] == '/') {
        return normalizeAbsolutePathAlloc(vm.allocator, base) catch return error.Fatal;
    }

    const cwd = try currentWorkingDir(vm);
    defer vm.allocator.free(cwd);
    const joined = joinPathPartsAlloc(vm.allocator, cwd, base) catch return error.Fatal;
    defer vm.allocator.free(joined);
    return normalizeAbsolutePathAlloc(vm.allocator, joined) catch return error.Fatal;
}

fn expandPathAlloc(vm: *VM, path: []const u8, base_opt: ?[]const u8) VMError![]u8 {
    if (path.len > 0 and path[0] == '~') {
        const expanded = try expandUserPathAlloc(vm, path);
        defer vm.allocator.free(expanded);
        return normalizeAbsolutePathAlloc(vm.allocator, expanded) catch return error.Fatal;
    }

    if (path.len > 0 and path[0] == '/') {
        return normalizeAbsolutePathAlloc(vm.allocator, path) catch return error.Fatal;
    }

    const base = try expandBaseDirAlloc(vm, base_opt);
    defer vm.allocator.free(base);

    const joined = joinPathPartsAlloc(vm.allocator, base, path) catch return error.Fatal;
    defer vm.allocator.free(joined);
    return normalizeAbsolutePathAlloc(vm.allocator, joined) catch return error.Fatal;
}

fn dirnameBytesAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, ".");

    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];

    if (std.mem.eql(u8, trimmed, "/")) return allocator.dupe(u8, "/");

    const last_slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return allocator.dupe(u8, ".");
    if (last_slash == 0) return allocator.dupe(u8, "/");
    return allocator.dupe(u8, trimmed[0..last_slash]);
}

fn extnameBytesAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, "");

    // Strip trailing slashes (keep at least one char)
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];

    // Find start of basename (after last '/')
    var p: usize = if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |slash|
        slash + 1
    else
        0;

    // Skip all leading dots in the basename (handles ".bashrc", "...", etc.)
    while (p < trimmed.len and trimmed[p] == '.') : (p += 1) {}

    // Find last '.' in the remaining basename characters
    var e: ?usize = null;
    var i = p;
    while (i < trimmed.len) : (i += 1) {
        if (trimmed[i] == '.') e = i;
    }

    if (e == null) return allocator.dupe(u8, "");
    return allocator.dupe(u8, trimmed[e.?..]);
}

fn basenameBytesAlloc(allocator: std.mem.Allocator, path: []const u8, suffix_opt: ?[]const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, "");

    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];

    const basename = if (std.mem.eql(u8, trimmed, "/"))
        trimmed
    else
        trimmed[(std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse return allocator.dupe(u8, trimmed)) + 1 ..];

    var result = basename;
    if (suffix_opt) |suffix| {
        if (std.mem.eql(u8, suffix, ".*")) {
            if (std.mem.lastIndexOfScalar(u8, basename, '.')) |dot_idx| {
                if (dot_idx > 0) result = basename[0..dot_idx];
            }
        } else if (suffix.len > 0 and std.mem.endsWith(u8, basename, suffix)) {
            result = basename[0 .. basename.len - suffix.len];
        }
    }

    return allocator.dupe(u8, result);
}

fn statTimestampToValue(vm: *VM, timestamp: std.Io.Timestamp) VMError!Value {
    return vm.newTime(vm.time_class, @intCast(timestamp.nanoseconds));
}

fn requireFileStatReceiver(vm: *VM, receiver: Value) VMError!Value {
    if (receiver.isObject() and vm.getClass(receiver) == vm.file_stat_class) return receiver;
    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a File::Stat", .{});
}

fn fileStatBoolIvar(vm: *VM, receiver: Value, name: []const u8) VMError!Value {
    const stat_val = try requireFileStatReceiver(vm, receiver);
    return vm.getInstanceVariable(stat_val, name);
}

fn fileStatIntegerIvar(vm: *VM, receiver: Value, name: []const u8) VMError!Value {
    const stat_val = try requireFileStatReceiver(vm, receiver);
    return vm.getInstanceVariable(stat_val, name);
}

fn fileStatTimeIvar(vm: *VM, receiver: Value, name: []const u8) VMError!Value {
    const stat_val = try requireFileStatReceiver(vm, receiver);
    return vm.getInstanceVariable(stat_val, name);
}

fn loadPosixStatMetadataForPath(vm: *VM, path_obj: *value.StringObject, default_mode: i64) VMError!PosixStatMetadata {
    if (builtin.os.tag != .linux) {
        return .{
            .uid = @intCast(std.c.getuid()),
            .gid = @intCast(std.c.getgid()),
            .mode = default_mode,
        };
    }

    const path_z = try vm.allocCStringZ(path_obj.str);
    defer vm.allocator.free(path_z);

    while (true) {
        var statx = std.mem.zeroes(std.os.linux.Statx);
        switch (std.c.errno(std.c.statx(std.os.linux.AT.FDCWD, path_z.ptr, std.os.linux.AT.NO_AUTOMOUNT, linux_statx_request, &statx))) {
            .SUCCESS => {
                return .{
                    .uid = @intCast(statx.uid),
                    .gid = @intCast(statx.gid),
                    .mode = @intCast(statx.mode),
                };
            },
            .INTR => continue,
            .ACCES, .PERM => return vm.raiseErrnoFmt(.ACCES, "Permission denied @ stat - {s}", .{path_obj.str}),
            .NOENT, .NOTDIR => return raiseEncodedPathErrno(vm, .NOENT, path_obj),
            else => return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed for {s}", .{path_obj.str}),
        }
    }
}

fn loadPosixStatMetadataForFd(vm: *VM, fd: std.c.fd_t, default_mode: i64) VMError!PosixStatMetadata {
    if (builtin.os.tag != .linux) {
        return .{
            .uid = @intCast(std.c.getuid()),
            .gid = @intCast(std.c.getgid()),
            .mode = default_mode,
        };
    }

    while (true) {
        var statx = std.mem.zeroes(std.os.linux.Statx);
        switch (std.c.errno(std.c.statx(fd, "", std.os.linux.AT.EMPTY_PATH, linux_statx_request, &statx))) {
            .SUCCESS => {
                return .{
                    .uid = @intCast(statx.uid),
                    .gid = @intCast(statx.gid),
                    .mode = @intCast(statx.mode),
                };
            },
            .INTR => continue,
            .ACCES, .PERM => return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed", .{}),
            else => return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed", .{}),
        }
    }
}

fn fileIdentityForPath(vm: *VM, path_obj: *value.StringObject) VMError!?FileIdentity {
    const path_z = try vm.allocCStringZ(path_obj.str);
    defer vm.allocator.free(path_z);

    if (builtin.os.tag == .linux) {
        while (true) {
            var statx = std.mem.zeroes(std.os.linux.Statx);
            switch (std.c.errno(std.c.statx(std.os.linux.AT.FDCWD, path_z.ptr, std.os.linux.AT.NO_AUTOMOUNT, linux_identical_statx_request, &statx))) {
                .SUCCESS => {
                    return .{
                        .inode = statx.ino,
                        .mount_id = if (statx.mask.MNT_ID or statx.mask.MNT_ID_UNIQUE) statx.mnt_id else null,
                    };
                },
                .INTR => continue,
                .NOENT, .NOTDIR => return null,
                .ACCES, .PERM => return null,
                else => return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed for {s}", .{path_obj.str}),
            }
        }
    }

    // POSIX fallback (macOS and other platforms): use stat(2) — follows symlinks,
    // so a symlink and its target correctly compare as identical.
    var st = std.mem.zeroes(std.posix.Stat);
    while (true) {
        if (callStat(path_z.ptr, &st) == 0) {
            return .{
                .inode = @intCast(st.ino),
                .mount_id = @intCast(st.dev),
            };
        }
        const err = std.posix.errno(-1);
        switch (err) {
            .INTR => continue,
            .NOENT, .NOTDIR => return null,
            .ACCES, .PERM => return null,
            else => return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed for {s}", .{path_obj.str}),
        }
    }
}

fn buildFileStat(vm: *VM, stat: std.Io.File.Stat, posix_metadata: PosixStatMetadata) VMError!Value {
    const stat_val = try vm.newInstance(vm.file_stat_class);
    const atime_value = try statTimestampToValue(vm, stat.atime orelse stat.mtime);
    try vm.setInstanceVariable(stat_val, "@directory", Value.boolean(stat.kind == .directory));
    try vm.setInstanceVariable(stat_val, "@file", Value.boolean(stat.kind == .file));
    try vm.setInstanceVariable(stat_val, "@symlink", Value.boolean(stat.kind == .sym_link));
    try vm.setInstanceVariable(stat_val, "@mode", Value.integer(posix_metadata.mode));
    try vm.setInstanceVariable(stat_val, "@uid", Value.integer(posix_metadata.uid));
    try vm.setInstanceVariable(stat_val, "@gid", Value.integer(posix_metadata.gid));
    try vm.setInstanceVariable(stat_val, "@size", Value.integer(@intCast(stat.size)));
    try vm.setInstanceVariable(stat_val, "@blksize", Value.integer(@intCast(stat.block_size)));
    try vm.setInstanceVariable(stat_val, "@ino", Value.integer(@intCast(stat.inode)));
    try vm.setInstanceVariable(stat_val, "@atime", atime_value);
    try vm.setInstanceVariable(stat_val, "@ctime", try statTimestampToValue(vm, stat.ctime));
    try vm.setInstanceVariable(stat_val, "@mtime", try statTimestampToValue(vm, stat.mtime));
    return stat_val;
}

fn raiseEncodedPathErrno(vm: *VM, errno_code: std.posix.E, path_obj: *value.StringObject) VMError {
    var message_bytes: std.ArrayList(u8) = .empty;
    defer message_bytes.deinit(vm.allocator);
    message_bytes.appendSlice(vm.allocator, "No such file or directory @ stat - ") catch return error.Fatal;
    message_bytes.appendSlice(vm.allocator, path_obj.str) catch return error.Fatal;

    const exc = try vm.createException(vm.errnoClass(@intCast(@intFromEnum(errno_code))), "");
    const msg_val = try vm.newStringWithEncoding(message_bytes.items, false, path_obj.encoding);
    exc.message = msg_val.toStringObject();
    vm.setPendingException(exc);
    return error.Unwind;
}

fn raisePathStatError(vm: *VM, path_obj: *value.StringObject, err: anyerror) VMError {
    return switch (err) {
        error.FileNotFound => raiseEncodedPathErrno(vm, .NOENT, path_obj),
        error.AccessDenied, error.PermissionDenied => vm.raiseErrnoFmt(.ACCES, "Permission denied @ stat - {s}", .{path_obj.str}),
        else => vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed for {s}", .{path_obj.str}),
    };
}

pub fn builtinFileNew(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len >= 1 and args[0].isInteger()) {
        const instance = try vm.newObjectForClass(vm.file_class);
        _ = try vm.callMethodByNameForwardingKeywords(instance, "initialize", args, null);
        return instance;
    }

    const config = try fileOpenConfig(vm, args);
    const file_val = try openFileWithMode(vm, config.path, config.mode, config.create_mode);
    try applyIoEncodingConfig(vm, file_val, config);
    return file_val;
}

pub fn builtinFileOpen(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    const config = try fileOpenConfig(vm, args);
    const file_val = try openFileWithMode(vm, config.path, config.mode, config.create_mode);
    try applyIoEncodingConfig(vm, file_val, config);

    if (block) |blk| {
        var yield_args: [1]Value = .{file_val};
        const yielded = vm.yieldToBlock(blk, &yield_args) catch |err| {
            _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
            return err;
        };
        _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
        return yielded.value;
    }

    return file_val;
}

pub fn builtinFileRead(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);
    const path = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const file_val = try openFileWithMode(vm, path, .{ .read = true, .write = false, .append = false, .create = false, .truncate = false }, 0o666);
    defer _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};

    if (args.len >= 3) {
        const offset_val = args[2];
        if (!offset_val.isInteger() and !offset_val.isNil()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        const offset: i64 = if (offset_val.isNil()) 0 else offset_val.toInteger();
        if (offset < 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "negative offset {d} given", .{offset});
        }
        const fd = file_val.toIoObject().fd;
        const result = std.c.lseek(fd, offset, 0);
        if (result < 0) {
            const errno_code = std.posix.errno(result);
            return vm.raiseErrnoFmt(errno_code, "seek failed", .{});
        }
    }

    if (args.len == 1) {
        return vm.callMethodByName(file_val, "read", &[_]Value{}, null);
    }

    const len_val = args[1];
    if (!len_val.isInteger() and !len_val.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    if (len_val.isInteger() and len_val.toInteger() < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len_val.toInteger()});
    }
    return vm.callMethodByName(file_val, "read", args[1..2], null);
}

pub fn builtinFileWrite(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const path = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const file_val = try openFileWithMode(vm, path, .{ .read = false, .write = true, .append = false, .create = true, .truncate = true }, 0o666);
    defer _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};
    return vm.callMethodByName(file_val, "write", args[1..2], null);
}

pub fn builtinFileBinread(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);
    const path = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const file_val = try openFileWithMode(vm, path, .{ .read = true, .write = false, .append = false, .create = false, .truncate = false }, 0o666);
    defer _ = vm.callMethodByName(file_val, "close", &[_]Value{}, null) catch {};

    const fd = file_val.toIoObject().fd;

    if (args.len >= 3) {
        const offset_val = args[2];
        if (!offset_val.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        const offset = offset_val.toInteger();
        if (offset < 0) {
            _ = std.c.lseek(fd, offset, 0);
            const errno_val = std.c._errno().*;
            return vm.raiseErrnoFmt(@enumFromInt(errno_val), "invalid argument", .{});
        }
        const result = std.c.lseek(fd, offset, 0);
        if (result < 0) {
            const errno_code = std.posix.errno(result);
            return vm.raiseErrnoFmt(errno_code, "seek failed", .{});
        }
    }

    if (args.len == 1) {
        var buf: [4096]u8 = undefined;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(vm.allocator);
        while (true) {
            const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
            if (n == 0) break;
            out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        }
        return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    const len_val = args[1];
    if (!len_val.isInteger() and !len_val.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const len: ?i64 = if (len_val.isNil()) null else len_val.toInteger();
    if (len != null and len.? < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative length {d} given", .{len.?});
    }

    if (len == null) {
        var buf: [4096]u8 = undefined;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(vm.allocator);
        while (true) {
            const n = std.posix.read(fd, &buf) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
            if (n == 0) break;
            out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        }
        return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    const len_usize: usize = @intCast(len.?);
    if (len_usize == 0) {
        return vm.newStringWithEncoding(&[_]u8{}, false, enc.Encoding{ .ascii_8bit = .{} });
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    out.ensureTotalCapacity(vm.allocator, len_usize) catch return error.Fatal;

    var remaining = len_usize;
    var buf: [4096]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const n = std.posix.read(fd, buf[0..to_read]) catch return vm.raiseExceptionFmt(vm.io_error_class, "read failed", .{});
        if (n == 0) break;
        out.appendSlice(vm.allocator, buf[0..n]) catch return error.Fatal;
        remaining -= n;
    }

    return vm.newStringWithEncoding(out.items, false, enc.Encoding{ .ascii_8bit = .{} });
}

pub fn builtinFileExpandPath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.expand_path is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();

    const base: ?[]const u8 = if (args.len == 2 and !args[1].isNil()) blk: {
        const base_value = try vm.coerceToPathValue(args[1], "no implicit conversion into String");
        break :blk base_value.toStringObject().str;
    } else null;

    const expanded = try expandPathAlloc(vm, path_obj.str, base);
    defer vm.allocator.free(expanded);
    return try vm.newStringWithEncoding(expanded, false, path_obj.encoding);
}

pub fn builtinFileRealpath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.realpath is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();

    const base: ?[]const u8 = if (args.len == 2 and !args[1].isNil()) blk: {
        const base_value = try vm.coerceToPathValue(args[1], "no implicit conversion into String");
        break :blk base_value.toStringObject().str;
    } else null;

    const expanded = try expandPathAlloc(vm, path_obj.str, base);
    defer vm.allocator.free(expanded);

    const resolved = std.Io.Dir.cwd().realPathFileAlloc(vm.io, expanded, vm.allocator) catch {
        return vm.raiseExceptionFmt(vm.io_error_class, "No such file or directory @ rb_check_realpath_internal - {s}", .{path_obj.str});
    };
    defer vm.allocator.free(resolved);

    return try vm.newStringWithEncoding(resolved, false, path_obj.encoding);
}

pub fn builtinFileJoin(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.join is not implemented on Windows", .{});
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(vm.allocator);

    var output_encoding: Encoding = .{ .utf8 = .{} };
    var have_encoding = false;

    var effective_args = args;
    if (args.len == 1 and args[0].isArray()) {
        effective_args = args[0].toArrayObject().elements.items;
    }

    for (effective_args, 0..) |arg, idx| {
        const part_value = try vm.coerceToPathValue(arg, "no implicit conversion into String");
        const part_obj = part_value.toStringObject();
        if (!have_encoding) {
            output_encoding = part_obj.encoding;
            have_encoding = true;
        }

        if (idx == 0) {
            result.appendSlice(vm.allocator, part_obj.str) catch return error.Fatal;
            continue;
        }

        if (result.items.len > 0 and result.items[result.items.len - 1] != '/') {
            result.append(vm.allocator, '/') catch return error.Fatal;
        }

        var start: usize = 0;
        while (start < part_obj.str.len and part_obj.str[start] == '/') : (start += 1) {}
        result.appendSlice(vm.allocator, part_obj.str[start..]) catch return error.Fatal;
    }

    return try vm.newStringWithEncoding(result.items, false, output_encoding);
}

pub fn builtinFileDirname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.dirname is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const dir = dirnameBytesAlloc(vm.allocator, path_obj.str) catch return error.Fatal;
    defer vm.allocator.free(dir);
    return try vm.newStringWithEncoding(dir, false, path_obj.encoding);
}

pub fn builtinFileBasename(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.basename is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const suffix: ?[]const u8 = if (args.len == 2 and !args[1].isNil())
        try args[1].coerceToStr(vm, "no implicit conversion into String")
    else
        null;
    const base = basenameBytesAlloc(vm.allocator, path_obj.str, suffix) catch return error.Fatal;
    defer vm.allocator.free(base);
    return try vm.newStringWithEncoding(base, false, path_obj.encoding);
}

pub fn builtinFileExtname(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const ext = extnameBytesAlloc(vm.allocator, path_obj.str) catch return error.Fatal;
    defer vm.allocator.free(ext);
    return try vm.newStringWithEncoding(ext, false, path_obj.encoding);
}

pub fn builtinFileSplit(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.split is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const dir = dirnameBytesAlloc(vm.allocator, path_obj.str) catch return error.Fatal;
    defer vm.allocator.free(dir);
    const base = basenameBytesAlloc(vm.allocator, path_obj.str, null) catch return error.Fatal;
    defer vm.allocator.free(base);

    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, try vm.newStringWithEncoding(dir, false, path_obj.encoding)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, try vm.newStringWithEncoding(base, false, path_obj.encoding)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinFileDirectory(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.directory? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    var dir = std.Io.Dir.cwd().openDir(vm.io, path, .{}) catch return Value.boolean(false);
    defer dir.close(vm.io);
    return Value.boolean(true);
}

pub fn builtinFileFile(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.file? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const st = std.Io.Dir.cwd().statFile(vm.io, path, .{}) catch return Value.boolean(false);
    return Value.boolean(st.kind == .file);
}

pub fn builtinFileIdentical(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const left_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const right_value = try vm.coerceToPathValue(args[1], "no implicit conversion into String");
    const left_identity = (try fileIdentityForPath(vm, left_value.toStringObject())) orelse return Value.boolean(false);
    const right_identity = (try fileIdentityForPath(vm, right_value.toStringObject())) orelse return Value.boolean(false);

    if (left_identity.mount_id) |left_mount_id| {
        if (right_identity.mount_id) |right_mount_id| {
            return Value.boolean(left_identity.inode == right_identity.inode and left_mount_id == right_mount_id);
        }
    }

    return Value.boolean(left_identity.inode == right_identity.inode);
}

pub fn builtinFileStat(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.stat is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const stat = std.Io.Dir.cwd().statFile(vm.io, path_obj.str, .{}) catch |err| return raisePathStatError(vm, path_obj, err);
    const posix_metadata = try loadPosixStatMetadataForPath(vm, path_obj, @intCast(stat.permissions.toMode()));
    return buildFileStat(vm, stat, posix_metadata);
}

pub fn builtinFileLstat(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinFileStat(vm, Value.nil(), args, null);
}

pub fn builtinFileMtime(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.mtime is not implemented on Windows", .{});
    }

    const path_value = try vm.coerceToPathValue(args[0], "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const stat = std.Io.Dir.cwd().statFile(vm.io, path_obj.str, .{}) catch |err| return raisePathStatError(vm, path_obj, err);
    const posix_metadata = try loadPosixStatMetadataForPath(vm, path_obj, @intCast(stat.permissions.toMode()));
    const stat_val = try buildFileStat(vm, stat, posix_metadata);
    return vm.getInstanceVariable(stat_val, "@mtime");
}

pub fn builtinFileInstanceMtime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const stat_value = try builtinIoStat(vm, receiver, &[_]Value{}, null);
    return builtinFileStatMtime(vm, stat_value, &[_]Value{}, null);
}

fn statSizeForValue(vm: *VM, arg: Value, nil_when_missing: bool) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.size is not implemented on Windows", .{});
    }

    if (arg.isIo()) {
        const stat_value = try builtinIoStat(vm, arg, &[_]Value{}, null);
        const size_value = try builtinFileStatSize(vm, stat_value, &[_]Value{}, null);
        if (nil_when_missing and size_value.isInteger() and size_value.toInteger() == 0) return Value.nil();
        return size_value;
    }

    const maybe_io = try vm.checkCallMethodByName(arg, "to_io", false, &[_]Value{}, null);
    if (maybe_io) |io_value| {
        if (!io_value.isIo()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into IO", .{vm.className(arg)});
        }
        const stat_value = try builtinIoStat(vm, io_value, &[_]Value{}, null);
        const size_value = try builtinFileStatSize(vm, stat_value, &[_]Value{}, null);
        if (nil_when_missing and size_value.isInteger() and size_value.toInteger() == 0) return Value.nil();
        return size_value;
    }

    const path_value = try vm.coerceToPathValue(arg, "no implicit conversion into String");
    const path_obj = path_value.toStringObject();
    const stat = std.Io.Dir.cwd().statFile(vm.io, path_obj.str, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (nil_when_missing) return Value.nil();
            return raisePathStatError(vm, path_obj, err);
        },
        else => return raisePathStatError(vm, path_obj, err),
    };
    const size_value = Value.integer(@intCast(stat.size));
    if (nil_when_missing and stat.size == 0) return Value.nil();
    return size_value;
}

pub fn builtinFileSize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return statSizeForValue(vm, args[0], false);
}

pub fn builtinFileSizeQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return statSizeForValue(vm, args[0], true);
}

pub fn builtinFileZeroQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const size_value = try statSizeForValue(vm, args[0], false);
    return Value.boolean(size_value.isInteger() and size_value.toInteger() == 0);
}

pub fn builtinIoStat(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "IO#stat is not implemented on Windows", .{});
    }
    if (!receiver.isIo()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});
    }

    const io_obj = receiver.toIoObject();
    if (io_obj.closed) {
        return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});
    }

    const file: std.Io.File = .{
        .handle = @intCast(io_obj.fd),
        .flags = .{ .nonblocking = false },
    };
    const stat = file.stat(vm.io) catch return vm.raiseExceptionFmt(vm.system_call_error_class, "stat failed", .{});
    const posix_metadata = try loadPosixStatMetadataForFd(vm, @intCast(io_obj.fd), @intCast(stat.permissions.toMode()));
    return buildFileStat(vm, stat, posix_metadata);
}

pub fn builtinFileSymlink(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.symlink is not implemented on Windows", .{});
    }

    const target = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const link = try vm.coerceToPath(args[1], "no implicit conversion into String");
    const target_z = try vm.allocCStringZ(target);
    defer vm.allocator.free(target_z);
    const link_z = try vm.allocCStringZ(link);
    defer vm.allocator.free(link_z);

    const result = std.c.symlink(target_z.ptr, link_z.ptr);
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(-1), "failed to create symlink: {s}", .{link});
    }
    return Value.integer(0);
}

pub fn builtinFileSymlinkQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return Value.boolean(false);
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const stat = std.Io.Dir.cwd().statFile(vm.io, path, .{}) catch return Value.boolean(false);
    return Value.boolean(stat.kind == .sym_link);
}

pub fn builtinFileChmod(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, std.math.maxInt(u8));
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.chmod is not implemented on Windows", .{});
    }

    const mode = try coerceModeBits(vm, args[0]);
    var changed: usize = 0;
    for (args[1..]) |arg| {
        const path = try vm.coerceToPath(arg, "no implicit conversion into String");
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);

        const result = std.c.chmod(path_z.ptr, mode);
        if (result != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(result), "failed to chmod: {s}", .{path});
        }
        changed += 1;
    }

    return Value.integer(@intCast(changed));
}

// Coerce uid/gid arg: nil or -1 → (uid_t)-1 (no change), otherwise cast integer.
fn coerceOwnerArg(vm: *VM, arg: Value) VMError!std.c.uid_t {
    if (arg.isNil()) return @bitCast(@as(i32, -1));
    const v = try arg.coerceToI64ViaToInt(
        vm,
        "can't convert nil into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "integer out of range",
    );
    if (v == -1) return @bitCast(@as(i32, -1));
    if (v < 0) return vm.raiseExceptionFmt(vm.range_error_class, "integer out of range", .{});
    return @intCast(v);
}

pub fn builtinFileChown(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, std.math.maxInt(u8));
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.chown is not implemented on Windows", .{});
    }

    const uid = try coerceOwnerArg(vm, args[0]);
    const gid = try coerceOwnerArg(vm, args[1]);
    var changed: usize = 0;
    for (args[2..]) |arg| {
        const path = try vm.coerceToPath(arg, "no implicit conversion into String");
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);

        const result = chown(path_z.ptr, uid, gid);
        if (result != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(result), "failed to chown: {s}", .{path});
        }
        changed += 1;
    }

    return Value.integer(@intCast(changed));
}

pub fn builtinFileInstanceChown(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File#chown is not implemented on Windows", .{});
    }
    if (!receiver.isIo()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not an IO", .{});
    }

    const io_obj = receiver.toIoObject();
    if (io_obj.closed) {
        return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});
    }

    const uid = try coerceOwnerArg(vm, args[0]);
    const gid = try coerceOwnerArg(vm, args[1]);

    const result = std.c.fchown(@intCast(io_obj.fd), uid, gid);
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "fchown failed", .{});
    }
    return Value.integer(0);
}

pub fn builtinFileUmask(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (builtin.os.tag == .windows) {
        return Value.integer(0);
    }

    if (args.len == 0) {
        const current = std.c.umask(0);
        _ = std.c.umask(current);
        return Value.integer(current);
    }

    const new_mask = try coerceModeBits(vm, args[0]);
    const previous = std.c.umask(@intCast(new_mask));
    return Value.integer(previous);
}

fn coerceTimeval(vm: *VM, arg: Value) VMError!i64 {
    if (arg.isNil()) return @as(i64, 0);
    if (arg.isInteger()) return arg.toInteger();
    if (arg.isFloat()) return @intFromFloat(arg.toFloatObject().val);
    const result = try vm.callMethodByName(arg, "to_i", &.{}, null);
    if (result.isInteger()) return result.toInteger();
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Integer", .{});
}

pub fn builtinFileUtime(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 3, std.math.maxInt(u8));
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.utime is not implemented on Windows", .{});
    }

    const atime_secs = try coerceTimeval(vm, args[0]);
    const mtime_secs = try coerceTimeval(vm, args[1]);
    var changed: usize = 0;

    for (args[2..]) |arg| {
        const path = try vm.coerceToPath(arg, "no implicit conversion into String");
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);

        var ts = [2]std.c.timespec{
            .{ .sec = atime_secs, .nsec = 0x3fffffff },
            .{ .sec = mtime_secs, .nsec = 0x3fffffff },
        };
        const result = std.c.utimensat(-100, path_z.ptr, &ts, 0);
        if (result != 0) {
            return vm.raiseErrnoFmt(std.posix.errno(result), "failed to utime: {s}", .{path});
        }
        changed += 1;
    }

    return Value.integer(@intCast(changed));
}

pub fn builtinFileRename(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.rename is not implemented on Windows", .{});
    }

    const from = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const to = try vm.coerceToPath(args[1], "no implicit conversion into String");
    const from_z = try vm.allocCStringZ(from);
    defer vm.allocator.free(from_z);
    const to_z = try vm.allocCStringZ(to);
    defer vm.allocator.free(to_z);

    const result = std.c.rename(from_z.ptr, to_z.ptr);
    if (result != 0) {
        return vm.raiseErrnoFmt(std.posix.errno(result), "failed to rename: {s}", .{from});
    }
    return Value.integer(0);
}

pub fn builtinFileExist(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.exist? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    std.Io.Dir.cwd().access(vm.io, path, .{}) catch return Value.boolean(false);
    return Value.boolean(true);
}

pub fn builtinFileWritable(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.writable? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const path_z = try vm.allocCStringZ(path);
    defer vm.allocator.free(path_z);
    return Value.boolean(std.c.access(path_z.ptr, std.c.W_OK) == 0);
}

pub fn builtinFileExecutable(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.executable? is not implemented on Windows", .{});
    }

    const path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const path_z = try vm.allocCStringZ(path);
    defer vm.allocator.free(path_z);
    return Value.boolean(std.c.access(path_z.ptr, std.c.X_OK) == 0);
}

pub fn builtinFileDelete(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "File.delete is not implemented on Windows", .{});
    }

    var deleted: usize = 0;
    for (args) |arg| {
        const path = try vm.coerceToPath(arg, "no implicit conversion into String");
        const path_z = try vm.allocCStringZ(path);
        defer vm.allocator.free(path_z);
        const result = std.c.unlink(path_z.ptr);
        if (result < 0) {
            return vm.raiseErrnoFmt(std.posix.errno(result), "No such file or directory @ unlink_internal - {s}", .{path});
        }
        deleted += 1;
    }
    return Value.integer(@intCast(deleted));
}

pub fn builtinFilePath(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const arg = args[0];
    if (arg.isIo()) {
        const io = arg.toIoObject();
        if (io.path) |p| {
            return vm.newStringWithEncoding(p, false, io.path_encoding orelse .{ .utf8 = .{} });
        }
        return Value.nil();
    }
    const path = try vm.coerceToPathValue(arg, "no implicit conversion into String");
    return vm.newStringWithEncoding(path.toStringObject().str, false, path.toStringObject().encoding);
}

pub fn builtinFileStatFileQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatBoolIvar(vm, receiver, "@file");
}

pub fn builtinFileStatDirectoryQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatBoolIvar(vm, receiver, "@directory");
}

pub fn builtinFileStatSymlinkQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatBoolIvar(vm, receiver, "@symlink");
}

pub fn builtinFileStatZeroQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const size = try fileStatIntegerIvar(vm, receiver, "@size");
    return Value.boolean(size.isInteger() and size.toInteger() == 0);
}

pub fn builtinFileStatSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@size");
}

pub fn builtinFileStatSizeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const size = try fileStatIntegerIvar(vm, receiver, "@size");
    if (size.isInteger() and size.toInteger() == 0) return Value.nil();
    return size;
}

pub fn builtinFileStatBlksize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@blksize");
}

pub fn builtinFileStatIno(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@ino");
}

pub fn builtinFileStatAtime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatTimeIvar(vm, receiver, "@atime");
}

pub fn builtinFileStatCtime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatTimeIvar(vm, receiver, "@ctime");
}

pub fn builtinFileStatMtime(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatTimeIvar(vm, receiver, "@mtime");
}

pub fn builtinFileStatMode(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@mode");
}

pub fn builtinFileStatUid(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@uid");
}

pub fn builtinFileStatGid(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return fileStatIntegerIvar(vm, receiver, "@gid");
}

pub fn builtinFileStatExecutableQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mode = try fileStatIntegerIvar(vm, receiver, "@mode");
    return Value.boolean(mode.isInteger() and (mode.toInteger() & 0o111) != 0);
}

// world_writable? returns the mode integer if world-writable, nil otherwise.
// In Ruby: (mode & 0o002 != 0) ? (mode & 0o7777) : nil
pub fn builtinFileStatWorldWritableQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mode = try fileStatIntegerIvar(vm, receiver, "@mode");
    if (!mode.isInteger()) return Value.nil();
    const m = mode.toInteger();
    if ((m & 0o002) != 0) return Value.integer(m & 0o7777);
    return Value.nil();
}

// sticky? returns true if the sticky bit is set.
pub fn builtinFileStatStickyQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mode = try fileStatIntegerIvar(vm, receiver, "@mode");
    return Value.boolean(mode.isInteger() and (mode.toInteger() & 0o1000) != 0);
}

// readable? returns true if world-readable or readable by owner/group.
pub fn builtinFileStatReadableQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mode = try fileStatIntegerIvar(vm, receiver, "@mode");
    return Value.boolean(mode.isInteger() and (mode.toInteger() & 0o444) != 0);
}

// writable? returns true if world-writable or writable by owner/group.
pub fn builtinFileStatWritableQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const mode = try fileStatIntegerIvar(vm, receiver, "@mode");
    return Value.boolean(mode.isInteger() and (mode.toInteger() & 0o222) != 0);
}

pub fn builtinFileFnmatch(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);

    const pattern_val = args[0];
    const path_val_raw = args[1];

    if (!pattern_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into String", .{vm.className(pattern_val)});
    }

    // Path accepts String or any object responding to #to_path.
    const path_val = try vm.coerceToPathValue(path_val_raw, "no implicit conversion of {s} into String");

    // Flags: must be Integer or respond to #to_int; string/nil raises TypeError.
    const flags: i64 = if (args.len == 3) blk: {
        const f = args[2];
        if (f.isInteger()) break :blk f.toInteger();
        break :blk try f.coerceToI64ViaToInt(
            vm,
            "no implicit conversion of {s} into Integer",
            "can't convert to Integer (to_int gives non-Integer)",
            "integer out of range",
        );
    } else 0;

    const pattern = pattern_val.toStringObject().str;
    const path = path_val.toStringObject().str;

    const matched = if ((flags & 0x10) != 0) // FNM_EXTGLOB
        (fnmBraceMatch(pattern, path, flags, vm.allocator) catch return error.Fatal)
    else
        fnmMatch(pattern, path, flags);

    return Value.boolean(matched);
}
