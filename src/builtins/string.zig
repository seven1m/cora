const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const inspect_util = @import("../inspect.zig");
const encoding_builtin = @import("encoding.zig");
const regexp_builtin = @import("regexp.zig");
const warning_builtin = @import("warning.zig");
const pack_runtime = @import("../pack.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const BigInt = std.math.big.int.Managed;

fn isTag(encoding: enc.Encoding, comptime tag: std.meta.Tag(enc.Encoding)) bool {
    return std.meta.activeTag(encoding) == tag;
}

fn transcodeToIso2022JpSimple(
    vm: *VM,
    source_bytes: []const u8,
    from_encoding: enc.Encoding,
    target_encoding: enc.Encoding,
) VMError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);

    var ascii_mode = true;
    var i: usize = 0;
    while (i < source_bytes.len) {
        const parsed = from_encoding.nextCodepoint(source_bytes, &i);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.encoding_invalid_byte_sequence_error_class, "invalid byte sequence in {s}", .{from_encoding.name()});
        }

        if (parsed.codepoint <= 0x7F) {
            if (!ascii_mode) {
                out.appendSlice(vm.gc_allocator_atomic, "\x1B(B") catch return error.Fatal;
                ascii_mode = true;
            }
            out.append(vm.gc_allocator_atomic, @intCast(parsed.codepoint)) catch return error.Fatal;
            continue;
        }

        var encoded: [4]u8 = undefined;
        const encoded_len = target_encoding.fromUnicodeCodepoint(parsed.codepoint, &encoded) orelse {
            return raiseUndefinedConversionForCodepoint(vm, parsed.codepoint, from_encoding, target_encoding);
        };
        if (encoded_len != 2) {
            return raiseUndefinedConversionForCodepoint(vm, parsed.codepoint, from_encoding, target_encoding);
        }

        if (ascii_mode) {
            out.appendSlice(vm.gc_allocator_atomic, "\x1B$B") catch return error.Fatal;
            ascii_mode = false;
        }
        out.appendSlice(vm.gc_allocator_atomic, encoded[0..2]) catch return error.Fatal;
    }

    if (!ascii_mode) {
        out.appendSlice(vm.gc_allocator_atomic, "\x1B(B") catch return error.Fatal;
    }
    return out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
}

pub fn register(vm: *VM) !void {
    const try_convert_sym = try vm.intern("try_convert");
    const string_class_val = Value.fromObject(vm.string_class);
    const string_singleton = try vm.getOrCreateSingletonClass(string_class_val);
    try string_singleton.module.methods.put(try_convert_sym, .{ .method = .{ .builtin = &builtinStringTryConvert } });

    const initialize_sym = try vm.intern("initialize");
    try vm.string_class.module.methods.put(initialize_sym, .{
        .method = .{ .builtin = &builtinStringInitialize },
        .visibility = .private,
    });

    const string_uplus_sym = try vm.intern("+@");
    try vm.string_class.module.methods.put(string_uplus_sym, .{ .method = .{ .builtin = &builtinStringUnaryPlus } });
    const string_uminus_sym = try vm.intern("-@");
    try vm.string_class.module.methods.put(string_uminus_sym, .{ .method = .{ .builtin = &builtinStringDedup } });

    const string_plus_sym = try vm.intern("+");
    try vm.string_class.module.methods.put(string_plus_sym, .{ .method = .{ .builtin = &builtinStringPlus } });

    const string_multiply_sym = try vm.intern("*");
    try vm.string_class.module.methods.put(string_multiply_sym, .{ .method = .{ .builtin = &builtinStringMultiply } });

    const string_append_sym = try vm.intern("<<");
    try vm.string_class.module.methods.put(string_append_sym, .{ .method = .{ .builtin = &builtinStringAppend } });

    const string_concat_sym = try vm.intern("concat");
    try vm.string_class.module.methods.put(string_concat_sym, .{ .method = .{ .builtin = &builtinStringConcat } });
    const string_append_as_bytes_sym = try vm.intern("append_as_bytes");
    try vm.string_class.module.methods.put(string_append_as_bytes_sym, .{ .method = .{ .builtin = &builtinStringAppendAsBytes } });

    const string_replace_sym = try vm.intern("replace");
    try vm.string_class.module.methods.put(string_replace_sym, .{ .method = .{ .builtin = &builtinStringReplace } });

    const string_equal_sym = try vm.intern("==");
    try vm.string_class.module.methods.put(string_equal_sym, .{ .method = .{ .builtin = &builtinStringEqual } });

    const string_eql_sym = try vm.intern("eql?");
    try vm.string_class.module.methods.put(string_eql_sym, .{ .method = .{ .builtin = &builtinStringEql } });

    const string_hash_sym = try vm.intern("hash");
    try vm.string_class.module.methods.put(string_hash_sym, .{ .method = .{ .builtin = &builtinStringHash } });

    const string_not_equal_sym = try vm.intern("!=");
    try vm.string_class.module.methods.put(string_not_equal_sym, .{ .method = .{ .builtin = &builtinStringNotEqual } });

    const string_compare_sym = try vm.intern("<=>");
    try vm.string_class.module.methods.put(string_compare_sym, .{ .method = .{ .builtin = &builtinStringCompare } });
    const string_casecmp_sym = try vm.intern("casecmp");
    try vm.string_class.module.methods.put(string_casecmp_sym, .{ .method = .{ .builtin = &builtinStringCasecmp } });
    const string_casecmp_pred_sym = try vm.intern("casecmp?");
    try vm.string_class.module.methods.put(string_casecmp_pred_sym, .{ .method = .{ .builtin = &builtinStringCasecmpQ } });

    const string_encoding_sym = try vm.intern("encoding");
    try vm.string_class.module.methods.put(string_encoding_sym, .{ .method = .{ .builtin = &builtinStringEncoding } });

    const string_encode_sym = try vm.intern("encode");
    try vm.string_class.module.methods.put(string_encode_sym, .{ .method = .{ .builtin = &builtinStringEncode } });

    const string_encode_bang_sym = try vm.intern("encode!");
    try vm.string_class.module.methods.put(string_encode_bang_sym, .{ .method = .{ .builtin = &builtinStringEncodeBang } });

    const string_force_encoding_sym = try vm.intern("force_encoding");
    try vm.string_class.module.methods.put(string_force_encoding_sym, .{ .method = .{ .builtin = &builtinStringForceEncoding } });

    const string_valid_encoding_sym = try vm.intern("valid_encoding?");
    try vm.string_class.module.methods.put(string_valid_encoding_sym, .{ .method = .{ .builtin = &builtinStringValidEncoding } });

    const string_ascii_only_sym = try vm.intern("ascii_only?");
    try vm.string_class.module.methods.put(string_ascii_only_sym, .{ .method = .{ .builtin = &builtinStringAsciiOnly } });

    const string_b_sym = try vm.intern("b");
    try vm.string_class.module.methods.put(string_b_sym, .{ .method = .{ .builtin = &builtinStringB } });
    const string_dedup_sym = try vm.intern("dedup");
    try vm.string_class.module.methods.put(string_dedup_sym, .{ .method = .{ .builtin = &builtinStringDedup } });

    const string_dup_sym = try vm.intern("dup");
    try vm.string_class.module.methods.put(string_dup_sym, .{ .method = .{ .builtin = &builtinStringDup } });

    const string_clone_sym = try vm.intern("clone");
    try vm.string_class.module.methods.put(string_clone_sym, .{ .method = .{ .builtin = &builtinStringClone } });

    const string_bytesize_sym = try vm.intern("bytesize");
    try vm.string_class.module.methods.put(string_bytesize_sym, .{ .method = .{ .builtin = &builtinStringBytesize } });

    const string_length_sym = try vm.intern("length");
    try vm.string_class.module.methods.put(string_length_sym, .{ .method = .{ .builtin = &builtinStringLength } });

    const string_size_sym = try vm.intern("size");
    try vm.string_class.module.methods.put(string_size_sym, .{ .method = .{ .builtin = &builtinStringLength } });

    const string_empty_sym = try vm.intern("empty?");
    try vm.string_class.module.methods.put(string_empty_sym, .{ .method = .{ .builtin = &builtinStringEmpty } });

    const string_clear_sym = try vm.intern("clear");
    try vm.string_class.module.methods.put(string_clear_sym, .{ .method = .{ .builtin = &builtinStringClear } });

    const string_ord_sym = try vm.intern("ord");
    try vm.string_class.module.methods.put(string_ord_sym, .{ .method = .{ .builtin = &builtinStringOrd } });

    const string_chr_sym = try vm.intern("chr");
    try vm.string_class.module.methods.put(string_chr_sym, .{ .method = .{ .builtin = &builtinStringChr } });

    const string_bracket_sym = try vm.intern("[]");
    try vm.string_class.module.methods.put(string_bracket_sym, .{ .method = .{ .builtin = &builtinStringBracket } });

    const string_slice_sym = try vm.intern("slice");
    try vm.string_class.module.methods.put(string_slice_sym, .{ .method = .{ .builtin = &builtinStringSlice } });
    const string_slice_bang_sym = try vm.intern("slice!");
    try vm.string_class.module.methods.put(string_slice_bang_sym, .{ .method = .{ .builtin = &builtinStringSliceBang } });

    const string_bracket_set_sym = try vm.intern("[]=");
    try vm.string_class.module.methods.put(string_bracket_set_sym, .{ .method = .{ .builtin = &builtinStringBracketSet } });

    const string_byteslice_sym = try vm.intern("byteslice");
    try vm.string_class.module.methods.put(string_byteslice_sym, .{ .method = .{ .builtin = &builtinStringByteSlice } });

    const string_chars_sym = try vm.intern("chars");
    try vm.string_class.module.methods.put(string_chars_sym, .{ .method = .{ .builtin = &builtinStringChars } });

    const string_each_char_sym = try vm.intern("each_char");
    try vm.string_class.module.methods.put(string_each_char_sym, .{ .method = .{ .builtin = &builtinStringEachChar } });

    const string_bytes_sym = try vm.intern("bytes");
    try vm.string_class.module.methods.put(string_bytes_sym, .{ .method = .{ .builtin = &builtinStringBytes } });

    const string_each_byte_sym = try vm.intern("each_byte");
    try vm.string_class.module.methods.put(string_each_byte_sym, .{ .method = .{ .builtin = &builtinStringEachByte } });

    const string_getbyte_sym = try vm.intern("getbyte");
    try vm.string_class.module.methods.put(string_getbyte_sym, .{ .method = .{ .builtin = &builtinStringGetbyte } });

    const string_setbyte_sym = try vm.intern("setbyte");
    try vm.string_class.module.methods.put(string_setbyte_sym, .{ .method = .{ .builtin = &builtinStringSetbyte } });

    const string_insert_sym = try vm.intern("insert");
    try vm.string_class.module.methods.put(string_insert_sym, .{ .method = .{ .builtin = &builtinStringInsert } });

    const string_codepoints_sym = try vm.intern("codepoints");
    try vm.string_class.module.methods.put(string_codepoints_sym, .{ .method = .{ .builtin = &builtinStringCodepoints } });

    const string_each_codepoint_sym = try vm.intern("each_codepoint");
    try vm.string_class.module.methods.put(string_each_codepoint_sym, .{ .method = .{ .builtin = &builtinStringEachCodepoint } });

    const string_start_with_sym = try vm.intern("start_with?");
    try vm.string_class.module.methods.put(string_start_with_sym, .{ .method = .{ .builtin = &builtinStringStartWith } });

    const string_end_with_sym = try vm.intern("end_with?");
    try vm.string_class.module.methods.put(string_end_with_sym, .{ .method = .{ .builtin = &builtinStringEndWith } });

    const string_delete_prefix_sym = try vm.intern("delete_prefix");
    try vm.string_class.module.methods.put(string_delete_prefix_sym, .{ .method = .{ .builtin = &builtinStringDeletePrefix } });

    const string_delete_prefix_bang_sym = try vm.intern("delete_prefix!");
    try vm.string_class.module.methods.put(string_delete_prefix_bang_sym, .{ .method = .{ .builtin = &builtinStringDeletePrefixBang } });

    const string_delete_suffix_sym = try vm.intern("delete_suffix");
    try vm.string_class.module.methods.put(string_delete_suffix_sym, .{ .method = .{ .builtin = &builtinStringDeleteSuffix } });

    const string_delete_suffix_bang_sym = try vm.intern("delete_suffix!");
    try vm.string_class.module.methods.put(string_delete_suffix_bang_sym, .{ .method = .{ .builtin = &builtinStringDeleteSuffixBang } });

    const string_include_sym = try vm.intern("include?");
    try vm.string_class.module.methods.put(string_include_sym, .{ .method = .{ .builtin = &builtinStringInclude } });

    const string_prepend_sym = try vm.intern("prepend");
    try vm.string_class.module.methods.put(string_prepend_sym, .{ .method = .{ .builtin = &builtinStringPrepend } });

    const string_split_sym = try vm.intern("split");
    try vm.string_class.module.methods.put(string_split_sym, .{ .method = .{ .builtin = &builtinStringSplit } });

    const string_reverse_sym = try vm.intern("reverse");
    try vm.string_class.module.methods.put(string_reverse_sym, .{ .method = .{ .builtin = &builtinStringReverse } });
    const string_reverse_bang_sym = try vm.intern("reverse!");
    try vm.string_class.module.methods.put(string_reverse_bang_sym, .{ .method = .{ .builtin = &builtinStringReverseBang } });

    const string_upcase_sym = try vm.intern("upcase");
    try vm.string_class.module.methods.put(string_upcase_sym, .{ .method = .{ .builtin = &builtinStringUpcase } });
    const string_upcase_bang_sym = try vm.intern("upcase!");
    try vm.string_class.module.methods.put(string_upcase_bang_sym, .{ .method = .{ .builtin = &builtinStringUpcaseBang } });
    const string_downcase_sym = try vm.intern("downcase");
    try vm.string_class.module.methods.put(string_downcase_sym, .{ .method = .{ .builtin = &builtinStringDowncase } });
    const string_downcase_bang_sym = try vm.intern("downcase!");
    try vm.string_class.module.methods.put(string_downcase_bang_sym, .{ .method = .{ .builtin = &builtinStringDowncaseBang } });
    const string_capitalize_sym = try vm.intern("capitalize");
    try vm.string_class.module.methods.put(string_capitalize_sym, .{ .method = .{ .builtin = &builtinStringCapitalize } });
    const string_capitalize_bang_sym = try vm.intern("capitalize!");
    try vm.string_class.module.methods.put(string_capitalize_bang_sym, .{ .method = .{ .builtin = &builtinStringCapitalizeBang } });
    const string_succ_sym = try vm.intern("succ");
    try vm.string_class.module.methods.put(string_succ_sym, .{ .method = .{ .builtin = &builtinStringNext } });
    const string_succ_bang_sym = try vm.intern("succ!");
    try vm.string_class.module.methods.put(string_succ_bang_sym, .{ .method = .{ .builtin = &builtinStringNextBang } });
    const string_next_sym = try vm.intern("next");
    try vm.string_class.module.methods.put(string_next_sym, .{ .method = .{ .builtin = &builtinStringNext } });
    const string_next_bang_sym = try vm.intern("next!");
    try vm.string_class.module.methods.put(string_next_bang_sym, .{ .method = .{ .builtin = &builtinStringNextBang } });

    const string_to_i_sym = try vm.intern("to_i");
    try vm.string_class.module.methods.put(string_to_i_sym, .{ .method = .{ .builtin = &builtinStringToI } });

    const string_to_f_sym = try vm.intern("to_f");
    try vm.string_class.module.methods.put(string_to_f_sym, .{ .method = .{ .builtin = &builtinStringToF } });

    const string_oct_sym = try vm.intern("oct");
    try vm.string_class.module.methods.put(string_oct_sym, .{ .method = .{ .builtin = &builtinStringOct } });

    const string_hex_sym = try vm.intern("hex");
    try vm.string_class.module.methods.put(string_hex_sym, .{ .method = .{ .builtin = &builtinStringHex } });

    const string_to_sym_sym = try vm.intern("to_sym");
    try vm.string_class.module.methods.put(string_to_sym_sym, .{ .method = .{ .builtin = &builtinStringToSym } });

    const string_intern_sym = try vm.intern("intern");
    try vm.string_class.module.methods.put(string_intern_sym, .{ .method = .{ .builtin = &builtinStringToSym } });

    const to_s_sym = try vm.intern("to_s");
    try vm.string_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinStringToS } });

    const to_str_sym = try vm.intern("to_str");
    try vm.string_class.module.methods.put(to_str_sym, .{ .method = .{ .builtin = &builtinStringToStr } });

    const inspect_sym = try vm.intern("inspect");
    try vm.string_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinStringInspect } });

    const match_op_sym = try vm.intern("=~");
    try vm.string_class.module.methods.put(match_op_sym, .{ .method = .{ .builtin = &builtinStringMatchOp } });

    const match_sym = try vm.intern("match");
    try vm.string_class.module.methods.put(match_sym, .{ .method = .{ .builtin = &builtinStringMatch } });

    const scan_sym = try vm.intern("scan");
    try vm.string_class.module.methods.put(scan_sym, .{ .method = .{ .builtin = &builtinStringScan } });

    const unpack_sym = try vm.intern("unpack");
    try vm.string_class.module.methods.put(unpack_sym, .{ .method = .{ .builtin = &builtinStringUnpack } });

    const unpack1_sym = try vm.intern("unpack1");
    try vm.string_class.module.methods.put(unpack1_sym, .{ .method = .{ .builtin = &builtinStringUnpack1 } });
}

pub fn builtinStringTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isString()) return arg;

    const maybe_converted = try vm.checkCallMethodByName(arg, "to_str", &[_]Value{}, null);
    const converted = maybe_converted orelse return Value.nil();
    if (converted.isNil()) return Value.nil();
    if (converted.isString()) return converted;

    return vm.raiseExceptionFmt(
        vm.type_error_class,
        "can't convert {s} to String ({s}#to_str gives {s})",
        .{ vm.className(arg), vm.className(arg), vm.className(converted) },
    );
}

pub fn builtinStringToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    if (string_obj.object.class == vm.string_class) {
        return receiver;
    }
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const string_obj = receiver.toStringObject();

    var keyword_encoding: ?Value = null;
    var keyword_capacity: ?Value = null;
    try vm.consumeKeywordArgs(
        .{ "encoding", "capacity" },
        .{ &keyword_encoding, &keyword_capacity },
    );
    try vm.validateKeywordArgsConsumed();

    if (keyword_capacity) |capacity| {
        _ = try capacity.coerceToI64ViaToInt(
            vm,
            "no implicit conversion of Object into Integer",
            "can't convert Object to Integer (Object#to_int gives Object)",
            "bignum too big to convert into `long`",
        );
    }

    var requested_encoding: ?enc.Encoding = null;
    if (keyword_encoding) |encoding_value| {
        if (encoding_value.isEncoding()) {
            requested_encoding = encoding_value.toEncodingObject().encoding;
        } else {
            var lookup_args = [_]Value{encoding_value};
            const found = try encoding_builtin.builtinEncodingFind(vm, receiver, lookup_args[0..], null);
            requested_encoding = found.toEncodingObject().encoding;
        }
    }

    const has_keyword_options = keyword_encoding != null or keyword_capacity != null;
    if (args.len == 0 and !has_keyword_options) {
        return receiver;
    }

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    if (args.len == 0) {
        if (requested_encoding) |encoding| {
            string_obj.encoding = encoding;
        }
        string_obj.validity = .unknown;
        return receiver;
    }

    const replacement_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const replacement = replacement_val.toStringObject();
    const final_encoding = requested_encoding orelse replacement.encoding;

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, replacement.str) catch return error.Fatal;
    string_obj.encoding = final_encoding;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringToStr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinStringToS(vm, receiver, args, null);
}

pub fn builtinStringUnaryPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    if (!receiver.isFrozen() and !string_obj.chilled_literal) {
        return receiver;
    }
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const rhs_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const rhs = rhs_value.toStringObject();

    const result_encoding = resolveStringConcatEncoding(lhs.encoding, lhs.str, rhs.encoding, rhs.str) orelse {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ lhs.encoding.name(), rhs.encoding.name() },
        );
    };

    const combined_str = try concatBytes(vm, lhs.str, rhs.str);
    return try vm.newStringWithEncoding(combined_str, false, result_encoding);
}

pub fn builtinStringMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const times = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (times < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative argument", .{});
    }

    const string_obj = receiver.toStringObject();
    if (times == 0 or string_obj.str.len == 0) {
        return vm.newStringWithEncoding("", false, string_obj.encoding);
    }

    const n: usize = @intCast(times);
    const out_len, const out_len_overflow = @mulWithOverflow(string_obj.str.len, n);
    if (out_len_overflow != 0 or out_len > @as(usize, @intCast(std.math.maxInt(i64)))) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "argument too big", .{});
    }

    const out = vm.gc_allocator_atomic.alloc(u8, out_len) catch return error.Fatal;
    var offset: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        @memcpy(out[offset .. offset + string_obj.str.len], string_obj.str);
        offset += string_obj.str.len;
    }
    return try vm.newStringWithEncoding(out, false, string_obj.encoding);
}

pub fn builtinStringAppend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const snapshot = ConcatSelfSnapshot{
        .bytes = receiver.toStringObject().str,
        .encoding = receiver.toStringObject().encoding,
    };
    try appendSingleConcatArg(vm, receiver, args[0], snapshot);
    return receiver;
}

pub fn builtinStringConcat(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = block;
    if (args.len == 0) return receiver;
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const snapshot = ConcatSelfSnapshot{
        .bytes = receiver.toStringObject().str,
        .encoding = receiver.toStringObject().encoding,
    };
    for (args) |arg| {
        try appendSingleConcatArg(vm, receiver, arg, snapshot);
    }
    return receiver;
}

pub fn builtinStringAppendAsBytes(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    var extra_len: usize = 0;
    for (args) |arg| {
        if (arg.isString()) {
            extra_len += arg.toStringObject().str.len;
            continue;
        }
        if (arg.isInteger() or arg.isBigInteger()) {
            extra_len += 1;
            continue;
        }
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "wrong argument type {s} (expected String or Integer)",
            .{vm.className(arg)},
        );
    }

    if (receiver.isFrozen() and extra_len > 0) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    if (extra_len == 0) return receiver;

    const string_obj = receiver.toStringObject();
    const old_len = string_obj.str.len;
    const out = vm.gc_allocator_atomic.alloc(u8, old_len + extra_len) catch return error.Fatal;
    @memcpy(out[0..old_len], string_obj.str);

    var write_index = old_len;
    for (args) |arg| {
        if (arg.isString()) {
            const bytes = arg.toStringObject().str;
            @memcpy(out[write_index .. write_index + bytes.len], bytes);
            write_index += bytes.len;
            continue;
        }

        out[write_index] = try integerLeastSignificantByte(vm, arg);
        write_index += 1;
    }

    string_obj.str = out;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringReplace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const other = args[0];

    const replacement_val = try other.coerceToStringValue(vm, "no implicit conversion into String");
    const replacement = replacement_val.toStringObject().str;
    string_obj.encoding = replacement_val.toStringObject().encoding;

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, replacement) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];

    if (other.isString()) {
        return builtinStringEql(vm, receiver, args, null);
    }

    const to_str_sym = try vm.intern("to_str");
    var respond_args = [_]Value{Value.fromObject(to_str_sym)};
    const responds_to_to_str = try vm.callMethodByName(other, "respond_to?", respond_args[0..], null);
    if (responds_to_to_str.is_truthy()) {
        var reverse_args = [_]Value{receiver};
        return try vm.callMethodByName(other, "==", reverse_args[0..], null);
    }

    return Value.boolean(false);
}

pub fn builtinStringEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isString()) {
        return Value.boolean(false);
    }

    const lhs = receiver.toStringObject();
    const rhs = other.toStringObject();
    if (!std.mem.eql(u8, lhs.str, rhs.str)) {
        return Value.boolean(false);
    }

    if (lhs.str.len == 0) {
        return Value.boolean(true);
    }

    if (lhs.encoding.eql(rhs.encoding)) {
        return Value.boolean(true);
    }

    if (lhs.encoding.isAsciiCompatible() and rhs.encoding.isAsciiCompatible() and enc.isAsciiOnly(lhs.str) and enc.isAsciiOnly(rhs.str)) {
        return Value.boolean(true);
    }

    return Value.boolean(false);
}

pub fn builtinStringHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_value: i64 = @bitCast(receiver.hash());
    return Value.integer(hash_value);
}

pub fn builtinStringNotEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    // String != returns true if other is not a String or has different content
    if (!other.isString()) {
        return Value.boolean(true);
    }
    const result = !std.mem.eql(u8, receiver.toStringObject().str, other.toStringObject().str);
    return Value.boolean(result);
}

pub fn builtinStringCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const other = args[0];

    if (other.isString()) {
        return compareStringObjects(lhs, other.toStringObject());
    }

    const coerced = try tryCoerceToStringForCompare(vm, other);
    if (coerced) |coerced_value| {
        return compareStringObjects(lhs, coerced_value.toStringObject());
    }

    if (try vm.enterRecursionGuard(.string_compare_fallback, receiver, other)) return Value.nil();
    defer vm.leaveRecursionGuard(.string_compare_fallback, receiver, other);

    var reverse_args = [_]Value{receiver};
    const maybe_reversed = try vm.checkCallMethodByName(other, "<=>", reverse_args[0..], null);
    const reversed = maybe_reversed orelse return Value.nil();

    if (reversed.isNil()) return Value.nil();
    if (reversed.isInteger()) {
        const value_int = reversed.toInteger();
        if (value_int < 0) return Value.integer(1);
        if (value_int > 0) return Value.integer(-1);
        return Value.integer(0);
    }
    if (reversed.isFloat()) {
        const value_float = reversed.toFloatObject().val;
        if (value_float < 0) return Value.integer(1);
        if (value_float > 0) return Value.integer(-1);
        return Value.integer(0);
    }
    return Value.nil();
}

fn compareStringObjects(lhs: *const value.StringObject, rhs: *const value.StringObject) Value {
    const order = std.mem.order(u8, lhs.str, rhs.str);
    if (order == .lt) return Value.integer(-1);
    if (order == .gt) return Value.integer(1);

    if (lhs.str.len == 0 or lhs.encoding.eql(rhs.encoding)) {
        return Value.integer(0);
    }

    if (lhs.encoding.isAsciiCompatible() and rhs.encoding.isAsciiCompatible() and
        enc.isAsciiOnly(lhs.str) and enc.isAsciiOnly(rhs.str))
    {
        return Value.integer(0);
    }

    const lhs_tag = @intFromEnum(@as(std.meta.Tag(enc.Encoding), lhs.encoding));
    const rhs_tag = @intFromEnum(@as(std.meta.Tag(enc.Encoding), rhs.encoding));
    if (lhs_tag < rhs_tag) return Value.integer(-1);
    if (lhs_tag > rhs_tag) return Value.integer(1);
    return Value.integer(0);
}

fn tryCoerceToStringForCompare(vm: *VM, other: Value) VMError!?Value {
    const maybe_coerced = try vm.checkCallMethodByName(other, "to_str", &[_]Value{}, null);
    const coerced = maybe_coerced orelse return null;

    if (coerced.isNil()) {
        return null;
    }

    if (!coerced.isString()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to String ({s}#to_str gives {s})",
            .{ vm.className(other), vm.className(other), vm.className(coerced) },
        );
    }

    return coerced;
}

fn casecmpOrder(
    vm: *VM,
    lhs: *const value.StringObject,
    rhs: *const value.StringObject,
    fold: bool,
) VMError!?i64 {
    if (enc.negotiate(lhs.encoding, lhs.str, rhs.encoding, rhs.str) == null) {
        return null;
    }

    const order = if (!fold) blk: {
        const lhs_mapped = vm.gc_allocator_atomic.dupe(u8, lhs.str) catch return error.Fatal;
        const rhs_mapped = vm.gc_allocator_atomic.dupe(u8, rhs.str) catch return error.Fatal;
        for (lhs_mapped) |*b| {
            if (b.* >= 'A' and b.* <= 'Z') b.* += 32;
        }
        for (rhs_mapped) |*b| {
            if (b.* >= 'A' and b.* <= 'Z') b.* += 32;
        }
        break :blk std.mem.order(u8, lhs_mapped, rhs_mapped);
    } else blk: {
        const options: enc.CaseMapOptions = .{
            .fold = true,
        };
        const lhs_mapped = enc.caseMap(vm.gc_allocator_atomic, lhs.str, lhs.encoding, .downcase, options) catch |err| switch (err) {
            error.OutOfMemory => return error.Fatal,
            error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
        };
        const rhs_mapped = enc.caseMap(vm.gc_allocator_atomic, rhs.str, rhs.encoding, .downcase, options) catch |err| switch (err) {
            error.OutOfMemory => return error.Fatal,
            error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
        };
        break :blk std.mem.order(u8, lhs_mapped.bytes, rhs_mapped.bytes);
    };
    return switch (order) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn builtinStringCasecmp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const other = args[0];

    const rhs_value = if (other.isString())
        other
    else
        (try tryCoerceToStringForCompare(vm, other) orelse return Value.nil());
    const rhs = rhs_value.toStringObject();

    const order = try casecmpOrder(vm, lhs, rhs, false) orelse return Value.nil();
    return Value.integer(order);
}

pub fn builtinStringCasecmpQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const other = args[0];

    const rhs_value = if (other.isString())
        other
    else
        (try tryCoerceToStringForCompare(vm, other) orelse return Value.nil());
    const rhs = rhs_value.toStringObject();

    const order = try casecmpOrder(vm, lhs, rhs, true) orelse return Value.nil();
    return Value.boolean(order == 0);
}
pub fn builtinStringEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    return vm.encodingToValue(string_obj.encoding);
}

fn replacementValueForEncode(
    vm: *VM,
    receiver: Value,
    replacement_opt: ?Value,
) VMError!Value {
    if (replacement_opt) |replacement| {
        return replacement.coerceToStringValue(vm, "no implicit conversion into String");
    }
    _ = receiver;
    return vm.newString("?", false);
}

fn appendDefaultReplacementForEncode(
    vm: *VM,
    out: *std.ArrayList(u8),
    target_encoding: enc.Encoding,
) VMError!void {
    var encoded: [4]u8 = undefined;
    if (target_encoding.fromUnicodeCodepoint(0xFFFD, &encoded)) |encoded_len| {
        out.appendSlice(vm.gc_allocator_atomic, encoded[0..encoded_len]) catch return error.Fatal;
        return;
    }
    if (target_encoding.fromUnicodeCodepoint('?', &encoded)) |encoded_len| {
        out.appendSlice(vm.gc_allocator_atomic, encoded[0..encoded_len]) catch return error.Fatal;
        return;
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "too big fallback string", .{});
}

fn appendReplacementForEncode(
    vm: *VM,
    out: *std.ArrayList(u8),
    replacement: Value,
    target_encoding: enc.Encoding,
) VMError!void {
    const replacement_obj = replacement.toStringObject();
    const transcoded = enc.transcode(vm.gc_allocator_atomic, replacement_obj.str, replacement_obj.encoding, target_encoding) catch |err| {
        switch (err) {
            error.UndefinedConversion => {
                return vm.raiseExceptionFmt(vm.argument_error_class, "too big fallback string", .{});
            },
            error.InvalidByteSequence => {
                return vm.raiseExceptionFmt(vm.encoding_invalid_byte_sequence_error_class, "invalid byte sequence in {s}", .{replacement_obj.encoding.name()});
            },
            else => return error.Fatal,
        }
    };
    out.appendSlice(vm.gc_allocator_atomic, transcoded) catch return error.Fatal;
}

fn raiseUndefinedConversionForCodepoint(vm: *VM, codepoint: u32, from: enc.Encoding, to: enc.Encoding) VMError {
    return vm.raiseExceptionFmt(
        vm.encoding_undefined_conversion_error_class,
        "U+{X:0>4} from {s} to {s}",
        .{ codepoint, from.name(), to.name() },
    );
}

const EncodeXmlMode = enum {
    none,
    text,
    attr,
};

fn parseEncodeXmlMode(vm: *VM, kw_xml: ?Value) VMError!EncodeXmlMode {
    if (kw_xml == null) return .none;
    const xml = kw_xml.?;
    if (!xml.isSymbol()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected value for xml option: {s}", .{vm.className(xml)});
    }
    const name = xml.toSymbolObject().name;
    if (std.mem.eql(u8, name, "text")) return .text;
    if (std.mem.eql(u8, name, "attr")) return .attr;
    return vm.raiseExceptionFmt(vm.argument_error_class, "unexpected value for xml option: :{s}", .{name});
}

fn appendCodepointInEncoding(
    vm: *VM,
    out: *std.ArrayList(u8),
    codepoint: u32,
    target_encoding: enc.Encoding,
) VMError!void {
    var encoded: [4]u8 = undefined;
    if (target_encoding.fromUnicodeCodepoint(codepoint, &encoded)) |encoded_len| {
        out.appendSlice(vm.gc_allocator_atomic, encoded[0..encoded_len]) catch return error.Fatal;
        return;
    }
    return raiseUndefinedConversionForCodepoint(vm, codepoint, .{ .utf8 = .{} }, target_encoding);
}

fn appendXmlEntity(
    vm: *VM,
    out: *std.ArrayList(u8),
    entity: []const u8,
    target_encoding: enc.Encoding,
) VMError!void {
    for (entity) |b| {
        try appendCodepointInEncoding(vm, out, @as(u32, b), target_encoding);
    }
}

fn appendXmlNumericCharRef(
    vm: *VM,
    out: *std.ArrayList(u8),
    codepoint: u32,
    target_encoding: enc.Encoding,
) VMError!void {
    var buf: [20]u8 = undefined;
    const char_ref = std.fmt.bufPrint(&buf, "&#x{X};", .{codepoint}) catch return error.Fatal;
    try appendXmlEntity(vm, out, char_ref, target_encoding);
}

fn transcodeWithEncodeOptions(
    vm: *VM,
    receiver: Value,
    source_bytes: []const u8,
    from_encoding: enc.Encoding,
    target_encoding: enc.Encoding,
    kw_invalid: ?Value,
    kw_undef: ?Value,
    kw_replace: ?Value,
    kw_fallback: ?Value,
    xml_mode: EncodeXmlMode,
) VMError![]u8 {
    const effective_target_encoding = enc.effectiveTranscodeTargetEncoding(target_encoding);

    if (isTag(effective_target_encoding, .iso_2022_jp) and
        kw_invalid == null and
        kw_undef == null and
        kw_replace == null and
        kw_fallback == null and
        xml_mode == .none)
    {
        return transcodeToIso2022JpSimple(vm, source_bytes, from_encoding, effective_target_encoding);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);

    const invalid_replace = kw_invalid != null and kw_invalid.?.isSymbol() and std.mem.eql(u8, kw_invalid.?.toSymbolObject().name, "replace");
    const undef_replace = kw_undef != null and kw_undef.?.isSymbol() and std.mem.eql(u8, kw_undef.?.toSymbolObject().name, "replace");
    const replacement = if (kw_replace) |_| try replacementValueForEncode(vm, receiver, kw_replace) else Value.nil();

    var i: usize = 0;
    while (i < source_bytes.len) {
        const start = i;
        const parsed = from_encoding.nextCodepoint(source_bytes, &i);
        if (parsed.len == 0) break;

        if (!parsed.valid) {
            if (invalid_replace) {
                if (kw_replace != null) {
                    try appendReplacementForEncode(vm, &out, replacement, effective_target_encoding);
                } else {
                    try appendDefaultReplacementForEncode(vm, &out, effective_target_encoding);
                }
                continue;
            }
            return vm.raiseExceptionFmt(vm.encoding_invalid_byte_sequence_error_class, "invalid byte sequence in {s}", .{from_encoding.name()});
        }

        const unicode_codepoint = from_encoding.toUnicodeCodepoint(source_bytes[start..i]);

        if (xml_mode != .none) {
            const codepoint = unicode_codepoint orelse {
                return raiseUndefinedConversionForCodepoint(vm, parsed.codepoint, from_encoding, effective_target_encoding);
            };
            if (codepoint == '&') {
                try appendXmlEntity(vm, &out, "&amp;", effective_target_encoding);
                continue;
            }
            if (codepoint == '<') {
                try appendXmlEntity(vm, &out, "&lt;", effective_target_encoding);
                continue;
            }
            if (codepoint == '>') {
                try appendXmlEntity(vm, &out, "&gt;", effective_target_encoding);
                continue;
            }
            if (xml_mode == .attr and codepoint == '"') {
                try appendXmlEntity(vm, &out, "&quot;", effective_target_encoding);
                continue;
            }
        }

        const codepoint = unicode_codepoint orelse {
            if (undef_replace) {
                if (kw_replace != null) {
                    try appendReplacementForEncode(vm, &out, replacement, effective_target_encoding);
                } else {
                    try appendDefaultReplacementForEncode(vm, &out, effective_target_encoding);
                }
                continue;
            }

            if (kw_fallback) |fallback| {
                const char_val = try vm.newStringWithEncoding(source_bytes[start..i], false, from_encoding);
                var fallback_result: ?Value = null;
                var fallback_args = [_]Value{char_val};

                if (fallback.isProc()) {
                    fallback_result = try vm.callProcObject(fallback.toProcObject(), fallback_args[0..], null, null);
                } else if (try vm.checkCallMethodByName(fallback, "call", fallback_args[0..], null)) |result| {
                    fallback_result = result;
                } else if (try vm.checkCallMethodByName(fallback, "[]", fallback_args[0..], null)) |result| {
                    fallback_result = result;
                }

                if (fallback_result == null or fallback_result.?.isNil()) {
                    return raiseUndefinedConversionForCodepoint(vm, parsed.codepoint, from_encoding, effective_target_encoding);
                }

                const fallback_str = fallback_result.?.coerceToStringValue(vm, "no implicit conversion of Object into String") catch {
                    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Object into String", .{});
                };
                try appendReplacementForEncode(vm, &out, fallback_str, effective_target_encoding);
                continue;
            }

            return raiseUndefinedConversionForCodepoint(vm, parsed.codepoint, from_encoding, effective_target_encoding);
        };

        var encoded: [4]u8 = undefined;
        if (effective_target_encoding.fromUnicodeCodepoint(codepoint, &encoded)) |encoded_len| {
            out.appendSlice(vm.gc_allocator_atomic, encoded[0..encoded_len]) catch return error.Fatal;
            continue;
        }

        if (xml_mode != .none) {
            try appendXmlNumericCharRef(vm, &out, codepoint, effective_target_encoding);
            continue;
        }

        if (undef_replace) {
            if (kw_replace != null) {
                try appendReplacementForEncode(vm, &out, replacement, effective_target_encoding);
            } else {
                try appendDefaultReplacementForEncode(vm, &out, effective_target_encoding);
            }
            continue;
        }

        if (kw_fallback) |fallback| {
            const char_val = try vm.newStringWithEncoding(source_bytes[start..i], false, from_encoding);
            var fallback_result: ?Value = null;
            var fallback_args = [_]Value{char_val};

            if (fallback.isProc()) {
                fallback_result = try vm.callProcObject(fallback.toProcObject(), fallback_args[0..], null, null);
            } else if (try vm.checkCallMethodByName(fallback, "call", fallback_args[0..], null)) |result| {
                fallback_result = result;
            } else if (try vm.checkCallMethodByName(fallback, "[]", fallback_args[0..], null)) |result| {
                fallback_result = result;
            }

            if (fallback_result == null or fallback_result.?.isNil()) {
                return raiseUndefinedConversionForCodepoint(vm, codepoint, from_encoding, effective_target_encoding);
            }

            const fallback_str = fallback_result.?.coerceToStringValue(vm, "no implicit conversion of Object into String") catch {
                return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Object into String", .{});
            };
            try appendReplacementForEncode(vm, &out, fallback_str, effective_target_encoding);
            continue;
        }

        return raiseUndefinedConversionForCodepoint(vm, codepoint, from_encoding, effective_target_encoding);
    }

    return out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
}

pub fn builtinStringEncode(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    var kw_invalid: ?Value = null;
    var kw_undef: ?Value = null;
    var kw_replace: ?Value = null;
    var kw_fallback: ?Value = null;
    var kw_cr_newline: ?Value = null;
    var kw_crlf_newline: ?Value = null;
    var kw_universal_newline: ?Value = null;
    var kw_xml: ?Value = null;
    try vm.consumeKeywordArgs(
        .{ "invalid", "undef", "replace", "fallback", "cr_newline", "crlf_newline", "universal_newline", "xml" },
        .{ &kw_invalid, &kw_undef, &kw_replace, &kw_fallback, &kw_cr_newline, &kw_crlf_newline, &kw_universal_newline, &kw_xml },
    );
    try vm.validateKeywordArgsConsumed();

    const has_encode_options = kw_invalid != null or
        kw_undef != null or
        kw_replace != null or
        kw_fallback != null or
        kw_cr_newline != null or
        kw_crlf_newline != null or
        kw_universal_newline != null or
        kw_xml != null;
    _ = has_encode_options;
    const xml_mode = try parseEncodeXmlMode(vm, kw_xml);

    const string_obj = receiver.toStringObject();
    const from_encoding: enc.Encoding = if (args.len >= 2)
        if (args[1].isEncoding())
            args[1].toEncodingObject().encoding
        else blk: {
            var find_args = [_]Value{args[1]};
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, find_args[0..], null);
            break :blk result.toEncodingObject().encoding;
        }
    else
        string_obj.encoding;
    const target_encoding: enc.Encoding = if (args.len >= 1)
        if (args[0].isEncoding())
            args[0].toEncodingObject().encoding
        else blk: {
            var find_args = [_]Value{args[0]};
            const result = try encoding_builtin.builtinEncodingFind(vm, receiver, find_args[0..], null);
            break :blk result.toEncodingObject().encoding;
        }
    else if (vm.default_internal_encoding) |internal|
        internal.encoding
    else
        string_obj.encoding;

    var normalized_newlines: std.ArrayList(u8) = .empty;
    defer normalized_newlines.deinit(vm.gc_allocator_atomic);
    const source_bytes: []const u8 = blk: {
        if (kw_universal_newline != null and kw_universal_newline.?.is_truthy()) {
            var i: usize = 0;
            while (i < string_obj.str.len) : (i += 1) {
                const b = string_obj.str[i];
                if (b == '\r') {
                    if (i + 1 < string_obj.str.len and string_obj.str[i + 1] == '\n') {
                        i += 1;
                    }
                    normalized_newlines.append(vm.gc_allocator_atomic, '\n') catch return error.Fatal;
                } else {
                    normalized_newlines.append(vm.gc_allocator_atomic, b) catch return error.Fatal;
                }
            }
            break :blk normalized_newlines.items;
        }

        if (kw_crlf_newline != null and kw_crlf_newline.?.is_truthy()) {
            for (string_obj.str) |b| {
                if (b == '\n') {
                    normalized_newlines.append(vm.gc_allocator_atomic, '\r') catch return error.Fatal;
                    normalized_newlines.append(vm.gc_allocator_atomic, '\n') catch return error.Fatal;
                } else {
                    normalized_newlines.append(vm.gc_allocator_atomic, b) catch return error.Fatal;
                }
            }
            break :blk normalized_newlines.items;
        }

        if (kw_cr_newline != null and kw_cr_newline.?.is_truthy()) {
            for (string_obj.str) |b| {
                normalized_newlines.append(vm.gc_allocator_atomic, if (b == '\n') '\r' else b) catch return error.Fatal;
            }
            break :blk normalized_newlines.items;
        }

        break :blk string_obj.str;
    };

    switch (enc.converterAvailability(from_encoding, target_encoding)) {
        .available => {},
        .ascii_only_passthrough => {
            if (enc.isAsciiOnly(source_bytes)) {
                return try vm.newStringWithEncoding(source_bytes, false, from_encoding);
            }
            return vm.raiseExceptionFmt(vm.encoding_converter_not_found_error_class, "code converter not found", .{});
        },
        .unavailable => {
            return vm.raiseExceptionFmt(vm.encoding_converter_not_found_error_class, "code converter not found", .{});
        },
    }

    const transcoded = try transcodeWithEncodeOptions(
        vm,
        receiver,
        source_bytes,
        from_encoding,
        target_encoding,
        kw_invalid,
        kw_undef,
        kw_replace,
        kw_fallback,
        xml_mode,
    );
    var encoded = try vm.newStringWithEncoding(transcoded, false, target_encoding);
    if (xml_mode == .attr) {
        const encoded_obj = encoded.toStringObject();
        var wrapped: std.ArrayList(u8) = .empty;
        defer wrapped.deinit(vm.gc_allocator_atomic);
        try appendCodepointInEncoding(vm, &wrapped, '"', target_encoding);
        wrapped.appendSlice(vm.gc_allocator_atomic, encoded_obj.str) catch return error.Fatal;
        try appendCodepointInEncoding(vm, &wrapped, '"', target_encoding);
        encoded = try vm.newStringWithEncoding(wrapped.items, true, target_encoding);
    }
    return encoded;
}

pub fn builtinStringEncodeBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const encoded = try builtinStringEncode(vm, receiver, args, null);
    const receiver_obj = receiver.toStringObject();
    const encoded_obj = encoded.toStringObject();
    receiver_obj.str = encoded_obj.str;
    receiver_obj.encoding = encoded_obj.encoding;
    receiver_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringForceEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    // Get the new encoding from argument
    const new_encoding: enc.Encoding = if (args[0].isEncoding())
        args[0].toEncodingObject().encoding
    else blk: {
        const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
        if (result.isNil()) {
            break :blk vm.encoding_ascii_8bit.encoding;
        }
        break :blk result.toEncodingObject().encoding;
    };

    const string_obj = receiver.toStringObject();
    string_obj.encoding = new_encoding;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringValidEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    return Value.boolean(string_obj.encoding.isValid(string_obj.str));
}

pub fn builtinStringAsciiOnly(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    if (!string_obj.encoding.isAsciiCompatible()) {
        return Value.boolean(false);
    }
    return Value.boolean(enc.isAsciiOnly(string_obj.str));
}

pub fn builtinStringB(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    // Return a new string with ASCII-8BIT encoding
    return try vm.newStringWithEncoding(string_obj.str, false, .{ .ascii_8bit = .{} });
}

pub fn builtinStringDedup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const string_obj = receiver.toStringObject();
    const object = receiver.getObjectPointer().?;
    const bare_string =
        vm.getClass(receiver) == vm.string_class and
        object.instance_variables == null;

    if (bare_string) {
        if (receiver.isFrozen()) {
            return try vm.getOrCreateCanonicalFStringValue(receiver);
        }
        return try vm.getOrCreateCanonicalFString(string_obj.str, string_obj.encoding);
    }

    var result = receiver;
    if (!receiver.isFrozen()) {
        result = try builtinStringDup(vm, receiver, &.{}, null);
    }

    const canonical = try vm.getOrCreateCanonicalFString(string_obj.str, string_obj.encoding);
    const result_obj = result.toStringObject();
    const canonical_obj = canonical.toStringObject();
    result_obj.str = canonical_obj.str;
    result_obj.encoding = canonical_obj.encoding;
    result_obj.validity = canonical_obj.validity;
    result.freeze();
    return result;
}

pub fn builtinStringDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const duplicate = try vm.newStringForClassWithEncoding(vm.getClass(receiver), string_obj.str, false, string_obj.encoding);

    const src_obj = receiver.getObjectPointer().?;
    const dst_obj = duplicate.getObjectPointer().?;
    if (src_obj.instance_variables) |*src_ivars| {
        var copied_ivars = std.AutoHashMap(*value.SymbolObject, Value).init(vm.gc_allocator);
        var iter = src_ivars.iterator();
        while (iter.next()) |entry| {
            copied_ivars.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }
        dst_obj.instance_variables = copied_ivars;
    }

    const initialize_copy_sym = try vm.intern("initialize_copy");
    if (try vm.findMethod(duplicate, initialize_copy_sym)) |_| {
        var initialize_copy_args = [_]Value{receiver};
        _ = try vm.callMethodByName(duplicate, "initialize_copy", initialize_copy_args[0..], null);
    }

    try vm.copyPackedPointerTargets(receiver.toStringObject(), duplicate.toStringObject());

    return duplicate;
}

pub fn builtinStringClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const duplicate = try builtinStringDup(vm, receiver, args, null);

    if (receiver.isFrozen()) {
        var mutable_duplicate = duplicate;
        mutable_duplicate.freeze();
    }

    try vm.copySingletonClassMetadata(receiver, duplicate);
    return duplicate;
}

pub fn builtinStringBytesize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.toStringObject().str.len));
}

pub fn builtinStringLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    return Value.integer(@intCast(string_obj.encoding.charCount(string_obj.str)));
}

pub fn builtinStringEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.toStringObject().str.len == 0);
}

pub fn builtinStringClear(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    string_obj.str = "";
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringOrd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    if (string_obj.str.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "empty string", .{});
    }

    var index: usize = 0;
    const parsed = string_obj.encoding.nextCodepoint(string_obj.str, &index);
    if (parsed.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "empty string", .{});
    }
    if (!parsed.valid) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{string_obj.encoding.name()});
    }
    return Value.integer(parsed.codepoint);
}

pub fn builtinStringChr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const bytes = string_obj.str;
    const encoding = string_obj.encoding;

    if (bytes.len == 0) {
        return vm.newStringWithEncoding("", false, encoding);
    }

    var index: usize = 0;
    const parsed = encoding.nextChar(bytes, &index);
    if (parsed.len == 0) {
        return vm.newStringWithEncoding("", false, encoding);
    }
    return vm.newStringWithEncoding(bytes[0..parsed.len], false, encoding);
}

pub fn builtinStringBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    if (args[0].isInteger()) {
        const idx = args[0].toInteger();
        const slice = string_obj.encoding.charSliceAtIndex(string_obj.str, idx);
        if (slice == null) return Value.nil();
        return try vm.newStringWithEncoding(slice.?, false, string_obj.encoding);
    } else if (args[0].isRange()) {
        const range_obj = args[0].toRangeObject();
        const slice = try charSliceByRange(vm, string_obj.str, string_obj.encoding, range_obj.begin, range_obj.end, range_obj.exclude_end);
        if (slice == null) return Value.nil();
        return try vm.newStringWithEncoding(slice.?, false, string_obj.encoding);
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
}

pub fn builtinStringSlice(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinStringBracket(vm, receiver, args, block);
}

pub fn builtinStringSliceBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const removed = try builtinStringBracket(vm, receiver, args, null);
    if (removed.isNil()) return Value.nil();

    const replacement = try vm.newStringWithEncoding("", false, receiver.toStringObject().encoding);
    var set_args: [3]Value = undefined;
    for (args, 0..) |arg, idx| {
        set_args[idx] = arg;
    }
    set_args[args.len] = replacement;
    _ = try builtinStringBracketSet(vm, receiver, set_args[0 .. args.len + 1], null);
    return removed;
}

pub fn builtinStringByteSlice(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const bytes = string_obj.str;
    const byte_len_i64: i64 = @intCast(bytes.len);

    if (args.len == 1) {
        if (args[0].isRange()) {
            const range_obj = args[0].toRangeObject();
            const slice = try byteSliceByRange(vm, bytes, range_obj.begin, range_obj.end, range_obj.exclude_end);
            if (slice == null) return Value.nil();
            return try vm.newStringWithEncoding(slice.?, false, string_obj.encoding);
        }

        var index = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (index < 0) index += byte_len_i64;
        if (index < 0 or index >= byte_len_i64) return Value.nil();
        const start: usize = @intCast(index);
        return try vm.newStringWithEncoding(bytes[start .. start + 1], false, string_obj.encoding);
    }

    if (args[0].isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Range into Integer", .{});
    }

    var index = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const length = try args[1].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    if (index < 0) index += byte_len_i64;
    if (index < 0 or index > byte_len_i64) return Value.nil();
    if (length < 0) return Value.nil();

    const clamped_len = byte_len_i64 - index;
    const normalized_len = if (length > clamped_len) clamped_len else length;
    const start: usize = @intCast(index);
    const finish: usize = @intCast(index + normalized_len);
    return try vm.newStringWithEncoding(bytes[start..finish], false, string_obj.encoding);
}

pub fn builtinStringBracketSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const bytes = string_obj.str;
    const encoding = string_obj.encoding;
    const char_len_i64: i64 = @intCast(encoding.charCount(bytes));

    var replace_start_byte: usize = 0;
    var replace_end_byte: usize = 0;
    const replacement_arg = args[args.len - 1];

    if (args.len == 3 and args[0].isRegexp()) {
        const regexp = args[0].toRegexpObject();
        const capture_ref = try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        const match_index = try regexp_builtin.regexpMatchOp(vm, regexp, receiver);
        if (match_index.isNil()) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index out of string", .{});
        }

        const md_val = vm.globals.get("$~") orelse return error.Fatal;
        if (!md_val.isMatchData()) return error.Fatal;
        const md = md_val.toMatchDataObject();

        const captures_total_i64: i64 = @intCast(md.captures.items.len);
        if (captures_total_i64 <= 1) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of regexp", .{capture_ref});
        }
        const capture_groups_i64 = captures_total_i64 - 1;

        var capture_idx = capture_ref;
        if (capture_idx > 0) {
            // Positive references are 1-based capture group indexes.
            if (capture_idx > capture_groups_i64) {
                return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of regexp", .{capture_ref});
            }
        } else if (capture_idx < 0) {
            // Negative references index capture groups from the end.
            capture_idx = capture_groups_i64 + capture_idx + 1;
            if (capture_idx <= 0 or capture_idx > capture_groups_i64) {
                return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of regexp", .{capture_ref});
            }
        } else {
            // MRI accepts 0 as the full match.
            capture_idx = 0;
        }

        if (capture_idx < 0 or capture_idx >= captures_total_i64) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of regexp", .{capture_ref});
        }

        const capture_usize: usize = @intCast(capture_idx);
        const begin_i64 = md.begin_byte_offsets.items[capture_usize];
        const end_i64 = md.end_byte_offsets.items[capture_usize];
        if (begin_i64 < 0 or end_i64 < 0) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of regexp", .{capture_ref});
        }
        replace_start_byte = @intCast(begin_i64);
        replace_end_byte = @intCast(end_i64);
    } else if (args.len == 2 and args[0].isRegexp()) {
        const regexp = args[0].toRegexpObject();
        const match_index = try regexp_builtin.regexpMatchOp(vm, regexp, receiver);
        if (match_index.isNil()) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index out of string", .{});
        }

        const md_val = vm.globals.get("$~") orelse return error.Fatal;
        if (!md_val.isMatchData()) return error.Fatal;
        const md = md_val.toMatchDataObject();
        if (md.begin_byte_offsets.items.len == 0 or md.end_byte_offsets.items.len == 0) {
            return error.Fatal;
        }

        const begin_i64 = md.begin_byte_offsets.items[0];
        const end_i64 = md.end_byte_offsets.items[0];
        if (begin_i64 < 0 or end_i64 < 0) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index out of string", .{});
        }
        replace_start_byte = @intCast(begin_i64);
        replace_end_byte = @intCast(end_i64);
    } else if (args.len == 2 and args[0].isString()) {
        const needle = args[0].toStringObject().str;
        const start = std.mem.indexOf(u8, bytes, needle) orelse {
            return vm.raiseExceptionFmt(vm.index_error_class, "string not matched", .{});
        };
        replace_start_byte = start;
        replace_end_byte = start + needle.len;
    } else if (args.len == 2 and args[0].isRange()) {
        const range_obj = args[0].toRangeObject();
        if (!range_obj.begin.isInteger() or !range_obj.end.isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }

        const begin_src = range_obj.begin.toInteger();
        const end_src = range_obj.end.toInteger();
        var start_char = begin_src;
        if (start_char < 0) start_char += char_len_i64;
        if (start_char < 0 or start_char > char_len_i64) {
            return vm.raiseExceptionFmt(
                vm.range_error_class,
                "{d}{s}{d} out of range",
                .{ begin_src, if (range_obj.exclude_end) "..." else "..", end_src },
            );
        }

        var finish_exclusive = end_src;
        if (finish_exclusive < 0) finish_exclusive += char_len_i64;
        if (!range_obj.exclude_end) finish_exclusive += 1;
        if (finish_exclusive < start_char) finish_exclusive = start_char;
        if (finish_exclusive < 0) finish_exclusive = 0;
        if (finish_exclusive > char_len_i64) finish_exclusive = char_len_i64;

        replace_start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(start_char)) orelse bytes.len;
        replace_end_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(finish_exclusive)) orelse bytes.len;
    } else if (args.len == 3) {
        var index = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        const index_source = index;
        const count = try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (index < 0) index += char_len_i64;
        if (index < 0 or index > char_len_i64) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of string", .{index_source});
        }
        if (count < 0) {
            return vm.raiseExceptionFmt(vm.index_error_class, "negative length {d}", .{count});
        }

        const max_count = char_len_i64 - index;
        const normalized_count = if (count > max_count) max_count else count;
        const finish = index + normalized_count;
        replace_start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(index)) orelse bytes.len;
        replace_end_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(finish)) orelse bytes.len;
    } else {
        var index = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        const index_source = index;
        var remove_chars: i64 = 1;
        if (index < 0) index += char_len_i64;
        if (char_len_i64 == 0 and index == 0) {
            remove_chars = 0;
        } else if (index < 0 or index >= char_len_i64) {
            return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of string", .{index_source});
        }

        const finish = index + remove_chars;
        replace_start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(index)) orelse bytes.len;
        replace_end_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(finish)) orelse bytes.len;
    }

    const replacement = try replacement_arg.coerceToStringValue(vm, "no implicit conversion into String");
    try spliceStringBytes(vm, receiver, replace_start_byte, replace_end_byte, replacement);
    return replacement;
}

pub fn builtinStringChars(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
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
                return yield_result.value;
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

    return Value.fromObject(array_obj);
}

pub fn builtinStringEachChar(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (block == null) {
        const string_obj = receiver.toStringObject();
        const size_value = Value.integer(@intCast(string_obj.encoding.charCount(string_obj.str)));
        return vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each_char"), &.{}, size_value);
    }
    return builtinStringChars(vm, receiver, args, block);
}

pub fn builtinStringBytes(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const bytes = receiver.toStringObject().str;

    if (block) |blk| {
        for (bytes) |b| {
            const yield_args = [_]Value{Value.integer(b)};
            const yield_result = try vm.yieldToBlock(blk, &yield_args);
            if (yield_result.break_occurred) {
                return yield_result.value;
            }
        }
        return receiver;
    }

    const array_obj = try vm.createArray();
    for (bytes) |b| {
        array_obj.elements.append(vm.gc_allocator, Value.integer(b)) catch return error.Fatal;
    }
    return Value.fromObject(array_obj);
}

pub fn builtinStringEachByte(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (block == null) {
        const size_value = Value.integer(@intCast(receiver.toStringObject().str.len));
        return vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each_byte"), &.{}, size_value);
    }

    var i: usize = 0;
    while (true) {
        const bytes = receiver.toStringObject().str;
        if (i >= bytes.len) break;
        const yield_args = [_]Value{Value.integer(bytes[i])};
        i += 1;
        const yield_result = try vm.yieldToBlock(block.?, &yield_args);
        if (yield_result.break_occurred) {
            return yield_result.value;
        }
    }

    return receiver;
}

pub fn builtinStringGetbyte(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try vm.requireIntegerArg(args, 0, "Integer");

    const bytes = receiver.toStringObject().str;
    const len: i64 = @intCast(bytes.len);
    var index = args[0].toInteger();
    if (index < 0) {
        index += len;
    }
    if (index < 0 or index >= len) {
        return Value.nil();
    }
    return Value.integer(bytes[@intCast(index)]);
}

pub fn builtinStringSetbyte(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    var index = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const index_source = index;
    const byte_value = try args[1].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (byte_value < 0 or byte_value > 255) {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{byte_value});
    }

    const string_obj = receiver.toStringObject();
    const len_i64: i64 = @intCast(string_obj.str.len);
    if (index < 0) {
        index += len_i64;
    }
    if (index < 0 or index >= len_i64) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of string", .{index_source});
    }

    const new_bytes = vm.gc_allocator_atomic.dupe(u8, string_obj.str) catch return error.Fatal;
    new_bytes[@intCast(index)] = @intCast(byte_value);
    string_obj.str = new_bytes;
    string_obj.validity = .unknown;
    return Value.integer(byte_value);
}

pub fn builtinStringInsert(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    var index = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const insert_value = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
    const insert_bytes = insert_value.toStringObject().str;
    const insert_encoding = insert_value.toStringObject().encoding;

    const string_obj = receiver.toStringObject();
    if (enc.negotiate(string_obj.encoding, string_obj.str, insert_encoding, insert_bytes) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), insert_encoding.name() },
        );
    }

    const char_len: i64 = @intCast(string_obj.encoding.charCount(string_obj.str));
    const index_source = index;
    if (index < 0) {
        index += char_len + 1;
    }
    if (index < 0 or index > char_len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of string", .{index_source});
    }

    const insert_byte_offset = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(index)) orelse string_obj.str.len;
    const replacement = try vm.newStringWithEncoding(insert_bytes, false, insert_encoding);
    try spliceStringBytes(vm, receiver, insert_byte_offset, insert_byte_offset, replacement);
    return receiver;
}

pub fn builtinStringCodepoints(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const bytes = string_obj.str;
    const encoding = string_obj.encoding;

    if (block) |blk| {
        var i: usize = 0;
        while (i < bytes.len) {
            const parsed = encoding.nextCodepoint(bytes, &i);
            if (parsed.len == 0) break;
            if (!parsed.valid) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{encoding.name()});
            }

            const yield_args = [_]Value{Value.integer(parsed.codepoint)};
            const yield_result = try vm.yieldToBlock(blk, &yield_args);
            if (yield_result.break_occurred) {
                return yield_result.value;
            }
        }
        return receiver;
    }

    const array_obj = try vm.createArray();
    var i: usize = 0;
    while (i < bytes.len) {
        const parsed = encoding.nextCodepoint(bytes, &i);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{encoding.name()});
        }
        array_obj.elements.append(vm.gc_allocator, Value.integer(parsed.codepoint)) catch return error.Fatal;
    }

    return Value.fromObject(array_obj);
}

pub fn builtinStringEachCodepoint(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (block == null) {
        const string_obj = receiver.toStringObject();
        const size_value = Value.integer(@intCast(string_obj.encoding.charCount(string_obj.str)));
        return vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each_codepoint"), &.{}, size_value);
    }
    return builtinStringCodepoints(vm, receiver, args, block);
}

pub fn builtinStringStartWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) return Value.boolean(false);
    const string_obj = receiver.toStringObject();

    for (args) |arg| {
        if (arg.isRegexp()) {
            const match_val = try regexp_builtin.regexpMatchOp(vm, arg.toRegexpObject(), receiver);
            if (match_val.isInteger() and match_val.toInteger() == 0) {
                return Value.boolean(true);
            }
            try vm.clearLastMatch();
            continue;
        }

        const prefix_val = try arg.coerceToStringValue(vm, "no implicit conversion into String");
        const prefix = prefix_val.toStringObject().str;
        const prefix_enc = prefix_val.toStringObject().encoding;
        if (enc.negotiate(string_obj.encoding, string_obj.str, prefix_enc, prefix) == null) {
            return vm.raiseExceptionFmt(
                vm.encoding_compatibility_error_class,
                "incompatible character encodings: {s} and {s}",
                .{ string_obj.encoding.name(), prefix_enc.name() },
            );
        }
        if (!std.mem.startsWith(u8, string_obj.str, prefix)) continue;
        if (string_obj.encoding.isCharBoundary(string_obj.str, prefix.len)) {
            return Value.boolean(true);
        }
    }

    return Value.boolean(false);
}

pub fn builtinStringEndWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) return Value.boolean(false);
    const string_obj = receiver.toStringObject();

    for (args) |arg| {
        const suffix_val = try arg.coerceToStringValue(vm, "no implicit conversion into String");
        const suffix = suffix_val.toStringObject().str;
        const suffix_enc = suffix_val.toStringObject().encoding;
        if (enc.negotiate(string_obj.encoding, string_obj.str, suffix_enc, suffix) == null) {
            return vm.raiseExceptionFmt(
                vm.encoding_compatibility_error_class,
                "incompatible character encodings: {s} and {s}",
                .{ string_obj.encoding.name(), suffix_enc.name() },
            );
        }
        if (!std.mem.endsWith(u8, string_obj.str, suffix)) continue;
        const start = string_obj.str.len - suffix.len;
        if (string_obj.encoding.isCharBoundary(string_obj.str, start)) {
            return Value.boolean(true);
        }
    }

    return Value.boolean(false);
}

pub fn builtinStringDeletePrefix(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    const prefix_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const prefix = prefix_val.toStringObject().str;
    const prefix_enc = prefix_val.toStringObject().encoding;
    if (enc.negotiate(string_obj.encoding, string_obj.str, prefix_enc, prefix) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), prefix_enc.name() },
        );
    }

    if (std.mem.startsWith(u8, string_obj.str, prefix) and string_obj.encoding.isCharBoundary(string_obj.str, prefix.len)) {
        return try vm.newStringWithEncoding(string_obj.str[prefix.len..], false, string_obj.encoding);
    }

    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringDeletePrefixBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();

    const prefix_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const prefix = prefix_val.toStringObject().str;
    const prefix_enc = prefix_val.toStringObject().encoding;
    if (enc.negotiate(string_obj.encoding, string_obj.str, prefix_enc, prefix) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), prefix_enc.name() },
        );
    }

    if (!(std.mem.startsWith(u8, string_obj.str, prefix) and string_obj.encoding.isCharBoundary(string_obj.str, prefix.len))) {
        return Value.nil();
    }
    if (prefix.len == 0) {
        return Value.nil();
    }

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[prefix.len..]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringDeleteSuffix(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    const suffix_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const suffix = suffix_val.toStringObject().str;
    const suffix_enc = suffix_val.toStringObject().encoding;
    if (enc.negotiate(string_obj.encoding, string_obj.str, suffix_enc, suffix) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), suffix_enc.name() },
        );
    }

    if (std.mem.endsWith(u8, string_obj.str, suffix)) {
        const start = string_obj.str.len - suffix.len;
        if (string_obj.encoding.isCharBoundary(string_obj.str, start)) {
            return try vm.newStringWithEncoding(string_obj.str[0..start], false, string_obj.encoding);
        }
    }

    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringDeleteSuffixBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();

    const suffix_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const suffix = suffix_val.toStringObject().str;
    const suffix_enc = suffix_val.toStringObject().encoding;
    if (enc.negotiate(string_obj.encoding, string_obj.str, suffix_enc, suffix) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), suffix_enc.name() },
        );
    }

    if (!std.mem.endsWith(u8, string_obj.str, suffix)) {
        return Value.nil();
    }
    if (suffix.len == 0) {
        return Value.nil();
    }
    const start = string_obj.str.len - suffix.len;
    if (!string_obj.encoding.isCharBoundary(string_obj.str, start)) {
        return Value.nil();
    }

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[0..start]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    const needle_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const needle = needle_val.toStringObject().str;
    const needle_enc = needle_val.toStringObject().encoding;

    if (needle.len == 0) {
        return Value.boolean(true);
    }

    if (enc.negotiate(string_obj.encoding, string_obj.str, needle_enc, needle) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), needle_enc.name() },
        );
    }

    if (needle.len > string_obj.str.len) {
        return Value.boolean(false);
    }

    var pos: usize = 0;
    while (pos <= string_obj.str.len - needle.len) {
        const found = std.mem.indexOfPos(u8, string_obj.str, pos, needle) orelse return Value.boolean(false);
        const end = found + needle.len;
        if (string_obj.encoding.isCharBoundary(string_obj.str, found) and string_obj.encoding.isCharBoundary(string_obj.str, end)) {
            return Value.boolean(true);
        }
        pos = found + 1;
    }

    return Value.boolean(false);
}

pub fn builtinStringPrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) return receiver;
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();

    var result = string_obj.str;
    var i: usize = args.len;
    while (i > 0) {
        i -= 1;
        const arg = args[i];
        const part = try arg.coerceToStringValue(vm, "no implicit conversion into String");
        result = try concatBytes(vm, part.toStringObject().str, result);
    }

    string_obj.str = result;
    return receiver;
}

pub fn builtinStringSplit(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);
    const string_obj = receiver.toStringObject();
    const source = string_obj.str;
    const array_obj = try vm.createArray();

    if (args.len == 0 or args[0].isNil()) {
        var i: usize = 0;
        while (i < source.len) {
            while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
            if (i >= source.len) break;
            const start = i;
            while (i < source.len and !std.ascii.isWhitespace(source[i])) : (i += 1) {}
            const token = source[start..i];
            const token_val = try vm.newStringWithEncoding(token, false, string_obj.encoding);
            array_obj.elements.append(vm.gc_allocator, token_val) catch return error.Fatal;
        }
        return Value.fromObject(array_obj);
    }

    const sep = try args[0].coerceToStr(vm, "no implicit conversion into String");
    if (sep.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "empty separator", .{});
    }

    var start: usize = 0;
    while (true) {
        const idx_opt = std.mem.indexOfPos(u8, source, start, sep);
        if (idx_opt == null) break;
        const idx = idx_opt.?;
        const part = source[start..idx];
        const part_val = try vm.newStringWithEncoding(part, false, string_obj.encoding);
        array_obj.elements.append(vm.gc_allocator, part_val) catch return error.Fatal;
        start = idx + sep.len;
    }
    const tail = source[start..];
    const tail_val = try vm.newStringWithEncoding(tail, false, string_obj.encoding);
    array_obj.elements.append(vm.gc_allocator, tail_val) catch return error.Fatal;
    return Value.fromObject(array_obj);
}

fn reverseStringChars(vm: *VM, bytes: []const u8, string_encoding: enc.Encoding) VMError![]const u8 {
    var chars: std.ArrayList([]const u8) = .empty;
    defer chars.deinit(vm.allocator);

    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const char_result = string_encoding.nextChar(bytes, &i);
        if (char_result.len == 0) break;
        chars.append(vm.allocator, bytes[start .. start + char_result.len]) catch return error.Fatal;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);
    out.ensureTotalCapacityPrecise(vm.gc_allocator_atomic, bytes.len) catch return error.Fatal;

    var idx = chars.items.len;
    while (idx > 0) {
        idx -= 1;
        out.appendSlice(vm.gc_allocator_atomic, chars.items[idx]) catch return error.Fatal;
    }

    return out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
}

pub fn builtinStringReverse(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const reversed = try reverseStringChars(vm, string_obj.str, string_obj.encoding);
    return vm.newStringWithEncoding(reversed, false, string_obj.encoding);
}

pub fn builtinStringReverseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const reversed = try reverseStringChars(vm, string_obj.str, string_obj.encoding);
    string_obj.str = reversed;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringUpcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .upcase);
    const string_obj = receiver.toStringObject();
    const mapped = enc.caseMap(vm.gc_allocator_atomic, string_obj.str, string_obj.encoding, .upcase, options) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringUpcaseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .upcase);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();

    const mapped = enc.caseMap(vm.gc_allocator_atomic, string_obj.str, string_obj.encoding, .upcase, options) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };
    if (!mapped.modified) return Value.nil();

    try warnSymbolToSMutation(vm, string_obj);
    string_obj.str = mapped.bytes;
    string_obj.encoding = mapped.encoding;
    string_obj.validity = .unknown;
    string_obj.symbol_to_s_source = null;
    return receiver;
}

pub fn builtinStringDowncase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .downcase);
    const string_obj = receiver.toStringObject();
    const mapped = enc.caseMap(vm.gc_allocator_atomic, string_obj.str, string_obj.encoding, .downcase, options) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringDowncaseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .downcase);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();

    const mapped = enc.caseMap(vm.gc_allocator_atomic, string_obj.str, string_obj.encoding, .downcase, options) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };
    if (!mapped.modified) return Value.nil();

    string_obj.str = mapped.bytes;
    string_obj.encoding = mapped.encoding;
    string_obj.validity = .unknown;
    return receiver;
}

fn mapStringCapitalize(
    vm: *VM,
    bytes: []const u8,
    source_encoding: enc.Encoding,
    options: enc.CaseMapOptions,
) VMError!enc.CaseMapResult {
    if (bytes.len == 0) {
        const dup = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
        return .{ .bytes = dup, .modified = false, .encoding = source_encoding };
    }

    var first_end: usize = 0;
    const first_char = source_encoding.nextChar(bytes, &first_end);
    if (first_char.len == 0) {
        const dup = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
        return .{ .bytes = dup, .modified = false, .encoding = source_encoding };
    }

    const first_up = enc.caseMap(
        vm.gc_allocator_atomic,
        bytes[0..first_end],
        source_encoding,
        .upcase,
        options,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };

    var first_up_first_end: usize = 0;
    const first_up_first_char = first_up.encoding.nextChar(first_up.bytes, &first_up_first_end);
    if (first_up_first_char.len == 0) {
        const dup = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
        return .{ .bytes = dup, .modified = false, .encoding = source_encoding };
    }

    const prefix = first_up.bytes[0..first_up_first_end];
    const first_up_tail = first_up.bytes[first_up_first_end..];
    const original_rest = bytes[first_end..];

    const downcase_input = blk: {
        if (first_up_tail.len == 0) break :blk original_rest;
        if (original_rest.len == 0) break :blk first_up_tail;
        break :blk try concatBytes(vm, first_up_tail, original_rest);
    };

    const down_tail = enc.caseMap(
        vm.gc_allocator_atomic,
        downcase_input,
        first_up.encoding,
        .downcase,
        options,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.Fatal,
        error.InvalidByteSequence => return vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
    };

    const result_bytes = try concatBytes(vm, prefix, down_tail.bytes);
    const modified = !std.mem.eql(u8, result_bytes, bytes) or !down_tail.encoding.eql(source_encoding);
    return .{ .bytes = result_bytes, .modified = modified, .encoding = down_tail.encoding };
}

pub fn builtinStringCapitalize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .capitalize);
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCapitalize(vm, string_obj.str, string_obj.encoding, options);
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringCapitalizeBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .capitalize);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCapitalize(vm, string_obj.str, string_obj.encoding, options);
    if (!mapped.modified) return Value.nil();

    string_obj.str = mapped.bytes;
    string_obj.encoding = mapped.encoding;
    string_obj.validity = .unknown;
    return receiver;
}

fn isAsciiDigitByte(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAsciiLowerByte(c: u8) bool {
    return c >= 'a' and c <= 'z';
}

fn isAsciiUpperByte(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn isAsciiAlnumByte(c: u8) bool {
    return isAsciiDigitByte(c) or isAsciiLowerByte(c) or isAsciiUpperByte(c);
}

fn insertByteAt(vm: *VM, bytes: []const u8, at: usize, byte: u8) VMError![]u8 {
    const out = vm.gc_allocator_atomic.alloc(u8, bytes.len + 1) catch return error.Fatal;
    @memcpy(out[0..at], bytes[0..at]);
    out[at] = byte;
    @memcpy(out[at + 1 ..], bytes[at..]);
    return out;
}

fn stringNextBytes(vm: *VM, bytes: []const u8) VMError![]u8 {
    const out = vm.gc_allocator_atomic.dupe(u8, bytes) catch return error.Fatal;
    if (out.len == 0) return out;

    var rightmost_alnum: ?usize = null;
    var idx_find = out.len;
    while (idx_find > 0) {
        idx_find -= 1;
        if (isAsciiAlnumByte(out[idx_find])) {
            rightmost_alnum = idx_find;
            break;
        }
    }

    if (rightmost_alnum == null) {
        var carry = true;
        var i = out.len;
        while (i > 0 and carry) {
            i -= 1;
            if (out[i] == 0xFF) {
                out[i] = 0;
            } else {
                out[i] +%= 1;
                carry = false;
            }
        }
        if (!carry) return out;
        return insertByteAt(vm, out, 0, 0x01);
    }

    var carry = true;
    var prepend_char: u8 = 0;
    var prepend_at: usize = rightmost_alnum.?;
    var idx: isize = @intCast(rightmost_alnum.?);

    while (idx >= 0 and carry) : (idx -= 1) {
        const uidx: usize = @intCast(idx);
        const c = out[uidx];
        if (!isAsciiAlnumByte(c)) continue;

        if (isAsciiDigitByte(c)) {
            if (c < '9') {
                out[uidx] = c + 1;
                carry = false;
            } else {
                out[uidx] = '0';
                prepend_char = '1';
                prepend_at = uidx;
            }
            continue;
        }

        if (isAsciiLowerByte(c)) {
            if (c < 'z') {
                out[uidx] = c + 1;
                carry = false;
            } else {
                out[uidx] = 'a';
                prepend_char = 'a';
                prepend_at = uidx;
            }
            continue;
        }

        if (c < 'Z') {
            out[uidx] = c + 1;
            carry = false;
        } else {
            out[uidx] = 'A';
            prepend_char = 'A';
            prepend_at = uidx;
        }
    }

    if (!carry) return out;
    return insertByteAt(vm, out, prepend_at, prepend_char);
}

pub fn builtinStringNext(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const next_bytes = try stringNextBytes(vm, string_obj.str);
    return vm.newStringWithEncoding(next_bytes, false, string_obj.encoding);
}

pub fn builtinStringNextBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const next_bytes = try stringNextBytes(vm, string_obj.str);
    string_obj.str = next_bytes;
    string_obj.validity = .unknown;
    return receiver;
}

fn parseStringToInteger(vm: *VM, s: []const u8, requested_base: i64, default_base_when_zero: u8) VMError!Value {
    if ((requested_base < 2 or requested_base > 36) and requested_base != 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid radix {d}", .{requested_base});
    }

    var base: u8 = if (requested_base == 0) default_base_when_zero else @intCast(requested_base);
    var i: usize = 0;
    while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {}

    var negative = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        negative = s[i] == '-';
        i += 1;
    }

    if (i < s.len and s[i] == '0') {
        const has_prefix_char = i + 1 < s.len;
        const prefix_ch = if (has_prefix_char) std.ascii.toLower(s[i + 1]) else 0;

        if (requested_base == 0) {
            switch (prefix_ch) {
                'b' => {
                    base = 2;
                    i += 2;
                },
                'd' => {
                    base = 10;
                    i += 2;
                },
                'o' => {
                    base = 8;
                    i += 2;
                },
                'x' => {
                    base = 16;
                    i += 2;
                },
                else => base = 8,
            }
        } else if ((requested_base == 2 and prefix_ch == 'b') or
            (requested_base == 8 and prefix_ch == 'o') or
            (requested_base == 10 and prefix_ch == 'd') or
            (requested_base == 16 and prefix_ch == 'x'))
        {
            i += 2;
        }
    }

    var saw_digit = false;
    var prev_was_digit = false;
    var value_i64: i64 = 0;
    var value_big: ?BigInt = null;
    defer if (value_big) |*b| b.deinit();
    var base_big = BigInt.initSet(vm.allocator, @as(i64, base)) catch return error.Fatal;
    defer base_big.deinit();

    while (i < s.len) : (i += 1) {
        if (s[i] == '_') {
            const next_digit = if (i + 1 < s.len) digitValue(s[i + 1]) else null;
            if (saw_digit and prev_was_digit and next_digit != null and next_digit.? < base) {
                prev_was_digit = false;
                continue;
            }
            break;
        }

        const d = digitValue(s[i]) orelse break;
        if (d >= base) break;
        saw_digit = true;
        prev_was_digit = true;

        if (value_big) |*big| {
            big.mul(big, &base_big) catch return error.Fatal;
            big.addScalar(big, d) catch return error.Fatal;
            continue;
        }

        const mul = std.math.mul(i64, value_i64, base);
        if (mul) |multiplied| {
            const add = std.math.add(i64, multiplied, @as(i64, d));
            if (add) |added| {
                value_i64 = added;
                continue;
            } else |_| {}
        } else |_| {}

        value_big = BigInt.initSet(vm.allocator, value_i64) catch return error.Fatal;
        value_big.?.mul(&value_big.?, &base_big) catch return error.Fatal;
        value_big.?.addScalar(&value_big.?, d) catch return error.Fatal;
    }

    if (!saw_digit) return Value.integer(0);

    if (value_big) |*big| {
        if (negative and !big.eqlZero()) {
            big.negate();
        }
        return vm.valueFromManagedInteger(big);
    }

    if (!negative) return Value.integer(value_i64);
    if (std.math.negate(value_i64)) |neg| {
        return Value.integer(neg);
    } else |_| {
        var promoted = BigInt.initSet(vm.allocator, value_i64) catch return error.Fatal;
        defer promoted.deinit();
        promoted.negate();
        return vm.valueFromManagedInteger(&promoted);
    }
}

fn parseStringToFloat(vm: *VM, s: []const u8) VMError!f64 {
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(vm.allocator);

    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        normalized.append(vm.allocator, s[i]) catch return error.Fatal;
        i += 1;
    }

    var saw_mantissa_digit = false;
    var saw_dot = false;
    var saw_exponent = false;
    var saw_exponent_digit = false;

    while (i < s.len) {
        const c = s[i];

        if (isAsciiDigitByte(c)) {
            normalized.append(vm.allocator, c) catch return error.Fatal;
            if (saw_exponent) {
                saw_exponent_digit = true;
            } else {
                saw_mantissa_digit = true;
            }
            i += 1;
            continue;
        }

        if (c == '_') {
            const prev_is_digit = normalized.items.len > 0 and isAsciiDigitByte(normalized.items[normalized.items.len - 1]);
            const next_is_digit = i + 1 < s.len and isAsciiDigitByte(s[i + 1]);
            if (prev_is_digit and next_is_digit) {
                i += 1;
                continue;
            }
            break;
        }

        if (c == '.' and !saw_dot and !saw_exponent) {
            normalized.append(vm.allocator, c) catch return error.Fatal;
            saw_dot = true;
            i += 1;
            continue;
        }

        if ((c == 'e' or c == 'E') and !saw_exponent and saw_mantissa_digit) {
            var exponent_start = i + 1;
            var exponent_sign: ?u8 = null;
            if (exponent_start < s.len and (s[exponent_start] == '+' or s[exponent_start] == '-')) {
                exponent_sign = s[exponent_start];
                exponent_start += 1;
            }

            if (exponent_start < s.len and isAsciiDigitByte(s[exponent_start])) {
                normalized.append(vm.allocator, 'e') catch return error.Fatal;
                if (exponent_sign) |sign| {
                    normalized.append(vm.allocator, sign) catch return error.Fatal;
                }
                saw_exponent = true;
                i = exponent_start;
                continue;
            }
            break;
        }

        break;
    }

    if (!saw_mantissa_digit) return 0.0;
    if (saw_exponent and !saw_exponent_digit) return 0.0;
    return std.fmt.parseFloat(f64, normalized.items) catch 0.0;
}

pub fn builtinStringToI(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    var requested_base: i64 = 10;
    if (args.len == 1) {
        requested_base = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion of Object into Integer",
            "can't convert Object to Integer (Object#to_int gives Object)",
            "base is too large",
        );
    }

    return parseStringToInteger(vm, receiver.toStringObject().str, requested_base, 10);
}

pub fn builtinStringToF(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const string_obj = receiver.toStringObject();
    if (!string_obj.encoding.isAsciiCompatible()) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "ASCII incompatible encoding: {s}",
            .{string_obj.encoding.name()},
        );
    }

    const trimmed = std.mem.trim(u8, string_obj.str, " \t\n\r\x0B\x0C");
    const parsed = try parseStringToFloat(vm, trimmed);
    return vm.newFloat(parsed);
}

pub fn builtinStringOct(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return parseStringToInteger(vm, receiver.toStringObject().str, 0, 8);
}

pub fn builtinStringHex(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return parseStringToInteger(vm, receiver.toStringObject().str, 16, 10);
}

fn appendSymbolErrorEscapedBytes(writer: anytype, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            '\r' => try writer.writeAll("\\r"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            '\x0b' => try writer.writeAll("\\v"),
            '\x00' => try writer.writeAll("\\0"),
            else => {
                if (c < 32 or c > 126) {
                    try std.fmt.format(writer, "\\x{X:0>2}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

pub fn builtinStringToSym(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();

    if (!string_obj.encoding.isValid(string_obj.str)) {
        var escaped_bytes: std.ArrayList(u8) = .empty;
        defer escaped_bytes.deinit(vm.allocator);
        const writer = escaped_bytes.writer(vm.allocator);
        appendSymbolErrorEscapedBytes(writer, string_obj.str) catch return error.Fatal;
        const escaped = escaped_bytes.toOwnedSlice(vm.allocator) catch return error.Fatal;
        defer vm.allocator.free(escaped);
        return vm.raiseExceptionFmt(vm.encoding_error_class, "invalid symbol in encoding {s} :\"{s}\"", .{ string_obj.encoding.name(), escaped });
    }

    const symbol_encoding: enc.Encoding = if (string_obj.encoding.isAsciiCompatible() and enc.isAsciiOnly(string_obj.str))
        .{ .us_ascii = .{} }
    else
        string_obj.encoding;
    const sym = try vm.internWithEncoding(string_obj.str, symbol_encoding);
    return Value.fromObject(sym);
}

pub fn builtinStringInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const str = inspect_util.inspectStringBytes(vm.allocator, string_obj.str, string_obj.encoding, vm.inspectTargetEncoding()) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, vm.inspectTargetEncoding());
}

pub fn builtinStringMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isRegexp()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "type mismatch: String given", .{});
    }
    return regexp_builtin.regexpMatchOp(vm, args[0].toRegexpObject(), receiver);
}

pub fn builtinStringMatch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isRegexp()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type", .{});
    }

    const match_idx = try regexp_builtin.regexpMatchOp(vm, args[0].toRegexpObject(), receiver);
    if (match_idx.isNil()) return Value.nil();

    const md_val = vm.globals.get("$~") orelse Value.nil();
    if (block) |blk| {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{md_val});
        if (yielded.break_occurred) return yielded.value;
        return yielded.value;
    }
    return md_val;
}

fn escapeRegexpLiteral(vm: *VM, bytes: []const u8) VMError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    for (bytes) |b| {
        switch (b) {
            '\\', '.', '^', '$', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}' => {
                out.append(vm.allocator, '\\') catch return error.Fatal;
                out.append(vm.allocator, b) catch return error.Fatal;
            },
            else => out.append(vm.allocator, b) catch return error.Fatal,
        }
    }

    return out.toOwnedSlice(vm.allocator) catch return error.Fatal;
}

pub fn builtinStringScan(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();
    const out = if (block == null) try vm.createArray() else null;
    var offset: usize = 0;
    var last_success_md: ?*value.MatchDataObject = null;

    if (args[0].isRegexp()) {
        const regexp_obj = args[0].toRegexpObject();

        while (offset <= string_obj.str.len) {
            const base_offset = offset;
            const sub = try vm.newStringWithEncoding(string_obj.str[base_offset..], false, string_obj.encoding);
            const match_idx = try regexp_builtin.regexpMatchOp(vm, regexp_obj, sub);
            if (match_idx.isNil()) break;

            const last_match = vm.globals.get("$~") orelse Value.nil();
            if (!last_match.isMatchData()) break;
            const md = last_match.toMatchDataObject();

            const base_i64: i64 = @intCast(base_offset);
            for (md.begin_byte_offsets.items) |*begin_pos| {
                if (begin_pos.* >= 0) begin_pos.* += base_i64;
            }
            for (md.end_byte_offsets.items) |*end_pos| {
                if (end_pos.* >= 0) end_pos.* += base_i64;
            }
            md.source = string_obj;
            try vm.setLastMatch(md);
            last_success_md = md;

            const yielded_value = if (md.captures.items.len <= 1)
                md.captures.items[0]
            else blk: {
                const captures = try vm.createArray();
                for (md.captures.items[1..]) |capture| {
                    captures.elements.append(vm.gc_allocator, capture) catch return error.Fatal;
                }
                break :blk Value.fromObject(captures);
            };

            if (block) |blk| {
                const yielded = try vm.yieldToBlock(blk, &[_]Value{yielded_value});
                if (yielded.break_occurred) return yielded.value;
                try vm.setLastMatch(md);
            } else {
                out.?.elements.append(vm.gc_allocator, yielded_value) catch return error.Fatal;
            }

            const end_offset_i64 = if (md.end_byte_offsets.items.len > 0) md.end_byte_offsets.items[0] else -1;
            const end_offset: usize = if (end_offset_i64 >= 0) @intCast(end_offset_i64) else base_offset;
            if (end_offset <= base_offset) {
                if (base_offset >= string_obj.str.len) {
                    offset = string_obj.str.len + 1;
                } else {
                    var next = base_offset;
                    const ch = string_obj.encoding.nextChar(string_obj.str, &next);
                    offset = if (ch.len > 0 and next > base_offset) next else base_offset + 1;
                }
            } else {
                offset = end_offset;
            }
        }
    } else {
        const pattern_value = try args[0].coerceToStringValue(vm, "wrong argument type");
        const pattern = pattern_value.toStringObject().str;
        const escaped_pattern = try escapeRegexpLiteral(vm, pattern);
        defer vm.allocator.free(escaped_pattern);
        const pattern_regexp = (try vm.newRegexp(escaped_pattern, 0)).toRegexpObject();

        while (offset <= string_obj.str.len) {
            const base_offset = offset;
            const match_start = if (pattern.len == 0)
                base_offset
            else
                std.mem.indexOfPos(u8, string_obj.str, base_offset, pattern) orelse break;
            const match_end = match_start + pattern.len;

            const match_str = try vm.newStringWithEncoding(string_obj.str[match_start..match_end], false, string_obj.encoding);
            const captures = [_]Value{match_str};
            const begins = [_]i64{@intCast(match_start)};
            const ends = [_]i64{@intCast(match_end)};
            const md_val = try vm.newMatchData(pattern_regexp, string_obj, captures[0..], begins[0..], ends[0..]);
            const md = md_val.toMatchDataObject();
            try vm.setLastMatch(md);
            last_success_md = md;

            if (block) |blk| {
                const yielded = try vm.yieldToBlock(blk, &[_]Value{match_str});
                if (yielded.break_occurred) return yielded.value;
                try vm.setLastMatch(md);
            } else {
                out.?.elements.append(vm.gc_allocator, match_str) catch return error.Fatal;
            }

            if (match_end <= base_offset) {
                if (base_offset >= string_obj.str.len) {
                    offset = string_obj.str.len + 1;
                } else {
                    var next = base_offset;
                    const ch = string_obj.encoding.nextChar(string_obj.str, &next);
                    offset = if (ch.len > 0 and next > base_offset) next else base_offset + 1;
                }
            } else {
                offset = match_end;
            }
        }
    }

    if (last_success_md) |md| {
        try vm.setLastMatch(md);
    } else {
        try vm.clearLastMatch();
    }

    if (block != null) return receiver;
    return Value.fromObject(out.?);
}

pub fn builtinStringUnpack(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    var keyword_offset: ?Value = null;
    try vm.consumeKeywordArgs(.{"offset"}, .{&keyword_offset});
    try vm.validateKeywordArgsConsumed();

    var offset: usize = 0;
    if (keyword_offset) |offset_value| {
        const offset_i64 = try offset_value.coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (offset_i64 < 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "offset can't be negative", .{});
        }

        offset = @intCast(offset_i64);
        if (offset > receiver.toStringObject().str.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "offset outside of string", .{});
        }
    }

    const format = try args[0].coerceToStr(vm, "no implicit conversion into String");
    return pack_runtime.stringUnpack(vm, receiver.toStringObject(), offset, format);
}

pub fn builtinStringUnpack1(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const unpacked = try builtinStringUnpack(vm, receiver, args, null);
    const unpacked_array = unpacked.toArrayObject();
    if (unpacked_array.elements.items.len == 0) return Value.nil();
    return unpacked_array.elements.items[0];
}

fn charSliceByRange(
    vm: *VM,
    bytes: []const u8,
    encoding: enc.Encoding,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
) VMError!?[]const u8 {
    const char_len_i64: i64 = @intCast(encoding.charCount(bytes));

    const begin_i64: i64 = if (begin_val.isInteger())
        begin_val.toInteger()
    else if (begin_val.isNil())
        0
    else
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});

    var start_idx = begin_i64;
    if (start_idx < 0) start_idx += char_len_i64;
    if (start_idx < 0 or start_idx > char_len_i64) return null;

    var finish_exclusive: i64 = if (end_val.isInteger()) blk: {
        var end_i64 = end_val.toInteger();
        if (end_i64 < 0) end_i64 += char_len_i64;
        break :blk if (exclude_end) end_i64 else end_i64 + 1;
    } else if (end_val.isNil())
        char_len_i64
    else
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});

    if (finish_exclusive < start_idx) {
        const start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(start_idx)) orelse bytes.len;
        return bytes[start_byte..start_byte];
    }

    if (finish_exclusive < 0) finish_exclusive = 0;
    if (finish_exclusive > char_len_i64) finish_exclusive = char_len_i64;

    const start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(start_idx)) orelse bytes.len;
    const end_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(finish_exclusive)) orelse bytes.len;
    return bytes[start_byte..end_byte];
}

fn byteSliceByRange(
    vm: *VM,
    bytes: []const u8,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
) VMError!?[]const u8 {
    const byte_len_i64: i64 = @intCast(bytes.len);

    const begin_i64: i64 = if (begin_val.isNil())
        0
    else
        try begin_val.coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );

    var start_idx = begin_i64;
    if (start_idx < 0) start_idx += byte_len_i64;
    if (start_idx < 0 or start_idx > byte_len_i64) return null;

    var finish_exclusive: i64 = if (end_val.isNil())
        byte_len_i64
    else blk: {
        var end_i64 = try end_val.coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (end_i64 < 0) end_i64 += byte_len_i64;
        if (exclude_end or end_i64 == std.math.maxInt(i64)) {
            break :blk end_i64;
        }
        break :blk end_i64 + 1;
    };

    if (finish_exclusive < start_idx) {
        const start_byte: usize = @intCast(start_idx);
        return bytes[start_byte..start_byte];
    }

    if (finish_exclusive < 0) finish_exclusive = 0;
    if (finish_exclusive > byte_len_i64) finish_exclusive = byte_len_i64;

    const start_byte: usize = @intCast(start_idx);
    const end_byte: usize = @intCast(finish_exclusive);
    return bytes[start_byte..end_byte];
}

fn spliceStringBytes(
    vm: *VM,
    receiver: Value,
    replace_start_byte: usize,
    replace_end_byte: usize,
    replacement: Value,
) VMError!void {
    const string_obj = receiver.toStringObject();
    if (replace_start_byte > replace_end_byte or replace_end_byte > string_obj.str.len) {
        return error.Fatal;
    }
    if (!replacement.isString()) {
        return error.Fatal;
    }

    const replacement_obj = replacement.toStringObject();
    const prefix = string_obj.str[0..replace_start_byte];
    const suffix = string_obj.str[replace_end_byte..];

    _ = resolveStringConcatEncoding(
        string_obj.encoding,
        string_obj.str,
        replacement_obj.encoding,
        replacement_obj.str,
    ) orelse {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), replacement_obj.encoding.name() },
        );
    };

    const interim_encoding = resolveStringConcatEncoding(
        string_obj.encoding,
        prefix,
        replacement_obj.encoding,
        replacement_obj.str,
    ) orelse {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), replacement_obj.encoding.name() },
        );
    };

    const prefix_with_replacement = try concatBytes(vm, prefix, replacement_obj.str);
    const result_encoding = resolveStringConcatEncoding(
        interim_encoding,
        prefix_with_replacement,
        string_obj.encoding,
        suffix,
    ) orelse {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ interim_encoding.name(), string_obj.encoding.name() },
        );
    };

    const result_bytes = try concatBytes(vm, prefix_with_replacement, suffix);
    string_obj.str = result_bytes;
    string_obj.encoding = result_encoding;
    string_obj.validity = .unknown;
}

fn concatBytes(vm: *VM, left: []const u8, right: []const u8) VMError![]const u8 {
    const new_len = left.len + right.len;
    const out = vm.gc_allocator_atomic.alloc(u8, new_len) catch return error.Fatal;
    @memcpy(out[0..left.len], left);
    @memcpy(out[left.len..], right);
    return out;
}

fn warnSymbolToSMutation(vm: *VM, string_obj: *value.StringObject) VMError!void {
    const sym = string_obj.symbol_to_s_source orelse return;
    if (!vm.warning_deprecated_enabled) return;
    const warning_text = std.fmt.allocPrint(
        vm.gc_allocator,
        "warning: string returned by :{s}.to_s will be frozen in the future\n",
        .{sym.name},
    ) catch return error.Fatal;
    try warning_builtin.writeWarning(vm, warning_text);
}

fn integerLeastSignificantByte(vm: *VM, arg: Value) VMError!u8 {
    if (arg.isInteger()) {
        const value_u64: u64 = @bitCast(arg.toInteger());
        return @truncate(value_u64);
    }
    if (arg.isBigInteger()) {
        const big_str = arg.toBigIntegerObject().value.toString(vm.allocator, 10, .lower) catch return error.Fatal;
        defer vm.allocator.free(big_str);

        var idx: usize = 0;
        var negative = false;
        if (big_str.len > 0 and big_str[0] == '-') {
            negative = true;
            idx = 1;
        }

        var modulo: u16 = 0;
        while (idx < big_str.len) : (idx += 1) {
            modulo = @intCast((@as(u32, modulo) * 10 + (big_str[idx] - '0')) % 256);
        }

        if (negative and modulo != 0) {
            modulo = 256 - modulo;
        }
        return @intCast(modulo);
    }
    return error.Fatal;
}
const ConcatSelfSnapshot = struct {
    bytes: []const u8,
    encoding: enc.Encoding,
};

fn appendSingleConcatArg(
    vm: *VM,
    receiver: Value,
    arg: Value,
    self_snapshot: ConcatSelfSnapshot,
) VMError!void {
    const string_obj = receiver.toStringObject();

    if (arg.isInteger() or arg.isBigInteger()) {
        const cp = try arg.integerArgToI64(vm, "no implicit conversion into Integer", "bignum too big to convert into `long`");
        if (cp < 0) {
            return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{cp});
        }

        // MRI treats US-ASCII receiver + byte values 128..255 as binary concatenation.
        if (string_obj.encoding == .us_ascii and cp >= 128 and cp <= 255) {
            const single_byte = [_]u8{@intCast(cp)};
            string_obj.str = try concatBytes(vm, string_obj.str, &single_byte);
            string_obj.encoding = .{ .ascii_8bit = .{} };
            string_obj.validity = .unknown;
            return;
        }

        var buf: [4]u8 = undefined;
        const encoded = try encodeCodepointForEncoding(vm, cp, string_obj.encoding, &buf);
        string_obj.str = try concatBytes(vm, string_obj.str, encoded);
        string_obj.validity = .unknown;
        return;
    }

    var rhs_bytes: []const u8 = undefined;
    var rhs_encoding: enc.Encoding = undefined;
    if (arg.isString() and arg.raw == receiver.raw) {
        rhs_bytes = self_snapshot.bytes;
        rhs_encoding = self_snapshot.encoding;
    } else {
        const rhs_value = try arg.coerceToStringValue(vm, "no implicit conversion into String");
        const rhs = rhs_value.toStringObject();
        rhs_bytes = rhs.str;
        rhs_encoding = rhs.encoding;
    }

    const result_encoding = resolveStringConcatEncoding(string_obj.encoding, string_obj.str, rhs_encoding, rhs_bytes) orelse {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), rhs_encoding.name() },
        );
    };

    string_obj.str = try concatBytes(vm, string_obj.str, rhs_bytes);
    string_obj.encoding = result_encoding;
    string_obj.validity = .unknown;
}

fn resolveStringConcatEncoding(
    lhs_encoding: enc.Encoding,
    lhs_bytes: []const u8,
    rhs_encoding: enc.Encoding,
    rhs_bytes: []const u8,
) ?enc.Encoding {
    if (lhs_encoding.eql(rhs_encoding)) return lhs_encoding;

    // Empty-string operands always inherit the other side's encoding.
    if (rhs_bytes.len == 0) return lhs_encoding;
    if (lhs_bytes.len == 0) return rhs_encoding;

    // Different ASCII-incompatible encodings are incompatible once both sides have content.
    if (!lhs_encoding.isAsciiCompatible() or !rhs_encoding.isAsciiCompatible()) return null;

    const lhs_ascii_only = enc.isAsciiOnly(lhs_bytes);
    const rhs_ascii_only = enc.isAsciiOnly(rhs_bytes);

    if (lhs_ascii_only and !rhs_ascii_only) return rhs_encoding;
    if (!lhs_ascii_only and rhs_ascii_only) return lhs_encoding;
    if (lhs_ascii_only and rhs_ascii_only) return lhs_encoding;

    return null;
}

fn encodeCodepointForEncoding(vm: *VM, cp: i64, encoding: enc.Encoding, out: *[4]u8) VMError![]const u8 {
    const codepoint: u32 = @intCast(cp);
    const len = encoding.fromUnicodeCodepoint(codepoint, out) orelse {
        return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{cp});
    };
    return out[0..len];
}

const CaseOperation = enum {
    upcase,
    downcase,
    capitalize,
};

fn parseCaseMapOptions(vm: *VM, args: []Value, operation: CaseOperation) VMError!enc.CaseMapOptions {
    try vm.requireArgCountRange(args, 0, 2);
    var options: enc.CaseMapOptions = .{};
    if (args.len == 0) return options;

    const ascii_sym = try vm.intern("ascii");
    const turkic_sym = try vm.intern("turkic");
    const lithuanian_sym = try vm.intern("lithuanian");
    const fold_sym = try vm.intern("fold");

    if (args.len == 1) {
        const opt = args[0];
        if (!opt.isSymbol()) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid option", .{});

        const symbol = opt.toSymbolObject();
        if (symbol == ascii_sym) {
            options.ascii_only = true;
            return options;
        }
        if (symbol == turkic_sym) {
            options.turkic = true;
            return options;
        }
        if (symbol == lithuanian_sym) {
            options.lithuanian = true;
            return options;
        }
        if (symbol == fold_sym) {
            if (operation == .downcase) {
                options.fold = true;
                return options;
            }
            return vm.raiseExceptionFmt(vm.argument_error_class, "option :fold only allowed for downcasing", .{});
        }
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid option", .{});
    }

    const first = args[0];
    const second = args[1];
    if (!first.isSymbol() or !second.isSymbol()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid option", .{});
    }
    const first_sym = first.toSymbolObject();
    const second_sym = second.toSymbolObject();
    const turk_lith = (first_sym == turkic_sym and second_sym == lithuanian_sym) or
        (first_sym == lithuanian_sym and second_sym == turkic_sym);
    if (!turk_lith) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid second option", .{});
    }
    options.turkic = true;
    options.lithuanian = true;
    return options;
}

fn digitValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'z') return c - 'a' + 10;
    if (c >= 'A' and c <= 'Z') return c - 'A' + 10;
    return null;
}
