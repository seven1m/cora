const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "instance variable basic assignment and read" {
    const result = try evalCode(
        \\class Foo
        \\  def set_x(val)
        \\    @x = val
        \\  end
        \\  def get_x
        \\    @x
        \\  end
        \\end
        \\f = Foo.new
        \\f.set_x(42)
        \\f.get_x
    );
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "instance variable uninitialized returns nil" {
    const result = try evalCode(
        \\class Bar
        \\  def get_undefined
        \\    @undefined
        \\  end
        \\end
        \\Bar.new.get_undefined
    );
    try std.testing.expect(result.data == .nil);
}
