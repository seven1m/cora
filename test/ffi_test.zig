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

test "FFI MemoryPointer preserves binary data across pointer calls" {
    const result = try evalCode(
        \\require "ffi"
        \\module LibC
        \\  extend FFI::Library
        \\  ffi_lib nil
        \\  attach_function :memcmp, [:pointer, :pointer, :size_t], :int
        \\end
        \\FFI::MemoryPointer.new(:char, 4) do |pointer|
        \\  pointer.write_string("a\0b")
        \\  pointer.put_char(3, 99)
        \\  pointer.read_string(4) == "a\0bc" && LibC.memcmp(pointer, "a\0bc", 4) == 0
        \\end
    );
    try std.testing.expect(result.isTruthy());
}

test "FFI Library converts named enum arguments and results" {
    const result = try evalCode(
        \\require "ffi"
        \\module LibC
        \\  extend FFI::Library
        \\  ffi_lib nil
        \\  enum :number, [:negative, -7, :positive, 7]
        \\  attach_function :abs, [:number], :number
        \\end
        \\LibC.abs(:negative)
    );
    try std.testing.expectEqualStrings("positive", result.toSymbolObject().name);
}
