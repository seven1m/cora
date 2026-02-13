const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "xstring executes command and returns stdout" {
    const result = try evalCode("`printf cora`");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("cora", result.data.string.str);
}

test "interpolated xstring executes with interpolation" {
    const result = try evalCode("name = \"cora\"; `printf #{name}`");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("cora", result.data.string.str);
}

test "xstring interpolation supports embedded global variable" {
    const result = try evalCode("$foo = \"ok\"; `printf #$foo`");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualStrings("ok", result.data.string.str);
}

test "xstring updates $?.exitstatus on success" {
    const result = try evalCode("`:`; $?.exitstatus");
    try std.testing.expect(result.data == .integer);
    try std.testing.expectEqual(@as(i64, 0), result.data.integer);
}

test "xstring updates $?.exitstatus on failure" {
    const result = try evalCode("`command_that_should_not_exist_12345`; $?.exitstatus > 0");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
}
