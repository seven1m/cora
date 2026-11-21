const std = @import("std");
const c = @import("onigmo_c");

test "Onigmo sharp-s expansion respects the output buffer boundary" {
    // GHSA-34m4-m9fh-gqp5: the old callbacks checked for one free byte
    // before writing two. Exercise the exact boundary, including a canary.
    const encodings = [_]c.OnigEncoding{
        c.ONIG_ENCODING_ISO_8859_1,   c.ONIG_ENCODING_ISO_8859_2,
        c.ONIG_ENCODING_ISO_8859_3,   c.ONIG_ENCODING_ISO_8859_4,
        c.ONIG_ENCODING_ISO_8859_9,   c.ONIG_ENCODING_ISO_8859_10,
        c.ONIG_ENCODING_ISO_8859_13,  c.ONIG_ENCODING_ISO_8859_14,
        c.ONIG_ENCODING_ISO_8859_15,  c.ONIG_ENCODING_ISO_8859_16,
        c.ONIG_ENCODING_WINDOWS_1250, c.ONIG_ENCODING_WINDOWS_1252,
        c.ONIG_ENCODING_WINDOWS_1254, c.ONIG_ENCODING_WINDOWS_1257,
    };
    const source = [_]u8{0xdf};
    const source_start: [*c]const u8 = &source;
    for (encodings) |encoding| {
        for ([_]c.OnigCaseFoldType{ c.ONIGENC_CASE_UPCASE, c.ONIGENC_CASE_FOLD }) |mode| {
            var flags = mode;
            var current = source_start;
            var output = [_]u8{ 0xa5, 0xa5, 0xa5 };
            const output_start: [*c]u8 = &output;
            const map = encoding.*.case_map.?;
            const written = map(&flags, &current, source_start + source.len, output_start, output_start + 1, encoding);
            try std.testing.expectEqual(@as(c_int, 0), written);
            try std.testing.expectEqual(@intFromPtr(&source), @intFromPtr(current));
            try std.testing.expectEqualSlices(u8, &.{ 0xa5, 0xa5, 0xa5 }, &output);

            const expanded = map(&flags, &current, source_start + source.len, output_start, output_start + 2, encoding);
            try std.testing.expectEqual(@as(c_int, 2), expanded);
            try std.testing.expectEqualSlices(u8, if (mode == c.ONIGENC_CASE_UPCASE) "SS" else "ss", output[0..2]);
            try std.testing.expectEqual(@as(u8, 0xa5), output[2]);
            try std.testing.expectEqual(@intFromPtr(&source) + 1, @intFromPtr(current));
        }
    }
}
