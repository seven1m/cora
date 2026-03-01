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
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Fiber.current returns main fiber and current fiber inside" {
    const result = try evalCode(
        \\root = Fiber.current
        \\f = Fiber.new { Fiber.current }
        \\ids = [root.object_id, f.resume.object_id]
        \\ids[0] == ids[1]
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
}

test "Fiber.resume and Fiber.yield exchange values" {
    const result = try evalCode(
        \\f = Fiber.new { Fiber.yield 1; 2 }
        \\a = f.resume
        \\b = f.resume
        \\[a, b]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expectEqual(@as(i64, 1), elems[0].toInteger());
    try std.testing.expectEqual(@as(i64, 2), elems[1].toInteger());
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
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isNil());
    try std.testing.expectEqual(@as(i64, 99), elems[1].toInteger());
}

test "Fiber preserves method local variables across yield and resume" {
    const result = try evalCode(
        \\def test_method
        \\  x = 42
        \\  yield
        \\  x
        \\end
        \\f = Fiber.new { test_method { Fiber.yield(:paused) } }
        \\a = f.resume
        \\b = f.resume
        \\[a, b]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("paused", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 42), elems[1].toInteger());
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
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 3), elems.len);
    try std.testing.expectEqual(true, elems[0].toBool());
    try std.testing.expectEqual(true, elems[1].toBool());
    try std.testing.expectEqual(false, elems[2].toBool());
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
    try std.testing.expect(result.value.isBool());
    try std.testing.expectEqual(false, result.value.toBool());
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

test "Array#each + Fiber.yield resumes inside builtin" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new { [1,2].each { |x| Fiber.yield(x) }; :done }
        \\p f.resume
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1\n2\n:done\n", result.stdout);
}

test "Kernel#tap resumes and returns receiver" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\f = Fiber.new do
        \\  a = 1.tap { Fiber.yield(:pause) }
        \\  p a
        \\  :done
        \\end
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(":pause\n1\n:done\n", result.stdout);
}

test "File.open block keeps io open across Fiber.yield" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\File.write('/tmp/cora_fiber_file_open_bug.txt', "hi")
        \\f = Fiber.new do
        \\  File.open('/tmp/cora_fiber_file_open_bug.txt', 'r') do |io|
        \\    Fiber.yield(:pause)
        \\    p io.read
        \\  end
        \\  :done
        \\end
        \\p f.resume
        \\p f.resume
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(":pause\n\"hi\"\n:done\n", result.stdout);
}

test "Fiber works in non-main Thread" {
    const result = try evalCode(
        \\Thread.new do
        \\  f = Fiber.new do
        \\    Fiber.yield(:pause)
        \\    :done
        \\  end
        \\  [f.resume, f.resume]
        \\end.value
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), elems.len);
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("pause", elems[0].toSymbolObject().name);
    try std.testing.expect(elems[1].isSymbol());
    try std.testing.expectEqualStrings("done", elems[1].toSymbolObject().name);
}

test "Thread.current stays correct inside Fiber in non-main Thread" {
    const result = try evalCode(
        \\Thread.new do
        \\  cur = Thread.current
        \\  Fiber.new { Thread.current == cur }.resume
        \\end.value
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Fiber.resume across threads raises FiberError" {
    const result = try evalCode(
        \\f = Fiber.new { :ok }
        \\Thread.new do
        \\  begin
        \\    f.resume
        \\  rescue => e
        \\    e.message
        \\  end
        \\end.value
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("fiber called across threads", result.toStringObject().str);
}

test "Fiber stress: 10000 yield/resume cycles" {
    const result = try evalCode(
        \\f = Fiber.new do
        \\  i = 0
        \\  while i < 10000
        \\    Fiber.yield(i)
        \\    i += 1
        \\  end
        \\  :done
        \\end
        \\i = 0
        \\ok = true
        \\while i < 10000
        \\  ok = false unless f.resume == i
        \\  i += 1
        \\end
        \\ok && f.resume == :done
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Fiber stress: nested builtins with many yields" {
    const result = try evalCode(
        \\vals = []
        \\f = Fiber.new do
        \\  50.times do |i|
        \\    [i, i + 1].each do |x|
        \\      vals.tap { Fiber.yield(x) }
        \\    end
        \\  end
        \\  vals.length
        \\end
        \\sum = 0
        \\100.times { sum += f.resume }
        \\len = f.resume
        \\sum == 2500 && len == 0
    );
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}
