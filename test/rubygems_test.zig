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

test "RubyGems applies matching Cora gem patches once after activation" {
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

    const code =
        \\require "rubygems"
        \\$patch_count = 0
        \\Cora::GemPatches.register("fake_gem", "~> 0.1") do |spec|
        \\  raise "patch ran before activation" unless Gem.loaded_specs[spec.name].equal?(spec)
        \\  $patch_count += 1
        \\end
        \\Cora::GemPatches.register("fake_gem", ">= 1.0") { $patch_count += 100 }
        \\require "fake_gem"
        \\Gem.loaded_specs["fake_gem"].activate
        \\p [$patch_count, FakeGem]
    ;

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[1, FakeGem]\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "cora: applied compatibility patch for fake_gem-0.1.0\n", result.stderr);
}

test "Bundler applies Cora gem patches after load paths are ready without recursion" {
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

    const gemfile = try std.Io.Dir.cwd().realPathFileAlloc(threaded.io(), "test/support/bundled_gems/Gemfile.patches", allocator);
    defer allocator.free(gemfile);
    try env_map.put("BUNDLE_GEMFILE", gemfile);

    const code =
        \\require "rubygems"
        \\$patch_count = 0
        \\Cora::GemPatches.register("fake_gem", "~> 0.1") do |spec|
        \\  raise "patch ran before activation" unless Gem.loaded_specs[spec.name].equal?(spec)
        \\  require "fake_gem"
        \\  Gem.add_to_load_path
        \\  $patch_count += 1
        \\end
        \\Cora::GemPatches.register("fake_gem", ">= 1.0") { $patch_count += 100 }
        \\require "bundler/setup"
        \\Bundler.setup
        \\p [$patch_count, FakeGem]
    ;

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[1, FakeGem]\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "cora: applied compatibility patch for fake_gem-0.1.0\n", result.stderr);
}

test "require rubygems/gem_runner avoids circular require warning" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Izig-out/ext/rubygems/lib",
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

test "RubyGems prefers source gems for Cora" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const code =
        \\require "rubygems"
        \\require "bundler"
        \\dependency = Gem::Dependency.new("sqlite3")
        \\p [
        \\  Gem::Platform.match_gem?(Gem::Platform::RUBY, "sqlite3"),
        \\  Gem::Platform.match_gem?(Gem::Platform.local, "sqlite3"),
        \\  dependency.default_force_ruby_platform,
        \\]
    ;

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", code },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[true, false, true]\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "", result.stderr);
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
        .argv = &.{ "zig-out/bin/cora", "-Izig-out/ext/rubygems/bundler/lib", "-e", code },
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
        .argv = &.{ "zig-out/bin/cora", "-Izig-out/ext/rubygems/bundler/lib", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "Bundler::Definition\n", result.stdout);
}

test "Bundler activates a default gemspec matching its shipped code" {
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
    const code =
        \\require "rubygems"
        \\require "bundler"
        \\spec = Gem.loaded_specs.fetch("bundler")
        \\raise "Bundler version mismatch" unless spec.version.to_s == Bundler::VERSION
        \\raise "Bundler is not a default gem" unless spec.default_gem?
        \\metadata = Bundler::Source::Metadata.new.specs.search("bundler").first
        \\raise "metadata uses a different Bundler" unless metadata.version == spec.version
        \\puts "ok"
    ;
    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", code },
        .environ_map = &env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("ok\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
