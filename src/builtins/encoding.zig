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
    .{ "BIG5", .shift_jis },
    .{ "CP949", .shift_jis },
    .{ "EMACS_MULE", .shift_jis },
    .{ "EUC_KR", .shift_jis },
    .{ "EUC_TW", .shift_jis },
    .{ "GB18030", .shift_jis },
    .{ "GBK", .shift_jis },
    .{ "STATELESS_ISO_2022_JP", .shift_jis },
    .{ "EUCJP_MS", .shift_jis },
    .{ "CP51932", .shift_jis },
    .{ "GB2312", .shift_jis },
    .{ "GB12345", .shift_jis },
    .{ "WINDOWS_31J", .shift_jis },
    .{ "MACJAPANESE", .shift_jis },
    .{ "ISO_8859_15", .iso_8859_15 },
    .{ "ISO8859_15", .iso_8859_15 },
    .{ "ISO_8859_1", .iso_8859_15 },
    .{ "ISO8859_1", .iso_8859_15 },
    .{ "ISO_8859_2", .iso_8859_15 },
    .{ "ISO_8859_3", .iso_8859_15 },
    .{ "ISO_8859_4", .iso_8859_15 },
    .{ "ISO_8859_5", .iso_8859_15 },
    .{ "ISO_8859_6", .iso_8859_15 },
    .{ "ISO_8859_7", .iso_8859_15 },
    .{ "ISO_8859_8", .iso_8859_15 },
    .{ "ISO_8859_9", .iso_8859_15 },
    .{ "ISO_8859_10", .iso_8859_15 },
    .{ "ISO_8859_11", .iso_8859_15 },
    .{ "ISO_8859_13", .iso_8859_15 },
    .{ "ISO_8859_14", .iso_8859_15 },
    .{ "ISO_8859_16", .iso_8859_15 },
    .{ "KOI8_R", .iso_8859_15 },
    .{ "KOI8_U", .iso_8859_15 },
    .{ "WINDOWS_1251", .iso_8859_15 },
    .{ "IBM437", .iso_8859_15 },
    .{ "IBM737", .iso_8859_15 },
    .{ "IBM775", .iso_8859_15 },
    .{ "CP850", .iso_8859_15 },
    .{ "IBM852", .iso_8859_15 },
    .{ "CP852", .iso_8859_15 },
    .{ "IBM855", .iso_8859_15 },
    .{ "CP855", .iso_8859_15 },
    .{ "IBM857", .iso_8859_15 },
    .{ "IBM860", .iso_8859_15 },
    .{ "IBM861", .iso_8859_15 },
    .{ "IBM862", .iso_8859_15 },
    .{ "IBM863", .iso_8859_15 },
    .{ "IBM864", .iso_8859_15 },
    .{ "IBM865", .iso_8859_15 },
    .{ "IBM866", .iso_8859_15 },
    .{ "IBM869", .iso_8859_15 },
    .{ "WINDOWS_1258", .iso_8859_15 },
    .{ "GB1988", .iso_8859_15 },
    .{ "MACCENTEURO", .iso_8859_15 },
    .{ "MACCROATIAN", .iso_8859_15 },
    .{ "MACCYRILLIC", .iso_8859_15 },
    .{ "MACGREEK", .iso_8859_15 },
    .{ "MACICELAND", .iso_8859_15 },
    .{ "MACROMAN", .iso_8859_15 },
    .{ "MACROMANIA", .iso_8859_15 },
    .{ "MACTHAI", .iso_8859_15 },
    .{ "MACTURKISH", .iso_8859_15 },
    .{ "MACUKRAINE", .iso_8859_15 },
    .{ "ISO_2022_JP_2", .iso_8859_15 },
    .{ "CP50221", .iso_8859_15 },
    .{ "WINDOWS_1252", .iso_8859_15 },
    .{ "WINDOWS_1250", .iso_8859_15 },
    .{ "WINDOWS_1256", .iso_8859_15 },
    .{ "WINDOWS_1253", .iso_8859_15 },
    .{ "WINDOWS_1255", .iso_8859_15 },
    .{ "WINDOWS_1254", .iso_8859_15 },
    .{ "TIS_620", .iso_8859_15 },
    .{ "WINDOWS_874", .iso_8859_15 },
    .{ "WINDOWS_1257", .iso_8859_15 },
    .{ "UTF8_MAC", .iso_8859_15 },
    .{ "IBM720", .iso_8859_15 },
    .{ "CP720", .iso_8859_15 },
    .{ "LATIN9", .iso_8859_15 },
    .{ "ISO_2022_JP", .iso_8859_15 },
    .{ "ISO2022_JP", .iso_8859_15 },
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
    const encoding_class_val = Value.fromObject(vm.encoding_class);
    const encoding_singleton = try vm.getOrCreateSingletonClass(encoding_class_val);
    try encoding_singleton.module.methods.put(find_sym, .{ .method = .{ .builtin = &builtinEncodingFind } });

    const default_internal_sym = try vm.intern("default_internal");
    try encoding_singleton.module.methods.put(default_internal_sym, .{ .method = .{ .builtin = &builtinEncodingDefaultInternal } });

    const set_default_internal_sym = try vm.intern("default_internal=");
    try encoding_singleton.module.methods.put(set_default_internal_sym, .{ .method = .{ .builtin = &builtinEncodingSetDefaultInternal } });
}

pub fn builtinEncodingName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.toEncodingObject();
    return try vm.newString(encoding_obj.encoding.name(), true);
}

pub fn builtinEncodingInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.toEncodingObject();
    const str = std.fmt.allocPrint(vm.gc_allocator, "#<Encoding:{s}>", .{encoding_obj.encoding.name()}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinEncodingAsciiCompatible(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.toEncodingObject();
    return Value.boolean(encoding_obj.encoding.isAsciiCompatible());
}

pub fn builtinEncodingEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isEncoding()) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.toEncodingObject().encoding.eql(other.toEncodingObject().encoding));
}

pub fn builtinEncodingFind(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isEncoding()) {
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

    if (std.mem.eql(u8, lookup, "INTERNAL")) {
        if (vm.default_internal_encoding) |encoding_obj| {
            return Value.fromObject(encoding_obj);
        }
        return Value.fromObject(vm.encoding_ascii_8bit);
    }

    if (encoding_name_map.get(lookup)) |enc_name| {
        return switch (enc_name) {
            .utf8 => Value.fromObject(vm.encoding_utf8),
            .ascii_8bit => Value.fromObject(vm.encoding_ascii_8bit),
            .us_ascii => Value.fromObject(vm.encoding_us_ascii),
            .shift_jis => Value.fromObject(vm.encoding_shift_jis),
            .iso_8859_15 => Value.fromObject(vm.encoding_iso_8859_15),
            .utf7 => Value.fromObject(vm.encoding_utf7),
            .utf16 => Value.fromObject(vm.encoding_utf16),
            .utf32 => Value.fromObject(vm.encoding_utf32),
            .utf16le => Value.fromObject(vm.encoding_utf16le),
            .utf16be => Value.fromObject(vm.encoding_utf16be),
            .utf32le => Value.fromObject(vm.encoding_utf32le),
            .utf32be => Value.fromObject(vm.encoding_utf32be),
        };
    }

    return vm.raiseExceptionFmt(vm.argument_error_class, "unknown encoding name - {s}", .{name_str});
}

pub fn builtinEncodingDefaultInternal(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (vm.default_internal_encoding) |encoding_obj| {
        return Value.fromObject(encoding_obj);
    }
    return Value.nil();
}

pub fn builtinEncodingSetDefaultInternal(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].isNil()) {
        vm.default_internal_encoding = null;
        return Value.nil();
    }

    const resolved: Value = if (args[0].isEncoding())
        args[0]
    else
        try builtinEncodingFind(vm, Value.nil(), args, null);

    vm.default_internal_encoding = resolved.toEncodingObject();
    return resolved;
}
