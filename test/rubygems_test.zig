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
            "build/bin/cora",
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

test "require rubygems/gem_runner avoids circular require warning" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-Ibuild/ext/rubygems/lib",
            "-e",
            "require \"rubygems/gem_runner\"; puts :ok",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "ok\n", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "circular require considered harmful") == null);
}

test "__send__ preserves call state across Bundler plugin autoload" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gemfile = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/support/Gemfile", allocator);
    defer allocator.free(gemfile);

    const home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test", allocator);
    defer allocator.free(home);

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("BUNDLE_GEMFILE", gemfile);
    try env_map.put("HOME", home);

    const code =
        \\require "bundler"
        \\module Bundler
        \\  class SendAutoloadRegression
        \\    def run
        \\      Plugin.gemfile_install(Bundler.default_gemfile)
        \\      puts Bundler.definition.class.name
        \\    end
        \\  end
        \\end
        \\Bundler::SendAutoloadRegression.new.__send__(:run)
    ;

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "-Ibuild/ext/rubygems/bundler/lib", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "Bundler::Definition\n", result.stdout);
}

test "Method#call preserves call state across Bundler plugin autoload" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const gemfile = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/support/Gemfile", allocator);
    defer allocator.free(gemfile);

    const home = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test", allocator);
    defer allocator.free(home);

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    try env_map.put("BUNDLE_GEMFILE", gemfile);
    try env_map.put("HOME", home);

    const code =
        \\require "bundler"
        \\module Bundler
        \\  class MethodCallAutoloadRegression
        \\    def run
        \\      Plugin.gemfile_install(Bundler.default_gemfile)
        \\      puts Bundler.definition.class.name
        \\    end
        \\  end
        \\end
        \\Bundler::MethodCallAutoloadRegression.new.method(:run).call
    ;

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "-Ibuild/ext/rubygems/bundler/lib", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "Bundler::Definition\n", result.stdout);
}
