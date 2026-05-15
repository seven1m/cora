const std = @import("std");

const evalCodeWithOutput = @import("../test_helper.zig").evalCodeWithOutput;
test "require loads RubyGems after extending $LOAD_PATH" {
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
            "require \"rubygems/version\"; require \"rubygems/requirement\"; puts Gem::Requirement.default.to_s",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, ">= 0\n", result.stdout);
}

test "require runs Ruby files at top level lexical scope" {
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
            "require \"rubygems/version\"; class ScopeCarrier; require File.expand_path(\"ext/rubygems/lib/rubygems/requirement\", Dir.pwd); end; puts Gem::Requirement.default.to_s",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, ">= 0\n", result.stdout);
}

test "stdlib require loads monitor by default" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", "require \"monitor\"; puts Monitor.new.synchronize { 1 }" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "1\n", result.stdout);
}

test "stdlib require loads set by default" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            "require \"set\"; s = Set.new([1, 2, 2]); s.add(3); puts [s.include?(2), s.size, (s & [2, 4]).to_a[0]].inspect",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[true, 3, 2]\n", result.stdout);
}

test "stdlib require loads thread condition variable" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-e",
            \\require "thread"
            \\mutex = Thread::Mutex.new
            \\cv = ConditionVariable.new
            \\ready = false
            \\waiting = false
            \\t = Thread.new do
            \\  mutex.synchronize do
            \\    waiting = true
            \\    cv.wait(mutex, 1.0)
            \\    puts ready
            \\  end
            \\end
            \\Thread.pass until waiting
            \\mutex.synchronize do
            \\  ready = true
            \\  cv.signal
            \\end
            \\t.join
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "true\n", result.stdout);
}

test "require lazily registers OpenSSL" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\p defined?(OpenSSL)
        \\begin
        \\  OpenSSL
        \\rescue NameError
        \\  puts "missing"
        \\end
        \\p require("openssl")
        \\p defined?(OpenSSL)
        \\puts OpenSSL::Digest.hexdigest("sha1", "abc")
        \\p require("openssl")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("nil\nmissing\ntrue\n\"constant\"\na9993e364706816aba3e25717850c26c9cd0d89d\nfalse\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
