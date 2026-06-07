const std = @import("std");

test "require optparse and parse a named option" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-e",
            \\require "optparse"
            \\name = nil
            \\parser = OptionParser.new
            \\parser.on("-nNAME", "--name=NAME") { |n| name = n }
            \\parser.parse!(["--name", "cora"])
            \\puts name
            ,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "cora\n", result.stdout);
}
