const std = @import("std");
const cora = @import("cora");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "compiler records literal block call-site handlers" {
    const allocator = test_helper.getAllocator();
    var parser = try cora.prism.Parser.init(allocator,
        \\receiver.foo { 1 }
        \\receiver.foo(key: 1) { 2 }
    , null);
    defer parser.deinit();

    var program = try cora.compiler.Compiler.compile(allocator, &parser, 1);
    defer program.deinit();

    const handlers = program.main_chunk.block_call_handlers.items;
    try std.testing.expectEqual(@as(usize, 2), handlers.len);
    for (handlers) |handler| {
        try std.testing.expect(handler.block_chunk_id != 0);
        try std.testing.expect(handler.continuation_byte_offset > handler.call_byte_offset);
    }
    try std.testing.expectEqual(@as(usize, 7), handlers[0].continuation_byte_offset - handlers[0].call_byte_offset);
    try std.testing.expectEqual(@as(usize, 10), handlers[1].continuation_byte_offset - handlers[1].call_byte_offset);
}

test "block break - basic with value" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break 42 if x == 2
        \\  x
        \\end
        \\result
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "block break - without value returns nil" {
    const result = try evalCode(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  99
        \\end
        \\
        \\result = each_test do |x|
        \\  break if x == 1
        \\end
        \\result
    );
    try std.testing.expect(result.isNil());
}

test "block break - stops execution immediately" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def each_test
        \\  yield 1
        \\  yield 2
        \\  yield 3
        \\end
        \\
        \\each_test do |x|
        \\  break if x == 2
        \\  puts x
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - method doesn't continue after yield" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const eval_result = test_helper.evalCodeWithOutput(
        \\def test_method
        \\  puts 1
        \\  yield
        \\  puts 2
        \\  yield
        \\  puts 3
        \\end
        \\
        \\test_method do
        \\  break
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(eval_result.err == null);
    // Should only print 1, not 2 or 3
    try std.testing.expectEqualStrings("1\n", eval_result.stdout);
}

test "block break - nested blocks use innermost" {
    const result = try evalCode(
        \\def outer
        \\  yield
        \\  99
        \\end
        \\
        \\def inner
        \\  yield
        \\  88
        \\end
        \\
        \\result = outer do
        \\  inner do
        \\    break 42
        \\  end
        \\end
        \\result
    );
    // Break from inner block should return 42 from inner, not outer
    // Outer continues and returns 99
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "block break - forwarded block exits the receiving method" {
    const result = try evalCode(
        \\def inner
        \\  yield
        \\end
        \\
        \\def outer(&block)
        \\  inner(&block)
        \\  :continued
        \\end
        \\
        \\outer { break :stopped }
    );
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualStrings("stopped", result.toSymbolObject().name);
}

test "block break - different from loop break" {
    const result = try evalCode(
        \\def test
        \\  yield
        \\  77
        \\end
        \\
        \\result = test do
        \\  x = 0
        \\  while x == 0
        \\    x = 1
        \\    break
        \\  end
        \\  55
        \\end
        \\result
    );
    // Loop break exits loop, block continues and returns 55 to yield,
    // but the method continues and returns 77
    try std.testing.expectEqual(@as(i64, 77), result.toInteger());
}
