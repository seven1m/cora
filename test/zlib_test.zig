const std = @import("std");

const evalCodeWithOutput = @import("test_helper.zig").evalCodeWithOutput;

test "require loads zlib deflate inflate helpers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "zlib"
        \\compressed = Zlib::Deflate.deflate("hello world")
        \\puts Zlib::Inflate.inflate(compressed)
        \\puts Zlib.zlib_version
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("hello world\n1.3.1\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "zlib gzip reader writer roundtrip through ruby io-like objects" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "zlib"
        \\class Sink
        \\  attr_reader :data
        \\  def initialize
        \\    @data = +""
        \\  end
        \\  def write(bytes)
        \\    @data << bytes
        \\    bytes.bytesize
        \\  end
        \\end
        \\class Source
        \\  def initialize(data)
        \\    @data = data
        \\    @used = false
        \\  end
        \\  def read(*)
        \\    return nil if @used
        \\    @used = true
        \\    @data
        \\  end
        \\end
        \\sink = Sink.new
        \\gz = Zlib::GzipWriter.new(sink, Zlib::BEST_COMPRESSION)
        \\gz.write("payload")
        \\gz.close
        \\reader = Zlib::GzipReader.new(Source.new(sink.data))
        \\puts reader.read
        \\puts Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(sink.data)
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("payload\npayload\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
