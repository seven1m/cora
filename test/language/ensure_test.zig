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

test "Explicit method return runs ensure before leaving the method" {
    const result = try evalCode(
        \\def return_with_ensure(trace)
        \\  begin
        \\    return 1
        \\  ensure
        \\    trace << :before
        \\    trace << :after
        \\  end
        \\end
        \\trace = []
        \\[return_with_ensure(trace), trace]
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 1), elems[0].toInteger());
    const trace = elems[1].toArrayObject().elements.items;
    try std.testing.expectEqualStrings("before", trace[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("after", trace[1].toSymbolObject().name);
}

test "Explicit lambda return and break run ensure" {
    const result = try evalCode(
        \\trace = []
        \\return_value = lambda do
        \\  begin
        \\    return 2
        \\  ensure
        \\    trace << :return
        \\  end
        \\end.call
        \\break_value = lambda do
        \\  begin
        \\    break 3
        \\  ensure
        \\    trace << :break
        \\  end
        \\end.call
        \\[return_value, break_value, trace]
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 2), elems[0].toInteger());
    try std.testing.expectEqual(@as(i64, 3), elems[1].toInteger());
    const trace = elems[2].toArrayObject().elements.items;
    try std.testing.expectEqualStrings("return", trace[0].toSymbolObject().name);
    try std.testing.expectEqualStrings("break", trace[1].toSymbolObject().name);
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

// Regression: non-local return from default expression inside ensure block
// should override the original exception. MRI behavior: return from proc
// called inside ensure overrides the exception that triggered the ensure.
test "non-local return from default inside ensure overrides original exception" {
    const result = try evalCode(
        \\def outer
        \\  my_proc = proc { return "proc_return" }
        \\  begin
        \\    raise "start unwind"
        \\  ensure
        \\    inner(my_proc)
        \\  end
        \\  "never"
        \\end
        \\
        \\def inner(blk, x = blk.call)
        \\  x
        \\end
        \\
        \\outer
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("proc_return", result.toStringObject().str);
}

// Regression: non-local return from default expression corrupts the frame stack
// of the calling method. After the non-local return pops the enclosing method frame,
// executeDefaultExpression must not let copyArgumentsWithRestParam write into
// the wrong frame's locals.
test "non-local return in default param does not corrupt caller locals" {
    const result = try evalCode(
        \\def foo(value = (proc { return 42 }.call))
        \\  99
        \\end
        \\def bar
        \\  a = 1
        \\  b = 2
        \\  foo()
        \\  a + b
        \\end
        \\bar()
    );
    // bar's locals a=1, b=2 should be untouched by foo's proc return
    try std.testing.expect(result.isInteger());
    try std.testing.expectEqual(@as(i64, 3), result.toInteger());
}

test "non-local return from keyword default inside ensure overrides original exception" {
    const result = try evalCode(
        \\def outer
        \\  my_proc = proc { return "proc_return" }
        \\  begin
        \\    raise "start unwind"
        \\  ensure
        \\    inner(blk: my_proc)
        \\  end
        \\  "never"
        \\end
        \\
        \\def inner(blk:, x: blk.call)
        \\  x
        \\end
        \\
        \\outer
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualStrings("proc_return", result.toStringObject().str);
}
