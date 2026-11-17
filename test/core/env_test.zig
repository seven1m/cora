const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "ENV membership predicates" {
    const result = try evalCode(
        \\ENV["CORA_ENV_TEST_KEY"] = "1"
        \\ENV.include?("CORA_ENV_TEST_KEY") &&
        \\  ENV.key?("CORA_ENV_TEST_KEY") &&
        \\  ENV.has_key?("CORA_ENV_TEST_KEY") &&
        \\  ENV.member?("CORA_ENV_TEST_KEY") &&
        \\  !ENV.include?("CORA_ENV_TEST_MISSING_KEY")
    );
    try std.testing.expect(result.toBool());
}

test "ENV.values_at returns values and nil for missing keys" {
    const result = try evalCode(
        \\ENV["CORA_ENV_VALUES_AT_A"] = "alpha"
        \\ENV.delete("CORA_ENV_VALUES_AT_B")
        \\ENV.values_at("CORA_ENV_VALUES_AT_A", "CORA_ENV_VALUES_AT_B")
    );
    try std.testing.expect(result.isArray());
    try std.testing.expectEqual(@as(usize, 2), result.toArrayObject().elements.items.len);
    try std.testing.expectEqualSlices(u8, "alpha", result.toArrayObject().elements.items[0].toStringObject().str);
    try std.testing.expect(result.toArrayObject().elements.items[1].isNil());
}
