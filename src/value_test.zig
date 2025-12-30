const std = @import("std");
const Value = @import("value.zig").Value;

test "Value.nil() is frozen" {
    const nil_value = Value.nil();
    try std.testing.expect(nil_value.frozen == true);
    try std.testing.expect(nil_value.data == .nil);
}

test "Value.frozenString() creates frozen string" {
    const test_string = "hello";
    const str_value = Value.frozenString(test_string);
    try std.testing.expect(str_value.frozen == true);
    try std.testing.expectEqualSlices(u8, str_value.data.string, test_string);
}

test "Value.integer() creates frozen integer" {
    const int_value = Value.integer(42);
    try std.testing.expect(int_value.frozen == true);
    try std.testing.expect(int_value.data.integer == 42);
}

test "Value.integer() handles negative integers" {
    const int_value = Value.integer(-123);
    try std.testing.expect(int_value.frozen == true);
    try std.testing.expect(int_value.data.integer == -123);
}
