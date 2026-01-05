const value_test = @import("value_test.zig");
const interpreter_test = @import("interpreter_test.zig");
const prism_test = @import("prism_test.zig");

comptime {
    _ = value_test;
    _ = interpreter_test;
    _ = prism_test;
}
