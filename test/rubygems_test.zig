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

test "require rubygems/gem_runner avoids circular require warning" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Iext/rubygems/lib",
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

test "rubygems request set install preserves locals across nested thread blocks" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Iext/rubygems/lib",
            "-e",
            \\require "thread"
            \\require "rubygems"
            \\require "rubygems/dependency_installer"
            \\dinst = Gem::DependencyInstaller.new({})
            \\request_set = dinst.resolve_dependencies("rack", Gem::Requirement.create(nil))
            \\def probe(rs, options)
            \\  requests = []
            \\  download_queue = Thread::Queue.new
            \\  rs.sorted_requests.each do |req|
            \\    download_queue << req
            \\  end
            \\  threads = Array.new(Gem.configuration.concurrent_downloads) do
            \\    download_queue << :stop
            \\    Thread.new do
            \\      while req = download_queue.pop
            \\        break if req == :stop
            \\        req.spec.download options unless req.installed?
            \\      end
            \\    end
            \\  end
            \\  threads.each(&:value)
            \\  rs.sorted_requests.each do |req|
            \\    requests << req
            \\  end
            \\  puts [threads.class, requests.length].join(":")
            \\end
            \\probe(request_set, {})
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "Array:1\n", result.stdout);
    try std.testing.expectEqualSlices(u8, "", result.stderr);
}
