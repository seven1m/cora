const std = @import("std");
const test_helper = @import("../test_helper.zig");
const evalCode = test_helper.evalCode;

test "C extension fixture loads and defines method" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\"".cora_cext_test
    );
    try std.testing.expect(result.isTruthy());
    try std.testing.expectEqual(true, result.toBool());
}

test "C extension method works on arbitrary receiver" {
    const result = try evalCode(
        \\$LOAD_PATH << "build/cext"
        \\require "fixture.so"
        \\"hello".cora_cext_test
    );
    try std.testing.expectEqual(true, result.toBool());
}
