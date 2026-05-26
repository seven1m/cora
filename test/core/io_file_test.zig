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

test "IO exposes binary mode constant" {
    const result = try evalCode("IO.const_defined?(:BINARY) && IO::BINARY == 0");
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(true, result.toBool());
}

test "File#tty? is false for regular files" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.write(path, "hello")
        \\f = File.open(path, "r")
        \\begin
        \\  f.tty?
        \\ensure
        \\  f.close
        \\end
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isBool());
    try std.testing.expectEqual(false, result.toBool());
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

test "File.read accepts optional length and offset" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.write(path, "abcdef")
        \\[
        \\  File.read(path, 2),
        \\  File.read(path, 3, 2),
        \\  File.read(path, 1, 6)
        \\]
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, "ab", items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "cde", items[1].toStringObject().str);
    try std.testing.expect(items[2].isNil());
}

test "File.read rejects negative length and offset" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.write(path, "abcdef")
        \\begin
        \\  File.read(path, -1)
        \\rescue => e
        \\  [e.class == ArgumentError, e.message]
        \\end
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());

    const source_offset = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.write(path, "abcdef")
        \\begin
        \\  File.read(path, 1, -1)
        \\rescue => e
        \\  [e.class == ArgumentError, e.message]
        \\end
    , .{path});
    defer std.testing.allocator.free(source_offset);

    const offset_result = try evalCode(source_offset);
    try std.testing.expect(offset_result.isArray());
    try std.testing.expectEqual(true, offset_result.toArrayObject().elements.items[0].toBool());
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

test "Errno exposes common unix constants" {
    const result = try evalCode(
        \\[
        \\  Errno::EBADF.name,
        \\  Errno::EBUSY.name,
        \\  Errno::EINTR.name,
        \\  Errno::EIO.name,
        \\  Errno::ELOOP.name,
        \\  Errno::EMLINK.name,
        \\  Errno::ENAMETOOLONG.name,
        \\  Errno::ENOMEM.name,
        \\  Errno::ENOTCONN.name,
        \\  Errno::ENOTSOCK.name,
        \\  Errno::ENOTTY.name,
        \\  Errno::EOVERFLOW.name,
        \\  Errno::ERANGE.name,
        \\  Errno::ESPIPE.name,
        \\  Errno::ESRCH.name
        \\]
    );

    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualSlices(u8, "Errno::EBADF", items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::EBUSY", items[1].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::EINTR", items[2].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::EIO", items[3].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ELOOP", items[4].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::EMLINK", items[5].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ENAMETOOLONG", items[6].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ENOMEM", items[7].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ENOTCONN", items[8].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ENOTSOCK", items[9].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ENOTTY", items[10].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::EOVERFLOW", items[11].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ERANGE", items[12].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ESPIPE", items[13].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "Errno::ESRCH", items[14].toStringObject().str);
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

test "File.open accepts integer mode flags" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\flags = File::RDWR | File::CREAT | File::BINARY
        \\File.open(path, flags) do |io|
        \\  io.write("x")
        \\end
        \\File.read(path)
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "x", result.toStringObject().str);
}

test "File.stat and IO#stat expose uid and gid" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.write(path, "x")
        \\f = File.open(path, "r")
        \\begin
        \\  st = File.stat(path)
        \\  io_st = f.stat
        \\  [st.uid, st.gid, io_st.uid, io_st.gid]
        \\ensure
        \\  f.close
        \\end
    , .{path});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 4), result.toArrayObject().elements.items.len);
    try std.testing.expectEqual(@as(i64, @intCast(std.c.getuid())), result.toArrayObject().elements.items[0].toInteger());
    try std.testing.expectEqual(@as(i64, @intCast(std.c.getgid())), result.toArrayObject().elements.items[1].toInteger());
    try std.testing.expectEqual(@as(i64, @intCast(std.c.getuid())), result.toArrayObject().elements.items[2].toInteger());
    try std.testing.expectEqual(@as(i64, @intCast(std.c.getgid())), result.toArrayObject().elements.items[3].toInteger());
}

test "File.split matches MRI path splitting" {
    var result = try evalCode("File.split('/a/b')");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "/a", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "b", result.toArrayObject().elements.items[1].toStringObject().str);

    result = try evalCode("File.split('foo/')");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, ".", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "foo", result.toArrayObject().elements.items[1].toStringObject().str);

    result = try evalCode("File.split('')");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, ".", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "", result.toArrayObject().elements.items[1].toStringObject().str);
}

test "File.join does not reset on later absolute segments" {
    var result = try evalCode("File.join('/base', 'host%80', '/quick/Marshal.4.8')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "/base/host%80/quick/Marshal.4.8", result.toStringObject().str);

    result = try evalCode("File.join('a', '/b')");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "a/b", result.toStringObject().str);

    result = try evalCode("File.join(['/base', '/b'])");
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "/base/b", result.toStringObject().str);
}

test "File.identical? returns true for same file and false for missing paths" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const alt_path = try std.fmt.allocPrint(std.testing.allocator, "{s}_link", .{path});
    defer std.testing.allocator.free(alt_path);
    const missing_path = try std.fmt.allocPrint(std.testing.allocator, "{s}_missing", .{path});
    defer std.testing.allocator.free(missing_path);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\alt = "{s}"
        \\missing = "{s}"
        \\File.write(path, "x")
        \\File.symlink(path, alt)
        \\[
        \\  File.identical?(path, path),
        \\  File.identical?(path, alt),
        \\  File.identical?(path, missing)
        \\]
    , .{ path, alt_path, missing_path });
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[0].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(false, result.toArrayObject().elements.items[2].toBool());
}

test "IO.copy_stream copies bytes between open files" {
    var src_buf: [128]u8 = undefined;
    var dst_buf: [128]u8 = undefined;
    const src = try uniquePath(&src_buf);
    const dst = try uniquePath(&dst_buf);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\src = "{s}"
        \\dst = "{s}"
        \\File.write(src, "hello")
        \\File.open(src, "rb") do |from|
        \\  File.open(dst, "wb") do |to|
        \\    IO.copy_stream(from, to)
        \\  end
        \\end
        \\File.read(dst)
    , .{ src, dst });
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isString());
    try std.testing.expectEqualSlices(u8, "hello", result.toStringObject().str);
}

test "Dir.children and File::Stat#directory? support vendored fileutils traversal" {
    var root_buf: [128]u8 = undefined;
    const root = try uniquePath(&root_buf);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\root = "{s}"
        \\Dir.mkdir(root)
        \\File.write(File.join(root, "a.txt"), "x")
        \\sub = File.join(root, "sub")
        \\Dir.mkdir(sub)
        \\[Dir.children(root).sort.inspect, File.lstat(root).directory?, File.lstat(File.join(root, "a.txt")).file?]
    , .{root});
    defer std.testing.allocator.free(source);

    const result = try evalCode(source);
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "[\"a.txt\", \"sub\"]", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[1].toBool());
    try std.testing.expectEqual(true, result.toArrayObject().elements.items[2].toBool());
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

test "File.open applies external encoding without transcoding write_nonblock bytes" {
    var path_buf: [128]u8 = undefined;
    const path = try uniquePath(&path_buf);
    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        \\path = "{s}"
        \\File.open(path, "w", external_encoding: Encoding::UTF_16BE) do |file|
        \\  puts file.external_encoding == Encoding::UTF_16BE
        \\  file.write_nonblock("hello")
        \\end
        \\p File.binread(path).bytes
        \\File.delete(path)
    , .{path});
    defer std.testing.allocator.free(source);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    const result = evalCodeWithOutput(source, &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("true\n[104, 101, 108, 108, 111]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
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

test "File.basename handles plain and suffix-stripped paths" {
    const result = try evalCode("[File.basename('/tmp/a/b.rb'), File.basename('/tmp/a/b.rb', '.*')]");
    try std.testing.expect(result.isArray());
    try std.testing.expectEqualSlices(u8, "b.rb", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "b", result.toArrayObject().elements.items[1].toStringObject().str);
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
