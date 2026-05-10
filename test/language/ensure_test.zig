const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Ensure clause runs on normal completion" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  42
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 42), result.value.toInteger());

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs after rescue" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\result = begin
        \\  raise "error"
        \\rescue
        \\  100
        \\ensure
        \\  puts "cleanup"
        \\end
        \\result
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqual(@as(i64, 100), result.value.toInteger());

    try std.testing.expectEqualSlices(u8, "cleanup\n", result.stdout);
}

test "Ensure clause runs during unwinding" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\begin
        \\  raise "error"
        \\ensure
        \\  puts "cleanup during unwind"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);

    try std.testing.expectEqualSlices(u8, "cleanup during unwind\n", result.stdout);
}

test "Ensure return value is ignored" {
    const result = try evalCode(
        \\begin
        \\  42
        \\ensure
        \\  999
        \\end
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Ensure clause runs during throw unwinding" {
    const result = try evalCode(
        \\trace = []
        \\def throw_with_ensure(trace)
        \\  begin
        \\    throw :done, 5
        \\  ensure
        \\    trace << :cleanup
        \\  end
        \\end
        \\value = catch(:done) { throw_with_ensure(trace) }
        \\[trace[0], value]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("cleanup", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 5), elems[1].toInteger());
}
