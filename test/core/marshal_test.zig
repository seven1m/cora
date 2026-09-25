const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Marshal round trips nested array and hash" {
    const result = try evalCode(
        \\obj = {"a" => [1, :two, nil, true, false], "b" => {"c" => 3}}
        \\Marshal.load(Marshal.dump(obj)) == obj
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal.load rejects sources without read" {
    const result = try evalCode(
        \\begin
        \\  Marshal.load(nil)
        \\rescue => e
        \\  [e.class.name, e.message]
        \\end
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualSlices(u8, "TypeError", items[0].toStringObject().str);
    try std.testing.expectEqualSlices(u8, "instance of IO needed", items[1].toStringObject().str);
}

test "Marshal dump returns ASCII-8BIT string" {
    const result = try evalCode(
        \\Marshal.dump([1, "x"]).encoding == Encoding::ASCII_8BIT
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal dump matches MRI bytes for basic values" {
    var dumped = try evalCode("Marshal.dump(nil)");
    try std.testing.expectEqualSlices(u8, &.{ 0x04, 0x08, 0x30 }, dumped.toStringObject().str);

    dumped = try evalCode("Marshal.dump(123)");
    try std.testing.expectEqualSlices(u8, &.{ 0x04, 0x08, 0x69, 0x01, 0x7b }, dumped.toStringObject().str);

    dumped = try evalCode("Marshal.dump(\"hi\")");
    try std.testing.expectEqualSlices(u8, &.{ 0x04, 0x08, 0x49, 0x22, 0x07, 0x68, 0x69, 0x06, 0x3a, 0x06, 0x45, 0x54 }, dumped.toStringObject().str);

    dumped = try evalCode("Marshal.dump(:hi)");
    try std.testing.expectEqualSlices(u8, &.{ 0x04, 0x08, 0x3a, 0x07, 0x68, 0x69 }, dumped.toStringObject().str);
}

test "Marshal dumps Time with MRI format and restores its offset and nanoseconds" {
    const dumped = try evalCode("Marshal.dump(Time.utc(2010))");
    try std.testing.expectEqualSlices(u8, &.{
        4, 8, 73, 117, 58, 9, 84, 105, 109, 101, 13, 32, 128, 27, 192, 0, 0, 0, 0,
        6, 58, 9, 122, 111, 110, 101, 73, 34, 8, 85, 84, 67, 6, 58, 6, 69, 70,
    }, dumped.toStringObject().str);

    const result = try evalCode(
        \\time = Time.new(2010, 1, 1, 0, 0, 0, "+05:00") + 0.123456789
        \\copy = Marshal.load(Marshal.dump(time))
        \\[copy.to_i == time.to_i, copy.nsec == time.nsec, copy.utc_offset == time.utc_offset]
    );
    for (result.toArrayObject().elements.items) |item| try std.testing.expect(item.isTruthy());
}

test "Marshal dump matches MRI links for repeated objects" {
    const dumped = try evalCode(
        \\s = "x"
        \\Marshal.dump([s, s, :k, :k])
    );
    try std.testing.expectEqualSlices(u8, &.{
        0x04, 0x08, 0x5b, 0x09, 0x49, 0x22, 0x06, 0x78, 0x06, 0x3a, 0x06, 0x45,
        0x54, 0x40, 0x06, 0x3a, 0x06, 0x6b, 0x3b, 0x06,
    }, dumped.toStringObject().str);
}

test "Marshal dump can write to io-like object" {
    const result = try evalCode(
        \\sink = Object.new
        \\def sink.write(str)
        \\  @data = str
        \\  str.length
        \\end
        \\def sink.read
        \\  @data
        \\end
        \\Marshal.dump([1, 2], sink)
        \\Marshal.load(sink) == [1, 2]
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal round trips nested objects using marshal_dump and marshal_load" {
    const result = try evalCode(
        \\module MarshalSpec
        \\  class UserMarshal
        \\    def initialize(value)
        \\      @value = value
        \\    end
        \\
        \\    def marshal_dump
        \\      [@value]
        \\    end
        \\
        \\    def marshal_load(array)
        \\      @value = array[0]
        \\    end
        \\
        \\    def value
        \\      @value
        \\    end
        \\  end
        \\end
        \\obj = MarshalSpec::UserMarshal.new(7)
        \\Marshal.load(Marshal.dump(obj)).value == 7
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal round trips ordinary objects and preserves links" {
    const result = try evalCode(
        \\class MarshalPlainObject
        \\  attr_reader :value
        \\  def initialize(value)
        \\    @value = value
        \\  end
        \\end
        \\obj = MarshalPlainObject.new("value")
        \\copy, linked = Marshal.load(Marshal.dump([obj, obj]))
        \\copy.class == MarshalPlainObject && copy.value == "value" && copy.equal?(linked)
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal round trips exceptions" {
    const result = try evalCode(
        \\error = RuntimeError.new("boom")
        \\error.set_backtrace(["first:1", "second:2"])
        \\error.instance_variable_set(:@extra, 7)
        \\copy = Marshal.load(Marshal.dump(error))
        \\copy.class == RuntimeError &&
        \\  copy.message == "boom" &&
        \\  copy.backtrace == ["first:1", "second:2"] &&
        \\  copy.instance_variable_get(:@extra) == 7
    );
    try std.testing.expect(result.isTruthy());
}

test "Marshal round trips RubyGems Requirement defaults" {
    const result = try evalCode(
        \\$LOAD_PATH.unshift(File.expand_path("build/ext/rubygems/lib", Dir.pwd))
        \\require "rubygems/requirement"
        \\req = Gem::Requirement.new(">= 0")
        \\copy = Marshal.load(Marshal.dump(req))
        \\copy == req
    );
    try std.testing.expect(result.isTruthy());
}
