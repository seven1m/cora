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

test "RbConfig::CONFIG initializes and expands values" {
    const result = try evalCode(
        \\require 'rbconfig'
        \\[
        \\  RbConfig::CONFIG["MAJOR"],
        \\  RbConfig::CONFIG["bindir"],
        \\  RbConfig::CONFIG["ruby_version"],
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, "4", items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "/usr/bin", items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "4.0.0", items[2].toStringObject().str);
}
