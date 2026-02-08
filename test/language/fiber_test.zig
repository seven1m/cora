const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Fiber.new does not invoke block until resume" {
    const result = try evalCode(
        \\invoked = false
        \\f = Fiber.new { invoked = true }
        \\invoked
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Fiber.current returns main fiber and current fiber inside" {
    const result = try evalCode(
        \\root = Fiber.current
        \\f = Fiber.new { Fiber.current }
        \\ids = [root.object_id, f.resume.object_id]
        \\ids[0] == ids[1]
    );
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}

test "Fiber.resume and Fiber.yield exchange values" {
    const result = try evalCode(
        \\f = Fiber.new { Fiber.yield 1; 2 }
        \\a = f.resume
        \\b = f.resume
        \\[a, b]
    );
    try std.testing.expect(result.data == .array);
    const elems = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expectEqual(@as(i64, 1), elems[0].data.integer);
    try std.testing.expectEqual(@as(i64, 2), elems[1].data.integer);
}

test "Fiber.yield returns resume argument to the fiber" {
    const result = try evalCode(
        \\f = Fiber.new do
        \\  x = Fiber.yield
        \\  x
        \\end
        \\a = f.resume
        \\b = f.resume(99)
        \\[a, b]
    );
    try std.testing.expect(result.data == .array);
    const elems = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].data == .nil);
    try std.testing.expectEqual(@as(i64, 99), elems[1].data.integer);
}

test "Fiber.alive? reflects fiber lifecycle" {
    const result = try evalCode(
        \\f = Fiber.new { Fiber.yield }
        \\a1 = f.alive?
        \\f.resume
        \\a2 = f.alive?
        \\f.resume
        \\a3 = f.alive?
        \\[a1, a2, a3]
    );
    try std.testing.expect(result.data == .array);
    const elems = result.data.array.elements.items;
    try std.testing.expectEqual(@as(usize, 3), elems.len);
    try std.testing.expectEqual(true, elems[0].data.boolean);
    try std.testing.expectEqual(true, elems[1].data.boolean);
    try std.testing.expectEqual(false, elems[2].data.boolean);
}

test "Fiber.yield from main fiber raises FiberError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput("Fiber.yield", &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unhandled exception: FiberError: can't yield from root fiber") != null);
}

test "Fiber terminates after unhandled exception" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { raise "boom" }
        \\begin
        \\  f.resume
        \\rescue => e
        \\  puts e.message
        \\end
        \\f.alive?
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.value.data == .boolean);
    try std.testing.expectEqual(false, result.value.data.boolean);
    try std.testing.expectEqualSlices(u8, "boom\n", result.stdout);
}

test "Fiber.resume on self raises FiberError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { Fiber.current.resume }
        \\f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unhandled exception: FiberError: attempt to resume the current fiber") != null);
}

test "return inside Fiber raises LocalJumpError" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { return 1 }
        \\f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "LocalJumpError") != null);
}
