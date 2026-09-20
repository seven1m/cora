const std = @import("std");
const cora = @import("cora");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Exception#message returns message string" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError, "my message"
        \\rescue => e
        \\  e.message
        \\end
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "my message", result.toStringObject().str);
}

test "Exception.new does not capture a backtrace" {
    const result = try evalCode("RuntimeError.new.backtrace");
    try std.testing.expect(result.isNil());
}

test "raise calls an overridden Exception#set_backtrace" {
    const result = try evalCode(
        \\class BacktraceOverrideError < RuntimeError
        \\  attr_reader :set_backtrace_called
        \\  def set_backtrace(backtrace)
        \\    @set_backtrace_called = true
        \\    super
        \\  end
        \\end
        \\begin
        \\  raise BacktraceOverrideError, "boom"
        \\rescue => e
        \\  [e.set_backtrace_called, !e.backtrace.empty?]
        \\end
    );
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].toBool());
    try std.testing.expect(elems[1].toBool());
}

test "raise accepts exception object with replacement message" {
    const result = try evalCode(
        \\begin
        \\  raise RuntimeError.new("old"), "new"
        \\rescue => e
        \\  [e.class.name, e.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("RuntimeError", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("new", elems[1].toStringObject().str);
}

test "Exception#cause returns nested exception" {
    const result = try evalCode(
        \\begin
        \\  begin
        \\    raise "inner"
        \\  rescue
        \\    raise "outer"
        \\  end
        \\rescue => e
        \\  [e.message, e.cause.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("outer", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("inner", elems[1].toStringObject().str);
}

test "Errno class exception builds default errno message" {
    const result = try evalCode(
        \\e = Errno::EMFILE.exception
        \\[e.class.name, e.message, e.inspect]
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("Errno::EMFILE", elems[0].toStringObject().str);
    try std.testing.expectEqualStrings("Too many open files", elems[1].toStringObject().str);
    try std.testing.expectEqualStrings("#<Errno::EMFILE: Too many open files>", elems[2].toStringObject().str);
}

test "pending SIGINT raises Interrupt and explicit rescue catches it" {
    cora.vm.requestSignal(@intCast(@intFromEnum(std.posix.SIG.INT)));
    const result = try evalCode(
        \\begin
        \\  1 + 1
        \\rescue Interrupt => e
        \\  e.signm == "SIGINT"
        \\end
    );
    try std.testing.expect(result.toBool());
}

test "SignalException accepts a signal name Symbol" {
    const result = try evalCode(
        \\error = SignalException.new(:INT)
        \\[error.signo == Signal.list["INT"], error.signm == "SIGINT", error.message == "SIGINT"]
    );
    for (result.toArrayObject().elements.items) |value| {
        try std.testing.expect(value.isTrue());
    }
}

test "pending SIGINT is not caught by bare rescue" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    cora.vm.requestSignal(@intCast(@intFromEnum(std.posix.SIG.INT)));
    const result = evalCodeWithOutput(
        \\begin
        \\  1 + 1
        \\rescue
        \\  42
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Interrupt") != null);
}

test "UncaughtThrowError exposes tag and value" {
    const result = try evalCode(
        \\begin
        \\  throw :boom, 12
        \\rescue UncaughtThrowError => e
        \\  [e.tag, e.value]
        \\end
    );
    try std.testing.expect(result.isArray());
    const elems = result.toArrayObject().elements.items;
    try std.testing.expect(elems[0].isSymbol());
    try std.testing.expectEqualStrings("boom", elems[0].toSymbolObject().name);
    try std.testing.expectEqual(@as(i64, 12), elems[1].toInteger());
}
