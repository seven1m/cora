const std = @import("std");

const evalCodeWithOutput = @import("test_helper.zig").evalCodeWithOutput;

test "require loads simple json dump and parse helpers" {
    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "json"
        \\data = {"a" => 1, "b" => [true, false, nil, "x"], "c" => {"d" => 1.5}}
        \\json = JSON.dump(data)
        \\puts json
        \\puts JSON.parse(json).inspect
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings(
        "{\"a\":1,\"b\":[true,false,null,\"x\"],\"c\":{\"d\":1.5}}\n{\"a\" => 1, \"b\" => [true, false, nil, \"x\"], \"c\" => {\"d\" => 1.5}}\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);
}
