const std = @import("std");

test "exit propagates process status" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", "exit 7" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 7);
}

test "unknown cli flag exits with ruby-style error" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "--wat" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings(
        "cora: invalid option --wat  (-h will show valid options) (RuntimeError)\n",
        result.stderr,
    );
}

test "frozen string literal cli defaults apply to loaded files and eval" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const enabled_code =
        \\# frozen_string_literal: false
        \\p ["main".frozen?, eval(%q{"eval".frozen?})]
        \\load "test/support/frozen_literals.rb"
    ;
    const disabled_code =
        \\# frozen_string_literal: true
        \\p ["main".frozen?, eval(%q{"eval".frozen?})]
        \\load "test/support/frozen_literals.rb"
    ;
    const cases = [_]struct { flag: []const u8, code: []const u8, expected: []const u8 }{
        .{ .flag = "--enable-frozen-string-literal", .code = enabled_code, .expected = "[false, true]\n[true, true]\n" },
        .{ .flag = "--enable=frozen-string-literal", .code = enabled_code, .expected = "[false, true]\n[true, true]\n" },
        .{ .flag = "--disable-frozen-string-literal", .code = disabled_code, .expected = "[true, false]\n[false, false]\n" },
        .{ .flag = "--disable=frozen-string-literal", .code = disabled_code, .expected = "[true, false]\n[false, false]\n" },
    };
    for (cases) |case| {
        const result = try std.process.run(allocator, threaded.io(), .{
            .argv = &.{ "zig-out/bin/cora", case.flag, "-e", case.code },
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings(case.expected, result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
    }
}

test "cli syntax errors exit before executing recovered source" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    for ([_][]const u8{ "puts 'executed'; /foo/a", "puts 'executed'; def bad; /(/; end", "puts 'executed'; break" }) |source| {
        const result = try std.process.run(std.testing.allocator, threaded.io(), .{
            .argv = &.{ "zig-out/bin/cora", "-e", source },
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        });
        defer std.testing.allocator.free(result.stdout);
        defer std.testing.allocator.free(result.stderr);
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("", result.stdout);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "SyntaxError") != null);
    }
}

test "inline source retains its label without acquiring a filesystem identity" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const source =
        \\def location; [__FILE__, __dir__]; end
        \\p location
        \\p proc { __dir__ }.call
        \\begin
        \\  require_relative "missing"
        \\rescue LoadError => error
        \\  puts error.message
        \\end
    ;
    const result = try std.process.run(std.testing.allocator, threaded.io(), .{
        .argv = &.{ "zig-out/bin/cora", "-e", source },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualStrings("[\"-e\", nil]\nnil\ncannot infer basepath\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
