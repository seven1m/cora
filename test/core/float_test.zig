const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Float literal evaluates to Float value" {
    const result = try evalCode("1.25");
    try std.testing.expect(result.data == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), result.data.float, 0.0000000001);
}

test "Float class identity and Numeric ancestry" {
    var result = try evalCode("1.0.instance_of?(Float)");
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("Numeric === 1.0");
    try std.testing.expectEqual(true, result.data.boolean);
}

test "Float arithmetic" {
    var result = try evalCode("1.5 + 2.25");
    try std.testing.expect(result.data == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 3.75), result.data.float, 0.0000000001);

    result = try evalCode("5.0 - 1.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), result.data.float, 0.0000000001);

    result = try evalCode("2.0 * 1.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.data.float, 0.0000000001);

    result = try evalCode("7.5 / 2.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.data.float, 0.0000000001);
}

test "Mixed Integer and Float arithmetic" {
    var result = try evalCode("1 + 0.5");
    try std.testing.expect(result.data == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.data.float, 0.0000000001);

    result = try evalCode("3 - 0.25");
    try std.testing.expectApproxEqAbs(@as(f64, 2.75), result.data.float, 0.0000000001);

    result = try evalCode("2 * 0.5");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.data.float, 0.0000000001);

    result = try evalCode("1 / 2.0");
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.data.float, 0.0000000001);
}

test "Float nan? and infinite?" {
    var result = try evalCode("(0 / 0.0).nan?");
    try std.testing.expectEqual(true, result.data.boolean);

    result = try evalCode("(1 / 0.0).infinite?");
    try std.testing.expectEqual(@as(i64, 1), result.data.integer);

    result = try evalCode("(-1 / 0.0).infinite?");
    try std.testing.expectEqual(@as(i64, -1), result.data.integer);

    result = try evalCode("(1.0).infinite?");
    try std.testing.expect(result.data == .nil);
}

test "Float abs" {
    var result = try evalCode("(-1.5).abs");
    try std.testing.expect(result.data == .float);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.data.float, 0.0000000001);

    result = try evalCode("2.0.abs");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.data.float, 0.0000000001);
}
