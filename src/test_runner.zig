//! Default test runner for unit tests.
const builtin = @import("builtin");

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const build_options = @import("build_options");
const ruby_spec_runner = @import("ruby_spec_runner");

const verbose = @hasDecl(build_options, "test_verbose") and build_options.test_verbose;
const timing = @hasDecl(build_options, "test_timing") and build_options.test_timing;
const perf_trace = @hasDecl(build_options, "test_trace") and build_options.test_trace;
const test_filter_raw = if (@hasDecl(build_options, "test_filter_raw")) build_options.test_filter_raw else "";
const configured_test_jobs = if (@hasDecl(build_options, "test_jobs")) build_options.test_jobs else 0;
const configured_test_timeout_s: u64 = if (@hasDecl(build_options, "test_timeout")) build_options.test_timeout else 0;

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;
var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
var fba_buffer: [8192]u8 = undefined;
var stdin_buffer: [4096]u8 = undefined;
var stdout_buffer: [4096]u8 = undefined;
var process_io: std.Io = std.testing.io;

const ZigTestFn = @TypeOf(builtin.test_functions[0]);
const worker_result_prefix = "__cora_worker_result__ ";
var failed_test_names: std.ArrayListUnmanaged([]const u8) = .{ .items = &.{}, .capacity = 0 };
const non_tty_progress_interval: usize = 1000;

const CliOptions = struct {
    listen: bool = false,
    cache_dir: ?[]const u8 = null,
    worker_test_index: ?usize = null,
};

const total_specs_path = "spec/.total-specs";

fn readTotalSpecs() ?usize {
    const flags = std.c.O{
        .ACCMODE = .RDONLY,
    };
    const fd = std.c.open(@ptrCast(total_specs_path.ptr), flags, @as(u32, 0));
    if (fd < 0) return null;
    defer _ = std.c.close(fd);
    var buf: [32]u8 = undefined;
    const bytes_read = std.c.read(fd, &buf, buf.len);
    if (bytes_read <= 0) return null;
    const trimmed = std.mem.trim(u8, buf[0..@as(usize, @intCast(bytes_read))], " \n\r\t");
    return std.fmt.parseUnsigned(usize, trimmed, 10) catch null;
}

fn writeTotalSpecs(total: usize) void {
    const flags = std.c.O{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    };
    const fd = std.c.open(@ptrCast(total_specs_path.ptr), flags, @as(u32, 0o644));
    if (fd < 0) return;
    defer _ = std.c.close(fd);
    var buf: [32]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "{d}", .{total}) catch return;
    _ = std.c.write(fd, len.ptr, len.len);
}

const TestName = struct {
    display: []const u8,
    source: []const u8,
};

fn zigTestSourcePath(test_fn_name: []const u8, buf: []u8) []const u8 {
    const test_marker = std.mem.indexOf(u8, test_fn_name, ".test.") orelse return test_fn_name;
    const module_prefix = test_fn_name[0..test_marker];

    if (std.mem.startsWith(u8, module_prefix, "cora.")) {
        const rel = module_prefix["cora.".len..];
        const prefix = "src/";
        const suffix = ".zig";
        var pos: usize = 0;
        @memcpy(buf[pos..][0..prefix.len], prefix);
        pos += prefix.len;
        for (rel) |ch| {
            if (pos >= buf.len - suffix.len) return module_prefix;
            buf[pos] = if (ch == '.') '/' else ch;
            pos += 1;
        }
        @memcpy(buf[pos..][0..suffix.len], suffix);
        pos += suffix.len;
        return buf[0..pos];
    }

    const prefix = "test/";
    const suffix = ".zig";
    var pos: usize = 0;
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;
    var it = std.mem.splitScalar(u8, module_prefix, '.');
    var first = true;
    while (it.next()) |part| {
        if (!first) {
            if (pos >= buf.len - suffix.len) return module_prefix;
            buf[pos] = '/';
            pos += 1;
        }
        first = false;
        if (pos + part.len > buf.len - suffix.len) return module_prefix;
        @memcpy(buf[pos..][0..part.len], part);
        pos += part.len;
    }
    @memcpy(buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;
    return buf[0..pos];
}

const RubySpecTest = union(enum) {
    spec: ruby_spec_runner.SpecCase,
    no_specs_found: void,

    fn displayName(self: RubySpecTest) []const u8 {
        return switch (self) {
            .spec => |spec| spec.name,
            .no_specs_found => "ruby/spec (no _spec.rb files found in spec/)",
        };
    }

    fn sourcePath(self: RubySpecTest) []const u8 {
        return switch (self) {
            .spec => |spec| spec.path,
            .no_specs_found => "ruby/spec",
        };
    }
};

fn deinitRubySpecTests(allocator: std.mem.Allocator, tests: *std.ArrayList(RubySpecTest)) void {
    for (tests.items) |test_case| {
        switch (test_case) {
            .spec => |spec| ruby_spec_runner.deinitSpecCase(allocator, spec),
            .no_specs_found => {},
        }
    }
    tests.deinit(allocator);
}

fn filterMatches(name: []const u8) bool {
    if (test_filter_raw.len == 0) return true;

    var it = std.mem.splitScalar(u8, test_filter_raw, '|');
    while (it.next()) |raw| {
        const part = std.mem.trim(u8, raw, " \t\r\n");
        if (part.len == 0) continue;
        if (std.ascii.indexOfIgnoreCase(name, part) != null) return true;
    }

    return false;
}

fn loadRubySpecTests(allocator: std.mem.Allocator) !std.ArrayList(RubySpecTest) {
    var collected_specs: std.ArrayList(ruby_spec_runner.SpecCase) = .empty;
    defer collected_specs.deinit(allocator);

    try ruby_spec_runner.collectSpecCases(allocator, "spec", &collected_specs);
    ruby_spec_runner.sortSpecCases(collected_specs.items);

    var ruby_spec_tests: std.ArrayList(RubySpecTest) = .empty;
    errdefer deinitRubySpecTests(allocator, &ruby_spec_tests);

    for (collected_specs.items) |spec| {
        if (filterMatches(spec.name)) {
            try ruby_spec_tests.append(allocator, .{ .spec = spec });
        } else {
            ruby_spec_runner.deinitSpecCase(allocator, spec);
        }
    }

    if (ruby_spec_tests.items.len == 0 and test_filter_raw.len == 0 and collected_specs.items.len == 0) {
        try ruby_spec_tests.append(allocator, .{ .no_specs_found = {} });
    }

    return ruby_spec_tests;
}

fn runRubySpecTest(test_case: RubySpecTest) TestRunResult {
    switch (test_case) {
        .spec => |spec| {
            const run_result = ruby_spec_runner.runSpec(spec.path);
            var spec_stats = ruby_spec_runner.SpecStats{};
            var has_stats = false;
            if (run_result.stats) |stats| {
                has_stats = true;
                spec_stats = stats;
            } else {
                std.debug.print("WARNING: missing ruby spec stats for {s}\n", .{spec.path});
            }
            return .{
                .is_ruby_spec = true,
                .outcome = if (run_result.outcome == .pass) .pass else .fail,
                .err_name = if (run_result.outcome == .pass) null else "SpecFailed",
                .spec_total_delta = if (has_stats) spec_stats.total else 0,
                .spec_completed_delta = if (has_stats) spec_stats.total else 0,
                .ruby_passed_delta = if (has_stats) blk: {
                    break :blk (spec_stats.total -| spec_stats.failed) -| spec_stats.skipped;
                } else 0,
                .ruby_failed_delta = if (has_stats) spec_stats.failed else 0,
                .ruby_skipped_delta = if (has_stats) spec_stats.skipped else 0,
                .spec_timings = run_result.timings,
            };
        },
        .no_specs_found => {
            std.debug.print("No spec files found in spec/\n", .{});
            return .{
                .is_ruby_spec = true,
                .outcome = .fail,
                .err_name = "NoSpecsFound",
                .ruby_failed_delta = 0,
            };
        },
    }
}

const TestOutcome = enum {
    pass,
    skip,
    fail,
};

const TestRunResult = struct {
    is_ruby_spec: bool = false,
    outcome: TestOutcome = .pass,
    err_name: ?[]const u8 = null,
    err_name_owned: bool = false,
    log_err_count: usize = 0,
    leak: bool = false,
    fuzz: bool = false,
    spec_total_delta: usize = 0,
    spec_completed_delta: usize = 0,
    ruby_passed_delta: usize = 0,
    ruby_failed_delta: usize = 0,
    ruby_skipped_delta: usize = 0,
    elapsed_ns: u64 = 0,
    spec_timings: ruby_spec_runner.SpecTimings = .{},
};

const WorkerJsonResult = struct {
    is_ruby_spec: bool = false,
    outcome: TestOutcome,
    err_name: ?[]const u8 = null,
    log_err_count: usize = 0,
    leak: bool = false,
    fuzz: bool = false,
    spec_total_delta: usize = 0,
    spec_completed_delta: usize = 0,
    ruby_passed_delta: usize = 0,
    ruby_failed_delta: usize = 0,
    ruby_skipped_delta: usize = 0,
    elapsed_ns: u64 = 0,
    spec_timings: ruby_spec_runner.SpecTimings = .{},
};

const ActiveWorker = struct {
    child: std.process.Child,
    test_index: usize,
    spawned_at_ns: u64 = 0,
    timed_out: bool = false,
    stdout_buffer: std.ArrayList(u8) = .empty,
    stderr_buffer: std.ArrayList(u8) = .empty,

    fn deinit(self: *ActiveWorker, allocator: std.mem.Allocator) void {
        self.stdout_buffer.deinit(allocator);
        self.stderr_buffer.deinit(allocator);
    }
};

fn parseCliOptions(args: []const []const u8) CliOptions {
    var options = CliOptions{};
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--listen=-")) {
            options.listen = true;
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            testing.random_seed = std.fmt.parseUnsigned(u32, arg["--seed=".len..], 0) catch
                @panic("unable to parse --seed command line argument");
        } else if (std.mem.startsWith(u8, arg, "--cache-dir")) {
            options.cache_dir = arg["--cache-dir=".len..];
        } else if (std.mem.startsWith(u8, arg, "--worker-test-index=")) {
            options.worker_test_index = std.fmt.parseUnsigned(usize, arg["--worker-test-index=".len..], 10) catch
                @panic("unable to parse --worker-test-index command line argument");
        } else {
            @panic("unrecognized command line argument");
        }
    }
    return options;
}

fn resolveWorkerCount(test_count: usize) usize {
    if (test_count == 0) return 1;
    if (configured_test_jobs > 0) {
        const requested: usize = @intCast(configured_test_jobs);
        return @max(@as(usize, 1), @min(requested, test_count));
    }
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @max(@as(usize, 1), @min(cpu_count, test_count));
}

fn testIdForIndex(test_fns: []const ZigTestFn, ruby_spec_tests: []const RubySpecTest, index: usize, buf: []u8) TestName {
    if (index < test_fns.len) return .{
        .display = test_fns[index].name,
        .source = zigTestSourcePath(test_fns[index].name, buf),
    };
    const spec = ruby_spec_tests[index - test_fns.len];
    return .{
        .display = spec.displayName(),
        .source = spec.sourcePath(),
    };
}

fn getTimeNsec() u64 {
    var ts: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts))) {
        .SUCCESS => return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec),
        else => return 0,
    }
}

fn executeTestAtIndex(test_fns: []const ZigTestFn, ruby_spec_tests: []const RubySpecTest, index: usize) TestRunResult {
    var result = TestRunResult{};
    log_err_count = 0;
    testing.log_level = .warn;
    is_fuzz_test = false;
    testing.allocator_instance = .{};
    const start_ts = if (timing) getTimeNsec() else 0;
    defer {
        result.log_err_count = log_err_count;
        result.fuzz = is_fuzz_test;
        result.leak = testing.allocator_instance.deinit() == .leak;
    }

    if (index < test_fns.len) {
        const test_fn = test_fns[index];
        result.spec_total_delta = 0;
        result.spec_completed_delta = 1;
        if (verbose) {
            std.debug.print("TEST {s}\n", .{test_fn.name});
        }
        if (test_fn.func()) |_| {
            result.outcome = .pass;
        } else |err| switch (err) {
            error.SkipZigTest => {
                result.outcome = .skip;
                result.err_name = null;
            },
            else => {
                result.outcome = .fail;
                result.err_name = @errorName(err);
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
            },
        }
        if (timing) result.elapsed_ns = getTimeNsec() - start_ts;
        return result;
    }

    const spec_index = index - test_fns.len;
    if (spec_index >= ruby_spec_tests.len) {
        return .{
            .outcome = .fail,
            .err_name = "InvalidTestIndex",
            .elapsed_ns = if (timing) getTimeNsec() - start_ts else 0,
        };
    }

    const ruby_spec_test = ruby_spec_tests[spec_index];
    const test_name = ruby_spec_test.displayName();
    if (verbose) {
        std.debug.print("TEST {s}\n", .{test_name});
    }
    const ruby_result = runRubySpecTest(ruby_spec_test);
    result.is_ruby_spec = ruby_result.is_ruby_spec;
    result.outcome = ruby_result.outcome;
    result.err_name = ruby_result.err_name;
    result.spec_total_delta = ruby_result.spec_total_delta;
    result.spec_completed_delta = ruby_result.spec_completed_delta;
    result.ruby_passed_delta = ruby_result.ruby_passed_delta;
    result.ruby_failed_delta = ruby_result.ruby_failed_delta;
    result.ruby_skipped_delta = ruby_result.ruby_skipped_delta;
    result.spec_timings = ruby_result.spec_timings;
    if (timing) result.elapsed_ns = getTimeNsec() - start_ts;
    return result;
}

fn emitWorkerJsonResult(result: TestRunResult) void {
    const payload = WorkerJsonResult{
        .is_ruby_spec = result.is_ruby_spec,
        .outcome = result.outcome,
        .err_name = result.err_name,
        .log_err_count = result.log_err_count,
        .leak = result.leak,
        .fuzz = result.fuzz,
        .spec_total_delta = result.spec_total_delta,
        .spec_completed_delta = result.spec_completed_delta,
        .ruby_passed_delta = result.ruby_passed_delta,
        .ruby_failed_delta = result.ruby_failed_delta,
        .ruby_skipped_delta = result.ruby_skipped_delta,
        .elapsed_ns = result.elapsed_ns,
        .spec_timings = result.spec_timings,
    };

    const allocator = std.heap.page_allocator;
    const json = std.json.Stringify.valueAlloc(allocator, payload, .{}) catch {
        std.process.exit(2);
    };
    defer allocator.free(json);

    const stdout = std.Io.File.stdout();
    stdout.writeStreamingAll(process_io, worker_result_prefix) catch {};
    stdout.writeStreamingAll(process_io, json) catch {};
    stdout.writeStreamingAll(process_io, "\n") catch {};
}

fn findWorkerJson(stdout_data: []const u8) ?[]const u8 {
    const prefix_start = std.mem.lastIndexOf(u8, stdout_data, worker_result_prefix) orelse return null;
    const after_prefix = stdout_data[prefix_start + worker_result_prefix.len ..];
    const line_end = std.mem.indexOfScalar(u8, after_prefix, '\n') orelse after_prefix.len;
    return std.mem.trim(u8, after_prefix[0..line_end], " \t\r\n");
}

fn parseWorkerResult(allocator: std.mem.Allocator, term: std.process.Child.Term, stdout_data: []const u8) TestRunResult {
    if (findWorkerJson(stdout_data)) |json_text| {
        var parsed = std.json.parseFromSlice(WorkerJsonResult, allocator, json_text, .{
            .ignore_unknown_fields = true,
        }) catch {
            return .{
                .outcome = .fail,
                .err_name = "WorkerJsonParseFailure",
            };
        };
        defer parsed.deinit();

        var result = TestRunResult{
            .is_ruby_spec = parsed.value.is_ruby_spec,
            .outcome = parsed.value.outcome,
            .log_err_count = parsed.value.log_err_count,
            .leak = parsed.value.leak,
            .fuzz = parsed.value.fuzz,
            .spec_total_delta = parsed.value.spec_total_delta,
            .spec_completed_delta = parsed.value.spec_completed_delta,
            .ruby_passed_delta = parsed.value.ruby_passed_delta,
            .ruby_failed_delta = parsed.value.ruby_failed_delta,
            .ruby_skipped_delta = parsed.value.ruby_skipped_delta,
            .elapsed_ns = parsed.value.elapsed_ns,
            .spec_timings = parsed.value.spec_timings,
        };
        if (parsed.value.err_name) |name| {
            if (allocator.dupe(u8, name)) |duped| {
                result.err_name = duped;
                result.err_name_owned = true;
            } else |_| {
                result.err_name = "WorkerErrNameOOM";
                result.err_name_owned = false;
            }
        }
        return result;
    }

    switch (term) {
        .exited => |code| {
            return .{
                .outcome = .fail,
                .err_name = if (code == 0) "WorkerMissingJsonResult" else "WorkerExitedNonZero",
            };
        },
        else => {
            return .{
                .outcome = .fail,
                .err_name = "WorkerProcessTerminated",
            };
        },
    }
}

fn spawnWorkerProcess(
    exe_path: []const u8,
    seed: u32,
    test_index: usize,
) !ActiveWorker {
    var seed_arg_buf: [64]u8 = undefined;
    const seed_arg = try std.fmt.bufPrint(&seed_arg_buf, "--seed={d}", .{seed});
    var test_arg_buf: [96]u8 = undefined;
    const test_arg = try std.fmt.bufPrint(&test_arg_buf, "--worker-test-index={d}", .{test_index});

    const argv = [_][]const u8{
        exe_path,
        seed_arg,
        test_arg,
    };

    const child = try std.process.spawn(process_io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    return .{
        .child = child,
        .test_index = test_index,
        .spawned_at_ns = getTimeNsec(),
    };
}

const WorkerStream = enum {
    stdout,
    stderr,
};

const WorkerPollTarget = struct {
    worker_index: usize,
    stream: WorkerStream,
};

fn drainWorkerStream(allocator: std.mem.Allocator, worker: *ActiveWorker, stream: WorkerStream) !void {
    var read_buf: [8192]u8 = undefined;
    switch (stream) {
        .stdout => {
            if (worker.child.stdout) |*pipe| {
                const bytes_read = pipe.readStreaming(process_io, &.{read_buf[0..]}) catch |err| switch (err) {
                    error.EndOfStream => {
                        pipe.close(process_io);
                        worker.child.stdout = null;
                        return;
                    },
                    error.WouldBlock => return,
                    else => return err,
                };
                if (bytes_read == 0) {
                    pipe.close(process_io);
                    worker.child.stdout = null;
                    return;
                }
                try worker.stdout_buffer.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        },
        .stderr => {
            if (worker.child.stderr) |*pipe| {
                const bytes_read = pipe.readStreaming(process_io, &.{read_buf[0..]}) catch |err| switch (err) {
                    error.EndOfStream => {
                        pipe.close(process_io);
                        worker.child.stderr = null;
                        return;
                    },
                    error.WouldBlock => return,
                    else => return err,
                };
                if (bytes_read == 0) {
                    pipe.close(process_io);
                    worker.child.stderr = null;
                    return;
                }
                try worker.stderr_buffer.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        },
    }
}

fn printBufferedWorkerBlock(have_tty: bool, data: []const u8) void {
    if (data.len == 0) return;
    if (have_tty) {
        if (data[0] == '\n') {
            std.debug.print("\r{s}", .{data});
        } else {
            std.debug.print("\r\n{s}", .{data});
        }
    } else {
        std.debug.print("{s}", .{data});
    }
    if (data[data.len - 1] != '\n') {
        std.debug.print("\n", .{});
    }
}

const RunSummary = struct {
    zig_passed: usize = 0,
    zig_skipped: usize = 0,
    zig_failed: usize = 0,
    ruby_passed: usize = 0,
    ruby_skipped: usize = 0,
    ruby_failed: usize = 0,
    fuzz_count: usize = 0,
    leaks: usize = 0,
    log_err_count: usize = 0,
    known_total_specs: usize = 0,
    completed_specs: usize = 0,
    traced_specs: usize = 0,
    spec_timings: ruby_spec_runner.SpecTimings = .{},
};

fn printElapsedSuffix(elapsed_ns: u64) void {
    const elapsed_ms = elapsed_ns / 1_000_000;
    std.debug.print(" [{d}ms]", .{elapsed_ms});
}

fn printNonTtyProgress(completed_specs: usize, known_total_specs: usize) void {
    if (known_total_specs == 0) {
        std.debug.print("{d} specs\n", .{completed_specs});
    } else {
        std.debug.print("{d}/{d} specs\n", .{ completed_specs, known_total_specs });
    }
}

fn printNonTtyProgressMilestones(previous_completed_specs: usize, completed_specs: usize, known_total_specs: usize) void {
    if (completed_specs < non_tty_progress_interval) return;
    var milestone = ((previous_completed_specs / non_tty_progress_interval) + 1) * non_tty_progress_interval;
    while (milestone <= completed_specs) : (milestone += non_tty_progress_interval) {
        printNonTtyProgress(milestone, known_total_specs);
    }
}

fn printTerminalOutcome(
    have_tty: bool,
    completed_specs: usize,
    known_total_specs: usize,
    test_name: TestName,
    result: TestRunResult,
) void {
    if (!have_tty and !verbose and !timing) {
        if (result.outcome == .fail) {
            if (known_total_specs == 0) {
                std.debug.print("{d} specs {s}...FAIL ({s})\n", .{
                    completed_specs,
                    test_name.display,
                    result.err_name orelse "UnknownError",
                });
            } else {
                std.debug.print("{d}/{d} specs {s}...FAIL ({s})\n", .{
                    completed_specs,
                    known_total_specs,
                    test_name.display,
                    result.err_name orelse "UnknownError",
                });
            }
            return;
        }
        const previous_completed_specs = completed_specs - result.spec_completed_delta;
        printNonTtyProgressMilestones(previous_completed_specs, completed_specs, known_total_specs);
        return;
    }

    if (have_tty and !verbose and !timing) {
        switch (result.outcome) {
            .skip => {
                if (known_total_specs == 0) {
                    std.debug.print("\r{d} specs {s}...SKIP\n", .{ completed_specs, test_name.display });
                } else {
                    std.debug.print("\r{d}/{d} specs {s}...SKIP\n", .{
                        completed_specs,
                        known_total_specs,
                        test_name.display,
                    });
                }
            },
            .fail => {
                if (known_total_specs == 0) {
                    std.debug.print("\r{d} specs {s}...FAIL ({s})\n", .{
                        completed_specs,
                        test_name.display,
                        result.err_name orelse "UnknownError",
                    });
                } else {
                    std.debug.print("\r{d}/{d} specs {s}...FAIL ({s})\n", .{
                        completed_specs,
                        known_total_specs,
                        test_name.display,
                        result.err_name orelse "UnknownError",
                    });
                }
            },
            .pass => {},
        }
        return;
    }

    if (known_total_specs == 0) {
        std.debug.print("{d} specs {s}...", .{ completed_specs, test_name.display });
    } else {
        std.debug.print("{d}/{d} specs {s}...", .{ completed_specs, known_total_specs, test_name.display });
    }
    switch (result.outcome) {
        .pass => std.debug.print("OK", .{}),
        .skip => std.debug.print("SKIP", .{}),
        .fail => std.debug.print("FAIL ({s})", .{result.err_name orelse "UnknownError"}),
    }
    if (timing) printElapsedSuffix(result.elapsed_ns);
    std.debug.print("\n", .{});
}

fn applyResult(summary: *RunSummary, result: TestRunResult, test_name: TestName) void {
    summary.log_err_count += result.log_err_count;
    summary.leaks += @intFromBool(result.leak);
    summary.fuzz_count += @intFromBool(result.fuzz);
    summary.completed_specs += result.spec_completed_delta;
    if (perf_trace and result.is_ruby_spec) {
        summary.traced_specs += 1;
        summary.spec_timings.gc_init_ns += result.spec_timings.gc_init_ns;
        summary.spec_timings.parse_ns += result.spec_timings.parse_ns;
        summary.spec_timings.vm_init_ns += result.spec_timings.vm_init_ns;
        summary.spec_timings.compile_ns += result.spec_timings.compile_ns;
        summary.spec_timings.prepare_ns += result.spec_timings.prepare_ns;
        summary.spec_timings.execute_ns += result.spec_timings.execute_ns;
    }
    if (result.is_ruby_spec) {
        summary.ruby_passed += result.ruby_passed_delta;
        summary.ruby_skipped += result.ruby_skipped_delta;
        summary.ruby_failed += result.ruby_failed_delta;
    } else {
        switch (result.outcome) {
            .pass => summary.zig_passed += 1,
            .skip => summary.zig_skipped += 1,
            .fail => summary.zig_failed += 1,
        }
    }
    if (result.outcome == .fail) {
        const source_dupe = std.heap.page_allocator.dupe(u8, test_name.source) catch return;
        failed_test_names.append(std.heap.page_allocator, source_dupe) catch {};
    }
}

fn printSummary(summary: RunSummary) void {
    const zig_total = summary.zig_passed + summary.zig_skipped + summary.zig_failed;
    const ruby_total = summary.ruby_passed + summary.ruby_skipped + summary.ruby_failed;
    std.debug.print("\n", .{});
    std.debug.print("| test type  | passed | skipped | failed | total |\n", .{});
    std.debug.print("|------------|--------|---------|--------|-------|\n", .{});
    std.debug.print("| zig tests  | {d:<6} | {d:<7} | {d:<6} | {d:<5} |\n", .{
        summary.zig_passed,
        summary.zig_skipped,
        summary.zig_failed,
        zig_total,
    });
    std.debug.print("| ruby specs | {d:<6} | {d:<7} | {d:<6} | {d:<5} |\n", .{
        summary.ruby_passed,
        summary.ruby_skipped,
        summary.ruby_failed,
        ruby_total,
    });
    if (perf_trace and summary.traced_specs > 0) {
        const timings = summary.spec_timings;
        const seconds = struct {
            fn fromNs(ns: u64) f64 {
                return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
            }
        }.fromNs;
        std.debug.print("\nRuby spec trace ({d} specs, aggregate):\n", .{summary.traced_specs});
        std.debug.print("  gc init: {d:.3}s\n", .{seconds(timings.gc_init_ns)});
        std.debug.print("  parse: {d:.3}s\n", .{seconds(timings.parse_ns)});
        std.debug.print("  VM init: {d:.3}s\n", .{seconds(timings.vm_init_ns)});
        std.debug.print("  compile: {d:.3}s\n", .{seconds(timings.compile_ns)});
        std.debug.print("  prepare: {d:.3}s\n", .{seconds(timings.prepare_ns)});
        std.debug.print("  execute: {d:.3}s\n", .{seconds(timings.execute_ns)});
    }
    std.debug.print("\n", .{});
}

fn deinitTestRunResult(allocator: std.mem.Allocator, result: *TestRunResult) void {
    if (result.err_name_owned) {
        if (result.err_name) |err_name| {
            allocator.free(err_name);
        }
        result.err_name_owned = false;
        result.err_name = null;
    }
}

fn printParallelProgressStatus(have_tty: bool, summary: RunSummary, active_workers: usize) void {
    if (!have_tty or verbose or timing) return;
    if (summary.known_total_specs == 0) {
        std.debug.print(
            "\r{d} specs complete ({d} workers active)      ",
            .{ summary.completed_specs, active_workers },
        );
    } else {
        std.debug.print(
            "\r{d}/{d} specs complete ({d} workers active)      ",
            .{ summary.completed_specs, summary.known_total_specs, active_workers },
        );
    }
}

fn runProcessWorkerQueue(
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    seed: u32,
    worker_count: usize,
    test_fns: []const ZigTestFn,
    ruby_spec_tests: []const RubySpecTest,
    have_tty: bool,
    initial_total: usize,
) RunSummary {
    var summary = RunSummary{
        .known_total_specs = initial_total,
    };
    const total_tests = test_fns.len + ruby_spec_tests.len;
    if (total_tests == 0) return summary;
    defer if (have_tty and !verbose) std.debug.print("\n", .{});

    var active_workers: std.ArrayList(ActiveWorker) = .empty;
    defer {
        for (active_workers.items) |*worker| {
            worker.deinit(allocator);
        }
        active_workers.deinit(allocator);
    }

    var next_index: usize = 0;
    while (next_index < total_tests or active_workers.items.len > 0) {
        while (next_index < total_tests and active_workers.items.len < worker_count) {
            const worker = spawnWorkerProcess(exe_path, seed, next_index) catch |err| {
                const failure = TestRunResult{
                    .outcome = .fail,
                    .err_name = @errorName(err),
                };
                var spawn_buf: [256]u8 = undefined;
                const spawn_test_name = testIdForIndex(test_fns, ruby_spec_tests, next_index, &spawn_buf);
                applyResult(&summary, failure, spawn_test_name);
                printTerminalOutcome(have_tty, summary.completed_specs, summary.known_total_specs, spawn_test_name, failure);
                next_index += 1;
                continue;
            };
            active_workers.append(allocator, worker) catch |err| {
                std.debug.print("Failed to allocate active worker list: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
            next_index += 1;
        }
        printParallelProgressStatus(have_tty, summary, active_workers.items.len);

        if (active_workers.items.len == 0) continue;

        const poll_fds = allocator.alloc(std.posix.pollfd, active_workers.items.len * 2) catch |err| {
            std.debug.print("Failed to allocate poll fds: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer allocator.free(poll_fds);
        const poll_targets = allocator.alloc(WorkerPollTarget, active_workers.items.len * 2) catch |err| {
            std.debug.print("Failed to allocate poll targets: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer allocator.free(poll_targets);

        var poll_count: usize = 0;
        for (active_workers.items, 0..) |worker, worker_idx| {
            if (worker.child.stdout) |stdout_pipe| {
                poll_fds[poll_count] = .{
                    .fd = stdout_pipe.handle,
                    .events = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR,
                    .revents = 0,
                };
                poll_targets[poll_count] = .{
                    .worker_index = worker_idx,
                    .stream = .stdout,
                };
                poll_count += 1;
            }
            if (worker.child.stderr) |stderr_pipe| {
                poll_fds[poll_count] = .{
                    .fd = stderr_pipe.handle,
                    .events = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR,
                    .revents = 0,
                };
                poll_targets[poll_count] = .{
                    .worker_index = worker_idx,
                    .stream = .stderr,
                };
                poll_count += 1;
            }
        }

        if (poll_count > 0) {
            _ = std.posix.poll(poll_fds[0..poll_count], 100) catch |err| {
                std.debug.print("poll failed: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };

            // Kill workers that have exceeded the per-test timeout.
            if (configured_test_timeout_s > 0) {
                const now_ns: u64 = getTimeNsec();
                const limit_ns: u64 = configured_test_timeout_s * std.time.ns_per_s;
                for (active_workers.items) |*worker| {
                    if (!worker.timed_out and (now_ns -| worker.spawned_at_ns) >= limit_ns) {
                        worker.timed_out = true;
                        worker.child.kill(process_io);
                    }
                }
            }

            for (poll_fds[0..poll_count], poll_targets[0..poll_count]) |poll_fd, poll_target| {
                const revents = poll_fd.revents;
                if ((revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR)) == 0) continue;
                drainWorkerStream(allocator, &active_workers.items[poll_target.worker_index], poll_target.stream) catch |err| {
                    std.debug.print("Failed to read worker {s}: {s}\n", .{
                        @tagName(poll_target.stream),
                        @errorName(err),
                    });
                    std.process.exit(1);
                };
            }
        }

        var idx = active_workers.items.len;
        while (idx > 0) {
            idx -= 1;
            const i = idx;
            if (active_workers.items[i].child.stdout != null or active_workers.items[i].child.stderr != null) {
                continue;
            }

            var finished_worker = active_workers.swapRemove(i);
            defer finished_worker.deinit(allocator);

            const test_index = finished_worker.test_index;
            var work_buf: [256]u8 = undefined;
            const test_name = testIdForIndex(test_fns, ruby_spec_tests, test_index, &work_buf);
            const worker_stdout = finished_worker.stdout_buffer.items;
            const worker_stderr = finished_worker.stderr_buffer.items;

            var result: TestRunResult = undefined;
            if (finished_worker.timed_out) {
                result = .{
                    .outcome = .fail,
                    .err_name = "SpecTimeout",
                };
            } else if (finished_worker.child.wait(process_io)) |term| {
                result = parseWorkerResult(allocator, term, worker_stdout);
            } else |err| {
                result = .{
                    .outcome = .fail,
                    .err_name = @errorName(err),
                };
            }

            if (result.outcome == .fail) {
                printBufferedWorkerBlock(have_tty, worker_stderr);
                if (findWorkerJson(worker_stdout) == null and worker_stdout.len != 0) {
                    printBufferedWorkerBlock(have_tty, worker_stdout);
                }
            }

            applyResult(&summary, result, test_name);
            printTerminalOutcome(have_tty, summary.completed_specs, summary.known_total_specs, test_name, result);
            deinitTestRunResult(allocator, &result);
            printParallelProgressStatus(have_tty, summary, active_workers.items.len);
        }
    }

    return summary;
}

const crippled = switch (builtin.zig_backend) {
    .stage2_aarch64,
    .stage2_powerpc,
    .stage2_riscv64,
    => true,
    else => false,
};

pub fn main(init: std.process.Init) void {
    @disableInstrumentation();
    process_io = init.io;

    if (builtin.cpu.arch.isSpirV()) {
        // SPIR-V needs an special test-runner
        return;
    }

    if (crippled) {
        return mainSimple() catch @panic("test failure\n");
    }

    const args = init.minimal.args.toSlice(fba.allocator()) catch
        @panic("unable to parse command line args");
    const cli_options = parseCliOptions(args);

    fba.reset();
    if (builtin.fuzz) {
        const cache_dir = cli_options.cache_dir orelse @panic("missing --cache-dir=[path] argument");
        fuzzer_init(FuzzerSlice.fromSlice(cache_dir));
    }

    if (cli_options.listen) {
        return mainServer() catch @panic("internal test runner failure");
    } else if (cli_options.worker_test_index) |test_index| {
        return runSingleTerminalTestWorker(test_index);
    } else {
        return mainTerminal();
    }
}

fn mainServer() !void {
    @disableInstrumentation();
    var stdin_reader = std.Io.File.stdin().readerStreaming(process_io, &stdin_buffer);
    var stdout_writer = std.Io.File.stdout().writerStreaming(process_io, &stdout_buffer);
    var server = try std.zig.Server.init(.{
        .in = &stdin_reader.interface,
        .out = &stdout_writer.interface,
        .zig_version = builtin.zig_version_string,
    });

    if (builtin.fuzz) {
        const coverage_id = fuzzer_coverage_id();
        try server.serveU64Message(.coverage_id, coverage_id);
    }

    while (true) {
        const hdr = try server.receiveMessage();
        switch (hdr.tag) {
            .exit => {
                return std.process.exit(0);
            },
            .query_test_metadata => {
                testing.allocator_instance = .{};
                defer if (testing.allocator_instance.deinit() == .leak) {
                    @panic("internal test runner memory leak");
                };

                var ruby_spec_tests = try loadRubySpecTests(testing.allocator);
                defer deinitRubySpecTests(testing.allocator, &ruby_spec_tests);

                var string_bytes: std.ArrayListUnmanaged(u8) = .empty;
                defer string_bytes.deinit(testing.allocator);
                try string_bytes.append(testing.allocator, 0); // Reserve 0 for null.

                const test_fns = builtin.test_functions;
                const total_tests = test_fns.len + ruby_spec_tests.items.len;
                const names = try testing.allocator.alloc(u32, total_tests);
                defer testing.allocator.free(names);
                const expected_panic_msgs = try testing.allocator.alloc(u32, total_tests);
                defer testing.allocator.free(expected_panic_msgs);

                for (test_fns, names, expected_panic_msgs) |test_fn, *name, *expected_panic_msg| {
                    name.* = @intCast(string_bytes.items.len);
                    try string_bytes.ensureUnusedCapacity(testing.allocator, test_fn.name.len + 1);
                    string_bytes.appendSliceAssumeCapacity(test_fn.name);
                    string_bytes.appendAssumeCapacity(0);
                    expected_panic_msg.* = 0;
                }

                for (ruby_spec_tests.items, test_fns.len..) |ruby_spec_test, i| {
                    const test_name = ruby_spec_test.displayName();
                    names[i] = @intCast(string_bytes.items.len);
                    try string_bytes.ensureUnusedCapacity(testing.allocator, test_name.len + 1);
                    string_bytes.appendSliceAssumeCapacity(test_name);
                    string_bytes.appendAssumeCapacity(0);
                    expected_panic_msgs[i] = 0;
                }

                try server.serveTestMetadata(.{
                    .names = names,
                    .expected_panic_msgs = expected_panic_msgs,
                    .string_bytes = string_bytes.items,
                });
            },

            .run_test => {
                testing.allocator_instance = .{};
                log_err_count = 0;
                const index = try server.receiveBody_u32();
                var fail = false;
                var skip = false;
                is_fuzz_test = false;

                const test_fns = builtin.test_functions;
                if (index < test_fns.len) {
                    const test_fn = test_fns[index];
                    test_fn.func() catch |err| switch (err) {
                        error.SkipZigTest => skip = true,
                        else => {
                            fail = true;
                            if (@errorReturnTrace()) |trace| {
                                std.debug.dumpErrorReturnTrace(trace);
                            }
                        },
                    };
                } else {
                    var ruby_spec_tests = try loadRubySpecTests(testing.allocator);
                    if (index - test_fns.len >= ruby_spec_tests.items.len) {
                        deinitRubySpecTests(testing.allocator, &ruby_spec_tests);
                        return error.InvalidTestIndex;
                    }
                    const ruby_spec_test = ruby_spec_tests.items[index - test_fns.len];
                    const ruby_result = runRubySpecTest(ruby_spec_test);
                    if (ruby_result.outcome == .fail) {
                        fail = true;
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpErrorReturnTrace(trace);
                        }
                    }
                    deinitRubySpecTests(testing.allocator, &ruby_spec_tests);
                }

                const leak = testing.allocator_instance.deinit() == .leak;
                try server.serveTestResults(.{
                    .index = index,
                    .flags = .{
                        .status = if (skip) .skip else if (fail) .fail else .pass,
                        .fuzz = is_fuzz_test,
                        .log_err_count = std.math.lossyCast(
                            @FieldType(std.zig.Server.Message.TestResults.Flags, "log_err_count"),
                            log_err_count,
                        ),
                        .leak_count = if (leak) 1 else 0,
                    },
                });
            },
            .start_fuzzing => {
                if (!builtin.fuzz) unreachable;
                const index = try server.receiveBody_u32();
                const test_fn = builtin.test_functions[index];
                const entry_addr = @intFromPtr(test_fn.func);
                try server.serveU64Message(.fuzz_start_addr, entry_addr);
                defer if (testing.allocator_instance.deinit() == .leak) std.process.exit(1);
                is_fuzz_test = false;
                fuzzer_set_name(test_fn.name.ptr, test_fn.name.len);
                test_fn.func() catch |err| switch (err) {
                    error.SkipZigTest => return,
                    else => {
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpErrorReturnTrace(trace);
                        }
                        std.debug.print("failed with error.{s}\n", .{@errorName(err)});
                        std.process.exit(1);
                    },
                };
                if (!is_fuzz_test) @panic("missed call to std.testing.fuzz");
                if (log_err_count != 0) @panic("error logs detected");
            },

            else => {
                std.debug.print("unsupported message: {x}\n", .{@intFromEnum(hdr.tag)});
                std.process.exit(1);
            },
        }
    }
}

fn runSingleTerminalTestWorker(test_index: usize) void {
    @disableInstrumentation();
    const allocator = std.heap.page_allocator;
    const test_fns = builtin.test_functions;

    // Zig tests come before ruby specs. If the index is for a Zig test,
    // skip loading ruby specs entirely — the worker only needs the Zig
    // test function.
    if (test_index < test_fns.len) {
        const result = executeTestAtIndex(test_fns, &.{}, test_index);
        emitWorkerJsonResult(result);
        return;
    }

    // Ruby spec: load and filter to match the parent's view.
    var all_ruby_spec_tests = loadRubySpecTests(allocator) catch |err| {
        emitWorkerJsonResult(.{
            .outcome = .fail,
            .err_name = @errorName(err),
        });
        return;
    };
    defer deinitRubySpecTests(allocator, &all_ruby_spec_tests);

    var filtered_ruby_spec_tests: std.ArrayList(RubySpecTest) = .empty;
    defer {
        for (filtered_ruby_spec_tests.items) |*test_case| {
            test_case.* = undefined;
        }
        filtered_ruby_spec_tests.deinit(allocator);
    }
    for (all_ruby_spec_tests.items) |test_case| {
        if (filterMatches(test_case.displayName())) {
            filtered_ruby_spec_tests.append(allocator, test_case) catch |err| {
                emitWorkerJsonResult(.{
                    .outcome = .fail,
                    .err_name = @errorName(err),
                });
                return;
            };
        }
    }

    const spec_index = test_index - test_fns.len;
    if (spec_index >= filtered_ruby_spec_tests.items.len) {
        emitWorkerJsonResult(.{
            .outcome = .fail,
            .err_name = "InvalidWorkerTestIndex",
        });
        return;
    }

    const result = executeTestAtIndex(test_fns, filtered_ruby_spec_tests.items, test_index);
    emitWorkerJsonResult(result);
}

fn mainTerminal() void {
    @disableInstrumentation();
    const test_fn_list = builtin.test_functions;

    var ruby_spec_tests = loadRubySpecTests(std.heap.page_allocator) catch |err| {
        std.debug.print("Failed to discover ruby specs: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer deinitRubySpecTests(std.heap.page_allocator, &ruby_spec_tests);

    const total_tests = test_fn_list.len + ruby_spec_tests.items.len;
    const worker_count = resolveWorkerCount(total_tests);

    const saved_total = readTotalSpecs();
    if (worker_count > 1) {
        const allocator = std.heap.page_allocator;
        const child_exe_path = std.process.executablePathAlloc(process_io, allocator) catch |err| {
            std.debug.print("Failed to resolve test runner executable path: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer allocator.free(child_exe_path);

        const interactive_tty = (std.Io.File.stderr().isTty(process_io) catch false) and !verbose;
        const initial_total = if (test_filter_raw.len == 0) (saved_total orelse 0) else 0;
        if (!interactive_tty and !timing) {
            printNonTtyProgress(0, initial_total);
        }
        const summary = runProcessWorkerQueue(
            allocator,
            child_exe_path,
            testing.random_seed,
            worker_count,
            test_fn_list,
            ruby_spec_tests.items,
            interactive_tty,
            initial_total,
        );

        printSummary(summary);
        if (failed_test_names.items.len > 0) {
            std.debug.print("\nFailing specs:\n", .{});
            for (failed_test_names.items) |name| {
                std.debug.print("{s}\n", .{name});
            }
        }
        if (summary.log_err_count != 0) {
            std.debug.print("{d} errors were logged.\n", .{summary.log_err_count});
        }
        if (summary.leaks != 0) {
            std.debug.print("{d} tests leaked memory.\n", .{summary.leaks});
        }
        if (summary.fuzz_count != 0) {
            std.debug.print("{d} fuzz tests found.\n", .{summary.fuzz_count});
        }
        if (summary.leaks != 0 or summary.log_err_count != 0 or summary.zig_failed != 0 or summary.ruby_failed != 0) {
            std.process.exit(1);
        }
        if (summary.completed_specs > 0 and test_filter_raw.len == 0) {
            writeTotalSpecs(summary.completed_specs);
        }
        return;
    }

    var summary = RunSummary{};
    if (saved_total != null and test_filter_raw.len == 0) {
        summary.known_total_specs = saved_total.?;
    }
    const root_node = if (builtin.fuzz or verbose) std.Progress.Node.none else std.Progress.start(process_io, .{
        .root_name = "Test",
        .estimated_total_items = total_tests,
    });
    const have_tty = (std.Io.File.stderr().isTty(process_io) catch false) and !verbose;
    if (!have_tty and !timing) {
        printNonTtyProgress(0, summary.known_total_specs);
    }

    var async_frame_buffer: []align(builtin.target.stackAlignment()) u8 = undefined;
    async_frame_buffer = &[_]u8{};

    for (0..total_tests) |test_index| {
        var buf: [256]u8 = undefined;
        const test_name = testIdForIndex(test_fn_list, ruby_spec_tests.items, test_index, &buf);
        const test_node = root_node.start(test_name.display, 0);
        const result = executeTestAtIndex(test_fn_list, ruby_spec_tests.items, test_index);
        test_node.end();

        applyResult(&summary, result, test_name);
        printTerminalOutcome(have_tty, summary.completed_specs, summary.known_total_specs, test_name, result);
        if (have_tty) {
            printParallelProgressStatus(have_tty, summary, 0);
        }
    }

    if (have_tty) std.debug.print("\n", .{});
    root_node.end();
    printSummary(summary);
    if (failed_test_names.items.len > 0) {
        std.debug.print("\nFailing specs:\n", .{});
        for (failed_test_names.items) |name| {
            std.debug.print("{s}\n", .{name});
        }
    }
    if (summary.log_err_count != 0) {
        std.debug.print("{d} errors were logged.\n", .{summary.log_err_count});
    }
    if (summary.leaks != 0) {
        std.debug.print("{d} tests leaked memory.\n", .{summary.leaks});
    }
    if (summary.fuzz_count != 0) {
        std.debug.print("{d} fuzz tests found.\n", .{summary.fuzz_count});
    }
    if (summary.leaks != 0 or summary.log_err_count != 0 or summary.zig_failed != 0 or summary.ruby_failed != 0) {
        std.process.exit(1);
    }
    if (summary.known_total_specs != 0 and test_filter_raw.len == 0) {
        writeTotalSpecs(summary.known_total_specs);
    }
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.foo),
    comptime format: []const u8,
    args: anytype,
) void {
    @disableInstrumentation();
    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) {
        log_err_count +|= 1;
    }
    if (@intFromEnum(message_level) <= @intFromEnum(testing.log_level)) {
        std.debug.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n",
            args,
        );
    }
}

/// Simpler main(), exercising fewer language features, so that
/// work-in-progress backends can handle it.
pub fn mainSimple() anyerror!void {
    @disableInstrumentation();
    // is the backend capable of calling `std.fs.File.writeAll`?
    const enable_write = switch (builtin.zig_backend) {
        .stage2_aarch64, .stage2_riscv64 => true,
        else => false,
    };
    // is the backend capable of calling `std.Io.Writer.print`?
    const enable_print = switch (builtin.zig_backend) {
        .stage2_aarch64, .stage2_riscv64 => true,
        else => false,
    };

    var passed: u64 = 0;
    var skipped: u64 = 0;
    var failed: u64 = 0;

    // we don't want to bring in File and Writer if the backend doesn't support it
    const stdout = if (enable_write) std.Io.File.stdout() else {};

    for (builtin.test_functions) |test_fn| {
        if (enable_write) {
            stdout.writeStreamingAll(process_io, test_fn.name) catch {};
            stdout.writeStreamingAll(process_io, "... ") catch {};
        }
        if (test_fn.func()) |_| {
            if (enable_write) stdout.writeStreamingAll(process_io, "PASS\n") catch {};
        } else |err| {
            if (err != error.SkipZigTest) {
                if (enable_write) stdout.writeStreamingAll(process_io, "FAIL\n") catch {};
                failed += 1;
                if (!enable_write) return err;
                continue;
            }
            if (enable_write) stdout.writeStreamingAll(process_io, "SKIP\n") catch {};
            skipped += 1;
            continue;
        }
        passed += 1;
    }
    if (enable_print) {
        var stdout_writer = stdout.writer(&.{});
        stdout_writer.interface.print("{} passed, {} skipped, {} failed\n", .{ passed, skipped, failed }) catch {};
    }
    if (failed != 0) std.process.exit(1);
}

const FuzzerSlice = extern struct {
    ptr: [*]const u8,
    len: usize,

    /// Inline to avoid fuzzer instrumentation.
    inline fn toSlice(s: FuzzerSlice) []const u8 {
        return s.ptr[0..s.len];
    }

    /// Inline to avoid fuzzer instrumentation.
    inline fn fromSlice(s: []const u8) FuzzerSlice {
        return .{ .ptr = s.ptr, .len = s.len };
    }
};

var is_fuzz_test: bool = undefined;

extern fn fuzzer_set_name(name_ptr: [*]const u8, name_len: usize) void;
extern fn fuzzer_init(cache_dir: FuzzerSlice) void;
extern fn fuzzer_init_corpus_elem(input_ptr: [*]const u8, input_len: usize) void;
extern fn fuzzer_start(testOne: *const fn ([*]const u8, usize) callconv(.c) void) void;
extern fn fuzzer_coverage_id() u64;

pub fn fuzz(
    context: anytype,
    comptime testOne: fn (context: @TypeOf(context), []const u8) anyerror!void,
    options: testing.FuzzInputOptions,
) anyerror!void {
    // Prevent this function from confusing the fuzzer by omitting its own code
    // coverage from being considered.
    @disableInstrumentation();

    // Some compiler backends are not capable of handling fuzz testing yet but
    // we still want CI test coverage enabled.
    if (crippled) return;

    // Smoke test to ensure the test did not use conditional compilation to
    // contradict itself by making it not actually be a fuzz test when the test
    // is built in fuzz mode.
    is_fuzz_test = true;

    // Ensure no test failure occurred before starting fuzzing.
    if (log_err_count != 0) @panic("error logs detected");

    // libfuzzer is in a separate compilation unit so that its own code can be
    // excluded from code coverage instrumentation. It needs a function pointer
    // it can call for checking exactly one input. Inside this function we do
    // our standard unit test checks such as memory leaks, and interaction with
    // error logs.
    const global = struct {
        var ctx: @TypeOf(context) = undefined;

        fn fuzzer_one(input_ptr: [*]const u8, input_len: usize) callconv(.c) void {
            @disableInstrumentation();
            testing.allocator_instance = .{};
            defer if (testing.allocator_instance.deinit() == .leak) std.process.exit(1);
            log_err_count = 0;
            testOne(ctx, input_ptr[0..input_len]) catch |err| switch (err) {
                error.SkipZigTest => return,
                else => {
                    std.debug.lockStdErr();
                    if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
                    std.debug.print("failed with error.{s}\n", .{@errorName(err)});
                    std.process.exit(1);
                },
            };
            if (log_err_count != 0) {
                std.debug.lockStdErr();
                std.debug.print("error logs detected\n", .{});
                std.process.exit(1);
            }
        }
    };
    if (builtin.fuzz) {
        const prev_allocator_state = testing.allocator_instance;
        testing.allocator_instance = .{};
        defer testing.allocator_instance = prev_allocator_state;

        for (options.corpus) |elem| fuzzer_init_corpus_elem(elem.ptr, elem.len);

        global.ctx = context;
        fuzzer_start(&global.fuzzer_one);
        return;
    }

    // When the unit test executable is not built in fuzz mode, only run the
    // provided corpus.
    for (options.corpus) |input| {
        try testOne(context, input);
    }

    // In case there is no provided corpus, also use an empty
    // string as a smoke test.
    try testOne(context, "");
}
