const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const Value = cora.value.Value;
const bdwgc = @import("bdwgc");

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

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
                .buffer = &.{}, // unbuffered - writes go directly to fbs
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

pub fn evalCode(ruby_code: []const u8) !Value {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(ruby_code, &stdout_buf, &stderr_buf);
    if (result.err) |err| return err;
    return result.value;
}

pub const EvalResult = struct {
    value: Value,
    stdout: []const u8,
    stderr: []const u8,
    err: ?anyerror,
};

fn syntaxErrorResult(stderr_buf: []u8, source_path: ?[]const u8, message: []const u8) EvalResult {
    const rendered = std.fmt.bufPrint(stderr_buf, "{s}: {s} (SyntaxError)\n", .{ source_path orelse "(eval)", message }) catch "SyntaxError\n";
    return .{
        .value = Value.nil(),
        .stdout = "",
        .stderr = rendered,
        .err = error.UnhandledException,
    };
}

pub fn evalCodeWithOutput(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    return evalCodeWithOutputAndPath(ruby_code, stdout_buf, stderr_buf, null);
}

pub fn evalFile(path: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    const allocator = getAllocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Get absolute path for require_relative resolution
    const abs_path = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = error.FileNotFound,
        };
    };

    // Read file contents
    const ruby_code = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = error.FileReadFailed,
        };
    };
    defer allocator.free(ruby_code);

    return evalCodeWithOutputAndPath(ruby_code, stdout_buf, stderr_buf, abs_path);
}

pub fn evalCodeWithOutputAndPath(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8, source_path: ?[]const u8) EvalResult {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();

    var parser = prism.Parser.init(allocator, ruby_code, source_path) catch |err| {
        if (err == error.ParseError) {
            return syntaxErrorResult(stderr_buf, source_path, "syntax error");
        }
        return .{
            .value = Value.nil(),
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
        if (compiler.syntaxErrorMessage(err)) |message| {
            return syntaxErrorResult(stderr_buf, source_path, message);
        }
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };
    defer program.deinit();

    vm.prepare(&program) catch |err| {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };
    {
        var path_buffer: [4096]u8 = undefined;
        const abs_len = std.Io.Dir.cwd().realPathFile(threaded.io(), "lib/stdlib", &path_buffer) catch 0;
        if (abs_len != 0) {
            vm.appendLoadPath(path_buffer[0..abs_len]) catch |err| {
                return .{
                    .value = Value.nil(),
                    .stdout = "",
                    .stderr = "",
                    .err = err,
                };
            };
        }
    }

    // Set up stdout capture
    var stdout_writer = TestWriter.init(stdout_buf);
    vm.stdout = &stdout_writer.interface;

    // Set up stderr capture
    var stderr_writer = TestWriter.init(stderr_buf);
    vm.stderr = &stderr_writer.interface;

    const run_result = vm.run();

    const at_exit_result = vm.runAtExitHandlers();
    if (at_exit_result) |_| {
        // at_exit handlers completed
    } else |err| {
        if (err == error.UnhandledException) {
            vm.printUnhandledException();
        }
        return .{
            .value = Value.nil(),
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }

    if (run_result) |result| {
        return .{
            .value = result,
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = null,
        };
    } else |err| {
        if (err == error.UnhandledException) {
            vm.printUnhandledException();
        }
        return .{
            .value = Value.nil(),
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }
}
