const std = @import("std");
const cora = @import("cora");
const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const Value = cora.value.Value;
const bdwgc = @import("bdwgc");

const test_helper = @import("test_helper.zig");

fn evalCodeWithTime(code: []const u8, stdout_buf: []u8, stderr_buf: []u8) test_helper.EvalResult {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = test_helper.getAllocator();

    var parser = prism.Parser.init(allocator, code, null) catch |err| {
        if (err == error.ParseError) {
            return .{
                .value = Value.nil(),
                .stdout = "",
                .stderr = "(eval): syntax error (SyntaxError)\n",
                .err = error.UnhandledException,
            };
        }
        return .{ .value = Value.nil(), .stdout = "", .stderr = "", .err = err };
    };
    defer parser.deinit();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, threaded.io(), std.testing.environ);
    defer vm.deinit();

    var program = compiler.Compiler.compile(allocator, &parser, 1) catch |err| {
        if (compiler.syntaxErrorMessage(err)) |message| {
            return .{
                .value = Value.nil(),
                .stdout = "",
                .stderr = message,
                .err = error.UnhandledException,
            };
        }
        return .{ .value = Value.nil(), .stdout = "", .stderr = "", .err = err };
    };
    defer program.deinit();

    vm.prepare(&program) catch |err| {
        return .{ .value = Value.nil(), .stdout = "", .stderr = "", .err = err };
    };

    {
        var path_buffer: [4096]u8 = undefined;
        const abs_len = std.Io.Dir.cwd().realPathFile(threaded.io(), "lib/stdlib", &path_buffer) catch 0;
        if (abs_len != 0) {
            vm.appendLoadPath(path_buffer[0..abs_len]) catch {};
        }
    }
    {
        var path_buffer: [4096]u8 = undefined;
        const abs_len = std.Io.Dir.cwd().realPathFile(threaded.io(), "ext/time/lib", &path_buffer) catch 0;
        if (abs_len != 0) {
            vm.appendLoadPath(path_buffer[0..abs_len]) catch {};
        }
    }

    var stdout_writer = test_helper.TestWriter.init(stdout_buf);
    vm.stdout = &stdout_writer.interface;

    var stderr_writer = test_helper.TestWriter.init(stderr_buf);
    vm.stderr = &stderr_writer.interface;

    const run_result = vm.run();

    const at_exit_result = vm.runAtExitHandlers();
    if (at_exit_result) |_| {} else |err| {
        if (err == error.UnhandledException) vm.printUnhandledException();
        return .{
            .value = Value.nil(),
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }

    if (run_result) |result| {
        return .{ .value = result, .stdout = stdout_writer.written(), .stderr = stderr_writer.written(), .err = null };
    } else |err| {
        if (err == error.UnhandledException) vm.printUnhandledException();
        return .{
            .value = Value.nil(),
            .stdout = stdout_writer.written(),
            .stderr = stderr_writer.written(),
            .err = err,
        };
    }
}

test "require time and use Time.parse" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const code =
        \\require "time"
        \\t = Time.parse("2023-01-15 12:30:00")
        \\print t.year
        \\print " "
        \\print t.month
        \\print " "
        \\print t.day
    ;
    const result = evalCodeWithTime(code, &stdout_buf, &stderr_buf);
    if (result.err != null) {
        std.debug.print("  stderr: {s}\n  stdout: {s}\n", .{ result.stderr, result.stdout });
    }
    try std.testing.expect(result.err == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "2023") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "15") != null);
}