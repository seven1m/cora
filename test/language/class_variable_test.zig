const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "class variable basic read/write" {
    const result = try evalCode(
        \\class A
        \\  @@count = 1
        \\  def self.count
        \\    @@count
        \\  end
        \\end
        \\A.count
    );

    try std.testing.expectEqual(@as(i64, 1), result.data.integer);
}

test "class variable operator write" {
    const result = try evalCode(
        \\class A
        \\  @@count = 0
        \\  @@count += 2
        \\  def self.count
        \\    @@count
        \\  end
        \\end
        \\A.count
    );

    try std.testing.expectEqual(@as(i64, 2), result.data.integer);
}

test "class variable ||= initializes missing" {
    const result = try evalCode(
        \\class A
        \\  def self.ensure
        \\    @@x ||= 5
        \\  end
        \\end
        \\A.ensure
    );

    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "class variable &&= raises NameError when missing" {
    var stdout_buf: [8192]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;

    const result = evalCodeWithOutput(
        \\class A
        \\  def self.run
        \\    @@y &&= 1
        \\  end
        \\end
        \\A.run
    ,
        &stdout_buf,
        &stderr_buf,
    );

    try std.testing.expectEqual(@as(?anyerror, error.UnhandledException), result.err);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "NameError") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "uninitialized class variable @@y") != null);
}

test "class variable is visible in subclass" {
    const result = try evalCode(
        \\class Parent
        \\  @@cv = 9
        \\end
        \\class Child < Parent
        \\  def self.cv
        \\    @@cv
        \\  end
        \\end
        \\Child.cv
    );

    try std.testing.expectEqual(@as(i64, 9), result.data.integer);
}

test "class variable target works in multi assignment" {
    const result = try evalCode(
        \\class A
        \\  @@x = 0
        \\  def self.set
        \\    @@x, y = [7, 8]
        \\    @@x
        \\  end
        \\end
        \\A.set
    );

    try std.testing.expectEqual(@as(i64, 7), result.data.integer);
}

test "class variable target works in splat assignment" {
    const result = try evalCode(
        \\class A
        \\  @@x = 0
        \\  def self.set
        \\    *a, @@x = [1, 2, 3]
        \\    @@x
        \\  end
        \\end
        \\A.set
    );

    try std.testing.expectEqual(@as(i64, 3), result.data.integer);
}
