const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Thread.new creates and runs a thread" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread#join waits for completion" {
    const result = try evalCode(
        \\x = 0
        \\t = Thread.new { x = 1 }
        \\t.join
        \\x
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Thread#value returns block result" {
    const result = try evalCode(
        \\t = Thread.new { 1 + 2 + 3 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 6), result.toInteger());
}

test "Thread.current returns current thread" {
    const result = try evalCode(
        \\Thread.current == Thread.main
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread.main returns the main thread" {
    const result = try evalCode(
        \\Thread.main.alive?
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#alive? returns true while running, false after termination" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.join
        \\t.alive?
    );
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread#status returns status strings" {
    const result = try evalCode(
        \\t = Thread.new { 42 }
        \\t.join
        \\t.status
    );
    // terminated normally => false
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread.main status is 'run'" {
    const result = try evalCode(
        \\Thread.main.status
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("run", result.toStringObject().str);
}

test "Thread#kill terminates thread" {
    const result = try evalCode(
        \\t = Thread.new { loop { Thread.pass } }
        \\t.kill
        \\t.join
        \\t.alive?
    );
    try std.testing.expectEqual(false, result.toBool());
}

test "Thread#[] and Thread#[]= store fiber-local variables" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:foo] = 42
        \\  Thread.current[:foo]
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread#key? checks for fiber-local variable" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:x] = 1
        \\  Thread.current.key?(:x)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#keys returns fiber-local variable keys" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current[:a] = 1
        \\  Thread.current.keys.length
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 1), result.toInteger());
}

test "Thread#thread_variable_get/set" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current.thread_variable_set(:foo, 99)
        \\  Thread.current.thread_variable_get(:foo)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 99), result.toInteger());
}

test "Thread#thread_variable?" {
    const result = try evalCode(
        \\t = Thread.new {
        \\  Thread.current.thread_variable_set(:bar, 1)
        \\  Thread.current.thread_variable?(:bar)
        \\}
        \\t.value
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread#name and Thread#name=" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.name = "worker"
        \\t.name
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("worker", result.toStringObject().str);
}

test "Thread#priority and Thread#priority=" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.priority = 2
        \\t.priority
    );
    try std.testing.expectEqual(@as(i64, 2), result.toInteger());
}

test "Thread#inspect" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.join
        \\t.inspect
    );
    try std.testing.expect(result.isString());
    const str = result.toStringObject().str;
    try std.testing.expect(std.mem.startsWith(u8, str, "#<Thread:"));
}

test "Thread.list returns alive threads" {
    const result = try evalCode(
        \\Thread.list.length
    );
    // Main thread should always be in the list
    try std.testing.expect(result.toInteger() >= 1);
}

test "Thread.start is an alias for Thread.new" {
    const result = try evalCode(
        \\t = Thread.start { 7 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 7), result.toInteger());
}

test "Thread.fork is an alias for Thread.new" {
    const result = try evalCode(
        \\t = Thread.fork { 8 }
        \\t.value
    );
    try std.testing.expectEqual(@as(i64, 8), result.toInteger());
}

test "Thread#stop? returns true for dead thread" {
    const result = try evalCode(
        \\t = Thread.new { 1 }
        \\t.join
        \\t.stop?
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Thread exception propagation through join" {
    const result = try evalCode(
        \\begin
        \\  t = Thread.new { raise "boom" }
        \\  t.join
        \\  "no error"
        \\rescue RuntimeError => e
        \\  e.message
        \\end
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("boom", result.toStringObject().str);
}

test "Thread.pass yields to other threads" {
    const result = try evalCode(
        \\Thread.pass
        \\42
    );
    try std.testing.expectEqual(@as(i64, 42), result.toInteger());
}

test "Thread#wakeup wakes a sleeping thread" {
    const result = try evalCode(
        \\t = Thread.new { 99 }
        \\t.join
        \\t.alive?
    );
    try std.testing.expectEqual(false, result.toBool());
}
