const std = @import("std");
const evalCode = @import("../test_helper.zig").evalCode;

test "Set freezing and cloning keep backing storage independent" {
    const result = try evalCode(
        \\original = Set[1, 2].freeze
        \\blocked = begin
        \\  original.add(3)
        \\  false
        \\rescue FrozenError
        \\  true
        \\end
        \\mutable = original.clone(freeze: false)
        \\mutable.add(3)
        \\frozen_clone = original.clone
        \\clone_blocked = begin
        \\  frozen_clone.add(4)
        \\  false
        \\rescue FrozenError
        \\  true
        \\end
        \\blocked && clone_blocked && original == Set[1, 2] &&
        \\  mutable == Set[1, 2, 3] && !mutable.frozen? && frozen_clone.frozen?
    );
    try std.testing.expect(result.isTrue());
}
