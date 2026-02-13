const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

fn uniquePath(buf: *[128]u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "/tmp/cora_io_{d}.txt", .{std.time.nanoTimestamp()});
}

test "STDIN/STDOUT/STDERR constants mirror $stdin/$stdout/$stderr" {
    const result = try evalCode(
        \\[
        \\  STDIN.object_id == $stdin.object_id,
        \\  STDOUT.object_id == $stdout.object_id,
        \\  STDERR.object_id == $stderr.object_id
        \\]
    );
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 3), result.data.array.elements.items.len);
    try std.testing.expectEqual(true, result.data.array.elements.items[0].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[1].data.boolean);
    try std.testing.expectEqual(true, result.data.array.elements.items[2].data.boolean);
}

test "standard stream fileno values are 0,1,2" {
    const result = try evalCode("[STDIN.fileno, STDOUT.fileno, STDERR.fileno]");
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 0), result.data.array.elements.items[0].data.integer);
    try std.testing.expectEqual(@as(i64, 1), result.data.array.elements.items[1].data.integer);
    try std.testing.expectEqual(@as(i64, 2), result.data.array.elements.items[2].data.integer);
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
    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(i64, 5), result.data.array.elements.items[0].data.integer);
    try std.testing.expect(result.data.array.elements.items[1].data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.array.elements.items[1].data.string.str);
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
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(true, result.data.boolean);
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
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "alpha\n42\n", result.data.string.str);
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
