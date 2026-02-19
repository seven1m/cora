const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const EncodingLookup = enum {
    utf8,
    ascii_8bit,
    us_ascii,
    shift_jis,
    iso_8859_15,
    utf7,
    utf16,
    utf32,
    utf16le,
    utf16be,
    utf32le,
    utf32be,
};

const encoding_name_map = std.StaticStringMap(EncodingLookup).initComptime(.{
    .{ "UTF_8", .utf8 },
    .{ "UTF8", .utf8 },
    .{ "ASCII_8BIT", .ascii_8bit },
    .{ "BINARY", .ascii_8bit },
    .{ "US_ASCII", .us_ascii },
    .{ "ASCII", .us_ascii },
    .{ "SHIFT_JIS", .shift_jis },
    .{ "SJIS", .shift_jis },
    .{ "EUC_JP", .shift_jis },
    .{ "ISO_8859_15", .iso_8859_15 },
    .{ "ISO8859_15", .iso_8859_15 },
    .{ "ISO_8859_1", .iso_8859_15 },
    .{ "ISO8859_1", .iso_8859_15 },
    .{ "LATIN9", .iso_8859_15 },
    .{ "ISO_2022_JP", .shift_jis },
    .{ "ISO2022_JP", .shift_jis },
    .{ "UTF_7", .utf7 },
    .{ "UTF7", .utf7 },
    .{ "UTF_16", .utf16 },
    .{ "UTF16", .utf16 },
    .{ "UTF_32", .utf32 },
    .{ "UTF32", .utf32 },
    .{ "UTF_16LE", .utf16le },
    .{ "UTF16LE", .utf16le },
    .{ "UTF_16BE", .utf16be },
    .{ "UTF16BE", .utf16be },
    .{ "UTF_32LE", .utf32le },
    .{ "UTF32LE", .utf32le },
    .{ "UTF_32BE", .utf32be },
    .{ "UTF32BE", .utf32be },
});

pub fn register(vm: *VM) !void {
    const name_sym = try vm.intern("name");
    try vm.encoding_class.module.methods.put(name_sym, .{ .method = .{ .builtin = &builtinEncodingName } });

    const to_s_sym = try vm.intern("to_s");
    try vm.encoding_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinEncodingName } });

    const inspect_sym = try vm.intern("inspect");
    try vm.encoding_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinEncodingInspect } });

    const equal_sym = try vm.intern("==");
    try vm.encoding_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinEncodingEqual } });

    const ascii_compatible_sym = try vm.intern("ascii_compatible?");
    try vm.encoding_class.module.methods.put(ascii_compatible_sym, .{ .method = .{ .builtin = &builtinEncodingAsciiCompatible } });

    const find_sym = try vm.intern("find");
    const encoding_class_val = Value{ .data = .{ .class = vm.encoding_class } };
    const encoding_singleton = try vm.getOrCreateSingletonClass(encoding_class_val);
    try encoding_singleton.module.methods.put(find_sym, .{ .method = .{ .builtin = &builtinEncodingFind } });
}

pub fn builtinEncodingName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    return try vm.newString(encoding_obj.encoding.name(), true);
}

pub fn builtinEncodingInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    const str = std.fmt.allocPrint(vm.gc_allocator, "#<Encoding:{s}>", .{encoding_obj.encoding.name()}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinEncodingAsciiCompatible(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    return Value.boolean(encoding_obj.encoding.isAsciiCompatible());
}

pub fn builtinEncodingEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (other.data != .encoding) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.data.encoding.encoding.eql(other.data.encoding.encoding));
}

pub fn builtinEncodingFind(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.data == .encoding) {
        return arg;
    }

    const name_str = try arg.coerceToStr(vm, "no implicit conversion into String");

    // Normalize: uppercase and replace - with _
    var normalized: [32]u8 = undefined;
    var len: usize = 0;
    for (name_str) |c| {
        if (len >= normalized.len) break;
        if (c == '-') {
            normalized[len] = '_';
        } else if (c >= 'a' and c <= 'z') {
            normalized[len] = c - 32; // uppercase
        } else {
            normalized[len] = c;
        }
        len += 1;
    }
    const lookup = normalized[0..len];

    if (encoding_name_map.get(lookup)) |enc_name| {
        return switch (enc_name) {
            .utf8 => Value{ .data = .{ .encoding = vm.encoding_utf8 } },
            .ascii_8bit => Value{ .data = .{ .encoding = vm.encoding_ascii_8bit } },
            .us_ascii => Value{ .data = .{ .encoding = vm.encoding_us_ascii } },
            .shift_jis => Value{ .data = .{ .encoding = vm.encoding_shift_jis } },
            .iso_8859_15 => Value{ .data = .{ .encoding = vm.encoding_iso_8859_15 } },
            .utf7 => Value{ .data = .{ .encoding = vm.encoding_utf7 } },
            .utf16 => Value{ .data = .{ .encoding = vm.encoding_utf16 } },
            .utf32 => Value{ .data = .{ .encoding = vm.encoding_utf32 } },
            .utf16le => Value{ .data = .{ .encoding = vm.encoding_utf16le } },
            .utf16be => Value{ .data = .{ .encoding = vm.encoding_utf16be } },
            .utf32le => Value{ .data = .{ .encoding = vm.encoding_utf32le } },
            .utf32be => Value{ .data = .{ .encoding = vm.encoding_utf32be } },
        };
    }

    return vm.raiseExceptionFmt(vm.argument_error_class, "unknown encoding name - {s}", .{name_str});
}
