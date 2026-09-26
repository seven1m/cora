const std = @import("std");

test "bundled gems activate through RubyGems and are not default gems" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gem_home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/gem", allocator);
    defer allocator.free(gem_home);
    const home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test", allocator);
    defer allocator.free(home);
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("GEM_HOME", gem_home);
    try env_map.put("HOME", home);

    const code =
        \\Test::Unit::AutoRunner.need_auto_run = false
        \\require "csv"
        \\p [Gem.path.include?(Gem.dir), Gem.path.include?(Gem.default_dir)]
        \\p [Gem.loaded_specs["test-unit"].full_name, Gem.loaded_specs["test-unit"].default_gem?, Gem.loaded_specs["power_assert"].full_name, Gem.loaded_specs["power_assert"].default_gem?, Gem.loaded_specs["csv"].full_name, Gem.loaded_specs["csv"].default_gem?, Gem::Specification.find_by_name("json").default_gem?]
        \\p ObjectSpace.each_object(Class).any? { |klass| klass == Class }
    ;
    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "-r", "test/unit", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("[true, true]\n[\"test-unit-3.7.5\", false, \"power_assert-3.0.1\", false, \"csv-3.3.6\", false, true]\ntrue\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "bundled test-unit runs a test case" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gem_home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/gem", allocator);
    defer allocator.free(gem_home);
    const home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test", allocator);
    defer allocator.free(home);
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("GEM_HOME", gem_home);
    try env_map.put("HOME", home);

    const code =
        \\require "test/unit"
        \\class BundledGemSmokeTest < Test::Unit::TestCase
        \\  def test_assertion
        \\    assert_equal(3, 1 + 2)
        \\  end
        \\end
    ;
    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1 tests, 1 assertions, 0 failures, 0 errors") != null);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "bundled gems obey explicit GEM_PATH and disable-gems" {
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

    for ([_][]const u8{ "test/unit", "csv" }) |library| {
        const expected_error = try std.fmt.allocPrint(allocator, "cannot load such file -- {s}", .{library});
        defer allocator.free(expected_error);

        const isolated = try std.process.run(allocator, threaded.io(), .{
            .argv = &.{ "build/bin/cora", "-r", library, "-e", "nil" },
            .environ_map = &env_map,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        defer allocator.free(isolated.stdout);
        defer allocator.free(isolated.stderr);
        try std.testing.expect(isolated.term == .exited and isolated.term.exited != 0);
        try std.testing.expect(std.mem.indexOf(u8, isolated.stderr, expected_error) != null);

        const no_gems = try std.process.run(allocator, threaded.io(), .{
            .argv = &.{ "build/bin/cora", "--disable-gems", "-r", library, "-e", "nil" },
            .environ_map = &env_map,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        defer allocator.free(no_gems.stdout);
        defer allocator.free(no_gems.stderr);
        try std.testing.expect(no_gems.term == .exited and no_gems.term.exited != 0);
        try std.testing.expect(std.mem.indexOf(u8, no_gems.stderr, expected_error) != null);
    }
}

test "Bundler resolves bundled test-unit from a Gemfile" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gem_home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/gem", allocator);
    defer allocator.free(gem_home);
    const gemfile = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/support/bundled_gems/Gemfile", allocator);
    defer allocator.free(gemfile);
    const home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test", allocator);
    defer allocator.free(home);
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("GEM_HOME", gem_home);
    try env_map.put("BUNDLE_GEMFILE", gemfile);
    try env_map.put("HOME", home);

    const code =
        \\require "bundler/setup"
        \\require "test/unit"
        \\Test::Unit::AutoRunner.need_auto_run = false
        \\p [Gem.loaded_specs["test-unit"].version.to_s, Gem.loaded_specs["power_assert"].version.to_s]
    ;
    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("[\"3.7.5\", \"3.0.1\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
