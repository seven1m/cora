const std = @import("std");
const Value = @import("value.zig").Value;
const bdwgc = @import("bdwgc");

test "Value.nil() is frozen" {
    const nil_value = Value.nil();
    try std.testing.expect(nil_value.isFrozen());
    try std.testing.expectEqual(.nil, nil_value.data);
}

test "Value.frozenString() creates frozen string" {
    const test_string = "hello";
    const str_value = Value.frozenString(test_string);
    try std.testing.expect(str_value.isFrozen());
    try std.testing.expectEqualSlices(u8, test_string, str_value.data.string);
}

test "Value.integer() creates frozen integer" {
    const int_value = Value.integer(42);
    try std.testing.expect(int_value.isFrozen());
    try std.testing.expectEqual(42, int_value.data.integer);
}

test "Value.integer() handles negative integers" {
    const int_value = Value.integer(-123);
    try std.testing.expect(int_value.isFrozen());
    try std.testing.expectEqual(-123, int_value.data.integer);
}
