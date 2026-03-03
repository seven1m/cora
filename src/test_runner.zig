//! Default test runner for unit tests.
const builtin = @import("builtin");

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const build_options = @import("build_options");
const ruby_spec_runner = @import("ruby_spec_runner");

const verbose = @hasDecl(build_options, "test_verbose") and build_options.test_verbose;
const test_filter_raw = if (@hasDecl(build_options, "test_filter_raw")) build_options.test_filter_raw else "";
const configured_test_jobs = if (@hasDecl(build_options, "test_jobs")) build_options.test_jobs else 0;

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;
var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
var fba_buffer: [8192]u8 = undefined;
var stdin_buffer: [4096]u8 = undefined;
var stdout_buffer: [4096]u8 = undefined;

const ZigTestFn = @TypeOf(builtin.test_functions[0]);
const worker_result_prefix = "__cora_worker_result__ ";

const CliOptions = struct {
    listen: bool = false,
    cache_dir: ?[]const u8 = null,
    worker_test_index: ?usize = null,
};

const RubySpecTest = union(enum) {
    spec: ruby_spec_runner.SpecCase,
    no_specs_found: void,

    fn displayName(self: RubySpecTest) []const u8 {
        return switch (self) {
            .spec => |spec| spec.name,
            .no_specs_found => "ruby/spec (no _spec.rb files found in spec/)",
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
        if (std.mem.indexOf(u8, name, part) != null) return true;
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
            var spec_total_delta: usize = 0;
            if (run_result.stats) |stats| {
                spec_total_delta = stats.total;
            }
            return .{
                .outcome = if (run_result.outcome == .pass) .pass else .fail,
                .err_name = if (run_result.outcome == .pass) null else "SpecFailed",
                .spec_total_delta = spec_total_delta,
                .spec_completed_delta = spec_total_delta,
            };
        },
        .no_specs_found => {
            std.debug.print("No spec files found in spec/\n", .{});
            return .{
                .outcome = .fail,
                .err_name = "NoSpecsFound",
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
    outcome: TestOutcome = .pass,
    err_name: ?[]const u8 = null,
    err_name_owned: bool = false,
    log_err_count: usize = 0,
    leak: bool = false,
    fuzz: bool = false,
    spec_total_delta: usize = 0,
    spec_completed_delta: usize = 0,
};

const WorkerJsonResult = struct {
    outcome: TestOutcome,
    err_name: ?[]const u8 = null,
    log_err_count: usize = 0,
    leak: bool = false,
    fuzz: bool = false,
    spec_total_delta: usize = 0,
    spec_completed_delta: usize = 0,
};

const ActiveWorker = struct {
    child: std.process.Child,
    test_index: usize,
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

fn testNameForIndex(test_fns: []const ZigTestFn, ruby_spec_tests: []const RubySpecTest, index: usize) []const u8 {
    if (index < test_fns.len) return test_fns[index].name;
    return ruby_spec_tests[index - test_fns.len].displayName();
}

fn executeTestAtIndex(test_fns: []const ZigTestFn, ruby_spec_tests: []const RubySpecTest, index: usize) TestRunResult {
    var result = TestRunResult{};
    log_err_count = 0;
    testing.log_level = .warn;
    is_fuzz_test = false;
    testing.allocator_instance = .{};
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
                    std.debug.dumpStackTrace(trace.*);
                }
            },
        }
        return result;
    }

    const spec_index = index - test_fns.len;
    if (spec_index >= ruby_spec_tests.len) {
        return .{
            .outcome = .fail,
            .err_name = "InvalidTestIndex",
        };
    }

    const ruby_spec_test = ruby_spec_tests[spec_index];
    if (verbose) {
        std.debug.print("TEST {s}\n", .{ruby_spec_test.displayName()});
    }
    const ruby_result = runRubySpecTest(ruby_spec_test);
    result.outcome = ruby_result.outcome;
    result.err_name = ruby_result.err_name;
    result.spec_total_delta = ruby_result.spec_total_delta;
    result.spec_completed_delta = ruby_result.spec_completed_delta;
    return result;
}

fn emitWorkerJsonResult(result: TestRunResult) void {
    const payload = WorkerJsonResult{
        .outcome = result.outcome,
        .err_name = result.err_name,
        .log_err_count = result.log_err_count,
        .leak = result.leak,
        .fuzz = result.fuzz,
        .spec_total_delta = result.spec_total_delta,
        .spec_completed_delta = result.spec_completed_delta,
    };

    const allocator = std.heap.page_allocator;
    const json = std.json.Stringify.valueAlloc(allocator, payload, .{}) catch {
        std.process.exit(2);
    };
    defer allocator.free(json);

    const stdout = std.fs.File.stdout();
    stdout.writeAll(worker_result_prefix) catch {};
    stdout.writeAll(json) catch {};
    stdout.writeAll("\n") catch {};
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
            .outcome = parsed.value.outcome,
            .log_err_count = parsed.value.log_err_count,
            .leak = parsed.value.leak,
            .fuzz = parsed.value.fuzz,
            .spec_total_delta = parsed.value.spec_total_delta,
            .spec_completed_delta = parsed.value.spec_completed_delta,
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
        .Exited => |code| {
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
    allocator: std.mem.Allocator,
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

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    return .{
        .child = child,
        .test_index = test_index,
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
                const bytes_read = pipe.read(&read_buf) catch |err| switch (err) {
                    error.WouldBlock => return,
                    else => return err,
                };
                if (bytes_read == 0) {
                    pipe.close();
                    worker.child.stdout = null;
                    return;
                }
                try worker.stdout_buffer.appendSlice(allocator, read_buf[0..bytes_read]);
            }
        },
        .stderr => {
            if (worker.child.stderr) |*pipe| {
                const bytes_read = pipe.read(&read_buf) catch |err| switch (err) {
                    error.WouldBlock => return,
                    else => return err,
                };
                if (bytes_read == 0) {
                    pipe.close();
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
    ok_count: usize = 0,
    skip_count: usize = 0,
    fail_count: usize = 0,
    fuzz_count: usize = 0,
    leaks: usize = 0,
    log_err_count: usize = 0,
    known_total_specs: usize = 0,
    completed_specs: usize = 0,
};

fn printTerminalOutcome(
    have_tty: bool,
    completed_specs: usize,
    known_total_specs: usize,
    test_name: []const u8,
    result: TestRunResult,
) void {
    if (have_tty) {
        switch (result.outcome) {
            .skip => std.debug.print("\r{d}/{d} specs {s}...SKIP\n", .{
                completed_specs,
                known_total_specs,
                test_name,
            }),
            .fail => std.debug.print("\r{d}/{d} specs {s}...FAIL ({s})\n", .{
                completed_specs,
                known_total_specs,
                test_name,
                result.err_name orelse "UnknownError",
            }),
            .pass => {},
        }
        return;
    }

    std.debug.print("{d}/{d} specs {s}...", .{ completed_specs, known_total_specs, test_name });
    switch (result.outcome) {
        .pass => std.debug.print("OK\n", .{}),
        .skip => std.debug.print("SKIP\n", .{}),
        .fail => std.debug.print("FAIL ({s})\n", .{result.err_name orelse "UnknownError"}),
    }
}

fn applyResult(summary: *RunSummary, result: TestRunResult) void {
    summary.log_err_count += result.log_err_count;
    summary.leaks += @intFromBool(result.leak);
    summary.fuzz_count += @intFromBool(result.fuzz);
    summary.known_total_specs += result.spec_total_delta;
    summary.completed_specs += result.spec_completed_delta;
    switch (result.outcome) {
        .pass => summary.ok_count += 1,
        .skip => summary.skip_count += 1,
        .fail => summary.fail_count += 1,
    }
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
    if (!have_tty) return;
    std.debug.print(
        "\r{d}/{d} specs complete ({d} workers active)      ",
        .{ summary.completed_specs, summary.known_total_specs, active_workers },
    );
}

fn runProcessWorkerQueue(
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    seed: u32,
    worker_count: usize,
    test_fns: []const ZigTestFn,
    ruby_spec_tests: []const RubySpecTest,
    have_tty: bool,
) RunSummary {
    var summary = RunSummary{
        .known_total_specs = test_fns.len,
    };
    const total_tests = test_fns.len + ruby_spec_tests.len;
    if (total_tests == 0) return summary;
    defer if (have_tty) std.debug.print("\n", .{});

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
            const worker = spawnWorkerProcess(allocator, exe_path, seed, next_index) catch |err| {
                const failure = TestRunResult{
                    .outcome = .fail,
                    .err_name = @errorName(err),
                };
                applyResult(&summary, failure);
                printTerminalOutcome(have_tty, summary.completed_specs, summary.known_total_specs, testNameForIndex(test_fns, ruby_spec_tests, next_index), failure);
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
            const test_name = testNameForIndex(test_fns, ruby_spec_tests, test_index);
            const worker_stdout = finished_worker.stdout_buffer.items;
            const worker_stderr = finished_worker.stderr_buffer.items;

            var result: TestRunResult = undefined;
            if (finished_worker.child.wait()) |term| {
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

            applyResult(&summary, result);
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

pub fn main() void {
    @disableInstrumentation();

    if (builtin.cpu.arch.isSpirV()) {
        // SPIR-V needs an special test-runner
        return;
    }

    if (crippled) {
        return mainSimple() catch @panic("test failure\n");
    }

    const args = std.process.argsAlloc(fba.allocator()) catch
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
    var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
    var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buffer);
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
                                std.debug.dumpStackTrace(trace.*);
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
                            std.debug.dumpStackTrace(trace.*);
                        }
                    }
                    deinitRubySpecTests(testing.allocator, &ruby_spec_tests);
                }

                const leak = testing.allocator_instance.deinit() == .leak;
                try server.serveTestResults(.{
                    .index = index,
                    .flags = .{
                        .fail = fail,
                        .skip = skip,
                        .leak = leak,
                        .fuzz = is_fuzz_test,
                        .log_err_count = std.math.lossyCast(
                            @FieldType(std.zig.Server.Message.TestResults.Flags, "log_err_count"),
                            log_err_count,
                        ),
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
                            std.debug.dumpStackTrace(trace.*);
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

    var ruby_spec_tests = loadRubySpecTests(allocator) catch |err| {
        emitWorkerJsonResult(.{
            .outcome = .fail,
            .err_name = @errorName(err),
        });
        return;
    };
    defer deinitRubySpecTests(allocator, &ruby_spec_tests);

    const total_tests = test_fns.len + ruby_spec_tests.items.len;
    if (test_index >= total_tests) {
        emitWorkerJsonResult(.{
            .outcome = .fail,
            .err_name = "InvalidWorkerTestIndex",
        });
        return;
    }

    const result = executeTestAtIndex(test_fns, ruby_spec_tests.items, test_index);
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

    if (worker_count > 1) {
        const allocator = std.heap.page_allocator;
        const child_exe_path = std.fs.selfExePathAlloc(allocator) catch |err| {
            std.debug.print("Failed to resolve test runner executable path: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer allocator.free(child_exe_path);

        const have_tty = std.fs.File.stderr().isTty();
        const summary = runProcessWorkerQueue(
            allocator,
            child_exe_path,
            testing.random_seed,
            worker_count,
            test_fn_list,
            ruby_spec_tests.items,
            have_tty,
        );

        if (summary.ok_count == total_tests) {
            std.debug.print("All {d} tests passed.\n", .{summary.ok_count});
        } else {
            std.debug.print("{d} passed; {d} skipped; {d} failed.\n", .{
                summary.ok_count,
                summary.skip_count,
                summary.fail_count,
            });
        }
        std.debug.print("Executed {d} specs.\n", .{summary.completed_specs});
        if (summary.log_err_count != 0) {
            std.debug.print("{d} errors were logged.\n", .{summary.log_err_count});
        }
        if (summary.leaks != 0) {
            std.debug.print("{d} tests leaked memory.\n", .{summary.leaks});
        }
        if (summary.fuzz_count != 0) {
            std.debug.print("{d} fuzz tests found.\n", .{summary.fuzz_count});
        }
        if (summary.leaks != 0 or summary.log_err_count != 0 or summary.fail_count != 0) {
            std.process.exit(1);
        }
        return;
    }

    var summary = RunSummary{
        .known_total_specs = test_fn_list.len,
    };
    const root_node = if (builtin.fuzz) std.Progress.Node.none else std.Progress.start(.{
        .root_name = "Test",
        .estimated_total_items = total_tests,
    });
    const have_tty = std.fs.File.stderr().isTty();

    var async_frame_buffer: []align(builtin.target.stackAlignment()) u8 = undefined;
    async_frame_buffer = &[_]u8{};

    for (0..total_tests) |test_index| {
        const test_name = testNameForIndex(test_fn_list, ruby_spec_tests.items, test_index);
        const test_node = root_node.start(test_name, 0);
        const result = executeTestAtIndex(test_fn_list, ruby_spec_tests.items, test_index);
        test_node.end();

        applyResult(&summary, result);
        printTerminalOutcome(have_tty, summary.completed_specs, summary.known_total_specs, test_name, result);
        if (have_tty) {
            printParallelProgressStatus(have_tty, summary, 0);
        }
    }

    if (have_tty) std.debug.print("\n", .{});
    root_node.end();
    if (summary.ok_count == total_tests) {
        std.debug.print("All {d} tests passed.\n", .{summary.ok_count});
    } else {
        std.debug.print("{d} passed; {d} skipped; {d} failed.\n", .{
            summary.ok_count,
            summary.skip_count,
            summary.fail_count,
        });
    }
    std.debug.print("Executed {d} specs.\n", .{summary.completed_specs});
    if (summary.log_err_count != 0) {
        std.debug.print("{d} errors were logged.\n", .{summary.log_err_count});
    }
    if (summary.leaks != 0) {
        std.debug.print("{d} tests leaked memory.\n", .{summary.leaks});
    }
    if (summary.fuzz_count != 0) {
        std.debug.print("{d} fuzz tests found.\n", .{summary.fuzz_count});
    }
    if (summary.leaks != 0 or summary.log_err_count != 0 or summary.fail_count != 0) {
        std.process.exit(1);
    }
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
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
    const stdout = if (enable_write) std.fs.File.stdout() else {};

    for (builtin.test_functions) |test_fn| {
        if (enable_write) {
            stdout.writeAll(test_fn.name) catch {};
            stdout.writeAll("... ") catch {};
        }
        if (test_fn.func()) |_| {
            if (enable_write) stdout.writeAll("PASS\n") catch {};
        } else |err| {
            if (err != error.SkipZigTest) {
                if (enable_write) stdout.writeAll("FAIL\n") catch {};
                failed += 1;
                if (!enable_write) return err;
                continue;
            }
            if (enable_write) stdout.writeAll("SKIP\n") catch {};
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
                    if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
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
