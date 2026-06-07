const std = @import("std");

test "require uri and parse an https URL" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-e",
            \\require "uri"
            \\uri = URI.parse("https://example.com:8443/path?q=1")
            \\puts uri.scheme
            \\puts uri.host
            \\puts uri.port
            \\puts uri.path
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "https\nexample.com\n8443\n/path\n", result.stdout);
}
