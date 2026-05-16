const std = @import("std");

const evalCodeWithOutput = @import("test_helper.zig").evalCodeWithOutput;

test "fileutils mkdir_p cp mv rm_rf roundtrip" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "fileutils"
        \\root = "/tmp/cora_fileutils_test"
        \\FileUtils.rm_rf(root)
        \\FileUtils.mkdir_p(File.join(root, "a", "b"))
        \\src = File.join(root, "a", "b", "src.txt")
        \\File.write(src, "hello")
        \\dst = File.join(root, "copy.txt")
        \\FileUtils.cp(src, dst)
        \\moved = File.join(root, "moved.txt")
        \\FileUtils.mv(dst, moved)
        \\puts [File.read(moved), File.exist?(src), File.exist?(moved)].inspect
        \\FileUtils.rm_rf(root)
        \\puts File.exist?(root)
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"hello\", true, true]\nfalse\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
