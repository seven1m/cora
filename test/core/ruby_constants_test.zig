const std = @import("std");
const builtin = @import("builtin");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "RUBY_ENGINE is cora" {
    const result = try evalCode("RUBY_ENGINE");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "cora", result.toStringObject().str);
}

test "RUBY_VERSION is 4.0.0" {
    const result = try evalCode("RUBY_VERSION");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "4.0.0", result.toStringObject().str);
}

test "RUBY_PLATFORM matches build target arch-os" {
    const result = try evalCode("RUBY_PLATFORM");
    try std.testing.expect(result.isString());
    const expected = comptime std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
    try std.testing.expectEqualSlices(u8, expected, result.toStringObject().str);
}

test "Marshal version constants are available" {
    const result = try evalCode("[Marshal::MAJOR_VERSION, Marshal::MINOR_VERSION]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 4), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 8), result.toArrayObject().elements.items[1].toInteger());
}
