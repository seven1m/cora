const std = @import("std");

test "binary: simple puts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var child = std.process.Child.init(&.{ "zig-out/bin/clara", "-e", "puts 1" }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try child.wait();

    try std.testing.expect(term == .Exited and term.Exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, stderr, "1") != null);
}
