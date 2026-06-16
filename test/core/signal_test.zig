const std = @import("std");
const cora = @import("cora");
const test_helper = @import("../test_helper.zig");
const bdwgc = @import("bdwgc");

const prism = cora.prism;
const compiler = cora.compiler;
const VM = cora.vm.VM;
const evalCode = test_helper.evalCode;

test "Signal.trap returns previous handler" {
    const result = try evalCode(
        \\first = Signal.trap("INT") { 1 }
        \\second = Signal.trap("INT", "DEFAULT")
        \\[first, second.class == Proc, second.call]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("DEFAULT", elems[0].toStringObject().str);
    try std.testing.expectEqual(true, elems[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), elems[2].toInteger());
}

test "Signal.trap dispatches queued signal to Ruby handler" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = test_helper.getAllocator();
    const ruby_code =
        \\$handled = 0
        \\$last_signo = nil
        \\Signal.trap("INT") { |signo| $handled += 1; $last_signo = signo }
    ;

    var parser = try prism.Parser.init(allocator, ruby_code, null);
    defer parser.deinit();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, threaded.io(), std.testing.environ);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    try vm.prepare(&program);
    _ = try vm.run();

    cora.vm.requestSignal(@intCast(@intFromEnum(std.posix.SIG.INT)));
    try vm.checkAsyncEvents();

    const handled = vm.getGlobalValue("$handled");
    const last_signo = vm.getGlobalValue("$last_signo");
    try std.testing.expectEqual(@as(i64, 1), handled.toInteger());
    try std.testing.expectEqual(@as(i64, @intCast(@intFromEnum(std.posix.SIG.INT))), last_signo.toInteger());
}

test "Signal.trap dispatches while IO.gets waits on a pipe" {
    bdwgc.init();
    defer bdwgc.deinit();

    const allocator = test_helper.getAllocator();
    const ruby_code =
        \\$handled = 0
        \\$r, $w = IO.pipe
        \\Signal.trap("INT") { $handled += 1 }
    ;

    var parser = try prism.Parser.init(allocator, ruby_code, null);
    defer parser.deinit();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var vm = VM.initEmpty(allocator, bdwgc.allocator, bdwgc.allocator_atomic, threaded.io(), std.testing.environ);
    defer vm.deinit();

    var program = try compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    try vm.prepare(&program);
    _ = try vm.run();

    const reader = vm.getGlobalValue("$r");
    const writer = vm.getGlobalValue("$w");
    const writer_fd: std.posix.fd_t = @intCast(writer.toIoObject().fd);

    const Worker = struct {
        fn sleepMs(ms: u64) void {
            var ts: std.posix.timespec = .{
                .sec = @intCast(@divTrunc(ms, 1000)),
                .nsec = @intCast(@mod(ms, 1000) * std.time.ns_per_ms),
            };
            while (std.posix.errno(std.posix.system.nanosleep(&ts, &ts)) == .INTR) {}
        }

        fn run(fd: std.posix.fd_t) void {
            sleepMs(50);
            cora.vm.requestSignal(@intCast(@intFromEnum(std.posix.SIG.INT)));
            sleepMs(50);
            _ = std.c.write(fd, "x\n", 2);
        }
    };

    const thread = try std.Thread.spawn(.{}, Worker.run, .{writer_fd});
    defer thread.join();

    const line = try vm.callMethodByName(reader, "gets", &.{}, null);
    try std.testing.expectEqualStrings("x\n", line.toStringObject().str);

    const handled = vm.getGlobalValue("$handled");
    try std.testing.expectEqual(@as(i64, 1), handled.toInteger());
}
