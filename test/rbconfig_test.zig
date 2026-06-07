const std = @import("std");
const test_helper = @import("test_helper.zig");

const evalCode = test_helper.evalCode;

test "RbConfig.ruby returns configured executable path" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var exe_path_buffer: [4096]u8 = undefined;
    const exe_path_len = try std.Io.Dir.cwd().realPathFile(threaded.io(), test_helper.cora_executable_path, &exe_path_buffer);
    const result = try evalCode(
        \\require 'rbconfig'
        \\RbConfig.ruby
    );
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, exe_path_buffer[0..exe_path_len], result.toStringObject().str);
}

test "RbConfig::CONFIG initializes and expands values" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var exe_path_buffer: [4096]u8 = undefined;
    const exe_path_len = try std.Io.Dir.cwd().realPathFile(threaded.io(), test_helper.cora_executable_path, &exe_path_buffer);
    const exe_path = exe_path_buffer[0..exe_path_len];
    const root = std.fs.path.dirname(std.fs.path.dirname(exe_path) orelse exe_path) orelse exe_path;
    var bindir_buf: [4096]u8 = undefined;
    const expected_bindir = try std.fmt.bufPrint(&bindir_buf, "{s}/bin", .{root});
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
    try std.testing.expectEqualSlices(u8, expected_bindir, items[1].toStringObject().str);
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
        \\  RbConfig::MAKEFILE_CONFIG["bindir"],
        \\  RbConfig.fire_update!("MAJOR", "8"),
        \\  conf["ruby_version"],
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(false, items[0].isTruthy());
    try std.testing.expectEqualSlices(u8, "$(MAJOR).$(MINOR).$(TEENY)", items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "4.0.0", items[2].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "$(exec_prefix)/bin", items[3].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "8.0.0", items[5].toStringObject().str);
}

test "RbConfig runtime refresh keeps raw templates and expanded runtime paths" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var exe_path_buffer: [4096]u8 = undefined;
    const exe_path_len = try std.Io.Dir.cwd().realPathFile(threaded.io(), test_helper.cora_executable_path, &exe_path_buffer);
    const exe_path = exe_path_buffer[0..exe_path_len];
    const root = std.fs.path.dirname(std.fs.path.dirname(exe_path) orelse exe_path) orelse exe_path;
    var bindir_buf: [4096]u8 = undefined;
    const expected_bindir = try std.fmt.bufPrint(&bindir_buf, "{s}/bin", .{root});
    var hdrdir_buf: [4096]u8 = undefined;
    const expected_hdrdir = try std.fmt.bufPrint(&hdrdir_buf, "{s}/include/cora", .{root});
    const result = try evalCode(
        \\require 'rbconfig'
        \\[
        \\  RbConfig::TOPDIR,
        \\  RbConfig::CONFIG["topdir"],
        \\  RbConfig::CONFIG["prefix"],
        \\  RbConfig::MAKEFILE_CONFIG["prefix"],
        \\  RbConfig::MAKEFILE_CONFIG["bindir"],
        \\  RbConfig::CONFIG["bindir"],
        \\  RbConfig::MAKEFILE_CONFIG["rubyhdrdir"],
        \\  RbConfig::CONFIG["rubyhdrdir"],
        \\  RbConfig::MAKEFILE_CONFIG["rubyarchhdrdir"],
        \\  RbConfig::CONFIG["rubyarchhdrdir"],
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, root, items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, root, items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, root, items[2].toStringObject().str);
    try std.testing.expectEqualSlices(u8, root, items[3].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "$(exec_prefix)/bin", items[4].toStringObject().str);
    try std.testing.expectEqualSlices(u8, expected_bindir, items[5].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "$(includedir)/cora", items[6].toStringObject().str);
    try std.testing.expectEqualSlices(u8, expected_hdrdir, items[7].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "$(rubyhdrdir)", items[8].toStringObject().str);
    try std.testing.expectEqualSlices(u8, expected_hdrdir, items[9].toStringObject().str);
}

test "RbConfig.fire_update! rebuilds dependent expanded values from MAKEFILE_CONFIG" {
    const result = try evalCode(
        \\require 'rbconfig'
        \\RbConfig.fire_update!("CC", "clang")
        \\[
        \\  RbConfig::MAKEFILE_CONFIG["CC"],
        \\  RbConfig::CONFIG["CC"],
        \\  RbConfig::CONFIG["CC_VERSION"],
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, "clang", items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "clang", items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "clang --version", items[2].toStringObject().str);
}
