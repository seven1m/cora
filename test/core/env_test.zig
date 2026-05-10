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
