const std = @import("std");

test "require lazily loads rubygems and activates fake gem from GEM_HOME" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gem_home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/gem", allocator);
    defer allocator.free(gem_home);

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("GEM_HOME", gem_home);
    try env_map.put("GEM_PATH", gem_home);

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            "require \"fake_gem\"; p FakeGem",
        },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "FakeGem\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "", result.stderr);
}
