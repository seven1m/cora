const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "private without args affects following defs and explicit self call fails" {
    const ok = try evalCode(
        \\class C
        \\  private
        \\  def hidden
        \\    11
        \\  end
        \\  public
        \\  def call_hidden
        \\    hidden
        \\  end
        \\end
        \\C.new.call_hidden
    );
    try std.testing.expectEqual(@as(i64, 11), ok.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  private
        \\  def hidden
        \\    11
        \\  end
        \\  public
        \\  def call_hidden
        \\    self.hidden
        \\  end
        \\end
        \\C.new.call_hidden
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "hidden") != null);
}

test "public without args restores visibility for following defs" {
    const ok = try evalCode(
        \\class C
        \\  private
        \\  def a
        \\    1
        \\  end
        \\  public
        \\  def b
        \\    2
        \\  end
        \\end
        \\C.new.b
    );
    try std.testing.expectEqual(@as(i64, 2), ok.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  private
        \\  def a
        \\    1
        \\  end
        \\  public
        \\  def b
        \\    2
        \\  end
        \\end
        \\C.new.a
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "a") != null);
}

test "private with names changes existing method visibility" {
    const ok = try evalCode(
        \\class C
        \\  def wrapped
        \\    7
        \\  end
        \\  private :wrapped
        \\  def call_wrapped
        \\    wrapped
        \\  end
        \\end
        \\C.new.call_wrapped
    );
    try std.testing.expectEqual(@as(i64, 7), ok.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  def wrapped
        \\    7
        \\  end
        \\  private :wrapped
        \\end
        \\C.new.wrapped
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "wrapped") != null);
}

test "protected allows same-family receiver calls and blocks external calls" {
    const ok = try evalCode(
        \\class C
        \\  protected
        \\  def tok
        \\    5
        \\  end
        \\  public
        \\  def check(other)
        \\    other.tok
        \\  end
        \\end
        \\C.new.check(C.new)
    );
    try std.testing.expectEqual(@as(i64, 5), ok.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  protected
        \\  def tok
        \\    5
        \\  end
        \\end
        \\C.new.tok
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "tok") != null);
}

test "define_method respects current default visibility" {
    const ok = try evalCode(
        \\class C
        \\  private
        \\  define_method(:dyn) { 42 }
        \\  public
        \\  def call_dyn
        \\    dyn
        \\  end
        \\end
        \\C.new.call_dyn
    );
    try std.testing.expectEqual(@as(i64, 42), ok.toInteger());

    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  private
        \\  define_method(:dyn) { 42 }
        \\end
        \\C.new.dyn
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NoMethodError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "dyn") != null);
}

test "visibility setters raise NameError for unknown names" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const bad = evalCodeWithOutput(
        \\class C
        \\  private :undefined_name
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, bad.err.?);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "undefined_name") != null);
}
