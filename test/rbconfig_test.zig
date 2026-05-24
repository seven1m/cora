const std = @import("std");
const test_helper = @import("test_helper.zig");

const evalCode = test_helper.evalCode;

test "RbConfig.ruby returns configured executable path" {
    const result = try evalCode(
        \\require 'rbconfig'
        \\RbConfig.ruby
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "/tmp/cora-test", result.toStringObject().str);
}
