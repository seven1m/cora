const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "required array pattern returns the matched value" {
    const result = try evalCode(
        \\value = [1, 2, 3]
        \\matched = (value => [Integer, Integer, Integer])
        \\[matched.equal?(value), matched]
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expect(values[0].isTrue());
    try std.testing.expectEqual(@as(usize, 3), values[1].toArrayObject().elements.items.len);
}

test "required array pattern raises on a length mismatch" {
    const result = try evalCode(
        \\begin
        \\  [1, 2, 3] => [Integer, Integer]
        \\rescue NoMatchingPatternError => error
        \\  [error.class, error.message]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("NoMatchingPatternError", values[0].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("length mismatch", values[1].toStringObject().str);
}

test "required array pattern checks each element with case equality" {
    const result = try evalCode(
        \\begin
        \\  [1, "two"] => [Integer, Integer]
        \\rescue NoMatchingPatternError => error
        \\  [error.class, error.message]
        \\end
    );
    const values = result.toArrayObject().elements.items;
    try std.testing.expectEqualStrings("NoMatchingPatternError", values[0].toClassObject().module.name.name);
    try std.testing.expectEqualStrings("pattern does not match", values[1].toStringObject().str);
}
