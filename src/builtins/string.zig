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
    const string_uplus_sym = try vm.intern("+@");
    try vm.string_class.module.methods.put(string_uplus_sym, .{ .method = .{ .builtin = &builtinStringUnaryPlus } });

    const string_plus_sym = try vm.intern("+");
    try vm.string_class.module.methods.put(string_plus_sym, .{ .method = .{ .builtin = &builtinStringPlus } });

    const string_equal_sym = try vm.intern("==");
    try vm.string_class.module.methods.put(string_equal_sym, .{ .method = .{ .builtin = &builtinStringEqual } });

    const string_not_equal_sym = try vm.intern("!=");
    try vm.string_class.module.methods.put(string_not_equal_sym, .{ .method = .{ .builtin = &builtinStringNotEqual } });

    const string_encoding_sym = try vm.intern("encoding");
    try vm.string_class.module.methods.put(string_encoding_sym, .{ .method = .{ .builtin = &builtinStringEncoding } });

    const string_encode_sym = try vm.intern("encode");
    try vm.string_class.module.methods.put(string_encode_sym, .{ .method = .{ .builtin = &builtinStringEncode } });

    const string_force_encoding_sym = try vm.intern("force_encoding");
    try vm.string_class.module.methods.put(string_force_encoding_sym, .{ .method = .{ .builtin = &builtinStringForceEncoding } });

    const string_valid_encoding_sym = try vm.intern("valid_encoding?");
    try vm.string_class.module.methods.put(string_valid_encoding_sym, .{ .method = .{ .builtin = &builtinStringValidEncoding } });

    const string_ascii_only_sym = try vm.intern("ascii_only?");
    try vm.string_class.module.methods.put(string_ascii_only_sym, .{ .method = .{ .builtin = &builtinStringAsciiOnly } });

    const string_b_sym = try vm.intern("b");
    try vm.string_class.module.methods.put(string_b_sym, .{ .method = .{ .builtin = &builtinStringB } });

    const string_dup_sym = try vm.intern("dup");
    try vm.string_class.module.methods.put(string_dup_sym, .{ .method = .{ .builtin = &builtinStringDup } });

    const string_bytesize_sym = try vm.intern("bytesize");
    try vm.string_class.module.methods.put(string_bytesize_sym, .{ .method = .{ .builtin = &builtinStringBytesize } });

    const string_chars_sym = try vm.intern("chars");
    try vm.string_class.module.methods.put(string_chars_sym, .{ .method = .{ .builtin = &builtinStringChars } });

    const to_s_sym = try vm.intern("to_s");
    try vm.string_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinStringToS } });

    const to_str_sym = try vm.intern("to_str");
    try vm.string_class.module.methods.put(to_str_sym, .{ .method = .{ .builtin = &builtinStringToStr } });

    const inspect_sym = try vm.intern("inspect");
    try vm.string_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinStringInspect } });
}

pub fn builtinStringToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver; // String#to_s returns vm
}

pub fn builtinStringToStr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinStringToS(vm, receiver, args, null);
}

pub fn builtinStringUnaryPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other_str = try vm.coerceToStr(args[0], "no implicit conversion into String");
    const combined_str = std.fmt.allocPrint(
        vm.gc_allocator,
        "{s}{s}",
        .{ receiver.data.string.str, other_str },
    ) catch return error.Fatal;

    return try vm.newString(combined_str, false);
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

pub fn builtinStringEncode(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const target_encoding: enc.Encoding = switch (args[0].data) {
        .encoding => |e| e.encoding,
        else => blk: {
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
            break :blk result.data.encoding.encoding;
        },
    };

    const string_obj = receiver.data.string;

    // Validate bytes for target encoding when needed.
    const requires_validation = switch (target_encoding) {
        .ascii_8bit => false,
        else => true,
    };
    if (requires_validation and !target_encoding.isValid(string_obj.str)) {
        const name = target_encoding.name();
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{name});
    }

    return try vm.newStringWithEncoding(string_obj.str, false, target_encoding);
}

pub fn builtinStringForceEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    // Get the new encoding from argument
    const new_encoding: enc.Encoding = switch (args[0].data) {
        .encoding => |e| e.encoding,
        else => blk: {
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
            break :blk result.data.encoding.encoding;
        },
    };

    // Create a new string with the same bytes but different encoding
    const string_obj = receiver.data.string;
    return try vm.newStringWithEncoding(string_obj.str, false, new_encoding);
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
    return try vm.newStringWithEncoding(string_obj.str, false, .{ .ascii_8bit = .{} });
}

pub fn builtinStringDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringBytesize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value{ .data = .{ .integer = @intCast(receiver.data.string.str.len) } };
}

pub fn builtinStringChars(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    const bytes = string_obj.str;
    const encoding = string_obj.encoding;

    if (block) |blk| {
        var i: usize = 0;
        while (i < bytes.len) {
            const start = i;
            const result = encoding.nextChar(bytes, &i);
            if (result.len == 0) break;
            const slice = bytes[start .. start + result.len];
            const char_val = try vm.newStringWithEncoding(slice, false, encoding);
            const yield_args = [_]Value{char_val};
            const yield_result = try vm.yieldToBlock(blk, &yield_args);
            if (yield_result.break_occurred) {
                return receiver;
            }
        }
        return receiver;
    }

    const array_obj = try vm.createArray();
    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const result = encoding.nextChar(bytes, &i);
        if (result.len == 0) break;
        const slice = bytes[start .. start + result.len];
        const char_val = try vm.newStringWithEncoding(slice, false, encoding);
        array_obj.elements.append(vm.gc_allocator, char_val) catch return error.Fatal;
    }

    return Value{ .data = .{ .array = array_obj } };
}

pub fn builtinStringInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const input = receiver.data.string.str;
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);

    writer.writeAll("\"") catch return error.Fatal;
    for (input) |c| {
        switch (c) {
            '"' => writer.writeAll("\\\"") catch return error.Fatal,
            '\\' => writer.writeAll("\\\\") catch return error.Fatal,
            '\n' => writer.writeAll("\\n") catch return error.Fatal,
            '\t' => writer.writeAll("\\t") catch return error.Fatal,
            '\r' => writer.writeAll("\\r") catch return error.Fatal,
            '\x08' => writer.writeAll("\\b") catch return error.Fatal, // backspace
            '\x0c' => writer.writeAll("\\f") catch return error.Fatal, // form feed
            '\x0b' => writer.writeAll("\\v") catch return error.Fatal, // vertical tab
            '\x00' => writer.writeAll("\\0") catch return error.Fatal, // null
            else => {
                if (c < 32 or c > 126) {
                    std.fmt.format(writer, "\\x{x:0>2}", .{c}) catch return error.Fatal;
                } else {
                    writer.writeByte(c) catch return error.Fatal;
                }
            },
        }
    }
    writer.writeAll("\"") catch return error.Fatal;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}
