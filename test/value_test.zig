const std = @import("std");
const Value = @import("cora").value.Value;
const bdwgc = @import("bdwgc");

test "Value.nil() is frozen" {
    const nil_value = Value.nil();
    try std.testing.expect(nil_value.isFrozen());
    try std.testing.expect(nil_value.isNil());
}

test "Value.integer() creates frozen integer" {
    const int_value = Value.integer(42);
    try std.testing.expect(int_value.isFrozen());
    try std.testing.expectEqual(42, int_value.toInteger());
}

test "Value.integer() handles negative integers" {
    const int_value = Value.integer(-123);
    try std.testing.expect(int_value.isFrozen());
    try std.testing.expectEqual(-123, int_value.toInteger());
}
