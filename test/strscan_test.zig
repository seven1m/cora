const std = @import("std");
const test_helper = @import("test_helper.zig");

const evalCode = test_helper.evalCode;
const evalCodeWithOutput = test_helper.evalCodeWithOutput;

test "require strscan supports basic scanning" {
    const result = try evalCode(
        \\require "strscan"
        \\s = StringScanner.new("This is an example")
        \\[
        \\  s.scan(/\w+/),
        \\  s.skip(/\s+/),
        \\  s.scan(/\w+/),
        \\  s.check(/\s+/),
        \\  s.match?(/\s+/),
        \\  s.pos,
        \\  s.eos?
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 7), items.len);
    try std.testing.expectEqualStrings("This", items[0].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 1), items[1].toInteger());
    try std.testing.expectEqualStrings("is", items[2].toStringObject().str);
    try std.testing.expectEqualStrings(" ", items[3].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 1), items[4].toInteger());
    try std.testing.expectEqual(@as(i64, 7), items[5].toInteger());
    try std.testing.expect(!items[6].toBool());
}

test "strscan tracks match state and unscan" {
    const result = try evalCode(
        \\require "strscan"
        \\s = StringScanner.new("abc123xyz")
        \\token = s.scan(/(abc)(\d+)/)
        \\before = [token, s[0], s[1], s.matched?, s.matched_size, s.pre_match, s.post_match, s.captures, s.size, s.pos]
        \\s.unscan
        \\after = [s.pos, s.matched?]
        \\[before, after]
    );
    try std.testing.expect(result.isArray());
    const outer = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), outer.len);

    const before = outer[0].toArrayObject().elements.items;
    try std.testing.expectEqualStrings("abc123", before[0].toStringObject().str);
    try std.testing.expectEqualStrings("abc123", before[1].toStringObject().str);
    try std.testing.expectEqualStrings("abc", before[2].toStringObject().str);
    try std.testing.expect(before[3].toBool());
    try std.testing.expectEqual(@as(i64, 6), before[4].toInteger());
    try std.testing.expectEqualStrings("", before[5].toStringObject().str);
    try std.testing.expectEqualStrings("xyz", before[6].toStringObject().str);
    const captures = before[7].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(usize, 2), captures.len);
    try std.testing.expectEqualStrings("abc", captures[0].toStringObject().str);
    try std.testing.expectEqualStrings("123", captures[1].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 3), before[8].toInteger());
    try std.testing.expectEqual(@as(i64, 6), before[9].toInteger());

    const after = outer[1].toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, 0), after[0].toInteger());
    try std.testing.expect(!after[1].toBool());
}

test "strscan supports until variants and byte reads" {
    const result = try evalCode(
        \\require "strscan"
        \\s = StringScanner.new("abc def ghi")
        \\[
        \\  s.scan_until(/ /),
        \\  s.rest,
        \\  s.exist?(/h/),
        \\  s.check_until(/h/),
        \\  s.skip_until(/h/),
        \\  s.pos,
        \\  s.get_byte,
        \\  s.peek(1),
        \\  s.scan_byte,
        \\  s.peek(1),
        \\  s.rest_size,
        \\  s.eos?
        \\]
    );
    try std.testing.expect(result.isArray());
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("abc ", items[0].toStringObject().str);
    try std.testing.expectEqualStrings("def ghi", items[1].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 6), items[2].toInteger());
    try std.testing.expectEqualStrings("def gh", items[3].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 6), items[4].toInteger());
    try std.testing.expectEqual(@as(i64, 10), items[5].toInteger());
    try std.testing.expectEqualStrings("i", items[6].toStringObject().str);
    try std.testing.expectEqualStrings("", items[7].toStringObject().str);
    try std.testing.expect(items[8].isNil());
    try std.testing.expectEqualStrings("", items[9].toStringObject().str);
    try std.testing.expectEqual(@as(i64, 0), items[10].toInteger());
    try std.testing.expect(items[11].toBool());
}

test "strscan require exposes class" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "strscan"
        \\puts StringScanner.must_C_version == StringScanner
    , &stdout_buf, &stderr_buf);
    if (result.err != null) {
        std.debug.print("stderr: {s}\nstdout: {s}\n", .{ result.stderr, result.stdout });
    }
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("true\n", result.stdout);
}
