const std = @import("std");

test "require uri, parse an https URL, and build HTTP URLs" {
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
            \\puts URI::HTTP.build(host: "example.com", port: 8080, path: "/hello", query: "x=1")
            \\puts URI::HTTP.build([nil, "example.com", nil, "/x", nil, nil])
            \\begin
            \\  URI::HTTP.build(host: "bad host")
            \\rescue URI::InvalidComponentError
            \\  puts "invalid host"
            \\end
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "https\nexample.com\n8443\n/path\nhttp://example.com:8080/hello?x=1\nhttp://example.com/x\ninvalid host\n", result.stdout);
}
