const std = @import("std");
const test_helper = @import("../test_helper.zig");

test "Data.define creates member readers and a bracket constructor" {
    const result = try test_helper.evalCode(
        \\klass = Data.define(:author, :year)
        \\book = klass["Tim", 2024]
        \\[book.author == "Tim", book.year == 2024, book.frozen?, klass.respond_to?(:[]), !Data.respond_to?(:[])]
    );
    const items = result.toArrayObject().elements.items;
    for (items) |item| try std.testing.expect(item.isTruthy());
}
