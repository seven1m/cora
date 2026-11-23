const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "Float literal evaluates to Float value" {
    const result = try evalCode("1.25");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), result.toFloatObject().val, 0.0000000001);
}

test "Float and large Integer values are frozen" {
    const result = try evalCode("[1.25.frozen?, (2 ** 100).frozen?]");
    for (result.toArrayObject().elements.items) |item| try std.testing.expect(item.isTrue());
}

test "Float class identity and Numeric ancestry" {
    var result = try evalCode("1.0.instance_of?(Float)");
    try std.testing.expectEqual(true, result.toBool());

    result = try evalCode("Numeric === 1.0");
    try std.testing.expectEqual(true, result.toBool());
}

test "Float arithmetic" {
    var result = try evalCode("1.5 + 2.25");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 3.75), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("5.0 - 1.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("2.0 * 1.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("7.5 / 2.5");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.toFloatObject().val, 0.0000000001);
}

test "Mixed Integer and Float arithmetic" {
    var result = try evalCode("1 + 0.5");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("3 - 0.25");
    try std.testing.expectApproxEqAbs(@as(f64, 2.75), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("2 * 0.5");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("1 / 2.0");
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.toFloatObject().val, 0.0000000001);
}

test "Float abs" {
    var result = try evalCode("(-1.5).abs");
    try std.testing.expect(result.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), result.toFloatObject().val, 0.0000000001);

    result = try evalCode("2.0.abs");
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.toFloatObject().val, 0.0000000001);
}

test "Float rounding coerces precision and rejects invalid inputs without aborting" {
    const result = try evalCode(
        \\precision = Object.new
        \\def precision.to_int; 1; end
        \\coerced = 1.26.round(precision) == 1.3 && 1.26.floor(precision) == 1.2 &&
        \\  1.26.ceil(precision) == 1.3 && 1.26.truncate(precision) == 1.2
        \\invalid = [:round, :ceil, :floor, :truncate].all? do |method|
        \\  [nil, "1", Object.new].all? do |argument|
        \\    begin
        \\      1.26.send(method, argument)
        \\      false
        \\    rescue TypeError
        \\      true
        \\    end
        \\  end
        \\end
        \\coerced && invalid && 1.26.round(-(2**31)) == 0 &&
        \\  1.26.round(2**31 - 1) == 1.26
    );
    try std.testing.expectEqual(true, result.toBool());
}

test "Float rounding handles subnormal decimal scaling and signed zero" {
    const result = try evalCode(
        \\Float::MIN.round(310) == 2.23e-308 &&
        \\  1e-320.round(322) == 1e-320 &&
        \\  5e-324.round(323) == 0.0 &&
        \\  5e-324.round(324) == 5e-324 &&
        \\  1.0 / (-0.0).round(2) == -Float::INFINITY &&
        \\  1.0 / (-1e-300).round(1) == Float::INFINITY
    );
    try std.testing.expectEqual(true, result.toBool());
}
