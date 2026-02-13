const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "ENV constant exists and is an object instance" {
    const result = try evalCode("ENV");
    try std.testing.expect(result.data == .instance);
}

test "ENV [] and []= read/write values" {
    const result = try evalCode(
        \\ENV['CORA_ENV_RW_TEST'] = 'hello'
        \\ENV['CORA_ENV_RW_TEST']
    );
    try std.testing.expect(result.data == .string);
    try std.testing.expectEqualSlices(u8, "hello", result.data.string.str);
}

test "ENV [] returns nil for missing key" {
    const result = try evalCode("ENV['CORA_ENV_MISSING_KEY_TEST']");
    try std.testing.expect(result.data == .nil);
}

test "ENV []= nil unsets value in ENV map" {
    const result = try evalCode(
        \\ENV['CORA_ENV_UNSET_TEST'] = 'x'
        \\ENV['CORA_ENV_UNSET_TEST'] = nil
        \\ENV['CORA_ENV_UNSET_TEST']
    );
    try std.testing.expect(result.data == .nil);
}

test "ENV []= syncs to host environment for child processes" {
    const result = try evalCode(
        \\k = 'CORA_ENV_SYNC_TEST_UNLIKELY_12345'
        \\ENV[k] = nil
        \\ENV[k] = 'ok'
        \\out1 = `/bin/sh -c 'printf %s "$CORA_ENV_SYNC_TEST_UNLIKELY_12345"'`
        \\ENV[k] = nil
        \\out2 = `/bin/sh -c 'printf %s "$CORA_ENV_SYNC_TEST_UNLIKELY_12345"'`
        \\[out1, out2]
    );

    try std.testing.expect(result.data == .array);
    try std.testing.expectEqual(@as(usize, 2), result.data.array.elements.items.len);
    const out1 = result.data.array.elements.items[0];
    const out2 = result.data.array.elements.items[1];
    try std.testing.expect(out1.data == .string);
    try std.testing.expect(out2.data == .string);
    try std.testing.expectEqualSlices(u8, "ok", out1.data.string.str);
    try std.testing.expectEqualSlices(u8, "", out2.data.string.str);
}

test "ENV.to_h returns a fresh hash object each call" {
    const result = try evalCode("ENV.to_h.object_id == ENV.to_h.object_id");
    try std.testing.expect(result.data == .boolean);
    try std.testing.expectEqual(false, result.data.boolean);
}
