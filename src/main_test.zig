const value_test = @import("value_test.zig");
const vm_test = @import("vm_test.zig");
const prism_test = @import("prism_test.zig");
const binary_test = @import("binary_test.zig");

comptime {
    _ = value_test;
    _ = vm_test;
    _ = prism_test;
    _ = binary_test;
}
