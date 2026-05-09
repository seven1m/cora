const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

fn uniquePath(buf: *[128]u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "/tmp/cora_io_{d}.txt", .{@as(i128, @intCast(std.Io.Clock.boot.now(std.testing.io).nanoseconds))});
}

test "STDIN/STDOUT/STDERR constants mirror $stdin/$stdout/$stderr" {
    const result = try evalCode(
        \\[
        \\  STDIN.object_id == $stdin.object_id,
        \\  STDOUT.object_id == $stdout.object_id,
        \\  STDERR.object_id == $stderr.object_id
        \\]
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 3), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[2].toBool());
}

test "standard stream fileno values are 0,1,2" {
    const result = try evalCode("[STDIN.fileno, STDOUT.fileno, STDERR.fileno]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 0), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, 2), result.toArrayObject().elements.items[2].toInteger());
}

test "File.write and File.read round trip content" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\n = File.write(path, "hello")
        \\[n, File.read(path)]
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 5), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expect(result.toArrayObject().elements.items[1].isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "File.delete and File.unlink remove files and return the deleted count" {
    var path1_buf: [128]u8 = undefined;
    var path2_buf: [128]u8 = undefined;
    const path1 = try uniquePath(&path1_buf);
    const path2 = try std.fmt.bufPrint(&path2_buf, "{s}_second", .{path1});

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path1 = "{s}"
        \\path2 = "{s}"
        \\File.write(path1, "a")
        \\File.write(path2, "b")
        \\[
        \\  File.delete(path1),
        \\  File.exist?(path1),
        \\  File.unlink(path2),
        \\  File.exist?(path2)
        \\]
    , .{ path1, path2 });
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[3].toBool());
}

test "File.delete accepts zero args and coerces to_path" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\obj = Object.new
        \\def obj.to_path
        \\  @path
        \\end
        \\obj.instance_variable_set(:@path, path)
        \\File.write(path, "x")
        \\[
        \\  File.delete,
        \\  File.delete(obj),
        \\  File.exist?(path)
        \\]
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(i64, 0), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, 1), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
}

test "File.open and File.delete raise mapped Errno classes" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\missing = "{s}"
        \\[
        \\  begin
        \\    File.open(missing, "r")
        \\  rescue Errno::ENOENT
        \\    :open_ok
        \\  end,
        \\  begin
        \\    File.delete(missing)
        \\  rescue Errno::ENOENT
        \\    :delete_ok
        \\  end
        \\]
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expect(result.toArrayObject().elements.items[0].isSymbol());
    try std.testing.expectEqualSlices(u8, "open_ok", result.toArrayObject().elements.items[0].toSymbolObject().name);
    try std.testing.expect(result.toArrayObject().elements.items[1].isSymbol());
    try std.testing.expectEqualSlices(u8, "delete_ok", result.toArrayObject().elements.items[1].toSymbolObject().name);
}

test "Dir.mkdir raises mapped Errno class for existing path" {
    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/tmp/cora_dir_{d}", .{@as(i128, @intCast(std.Io.Clock.boot.now(std.testing.io).nanoseconds))});

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\Dir.mkdir(path)
        \\begin
        \\  Dir.mkdir(path)
        \\rescue Errno::EEXIST
        \\  :mkdir_ok
        \\end
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isSymbol());
    try std.testing.expectEqualSlices(u8, "mkdir_ok", result.toSymbolObject().name);
}

test "File.open with block closes file automatically" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\f = nil
        \\File.open(path, "w") {{ |io| f = io; io.write("x") }}
        \\f.closed?
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "Kernel puts and p follow $stdout reassignment" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\f = File.open(path, "w")
        \\$stdout = f
        \\puts "alpha"
        \\p 42
        \\$stdout = STDOUT
        \\f.close
        \\File.read(path)
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "alpha\n42\n", result.toStringObject().str);
}

test "File.new invalid mode raises ArgumentError" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const source = try std.fmt.allocPrint(std.testing.allocator, "File.new(\"{s}\", \"q\")", .{path});
    defer std.testing.allocator.free(source);

    const result = evalCodeWithOutput(source, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "write on closed File raises IOError" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\f = File.open("{s}", "w")
        \\f.close
        \\f.write("x")
    , .{path});
    defer std.testing.allocator.free(source);

    const result = evalCodeWithOutput(source, &stdout_buf, &stderr_buf);
    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "IOError") != null);
}

test "Dir.pwd returns the current working directory" {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);

    const result = try evalCode("Dir.pwd");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, cwd, result.toStringObject().str);
}

test "Dir.home follows HOME and supports the current USER" {
    const passwd = std.c.getpwuid(std.c.getuid()) orelse return error.SkipZigTest;
    const current_user = std.mem.span(passwd.name orelse return error.SkipZigTest);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\old_home = ENV["HOME"]
        \\old_user = ENV["USER"]
        \\ENV["HOME"] = "/tmp/cora_home"
        \\ENV["USER"] = "{s}"
        \\begin
        \\  [Dir.home, Dir.home("{s}")]
        \\ensure
        \\  ENV["HOME"] = old_home
        \\  ENV["USER"] = old_user
        \\end
    , .{ current_user, current_user });
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);

    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "/tmp/cora_home", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expect(result.toArrayObject().elements.items[1].isString());
}

test "Dir.home rejects a non-current user" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [8192]u8 = undefined;
    const result = evalCodeWithOutput(
        \\old_home = ENV["HOME"]
        \\old_user = ENV["USER"]
        \\ENV["HOME"] = "/tmp/cora_home"
        \\ENV["USER"] = "cora_spec_user"
        \\begin
        \\  Dir.home("other_user")
        \\ensure
        \\  ENV["HOME"] = old_home
        \\  ENV["USER"] = old_user
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expectEqual(error.UnhandledException, result.err.?);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "ArgumentError") != null);
}

test "File.join and File.dirname provide minimal Unix path helpers" {
    const result = try evalCode("[File.join('/tmp', 'a', 'b'), File.dirname('/tmp/a/b')]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "/tmp/a/b", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "/tmp/a", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "File.join accepts array as single argument" {
    const result = try evalCode("File.join(['food', 'bar'])");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "food/bar", result.toStringObject().str);
}

test "File.expand_path handles relative and home-based paths" {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\old_home = ENV["HOME"]
        \\ENV["HOME"] = "/tmp/cora_home"
        \\begin
        \\  [
        \\    File.expand_path("a"),
        \\    File.expand_path("../bin", "tmp/x"),
        \\    File.expand_path("~/lib")
        \\  ]
        \\ensure
        \\  ENV["HOME"] = old_home
        \\end
    , .{});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());

    const expected_a = try std.fmt.allocPrint(std.testing.allocator, "{s}/a", .{cwd});
    defer std.testing.allocator.free(expected_a);
    const expected_bin = try std.fmt.allocPrint(std.testing.allocator, "{s}/tmp/bin", .{cwd});
    defer std.testing.allocator.free(expected_bin);

    try std.testing.expectEqualSlices(u8, expected_a, result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, expected_bin, result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "/tmp/cora_home/lib", result.toArrayObject().elements.items[2].toStringObject().str);
}

test "Dir.home and File.expand_path fall back to passwd lookup when HOME is unset" {
    const passwd_home = std.mem.span((std.c.getpwuid(std.c.getuid()) orelse return error.SkipZigTest).dir orelse return error.SkipZigTest);

    const result = try evalCode(
        \\old_home = ENV["HOME"]
        \\begin
        \\  ENV.delete("HOME")
        \\  [Dir.home, File.expand_path("~"), File.expand_path("~/")]
        \\ensure
        \\  ENV["HOME"] = old_home
        \\end
    );

    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, passwd_home, result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, passwd_home, result.toArrayObject().elements.items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, passwd_home, result.toArrayObject().elements.items[2].toStringObject().str);
}
