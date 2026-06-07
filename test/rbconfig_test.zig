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

test "RbConfig::MAKEFILE_CONFIG stays raw and separate from CONFIG" {
    const result = try evalCode(
        \\require 'rbconfig'
        \\raw = RbConfig::MAKEFILE_CONFIG
        \\conf = RbConfig::CONFIG
        \\raw["MAJOR"] = "9"
        \\[
        \\  raw.equal?(conf),
        \\  raw["ruby_version"],
        \\  conf["ruby_version"],
        \\  RbConfig.fire_update!("MAJOR", "8"),
        \\  conf["ruby_version"],
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(false, items[0].isTruthy());
    try std.testing.expectEqualSlices(u8, "$(MAJOR).$(MINOR).$(TEENY)", items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "4.0.0", items[2].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "8.0.0", items[4].toStringObject().str);
}
