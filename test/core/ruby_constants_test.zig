const std = @import("std");
const builtin = @import("builtin");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "RUBY_ENGINE is cora" {
    const result = try evalCode("RUBY_ENGINE");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "cora", result.data.string.str);
}

test "RUBY_VERSION is 4.0.0" {
    const result = try evalCode("RUBY_VERSION");
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "4.0.0", result.data.string.str);
}

test "RUBY_PLATFORM matches build target arch-os" {
    const result = try evalCode("RUBY_PLATFORM");
    try std.testing.expect(result.data == .string);
    const expected = comptime std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
    try std.testing.expectEqualSlices(u8, expected, result.data.string.str);
}
