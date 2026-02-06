const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const encoding_builtin = @import("encoding.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const string_plus_sym = try vm.intern("+");
    try vm.string_class.module.methods.put(string_plus_sym, .{ .builtin = &builtinStringPlus });

    const string_equal_sym = try vm.intern("==");
    try vm.string_class.module.methods.put(string_equal_sym, .{ .builtin = &builtinStringEqual });

    const string_not_equal_sym = try vm.intern("!=");
    try vm.string_class.module.methods.put(string_not_equal_sym, .{ .builtin = &builtinStringNotEqual });

    const string_encoding_sym = try vm.intern("encoding");
    try vm.string_class.module.methods.put(string_encoding_sym, .{ .builtin = &builtinStringEncoding });

    const string_force_encoding_sym = try vm.intern("force_encoding");
    try vm.string_class.module.methods.put(string_force_encoding_sym, .{ .builtin = &builtinStringForceEncoding });

    const string_valid_encoding_sym = try vm.intern("valid_encoding?");
    try vm.string_class.module.methods.put(string_valid_encoding_sym, .{ .builtin = &builtinStringValidEncoding });

    const string_ascii_only_sym = try vm.intern("ascii_only?");
    try vm.string_class.module.methods.put(string_ascii_only_sym, .{ .builtin = &builtinStringAsciiOnly });

    const string_b_sym = try vm.intern("b");
    try vm.string_class.module.methods.put(string_b_sym, .{ .builtin = &builtinStringB });

    const to_s_sym = try vm.intern("to_s");
    try vm.string_class.module.methods.put(to_s_sym, .{ .builtin = &builtinStringToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.string_class.module.methods.put(inspect_sym, .{ .builtin = &builtinStringInspect });
}

pub fn builtinStringToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver; // String#to_s returns vm
}

pub fn builtinStringPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .string, "String");
    const other_str = args[0].data.string;
    const combined_str = std.fmt.allocPrint(
        vm.gc_allocator,
        "{s}{s}",
        .{ receiver.data.string.str, other_str.str },
    ) catch return error.Unwind;

    return vm.newString(combined_str, false);
}

pub fn builtinStringEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    // String == only returns true if other is also a String with same content
    if (other.data != .string) {
        return Value.boolean(false);
    }
    const result = std.mem.eql(u8, receiver.data.string.str, other.data.string.str);
    return Value.boolean(result);
}

pub fn builtinStringNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    // String != returns true if other is not a String or has different content
    if (other.data != .string) {
        return Value.boolean(true);
    }
    const result = !std.mem.eql(u8, receiver.data.string.str, other.data.string.str);
    return Value.boolean(result);
}

pub fn builtinStringEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    // Return the appropriate encoding singleton
    return switch (string_obj.encoding) {
        .utf8 => Value{ .data = .{ .encoding = vm.encoding_utf8 } },
        .ascii_8bit => Value{ .data = .{ .encoding = vm.encoding_ascii_8bit } },
        .us_ascii => Value{ .data = .{ .encoding = vm.encoding_us_ascii } },
    };
}

pub fn builtinStringForceEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    // Get the new encoding from argument
    const new_encoding: enc.Encoding = switch (args[0].data) {
        .encoding => |e| e.encoding,
        .string, .symbol => blk: {
            // Use Encoding.find logic - works for both strings and symbols
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
            break :blk result.data.encoding.encoding;
        },
        else => return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Encoding, String, or Symbol)", .{@tagName(args[0].data)}),
    };

    // Create a new string with the same bytes but different encoding
    const string_obj = receiver.data.string;
    return vm.newStringWithEncoding(string_obj.str, false, new_encoding);
}

pub fn builtinStringValidEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return Value.boolean(string_obj.encoding.isValid(string_obj.str));
}

pub fn builtinStringAsciiOnly(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return Value.boolean(enc.isAsciiOnly(string_obj.str));
}

pub fn builtinStringB(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    // Return a new string with ASCII-8BIT encoding
    return vm.newStringWithEncoding(string_obj.str, false, .{ .ascii_8bit = .{} });
}

pub fn builtinStringInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const input = receiver.data.string.str;
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("\"") catch return error.Unwind;
    for (input) |c| {
        switch (c) {
            '"' => writer.writeAll("\\\"") catch return error.Unwind,
            '\\' => writer.writeAll("\\\\") catch return error.Unwind,
            '\n' => writer.writeAll("\\n") catch return error.Unwind,
            '\t' => writer.writeAll("\\t") catch return error.Unwind,
            '\r' => writer.writeAll("\\r") catch return error.Unwind,
            '\x08' => writer.writeAll("\\b") catch return error.Unwind, // backspace
            '\x0c' => writer.writeAll("\\f") catch return error.Unwind, // form feed
            '\x0b' => writer.writeAll("\\v") catch return error.Unwind, // vertical tab
            '\x00' => writer.writeAll("\\0") catch return error.Unwind, // null
            else => {
                if (c < 32 or c > 126) {
                    std.fmt.format(writer, "\\x{x:0>2}", .{c}) catch return error.Unwind;
                } else {
                    writer.writeByte(c) catch return error.Unwind;
                }
            },
        }
    }
    writer.writeAll("\"") catch return error.Unwind;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Unwind;
    defer vm.allocator.free(str);
    return vm.newString(str, false);
}
