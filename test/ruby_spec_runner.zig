const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const Value = cora.value.Value;
const bdwgc = @import("bdwgc");

pub const SpecCase = struct {
    path: []const u8,
    name: []const u8,
};

pub const EvalResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    err: ?anyerror,
};

pub const TestWriter = struct {
    fbs: *std.io.FixedBufferStream([]u8),
    interface: std.Io.Writer,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .sendFile = std.Io.Writer.unimplementedSendFile,
    };

    pub fn init(fbs: *std.io.FixedBufferStream([]u8)) TestWriter {
        return .{
            .fbs = fbs,
            .interface = .{
                .vtable = &vtable,
                .buffer = &.{},
            },
        };
    }

    fn drain(io_w: *std.Io.Writer, data: []const []const u8, _: usize) std.Io.Writer.Error!usize {
        const w: *TestWriter = @alignCast(@fieldParentPtr("interface", io_w));
        var total: usize = 0;
        for (data) |slice| {
            w.fbs.writer().writeAll(slice) catch return error.WriteFailed;
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
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
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

pub fn runSpec(path: []const u8) !void {
    var stdout_buf: [32768]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalFile(path, &stdout_buf, &stderr_buf);

    if (result.err != null) {
        std.debug.print("\nSpec error ({s}): {s}\n{s}\n", .{ path, result.stdout, result.stderr });
        return error.SpecFailed;
    }

    if (std.mem.indexOf(u8, result.stdout, "OK:") == null) {
        std.debug.print("\nSpec failed ({s}):\n{s}\n", .{ path, result.stdout });
        return error.SpecFailed;
    }
}

pub fn evalFile(path: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    const allocator = std.heap.page_allocator;

    const abs_path = std.fs.cwd().realpathAlloc(allocator, path) catch {
        return .{
            .stdout = "",
            .stderr = "",
            .err = error.FileNotFound,
        };
    };
    defer allocator.free(abs_path);

    const file = std.fs.cwd().openFile(path, .{}) catch {
        return .{
            .stdout = "",
            .stderr = "",
            .err = error.FileNotFound,
        };
    };
    defer file.close();

    const ruby_code = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return .{
            .stdout = "",
            .stderr = "",
            .err = error.FileReadFailed,
        };
    };
    defer allocator.free(ruby_code);

    return evalCodeWithOutputAndPath(ruby_code, stdout_buf, stderr_buf, abs_path);
}

fn evalCodeWithOutputAndPath(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8, source_path: ?[]const u8) EvalResult {
    bdwgc.init();
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

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic);
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

    var stdout_fbs = std.io.fixedBufferStream(stdout_buf);
    var stdout_writer = TestWriter.init(&stdout_fbs);
    vm.stdout = &stdout_writer.interface;

    var stderr_fbs = std.io.fixedBufferStream(stderr_buf);
    var stderr_writer = TestWriter.init(&stderr_fbs);
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
            .stdout = stdout_fbs.getWritten(),
            .stderr = stderr_fbs.getWritten(),
            .err = err,
        };
    }

    if (run_result) |_| {
        return .{
            .stdout = stdout_fbs.getWritten(),
            .stderr = stderr_fbs.getWritten(),
            .err = null,
        };
    } else |err| {
        if (err == error.UnhandledException) {
            vm.printUnhandledException();
        }
        return .{
            .stdout = stdout_fbs.getWritten(),
            .stderr = stderr_fbs.getWritten(),
            .err = err,
        };
    }
}
