const std = @import("std");

const magic = "CORAPAK1";
const trailer_size = 64;
const archive_version: u32 = 1;

extern fn mkdtemp(template: [*:0]u8) ?[*:0]u8;

pub const ExtractedPackage = struct {
    root: []u8,
    entrypoint: []u8,

    pub fn deinit(self: *ExtractedPackage, allocator: std.mem.Allocator, io: std.Io) void {
        std.Io.Dir.cwd().deleteTree(io, self.root) catch {};
        allocator.free(self.entrypoint);
        allocator.free(self.root);
    }
};

const FileEntry = struct {
    path: []u8,
    contents: []u8,
};

fn appendInt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try list.appendSlice(allocator, &bytes);
}

fn readInt(comptime T: type, bytes: []const u8, cursor: *usize) !T {
    if (bytes.len -| cursor.* < @sizeOf(T)) return error.InvalidPackage;
    const result = std.mem.readInt(T, bytes[cursor.*..][0..@sizeOf(T)], .little);
    cursor.* += @sizeOf(T);
    return result;
}

fn isSafeRelativePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return false;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn isWithinRoot(path: []const u8, root: []const u8) bool {
    return std.mem.eql(u8, path, root) or
        (std.mem.startsWith(u8, path, root) and path.len > root.len and path[root.len] == '/');
}

fn isIgnored(relative_path: []const u8, patterns: []const []const u8) bool {
    for (patterns) |raw_pattern| {
        const pattern = std.mem.trim(u8, raw_pattern, " \t\r\n");
        if (pattern.len == 0 or pattern[0] == '#') continue;
        const normalized = std.mem.trimStart(u8, pattern, "/");
        if (std.mem.endsWith(u8, normalized, "/")) {
            const prefix = normalized[0 .. normalized.len - 1];
            if (std.mem.eql(u8, relative_path, prefix)) return true;
            if (std.mem.startsWith(u8, relative_path, prefix) and relative_path.len > prefix.len and relative_path[prefix.len] == '/') return true;
        } else if (std.mem.eql(u8, relative_path, normalized)) {
            return true;
        }
    }
    return false;
}

fn collectFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    relative_dir: []const u8,
    patterns: []const []const u8,
    entries: *std.ArrayList(FileEntry),
) !void {
    const disk_dir = if (relative_dir.len == 0) try allocator.dupe(u8, root) else try std.fs.path.join(allocator, &.{ root, relative_dir });
    defer allocator.free(disk_dir);
    var dir = try std.Io.Dir.cwd().openDir(io, disk_dir, .{ .iterate = true });
    defer dir.close(io);
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const relative_path = if (relative_dir.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fs.path.join(allocator, &.{ relative_dir, entry.name });
        defer allocator.free(relative_path);
        if (isIgnored(relative_path, patterns)) continue;
        switch (entry.kind) {
            .directory => try collectFiles(allocator, io, root, relative_path, patterns, entries),
            .file => {
                if (std.mem.endsWith(u8, relative_path, ".so") or std.mem.endsWith(u8, relative_path, ".bundle") or std.mem.endsWith(u8, relative_path, ".dylib")) return error.NativeExtensionsUnsupported;
                const disk_path = try std.fs.path.join(allocator, &.{ root, relative_path });
                defer allocator.free(disk_path);
                const contents = try std.Io.Dir.cwd().readFileAlloc(io, disk_path, allocator, .limited(std.math.maxInt(usize)));
                try entries.append(allocator, .{ .path = try allocator.dupe(u8, relative_path), .contents = contents });
            },
            else => return error.UnsupportedPackageFile,
        }
    }
}

fn entryLessThan(_: void, a: FileEntry, b: FileEntry) bool {
    return std.mem.order(u8, a.path, b.path) == .lt;
}

fn readIgnorePatterns(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !std.ArrayList([]const u8) {
    var patterns: std.ArrayList([]const u8) = .empty;
    const ignore_path = try std.fs.path.join(allocator, &.{ root, ".coraignore" });
    defer allocator.free(ignore_path);
    const contents = std.Io.Dir.cwd().readFileAlloc(io, ignore_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return patterns,
        else => return err,
    };
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| try patterns.append(allocator, try allocator.dupe(u8, line));
    allocator.free(contents);
    return patterns;
}

fn deinitEntries(allocator: std.mem.Allocator, entries: *std.ArrayList(FileEntry)) void {
    for (entries.items) |entry| {
        allocator.free(entry.path);
        allocator.free(entry.contents);
    }
    entries.deinit(allocator);
}

pub fn create(allocator: std.mem.Allocator, io: std.Io, entrypoint_arg: []const u8, root_arg: ?[]const u8, output: []const u8) !void {
    const entrypoint = try std.Io.Dir.cwd().realPathFileAlloc(io, entrypoint_arg, allocator);
    defer allocator.free(entrypoint);
    const default_root = std.fs.path.dirname(entrypoint) orelse return error.InvalidEntrypoint;
    const root = if (root_arg) |arg| try std.Io.Dir.cwd().realPathFileAlloc(io, arg, allocator) else try allocator.dupe(u8, default_root);
    defer allocator.free(root);
    if (!isWithinRoot(entrypoint, root)) return error.EntrypointOutsideRoot;
    const output_path = if (std.fs.path.isAbsolute(output))
        try allocator.dupe(u8, output)
    else blk: {
        const cwd = try std.process.currentPathAlloc(io, allocator);
        defer allocator.free(cwd);
        break :blk try std.fs.path.join(allocator, &.{ cwd, output });
    };
    defer allocator.free(output_path);
    if (isWithinRoot(output_path, root)) return error.OutputInsidePackageRoot;
    const entry_relative = std.mem.trimStart(u8, entrypoint[root.len..], "/");
    if (!isSafeRelativePath(entry_relative)) return error.InvalidEntrypoint;

    var patterns = try readIgnorePatterns(allocator, io, root);
    defer {
        for (patterns.items) |pattern| allocator.free(pattern);
        patterns.deinit(allocator);
    }
    var entries: std.ArrayList(FileEntry) = .empty;
    defer deinitEntries(allocator, &entries);
    try collectFiles(allocator, io, root, "", patterns.items, &entries);
    var included_entrypoint = false;
    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.path, entry_relative)) included_entrypoint = true;
    }
    if (!included_entrypoint) return error.EntrypointExcluded;
    std.mem.sort(FileEntry, entries.items, {}, entryLessThan);

    var archive: std.ArrayList(u8) = .empty;
    defer archive.deinit(allocator);
    try appendInt(&archive, allocator, u32, @intCast(entry_relative.len));
    try archive.appendSlice(allocator, entry_relative);
    try appendInt(&archive, allocator, u32, @intCast(entries.items.len));
    for (entries.items) |entry| {
        try appendInt(&archive, allocator, u32, @intCast(entry.path.len));
        try appendInt(&archive, allocator, u64, @intCast(entry.contents.len));
        try archive.appendSlice(allocator, entry.path);
        try archive.appendSlice(allocator, entry.contents);
    }

    const executable = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(executable);
    const stub = try std.Io.Dir.cwd().readFileAlloc(io, executable, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(stub);
    var trailer: [trailer_size]u8 = [_]u8{0} ** trailer_size;
    @memcpy(trailer[0..magic.len], magic);
    std.mem.writeInt(u32, trailer[8..12], archive_version, .little);
    std.mem.writeInt(u64, trailer[16..24], @intCast(stub.len), .little);
    std.mem.writeInt(u64, trailer[24..32], @intCast(archive.items.len), .little);
    std.crypto.hash.sha2.Sha256.hash(archive.items, trailer[32..64], .{});

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    try result.appendSlice(allocator, stub);
    try result.appendSlice(allocator, archive.items);
    try result.appendSlice(allocator, &trailer);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output, .data = result.items, .flags = .{ .permissions = @enumFromInt(0o755) } });
}

fn createTempRoot(allocator: std.mem.Allocator) ![]u8 {
    const template = try allocator.dupeZ(u8, "/tmp/cora-pack-XXXXXX");
    if (mkdtemp(template.ptr) == null) {
        allocator.free(template);
        return error.TempDirectoryUnavailable;
    }
    return template;
}

pub fn maybeExtract(allocator: std.mem.Allocator, io: std.Io) !?ExtractedPackage {
    const executable = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(executable);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, executable, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(bytes);
    if (bytes.len < trailer_size) return null;
    const trailer = bytes[bytes.len - trailer_size ..];
    if (!std.mem.eql(u8, trailer[0..magic.len], magic)) return null;
    if (std.mem.readInt(u32, trailer[8..12], .little) != archive_version) return error.InvalidPackage;
    const archive_offset: usize = @intCast(std.mem.readInt(u64, trailer[16..24], .little));
    const archive_len: usize = @intCast(std.mem.readInt(u64, trailer[24..32], .little));
    if (archive_offset > bytes.len or archive_len > bytes.len - archive_offset or archive_offset + archive_len != bytes.len - trailer_size) return error.InvalidPackage;
    const archive = bytes[archive_offset .. archive_offset + archive_len];
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(archive, &digest, .{});
    if (!std.mem.eql(u8, &digest, trailer[32..64])) return error.InvalidPackage;

    var cursor: usize = 0;
    const entry_len: usize = @intCast(try readInt(u32, archive, &cursor));
    if (archive.len -| cursor < entry_len) return error.InvalidPackage;
    const entry_relative = archive[cursor .. cursor + entry_len];
    cursor += entry_len;
    if (!isSafeRelativePath(entry_relative)) return error.InvalidPackage;
    const file_count: usize = @intCast(try readInt(u32, archive, &cursor));
    const root = try createTempRoot(allocator);
    errdefer {
        std.Io.Dir.cwd().deleteTree(io, root) catch {};
        allocator.free(root);
    }
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    var file_index: usize = 0;
    while (file_index < file_count) : (file_index += 1) {
        const path_len: usize = @intCast(try readInt(u32, archive, &cursor));
        const data_len: usize = @intCast(try readInt(u64, archive, &cursor));
        if (archive.len -| cursor < path_len) return error.InvalidPackage;
        const relative_path = archive[cursor .. cursor + path_len];
        cursor += path_len;
        if (!isSafeRelativePath(relative_path) or seen.contains(relative_path) or archive.len -| cursor < data_len) return error.InvalidPackage;
        try seen.put(relative_path, {});
        const data = archive[cursor .. cursor + data_len];
        cursor += data_len;
        const destination = try std.fs.path.join(allocator, &.{ root, relative_path });
        defer allocator.free(destination);
        if (std.fs.path.dirname(destination)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = destination, .data = data, .flags = .{ .permissions = @enumFromInt(0o600) } });
    }
    if (cursor != archive.len or !seen.contains(entry_relative)) return error.InvalidPackage;
    const entrypoint = try std.fs.path.join(allocator, &.{ root, entry_relative });
    return .{ .root = root, .entrypoint = entrypoint };
}
