const std = @import("std");

test "require yaml loads psych by default" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-e",
            "require \"yaml\"; puts [YAML == Psych, YAML.load(\"---\\na: 1\\n\")[\"a\"]].inspect",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[true, 1]\n", result.stdout);
}

test "YAML.load_file parses file contents" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-e",
            "require \"yaml\"; p YAML.load_file(\"test/support/load_file.yml\")[\"dist\"]",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "\"jammy\"\n", result.stdout);
}

test "psych and yaml are registered as default gems" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "bin/cora",
            "-e",
            "require \"rubygems\"; p Gem::Specification.find_all_by_name(\"psych\").select(&:default_gem?).map { |s| [s.name, s.version.to_s, s.default_gem?] }; p Gem::Specification.find_all_by_name(\"yaml\").select(&:default_gem?).map { |s| [s.name, s.version.to_s, s.default_gem?] }",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "[[\"psych\", \"5.4.0\", true]]\n[[\"yaml\", \"0.4.0\", true]]\n", result.stdout);
}
