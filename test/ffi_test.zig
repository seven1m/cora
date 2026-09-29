const std = @import("std");
const evalCode = @import("test_helper.zig").evalCode;

test "CoraFFI calls a C function with a string and returns size_t" {
    const result = try evalCode(
        \\require "cora_ffi"
        \\libc = CoraFFI.open(nil)
        \\strlen = CoraFFI.symbol(libc, "strlen")
        \\CoraFFI.call(strlen, "size_t", ["string"], ["hello"])
    );
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}

test "CoraFFI supports signed integer and floating point calls" {
    const result = try evalCode(
        \\require "cora_ffi"
        \\libc = CoraFFI.open(nil)
        \\atoi = CoraFFI.symbol(libc, "atoi")
        \\atof = CoraFFI.symbol(libc, "atof")
        \\[
        \\  CoraFFI.call(atoi, "int", ["string"], ["-42"]),
        \\  CoraFFI.call(atof, "double", ["string"], ["8.0"])
        \\]
    );
    const items = result.toArrayObject().elements.items;
    try std.testing.expectEqual(@as(i64, -42), items[0].toInteger());
    try std.testing.expectEqual(@as(f64, 8.0), items[1].toFloatObject().val);
}

test "FFI Library attaches a C function" {
    const result = try evalCode(
        \\require "ffi"
        \\module LibC
        \\  extend FFI::Library
        \\  ffi_lib nil
        \\  attach_function :strlen, [:string], :size_t
        \\end
        \\LibC.strlen("hello")
    );
    try std.testing.expectEqual(@as(i64, 5), result.toInteger());
}
