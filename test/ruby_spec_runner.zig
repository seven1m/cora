const std = @import("std");
const builtin = @import("builtin");
const cora = @import("cora");
const load_path = cora.load_path;
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const Value = cora.value.Value;
const bdwgc = @import("bdwgc");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

const spec_stats_prefix = "__cora_spec_stats__ ";

pub const SpecCase = struct {
    path: []const u8,
    name: []const u8,
};

pub const SpecStats = struct {
    total: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
};

pub const RunSpecResult = struct {
    outcome: enum {
        pass,
        fail,
    },
    stats: ?SpecStats = null,
};

pub const EvalResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    err: ?anyerror,
};

pub const TestWriter = struct {
    buffer: []u8,
    used: usize = 0,
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .sendFile = std.Io.Writer.unimplementedSendFile,
    };

    pub fn init(buffer: []u8) TestWriter {
        return .{
            .buffer = buffer,
            .interface = .{
                .vtable = &vtable,
                .buffer = &.{},
            },
        };
    }

    pub fn written(self: *const TestWriter) []const u8 {
        return self.buffer[0..self.used];
    }

    fn drain(io_w: *std.Io.Writer, data: []const []const u8, _: usize) std.Io.Writer.Error!usize {
        const w: *TestWriter = @alignCast(@fieldParentPtr("interface", io_w));
        var total: usize = 0;
        for (data) |slice| {
            if (w.used + slice.len > w.buffer.len) return error.WriteFailed;
            @memcpy(w.buffer[w.used..][0..slice.len], slice);
            w.used += slice.len;
            total += slice.len;
        }
        return total;
    }
};

pub fn deinitSpecCase(allocator: std.mem.Allocator, spec: SpecCase) void {
    allocator.free(spec.path);
    allocator.free(spec.name);
}

pub fn deinitSpecCases(allocator: std.mem.Allocator, specs: *std.ArrayList(SpecCase)) void {
    for (specs.items) |spec| {
        deinitSpecCase(allocator, spec);
    }
    specs.deinit(allocator);
}

pub fn collectSpecCases(allocator: std.mem.Allocator, dir_path: []const u8, specs: *std.ArrayList(SpecCase)) !void {
    var dir = std.Io.Dir.cwd().openDir(std.testing.io, dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close(std.testing.io);

    var iter = dir.iterate();
    while (try iter.next(std.testing.io)) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });

        if (entry.kind == .directory) {
            try collectSpecCases(allocator, full_path, specs);
            allocator.free(full_path);
            continue;
        }

        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, "_spec.rb")) {
            const test_name = try std.fmt.allocPrint(allocator, "ruby/spec {s}", .{full_path});
            try specs.append(allocator, .{
                .path = full_path,
                .name = test_name,
            });
            continue;
        }

        allocator.free(full_path);
    }
}

pub fn sortSpecCases(specs: []SpecCase) void {
    std.sort.block(SpecCase, specs, {}, struct {
        fn lessThan(_: void, lhs: SpecCase, rhs: SpecCase) bool {
            return std.mem.order(u8, lhs.path, rhs.path) == .lt;
        }
    }.lessThan);
}

fn parseSpecStats(stdout: []const u8) ?SpecStats {
    var search_start: usize = 0;
    var marker_line: ?[]const u8 = null;
    while (std.mem.indexOfPos(u8, stdout, search_start, spec_stats_prefix)) |prefix_start| {
        const line_start = prefix_start + spec_stats_prefix.len;
        const after_start = stdout[line_start..];
        const line_end_rel = std.mem.indexOfScalar(u8, after_start, '\n') orelse after_start.len;
        marker_line = std.mem.trim(u8, after_start[0..line_end_rel], " \t\r\n");
        search_start = line_start + line_end_rel;
    }
    const line = marker_line orelse return null;

    var stats = SpecStats{};
    var has_total = false;
    var has_passed = false;
    var has_failed = false;
    var has_skipped = false;

    var token_it = std.mem.splitScalar(u8, line, ' ');
    while (token_it.next()) |token| {
        if (token.len == 0) continue;
        const eq_index = std.mem.indexOfScalar(u8, token, '=') orelse continue;
        const key = token[0..eq_index];
        const value = token[eq_index + 1 ..];
        const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return null;

        if (std.mem.eql(u8, key, "total")) {
            stats.total = parsed;
            has_total = true;
        } else if (std.mem.eql(u8, key, "passed")) {
            stats.passed = parsed;
            has_passed = true;
        } else if (std.mem.eql(u8, key, "failed")) {
            stats.failed = parsed;
            has_failed = true;
        } else if (std.mem.eql(u8, key, "skipped")) {
            stats.skipped = parsed;
            has_skipped = true;
        }
    }

    if (!(has_total and has_passed and has_failed and has_skipped)) return null;
    return stats;
}

fn setSpecStatsEnv() ?[]u8 {
    const allocator = std.heap.page_allocator;
    const previous = if (std.c.getenv("CORA_SPEC_STATS")) |value_z|
        allocator.dupe(u8, std.mem.span(value_z)) catch null
    else
        null;

    const key_z = allocator.dupeZ(u8, "CORA_SPEC_STATS") catch {
        if (previous) |value| allocator.free(value);
        return previous;
    };
    defer allocator.free(key_z);
    const value_z = allocator.dupeZ(u8, "1") catch {
        if (previous) |value| allocator.free(value);
        return previous;
    };
    defer allocator.free(value_z);

    _ = setenv(key_z.ptr, value_z.ptr, 1);
    return previous;
}

fn restoreSpecStatsEnv(previous_value: ?[]u8) void {
    const allocator = std.heap.page_allocator;
    defer if (previous_value) |value| allocator.free(value);

    const key_z = allocator.dupeZ(u8, "CORA_SPEC_STATS") catch return;
    defer allocator.free(key_z);

    if (previous_value) |value| {
        const value_z = allocator.dupeZ(u8, value) catch return;
        defer allocator.free(value_z);
        _ = setenv(key_z.ptr, value_z.ptr, 1);
    } else {
        _ = unsetenv(key_z.ptr);
    }
}

pub fn runSpec(path: []const u8) RunSpecResult {
    var stdout_buf: [32768]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const previous_env_value = setSpecStatsEnv();
    defer restoreSpecStatsEnv(previous_env_value);

    const result = evalFile(path, &stdout_buf, &stderr_buf);
    const stats = parseSpecStats(result.stdout);

    if (result.err != null) {
        std.debug.print("\nSpec error ({s}): {s}\n{s}\n", .{ path, result.stdout, result.stderr });
        return .{
            .outcome = .fail,
            .stats = stats,
        };
    }

    if (std.mem.indexOf(u8, result.stdout, "OK:") == null) {
        std.debug.print("\nSpec failed ({s}):\n{s}\n", .{ path, result.stdout });
        return .{
            .outcome = .fail,
            .stats = stats,
        };
    }

    return .{
        .outcome = .pass,
        .stats = stats,
    };
}

pub fn evalFile(path: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    const allocator = std.heap.page_allocator;
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const abs_path = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch {
        return .{
            .stdout = "",
            .stderr = "",
            .err = error.FileNotFound,
        };
    };
    defer allocator.free(abs_path);

    const ruby_code = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch {
        return .{
            .stdout = "",
            .stderr = "",
            .err = error.FileReadFailed,
        };
    };
    defer allocator.free(ruby_code);

    return evalCodeWithOutputAndPath(ruby_code, stdout_buf, stderr_buf, abs_path);
}

fn appendRepoLoadPaths(vm: *VM, io: std.Io) !void {
    for (load_path.repo_load_paths) |path| {
        var rel_path_buffer: [4096]u8 = undefined;
        const runtime_path = std.fmt.bufPrint(&rel_path_buffer, "build/{s}", .{path}) catch continue;
        var path_buffer: [4096]u8 = undefined;
        const abs_len = std.Io.Dir.cwd().realPathFile(io, runtime_path, &path_buffer) catch 0;
        if (abs_len == 0) continue;
        try vm.appendLoadPath(path_buffer[0..abs_len]);
    }
    try vm.syncLoadPathGlobals();
}

fn evalCodeWithOutputAndPath(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8, source_path: ?[]const u8) EvalResult {
    bdwgc.init();
    if (builtin.mode != .Debug) bdwgc.disableWarnings();
    defer bdwgc.deinit();

    const allocator = std.heap.page_allocator;

    var parser = prism.Parser.init(allocator, ruby_code, source_path) catch |err| {
        return .{
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };
    defer parser.deinit();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, threaded.io(), std.testing.environ);
    defer vm.deinit();

    var program = compiler.Compiler.compile(allocator, &parser, 1) catch |err| {
        return .{
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };
    defer program.deinit();

    vm.prepare(&program) catch |err| {
        return .{
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };

    appendRepoLoadPaths(&vm, threaded.io()) catch |err| {
        return .{
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };

    var stdout_writer = TestWriter.init(stdout_buf);
    vm.stdout = &stdout_writer.interface;

    var stderr_writer = TestWriter.init(stderr_buf);
    vm.stderr = &stderr_writer.interface;

    const run_result = vm.run();

    const at_exit_result = vm.runAtExitHandlers();
    if (at_exit_result) |_| {
        // Completed.
    } else |err| {
        if (err == error.UnhandledException) {
            vm.printUnhandledException();
        }
        return .{
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }

    if (run_result) |_| {
        return .{
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = null,
        };
    } else |err| {
        if (err == error.UnhandledException) {
            vm.printUnhandledException();
        }
        return .{
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }
}
