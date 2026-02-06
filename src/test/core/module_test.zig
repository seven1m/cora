const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "Modules" {
    const result = try evalCode(
        \\module Foo
        \\end
    );
    try std.testing.expect(result.data == .module);
    try std.testing.expectEqualSlices(u8, "Foo", result.data.module.name.name);
}

test "Module include" {
    var result = try evalCode(
        \\module Foo
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\module Baz
        \\  def call
        \\    'baz'
        \\  end
        \\end
        \\
        \\class Bar
        \\  include Foo
        \\  include Baz
        \\end
        \\
        \\bar = Bar.new
        \\bar.call
    );
    try std.testing.expectEqualSlices(u8, "baz", result.data.string.str);

    result = try evalCode(
        \\module Foo
        \\  def call
        \\    'nope'
        \\  end
        \\end
        \\
        \\class Bar
        \\  include Foo
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\bar = Bar.new
        \\bar.call
    );
    try std.testing.expectEqualSlices(u8, "foo", result.data.string.str);
}

test "Module prepend" {
    const result = try evalCode(
        \\module Before
        \\  def call
        \\    'before'
        \\  end
        \\end
        \\
        \\module Before2
        \\  def call
        \\    'before 2'
        \\  end
        \\end
        \\
        \\class Foo
        \\  prepend Before
        \\  prepend Before2
        \\  def call
        \\    'foo'
        \\  end
        \\end
        \\
        \\Foo.new.call
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "before 2", result.data.string.str);
}

test "Module define_method on class" {
    const result = try evalCode(
        \\class Foo
        \\  define_method(:sum) { |a, b| a + b }
        \\end
        \\Foo.new.sum(2, 3)
    );
    try std.testing.expectEqual(@as(i64, 5), result.data.integer);
}

test "Module define_method on module include" {
    const result = try evalCode(
        \\module M
        \\  define_method(:hello) { 'hi' }
        \\end
        \\class C
        \\  include M
        \\end
        \\C.new.hello
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hi", result.data.string.str);
}

test "Module define_method with string name" {
    const result = try evalCode(
        \\class Foo
        \\  define_method("mul") { |a, b| a * b }
        \\end
        \\Foo.new.mul(2, 4)
    );
    try std.testing.expectEqual(@as(i64, 8), result.data.integer);
}
