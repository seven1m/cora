const std = @import("std");

const evalCodeWithOutput = @import("test_helper.zig").evalCodeWithOutput;

test "zlib exposes MRI compression levels and strategies" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "zlib"
        \\p [Zlib::NO_COMPRESSION, Zlib::BEST_SPEED, Zlib::FILTERED, Zlib::HUFFMAN_ONLY]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[0, 1, 1, 2]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "zlib treats nil compression level as the default" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "zlib"
        \\require "stringio"
        \\deflated = Zlib::Deflate.deflate("hello", nil)
        \\io = StringIO.new
        \\writer = Zlib::GzipWriter.new(io, nil)
        \\writer.write("hello")
        \\writer.close
        \\p [Zlib::Inflate.inflate(deflated), Zlib::GzipReader.new(StringIO.new(io.string)).read]
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[\"hello\", \"hello\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "gzip reader reports compression level from the header" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "zlib"
        \\require "stringio"
        \\levels = [Zlib::BEST_SPEED, Zlib::BEST_COMPRESSION, nil]
        \\p levels.map { |level| io = StringIO.new; writer = Zlib::GzipWriter.new(io, level); writer.write("payload"); writer.close; reader = Zlib::GzipReader.new(StringIO.new(io.string)); [reader.level, io.string.getbyte(8)] }
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[[1, 4], [9, 2], [-1, 0]]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "gzip reader validates CRC and uncompressed size" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "zlib"
        \\require "stringio"
        \\io = StringIO.new
        \\writer = Zlib::GzipWriter.new(io)
        \\writer.write("payload")
        \\writer.close
        \\crc = io.string.dup
        \\crc.setbyte(-8, crc.getbyte(-8) ^ 1)
        \\size = io.string.dup
        \\size.setbyte(-4, size.getbyte(-4) ^ 1)
        \\errors = [crc, size].map { |data| begin; Zlib::GzipReader.new(StringIO.new(data)).read; rescue => error; [error.class, error.message]; end }
        \\p errors
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[[Zlib::GzipFile::CRCError, \"invalid compressed data -- crc error\"], [Zlib::GzipFile::LengthError, \"invalid compressed data -- length error\"]]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

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
        \\  def close
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
