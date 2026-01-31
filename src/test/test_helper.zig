const std = @import("std");
const prism = @import("../prism.zig");
const compiler = @import("../compiler.zig");
const VM = @import("../vm.zig").VM;
const Value = @import("../value.zig").Value;
const bdwgc = @import("bdwgc");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

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
                .buffer = &.{}, // unbuffered - writes go directly to fbs
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

pub fn evalCodeWithOutput(ruby_code: []const u8, stdout_buf: []u8, stderr_buf: []u8) EvalResult {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = getAllocator();

    const parser = prism.Parser.init(allocator, ruby_code, null) catch |err| {
        return .{
            .value = Value.nil(),
            .stdout = "",
            .stderr = "",
            .err = err,
        };
    };

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, parser);
    defer vm.deinit();

    var program = compiler.Compiler.compile(allocator, &vm.parser, 1) catch |err| {
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

    // Set up stdout capture
    var stdout_fbs = std.io.fixedBufferStream(stdout_buf);
    var stdout_writer = TestWriter.init(&stdout_fbs);
    vm.stdout = &stdout_writer.interface;

    // Set up stderr capture
    var stderr_fbs = std.io.fixedBufferStream(stderr_buf);
    var stderr_writer = TestWriter.init(&stderr_fbs);
    vm.stderr = &stderr_writer.interface;

    const result = vm.run() catch |err| {
        // If there was an error, print the exception to stderr
        if (err == error.RuntimeError) {
            vm.printUnhandledException();
        }
        return .{
            .value = Value.nil(),
            .stdout = stdout_fbs.getWritten(),
            .stderr = stderr_fbs.getWritten(),
            .err = err,
        };
    };

    return .{
        .value = result,
        .stdout = stdout_fbs.getWritten(),
        .stderr = stderr_fbs.getWritten(),
        .err = null,
    };
}
