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

    const handled = vm.globals.get("$handled") orelse return error.TestExpectedEqual;
    const last_signo = vm.globals.get("$last_signo") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(i64, 1), handled.toInteger());
    try std.testing.expectEqual(@as(i64, @intCast(@intFromEnum(std.posix.SIG.INT))), last_signo.toInteger());
}
