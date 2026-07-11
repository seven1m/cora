const std = @import("std");

fn uniqueId() u64 {
    return @intCast(std.Io.Clock.boot.now(std.testing.io).nanoseconds);
}

test "--pack creates an executable that extracts and runs a Ruby application" {
    const allocator = std.testing.allocator;
    const root = try std.fmt.allocPrint(allocator, "/tmp/cora-pack-test-{d}", .{uniqueId()});
    defer allocator.free(root);
    try std.Io.Dir.createDirAbsolute(std.testing.io, root, @enumFromInt(0o700));
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};

    const lib_dir = try std.fs.path.join(allocator, &.{ root, "lib" });
    defer allocator.free(lib_dir);
    const data_dir = try std.fs.path.join(allocator, &.{ root, "data" });
    defer allocator.free(data_dir);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, lib_dir);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, data_dir);

    const main_path = try std.fs.path.join(allocator, &.{ root, "main.rb" });
    defer allocator.free(main_path);
    const lib_path = try std.fs.path.join(allocator, &.{ lib_dir, "greeting.rb" });
    defer allocator.free(lib_path);
    const asset_path = try std.fs.path.join(allocator, &.{ data_dir, "message.txt" });
    defer allocator.free(asset_path);
    const output_path = try std.fmt.allocPrint(allocator, "/tmp/cora-packed-test-{d}", .{uniqueId()});
    defer allocator.free(output_path);
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, output_path) catch {};

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = main_path, .data = "$LOAD_PATH.unshift(File.join(__dir__, 'lib'))\nrequire 'greeting'\nputs Greeting.message(ARGV[0])\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = lib_path, .data = "module Greeting\n  def self.message(name)\n    \"#{File.read(File.join(__dir__, '..', 'data', 'message.txt')).strip}, #{name}!\"\n  end\nend\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = asset_path, .data = "hello\n" });

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const pack_result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ "build/bin/cora", "--pack", "-o", output_path, main_path },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(pack_result.stdout);
    defer allocator.free(pack_result.stderr);
    try std.testing.expect(pack_result.term == .exited and pack_result.term.exited == 0);

    const run_result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{ output_path, "Cora" },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);
    try std.testing.expect(run_result.term == .exited and run_result.term.exited == 0);
    try std.testing.expectEqualStrings("hello, Cora!\n", run_result.stdout);
}
