const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Marshal round trips nested array and hash" {
    const result = try evalCode(
        \\obj = {"a" => [1, :two, nil, true, false], "b" => {"c" => 3}}
        \\Marshal.load(Marshal.dump(obj)) == obj
    );
    try std.testing.expect(result.is_truthy());
}

test "Marshal dump returns ASCII-8BIT string" {
    const result = try evalCode(
        \\Marshal.dump([1, "x"]).encoding == Encoding::ASCII_8BIT
    );
    try std.testing.expect(result.is_truthy());
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
    try std.testing.expect(result.is_truthy());
}
