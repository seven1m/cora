const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const inspect_util = @import("../inspect.zig");
const onigmo = @import("../onigmo.zig");
const encoding_builtin = @import("encoding.zig");
const regexp_builtin = @import("regexp.zig");
const rational_builtin = @import("rational.zig");
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
    const string_class_val = Value.fromObject(&vm.string_class.module.object);
    const string_singleton = try vm.getOrCreateSingletonClass(string_class_val);
    try string_singleton.module.methods.put(try_convert_sym, value.MethodEntry.builtin(&builtinStringTryConvert, .{ .exact = 1 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.string_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinStringInitialize, .{ .variadic = 0 }, .private));

    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.string_class.module.methods.put(initialize_copy_sym, value.MethodEntry.builtinWithVisibility(&builtinStringInitializeCopy, .{ .exact = 1 }, .private));

    const string_uplus_sym = try vm.intern("+@");
    try vm.string_class.module.methods.put(string_uplus_sym, value.MethodEntry.builtin(&builtinStringUnaryPlus, .{ .exact = 0 }));
    const string_uminus_sym = try vm.intern("-@");
    try vm.string_class.module.methods.put(string_uminus_sym, value.MethodEntry.builtin(&builtinStringDedup, .{ .exact = 0 }));

    const string_plus_sym = try vm.intern("+");
    try vm.string_class.module.methods.put(string_plus_sym, value.MethodEntry.builtin(&builtinStringPlus, .{ .exact = 1 }));

    const string_multiply_sym = try vm.intern("*");
    try vm.string_class.module.methods.put(string_multiply_sym, value.MethodEntry.builtin(&builtinStringMultiply, .{ .exact = 1 }));
    const string_percent_sym = try vm.intern("%");
    try vm.string_class.module.methods.put(string_percent_sym, value.MethodEntry.builtin(&builtinStringPercent, .{ .exact = 1 }));

    const string_append_sym = try vm.intern("<<");
    try vm.string_class.module.methods.put(string_append_sym, value.MethodEntry.builtin(&builtinStringAppend, .{ .exact = 1 }));

    const string_concat_sym = try vm.intern("concat");
    try vm.string_class.module.methods.put(string_concat_sym, value.MethodEntry.builtin(&builtinStringConcat, .{ .variadic = 0 }));
    const string_append_as_bytes_sym = try vm.intern("append_as_bytes");
    try vm.string_class.module.methods.put(string_append_as_bytes_sym, value.MethodEntry.builtin(&builtinStringAppendAsBytes, .{ .variadic = 0 }));

    const string_replace_sym = try vm.intern("replace");
    try vm.string_class.module.methods.put(string_replace_sym, value.MethodEntry.builtin(&builtinStringReplace, .{ .exact = 1 }));

    const string_gsub_sym = try vm.intern("gsub");
    try vm.string_class.module.methods.put(string_gsub_sym, value.MethodEntry.builtin(&builtinStringGsub, .{ .variadic = 0 }));
    const string_gsub_bang_sym = try vm.intern("gsub!");
    try vm.string_class.module.methods.put(string_gsub_bang_sym, value.MethodEntry.builtin(&builtinStringGsubBang, .{ .variadic = 0 }));
    const string_sub_sym = try vm.intern("sub");
    try vm.string_class.module.methods.put(string_sub_sym, value.MethodEntry.builtin(&builtinStringSub, .{ .variadic = 0 }));
    const string_sub_bang_sym = try vm.intern("sub!");
    try vm.string_class.module.methods.put(string_sub_bang_sym, value.MethodEntry.builtin(&builtinStringSubBang, .{ .variadic = 0 }));

    const string_equal_sym = try vm.intern("==");
    try vm.string_class.module.methods.put(string_equal_sym, value.MethodEntry.builtin(&builtinStringEqual, .{ .exact = 1 }));

    const string_eql_sym = try vm.intern("eql?");
    try vm.string_class.module.methods.put(string_eql_sym, value.MethodEntry.builtin(&builtinStringEql, .{ .exact = 1 }));

    const string_hash_sym = try vm.intern("hash");
    try vm.string_class.module.methods.put(string_hash_sym, value.MethodEntry.builtin(&builtinStringHash, .{ .exact = 0 }));

    const string_not_equal_sym = try vm.intern("!=");
    try vm.string_class.module.methods.put(string_not_equal_sym, value.MethodEntry.builtin(&builtinStringNotEqual, .{ .exact = 1 }));

    const string_compare_sym = try vm.intern("<=>");
    try vm.string_class.module.methods.put(string_compare_sym, value.MethodEntry.builtin(&builtinStringCompare, .{ .exact = 1 }));
    const string_casecmp_sym = try vm.intern("casecmp");
    try vm.string_class.module.methods.put(string_casecmp_sym, value.MethodEntry.builtin(&builtinStringCasecmp, .{ .exact = 1 }));
    const string_casecmp_pred_sym = try vm.intern("casecmp?");
    try vm.string_class.module.methods.put(string_casecmp_pred_sym, value.MethodEntry.builtin(&builtinStringCasecmpQ, .{ .exact = 1 }));

    const string_encoding_sym = try vm.intern("encoding");
    try vm.string_class.module.methods.put(string_encoding_sym, value.MethodEntry.builtin(&builtinStringEncoding, .{ .exact = 0 }));

    const string_encode_sym = try vm.intern("encode");
    try vm.string_class.module.methods.put(string_encode_sym, value.MethodEntry.builtin(&builtinStringEncode, .{ .variadic = 0 }));

    const string_encode_bang_sym = try vm.intern("encode!");
    try vm.string_class.module.methods.put(string_encode_bang_sym, value.MethodEntry.builtin(&builtinStringEncodeBang, .{ .variadic = 0 }));

    const string_force_encoding_sym = try vm.intern("force_encoding");
    try vm.string_class.module.methods.put(string_force_encoding_sym, value.MethodEntry.builtin(&builtinStringForceEncoding, .{ .exact = 1 }));

    const string_unicode_normalize_sym = try vm.intern("unicode_normalize");
    try vm.string_class.module.methods.put(string_unicode_normalize_sym, value.MethodEntry.builtin(&builtinStringUnicodeNormalize, .{ .variadic = 0 }));

    const string_valid_encoding_sym = try vm.intern("valid_encoding?");
    try vm.string_class.module.methods.put(string_valid_encoding_sym, value.MethodEntry.builtin(&builtinStringValidEncoding, .{ .exact = 0 }));

    const string_ascii_only_sym = try vm.intern("ascii_only?");
    try vm.string_class.module.methods.put(string_ascii_only_sym, value.MethodEntry.builtin(&builtinStringAsciiOnly, .{ .exact = 0 }));

    const string_b_sym = try vm.intern("b");
    try vm.string_class.module.methods.put(string_b_sym, value.MethodEntry.builtin(&builtinStringB, .{ .exact = 0 }));
    const string_dedup_sym = try vm.intern("dedup");
    try vm.string_class.module.methods.put(string_dedup_sym, value.MethodEntry.builtin(&builtinStringDedup, .{ .exact = 0 }));

    const string_dup_sym = try vm.intern("dup");
    try vm.string_class.module.methods.put(string_dup_sym, value.MethodEntry.builtin(&builtinStringDup, .{ .exact = 0 }));

    const string_clone_sym = try vm.intern("clone");
    try vm.string_class.module.methods.put(string_clone_sym, value.MethodEntry.builtin(&builtinStringClone, .{ .variadic = 0 }));

    const string_bytesize_sym = try vm.intern("bytesize");
    try vm.string_class.module.methods.put(string_bytesize_sym, value.MethodEntry.builtin(&builtinStringBytesize, .{ .exact = 0 }));

    const string_length_sym = try vm.intern("length");
    try vm.string_class.module.methods.put(string_length_sym, value.MethodEntry.builtin(&builtinStringLength, .{ .exact = 0 }));

    const string_size_sym = try vm.intern("size");
    try vm.string_class.module.methods.put(string_size_sym, value.MethodEntry.builtin(&builtinStringLength, .{ .exact = 0 }));

    const string_count_sym = try vm.intern("count");
    try vm.string_class.module.methods.put(string_count_sym, value.MethodEntry.builtin(&builtinStringCount, .{ .variadic = 1 }));

    const string_empty_sym = try vm.intern("empty?");
    try vm.string_class.module.methods.put(string_empty_sym, value.MethodEntry.builtin(&builtinStringEmpty, .{ .exact = 0 }));

    const string_clear_sym = try vm.intern("clear");
    try vm.string_class.module.methods.put(string_clear_sym, value.MethodEntry.builtin(&builtinStringClear, .{ .exact = 0 }));
    const string_chop_sym = try vm.intern("chop");
    try vm.string_class.module.methods.put(string_chop_sym, value.MethodEntry.builtin(&builtinStringChop, .{ .exact = 0 }));
    const string_chop_bang_sym = try vm.intern("chop!");
    try vm.string_class.module.methods.put(string_chop_bang_sym, value.MethodEntry.builtin(&builtinStringChopBang, .{ .exact = 0 }));
    const string_chomp_sym = try vm.intern("chomp");
    try vm.string_class.module.methods.put(string_chomp_sym, value.MethodEntry.builtin(&builtinStringChomp, .{ .variadic = 0 }));
    const string_chomp_bang_sym = try vm.intern("chomp!");
    try vm.string_class.module.methods.put(string_chomp_bang_sym, value.MethodEntry.builtin(&builtinStringChompBang, .{ .variadic = 0 }));

    const string_ord_sym = try vm.intern("ord");
    try vm.string_class.module.methods.put(string_ord_sym, value.MethodEntry.builtin(&builtinStringOrd, .{ .exact = 0 }));

    const string_chr_sym = try vm.intern("chr");
    try vm.string_class.module.methods.put(string_chr_sym, value.MethodEntry.builtin(&builtinStringChr, .{ .exact = 0 }));

    const string_bracket_sym = try vm.intern("[]");
    try vm.string_class.module.methods.put(string_bracket_sym, value.MethodEntry.builtin(&builtinStringBracket, .{ .variadic = 0 }));

    const string_slice_sym = try vm.intern("slice");
    try vm.string_class.module.methods.put(string_slice_sym, value.MethodEntry.builtin(&builtinStringSlice, .{ .variadic = 0 }));
    const string_slice_bang_sym = try vm.intern("slice!");
    try vm.string_class.module.methods.put(string_slice_bang_sym, value.MethodEntry.builtin(&builtinStringSliceBang, .{ .variadic = 0 }));

    const string_bracket_set_sym = try vm.intern("[]=");
    try vm.string_class.module.methods.put(string_bracket_set_sym, value.MethodEntry.builtin(&builtinStringBracketSet, .{ .variadic = 0 }));

    const string_byteslice_sym = try vm.intern("byteslice");
    try vm.string_class.module.methods.put(string_byteslice_sym, value.MethodEntry.builtin(&builtinStringByteSlice, .{ .variadic = 0 }));

    const string_chars_sym = try vm.intern("chars");
    try vm.string_class.module.methods.put(string_chars_sym, value.MethodEntry.builtin(&builtinStringChars, .{ .exact = 0 }));

    const string_each_char_sym = try vm.intern("each_char");
    try vm.string_class.module.methods.put(string_each_char_sym, value.MethodEntry.builtin(&builtinStringEachChar, .{ .exact = 0 }));

    const string_bytes_sym = try vm.intern("bytes");
    try vm.string_class.module.methods.put(string_bytes_sym, value.MethodEntry.builtin(&builtinStringBytes, .{ .exact = 0 }));

    const string_each_byte_sym = try vm.intern("each_byte");
    try vm.string_class.module.methods.put(string_each_byte_sym, value.MethodEntry.builtin(&builtinStringEachByte, .{ .exact = 0 }));

    const string_getbyte_sym = try vm.intern("getbyte");
    try vm.string_class.module.methods.put(string_getbyte_sym, value.MethodEntry.builtin(&builtinStringGetbyte, .{ .exact = 1 }));

    const string_setbyte_sym = try vm.intern("setbyte");
    try vm.string_class.module.methods.put(string_setbyte_sym, value.MethodEntry.builtin(&builtinStringSetbyte, .{ .exact = 2 }));

    const string_insert_sym = try vm.intern("insert");
    try vm.string_class.module.methods.put(string_insert_sym, value.MethodEntry.builtin(&builtinStringInsert, .{ .exact = 2 }));

    const string_codepoints_sym = try vm.intern("codepoints");
    try vm.string_class.module.methods.put(string_codepoints_sym, value.MethodEntry.builtin(&builtinStringCodepoints, .{ .exact = 0 }));

    const string_each_codepoint_sym = try vm.intern("each_codepoint");
    try vm.string_class.module.methods.put(string_each_codepoint_sym, value.MethodEntry.builtin(&builtinStringEachCodepoint, .{ .exact = 0 }));

    const string_each_line_sym = try vm.intern("each_line");
    try vm.string_class.module.methods.put(string_each_line_sym, value.MethodEntry.builtin(&builtinStringEachLine, .{ .variadic = 0 }));

    const string_lines_sym = try vm.intern("lines");
    try vm.string_class.module.methods.put(string_lines_sym, value.MethodEntry.builtin(&builtinStringLines, .{ .variadic = 0 }));

    const string_start_with_sym = try vm.intern("start_with?");
    try vm.string_class.module.methods.put(string_start_with_sym, value.MethodEntry.builtin(&builtinStringStartWith, .{ .variadic = 0 }));

    const string_end_with_sym = try vm.intern("end_with?");
    try vm.string_class.module.methods.put(string_end_with_sym, value.MethodEntry.builtin(&builtinStringEndWith, .{ .variadic = 0 }));

    const string_delete_prefix_sym = try vm.intern("delete_prefix");
    try vm.string_class.module.methods.put(string_delete_prefix_sym, value.MethodEntry.builtin(&builtinStringDeletePrefix, .{ .exact = 1 }));

    const string_delete_prefix_bang_sym = try vm.intern("delete_prefix!");
    try vm.string_class.module.methods.put(string_delete_prefix_bang_sym, value.MethodEntry.builtin(&builtinStringDeletePrefixBang, .{ .exact = 1 }));

    const string_delete_suffix_sym = try vm.intern("delete_suffix");
    try vm.string_class.module.methods.put(string_delete_suffix_sym, value.MethodEntry.builtin(&builtinStringDeleteSuffix, .{ .exact = 1 }));

    const string_delete_suffix_bang_sym = try vm.intern("delete_suffix!");
    try vm.string_class.module.methods.put(string_delete_suffix_bang_sym, value.MethodEntry.builtin(&builtinStringDeleteSuffixBang, .{ .exact = 1 }));

    const string_delete_sym = try vm.intern("delete");
    try vm.string_class.module.methods.put(string_delete_sym, value.MethodEntry.builtin(&builtinStringDelete, .{ .variadic = 0 }));
    const string_delete_bang_sym = try vm.intern("delete!");
    try vm.string_class.module.methods.put(string_delete_bang_sym, value.MethodEntry.builtin(&builtinStringDeleteBang, .{ .variadic = 0 }));

    const string_tr_sym = try vm.intern("tr");
    try vm.string_class.module.methods.put(string_tr_sym, value.MethodEntry.builtin(&builtinStringTr, .{ .exact = 2 }));
    const string_tr_bang_sym = try vm.intern("tr!");
    try vm.string_class.module.methods.put(string_tr_bang_sym, value.MethodEntry.builtin(&builtinStringTrBang, .{ .exact = 2 }));

    const string_tr_s_sym = try vm.intern("tr_s");
    try vm.string_class.module.methods.put(string_tr_s_sym, value.MethodEntry.builtin(&builtinStringTrS, .{ .exact = 2 }));
    const string_tr_s_bang_sym = try vm.intern("tr_s!");
    try vm.string_class.module.methods.put(string_tr_s_bang_sym, value.MethodEntry.builtin(&builtinStringTrSBang, .{ .exact = 2 }));

    const string_squeeze_sym = try vm.intern("squeeze");
    try vm.string_class.module.methods.put(string_squeeze_sym, value.MethodEntry.builtin(&builtinStringSqueeze, .{ .variadic = 0 }));
    const string_squeeze_bang_sym = try vm.intern("squeeze!");
    try vm.string_class.module.methods.put(string_squeeze_bang_sym, value.MethodEntry.builtin(&builtinStringSqueezeBang, .{ .variadic = 0 }));

    const string_include_sym = try vm.intern("include?");
    try vm.string_class.module.methods.put(string_include_sym, value.MethodEntry.builtin(&builtinStringInclude, .{ .exact = 1 }));

    const string_index_sym = try vm.intern("index");
    try vm.string_class.module.methods.put(string_index_sym, value.MethodEntry.builtin(&builtinStringIndex, .{ .variadic = 0 }));

    const string_rindex_sym = try vm.intern("rindex");
    try vm.string_class.module.methods.put(string_rindex_sym, value.MethodEntry.builtin(&builtinStringRindex, .{ .variadic = 0 }));

    const string_partition_sym = try vm.intern("partition");
    try vm.string_class.module.methods.put(string_partition_sym, value.MethodEntry.builtin(&builtinStringPartition, .{ .exact = 1 }));
    const string_rpartition_sym = try vm.intern("rpartition");
    try vm.string_class.module.methods.put(string_rpartition_sym, value.MethodEntry.builtin(&builtinStringRpartition, .{ .exact = 1 }));

    const string_prepend_sym = try vm.intern("prepend");
    try vm.string_class.module.methods.put(string_prepend_sym, value.MethodEntry.builtin(&builtinStringPrepend, .{ .variadic = 0 }));

    const string_split_sym = try vm.intern("split");
    try vm.string_class.module.methods.put(string_split_sym, value.MethodEntry.builtin(&builtinStringSplit, .{ .variadic = 0 }));

    const string_strip_sym = try vm.intern("strip");
    try vm.string_class.module.methods.put(string_strip_sym, value.MethodEntry.builtin(&builtinStringStrip, .{ .exact = 0 }));
    const string_strip_bang_sym = try vm.intern("strip!");
    try vm.string_class.module.methods.put(string_strip_bang_sym, value.MethodEntry.builtin(&builtinStringStripBang, .{ .exact = 0 }));

    const string_lstrip_sym = try vm.intern("lstrip");
    try vm.string_class.module.methods.put(string_lstrip_sym, value.MethodEntry.builtin(&builtinStringLstrip, .{ .exact = 0 }));
    const string_lstrip_bang_sym = try vm.intern("lstrip!");
    try vm.string_class.module.methods.put(string_lstrip_bang_sym, value.MethodEntry.builtin(&builtinStringLstripBang, .{ .exact = 0 }));

    const string_rstrip_sym = try vm.intern("rstrip");
    try vm.string_class.module.methods.put(string_rstrip_sym, value.MethodEntry.builtin(&builtinStringRstrip, .{ .exact = 0 }));
    const string_rstrip_bang_sym = try vm.intern("rstrip!");
    try vm.string_class.module.methods.put(string_rstrip_bang_sym, value.MethodEntry.builtin(&builtinStringRstripBang, .{ .exact = 0 }));

    const string_center_sym = try vm.intern("center");
    try vm.string_class.module.methods.put(string_center_sym, value.MethodEntry.builtin(&builtinStringCenter, .{ .variadic = 0 }));

    const string_ljust_sym = try vm.intern("ljust");
    try vm.string_class.module.methods.put(string_ljust_sym, value.MethodEntry.builtin(&builtinStringLjust, .{ .variadic = 0 }));

    const string_rjust_sym = try vm.intern("rjust");
    try vm.string_class.module.methods.put(string_rjust_sym, value.MethodEntry.builtin(&builtinStringRjust, .{ .variadic = 0 }));

    const string_reverse_sym = try vm.intern("reverse");
    try vm.string_class.module.methods.put(string_reverse_sym, value.MethodEntry.builtin(&builtinStringReverse, .{ .exact = 0 }));
    const string_reverse_bang_sym = try vm.intern("reverse!");
    try vm.string_class.module.methods.put(string_reverse_bang_sym, value.MethodEntry.builtin(&builtinStringReverseBang, .{ .exact = 0 }));

    const string_upcase_sym = try vm.intern("upcase");
    try vm.string_class.module.methods.put(string_upcase_sym, value.MethodEntry.builtin(&builtinStringUpcase, .{ .variadic = 0 }));
    const string_upcase_bang_sym = try vm.intern("upcase!");
    try vm.string_class.module.methods.put(string_upcase_bang_sym, value.MethodEntry.builtin(&builtinStringUpcaseBang, .{ .variadic = 0 }));
    const string_downcase_sym = try vm.intern("downcase");
    try vm.string_class.module.methods.put(string_downcase_sym, value.MethodEntry.builtin(&builtinStringDowncase, .{ .variadic = 0 }));
    const string_downcase_bang_sym = try vm.intern("downcase!");
    try vm.string_class.module.methods.put(string_downcase_bang_sym, value.MethodEntry.builtin(&builtinStringDowncaseBang, .{ .variadic = 0 }));
    const string_swapcase_sym = try vm.intern("swapcase");
    try vm.string_class.module.methods.put(string_swapcase_sym, value.MethodEntry.builtin(&builtinStringSwapcase, .{ .variadic = 0 }));
    const string_swapcase_bang_sym = try vm.intern("swapcase!");
    try vm.string_class.module.methods.put(string_swapcase_bang_sym, value.MethodEntry.builtin(&builtinStringSwapcaseBang, .{ .variadic = 0 }));
    const string_capitalize_sym = try vm.intern("capitalize");
    try vm.string_class.module.methods.put(string_capitalize_sym, value.MethodEntry.builtin(&builtinStringCapitalize, .{ .variadic = 0 }));
    const string_capitalize_bang_sym = try vm.intern("capitalize!");
    try vm.string_class.module.methods.put(string_capitalize_bang_sym, value.MethodEntry.builtin(&builtinStringCapitalizeBang, .{ .variadic = 0 }));
    const string_succ_sym = try vm.intern("succ");
    try vm.string_class.module.methods.put(string_succ_sym, value.MethodEntry.builtin(&builtinStringNext, .{ .exact = 0 }));
    const string_succ_bang_sym = try vm.intern("succ!");
    try vm.string_class.module.methods.put(string_succ_bang_sym, value.MethodEntry.builtin(&builtinStringNextBang, .{ .exact = 0 }));
    const string_next_sym = try vm.intern("next");
    try vm.string_class.module.methods.put(string_next_sym, value.MethodEntry.builtin(&builtinStringNext, .{ .exact = 0 }));
    const string_next_bang_sym = try vm.intern("next!");
    try vm.string_class.module.methods.put(string_next_bang_sym, value.MethodEntry.builtin(&builtinStringNextBang, .{ .exact = 0 }));

    const string_to_i_sym = try vm.intern("to_i");
    try vm.string_class.module.methods.put(string_to_i_sym, value.MethodEntry.builtin(&builtinStringToI, .{ .variadic = 0 }));

    const string_to_f_sym = try vm.intern("to_f");
    try vm.string_class.module.methods.put(string_to_f_sym, value.MethodEntry.builtin(&builtinStringToF, .{ .exact = 0 }));

    const string_to_r_sym = try vm.intern("to_r");
    try vm.string_class.module.methods.put(string_to_r_sym, value.MethodEntry.builtin(&builtinStringToR, .{ .exact = 0 }));

    const string_oct_sym = try vm.intern("oct");
    try vm.string_class.module.methods.put(string_oct_sym, value.MethodEntry.builtin(&builtinStringOct, .{ .exact = 0 }));

    const string_hex_sym = try vm.intern("hex");
    try vm.string_class.module.methods.put(string_hex_sym, value.MethodEntry.builtin(&builtinStringHex, .{ .exact = 0 }));

    const string_to_sym_sym = try vm.intern("to_sym");
    try vm.string_class.module.methods.put(string_to_sym_sym, value.MethodEntry.builtin(&builtinStringToSym, .{ .exact = 0 }));

    const string_intern_sym = try vm.intern("intern");
    try vm.string_class.module.methods.put(string_intern_sym, value.MethodEntry.builtin(&builtinStringToSym, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.string_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinStringToS, .{ .exact = 0 }));

    const to_str_sym = try vm.intern("to_str");
    try vm.string_class.module.methods.put(to_str_sym, value.MethodEntry.builtin(&builtinStringToStr, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.string_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinStringInspect, .{ .exact = 0 }));
    const dump_sym = try vm.intern("dump");
    try vm.string_class.module.methods.put(dump_sym, value.MethodEntry.builtin(&builtinStringDump, .{ .exact = 0 }));

    const sum_sym = try vm.intern("sum");
    try vm.string_class.module.methods.put(sum_sym, value.MethodEntry.builtin(&builtinStringSum, .{ .variadic = 0 }));

    const match_op_sym = try vm.intern("=~");
    try vm.string_class.module.methods.put(match_op_sym, value.MethodEntry.builtin(&builtinStringMatchOp, .{ .exact = 1 }));

    const match_sym = try vm.intern("match");
    try vm.string_class.module.methods.put(match_sym, value.MethodEntry.builtin(&builtinStringMatch, .{ .variadic = 0 }));

    const match_q_sym = try vm.intern("match?");
    try vm.string_class.module.methods.put(match_q_sym, value.MethodEntry.builtin(&builtinStringMatchQ, .{ .variadic = 0 }));

    const scan_sym = try vm.intern("scan");
    try vm.string_class.module.methods.put(scan_sym, value.MethodEntry.builtin(&builtinStringScan, .{ .exact = 1 }));

    const unpack_sym = try vm.intern("unpack");
    try vm.string_class.module.methods.put(unpack_sym, value.MethodEntry.builtin(&builtinStringUnpack, .{ .variadic = 1 }));

    const unpack1_sym = try vm.intern("unpack1");
    try vm.string_class.module.methods.put(unpack1_sym, value.MethodEntry.builtin(&builtinStringUnpack1, .{ .variadic = 1 }));
}

const StringPercentFlags = struct {
    left_justify: bool = false,
    show_sign: bool = false,
    leading_space: bool = false,
    zero_pad: bool = false,
    alternate_form: bool = false,
};

const StringPercentSpec = struct {
    flags: StringPercentFlags = .{},
    width: ?usize = null,
    precision: ?usize = null,
    conversion: u8,
};

fn malformedStringPercent(vm: *VM) VMError {
    return vm.raiseExceptionFmt(vm.argument_error_class, "malformed format string - %", .{});
}

fn parseStringPercentNumber(format: []const u8, index: *usize) !?usize {
    const start = index.*;
    var value_num: usize = 0;
    while (index.* < format.len and std.ascii.isDigit(format[index.*])) : (index.* += 1) {
        value_num = try std.math.mul(usize, value_num, 10);
        value_num = try std.math.add(usize, value_num, format[index.*] - '0');
    }
    if (index.* == start) return null;
    return value_num;
}

fn parseStringPercentSpec(vm: *VM, format: []const u8, index: *usize) VMError!StringPercentSpec {
    var spec: StringPercentSpec = .{ .conversion = 0 };
    while (index.* < format.len) : (index.* += 1) {
        switch (format[index.*]) {
            '-' => spec.flags.left_justify = true,
            '+' => spec.flags.show_sign = true,
            ' ' => spec.flags.leading_space = true,
            '0' => spec.flags.zero_pad = true,
            '#' => spec.flags.alternate_form = true,
            else => break,
        }
    }

    spec.width = parseStringPercentNumber(format, index) catch return malformedStringPercent(vm);

    if (index.* < format.len and format[index.*] == '.') {
        index.* += 1;
        spec.precision = parseStringPercentNumber(format, index) catch return malformedStringPercent(vm);
        if (spec.precision == null) return malformedStringPercent(vm);
    }

    if (index.* >= format.len) return malformedStringPercent(vm);
    spec.conversion = format[index.*];
    switch (spec.conversion) {
        '%', 'B', 'X', 'b', 'c', 'd', 'e', 'E', 'f', 'g', 'G', 'i', 'o', 'p', 's', 'u', 'x' => {},
        else => return malformedStringPercent(vm),
    }
    index.* += 1;
    return spec;
}

fn appendRepeatedByte(out: *std.ArrayList(u8), allocator: std.mem.Allocator, byte: u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try out.append(allocator, byte);
    }
}

fn appendStringPercentFragment(
    vm: *VM,
    out: *std.ArrayList(u8),
    result_encoding: *enc.Encoding,
    bytes: []const u8,
    bytes_encoding: enc.Encoding,
) VMError!void {
    const next_encoding = resolveStringConcatEncoding(result_encoding.*, out.items, bytes_encoding, bytes) orelse {
        return vm.raiseEncodingCompatibilityError(result_encoding.*, bytes_encoding);
    };
    result_encoding.* = next_encoding;
    out.appendSlice(vm.gc_allocator_atomic, bytes) catch return error.Fatal;
}

fn coerceStringPercentInteger(vm: *VM, arg: Value) VMError!Value {
    if (arg.isInteger() or arg.isBigInteger()) return arg;

    if (try vm.checkCallMethodByName(arg, "to_int", false, &[_]Value{}, null)) |coerced| {
        if (coerced.isInteger() or coerced.isBigInteger()) return coerced;
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Integer ({s}#to_int gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(coerced) },
        );
    }

    if (try vm.checkCallMethodByName(arg, "to_i", false, &[_]Value{}, null)) |coerced| {
        if (coerced.isInteger() or coerced.isBigInteger()) return coerced;
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Integer ({s}#to_i gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(coerced) },
        );
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Integer", .{vm.className(arg)});
}

fn appendStringPercentPaddedText(
    vm: *VM,
    out: *std.ArrayList(u8),
    result_encoding: *enc.Encoding,
    spec: StringPercentSpec,
    bytes: []const u8,
    bytes_encoding: enc.Encoding,
) VMError!void {
    const width = spec.width orelse 0;
    const pad_len = if (width > bytes.len) width - bytes.len else 0;
    if (!spec.flags.left_justify) {
        appendRepeatedByte(out, vm.gc_allocator_atomic, ' ', pad_len) catch return error.Fatal;
    }
    try appendStringPercentFragment(vm, out, result_encoding, bytes, bytes_encoding);
    if (spec.flags.left_justify) {
        appendRepeatedByte(out, vm.gc_allocator_atomic, ' ', pad_len) catch return error.Fatal;
    }
}

fn coerceStringPercentFloat(vm: *VM, arg: Value) VMError!Value {
    if (arg.isFloat()) return arg;

    if (try vm.checkCallMethodByName(arg, "to_f", false, &[_]Value{}, null)) |coerced| {
        if (coerced.isFloat()) return coerced;
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
}

fn appendStringPercentFloat(
    vm: *VM,
    out: *std.ArrayList(u8),
    result_encoding: *enc.Encoding,
    spec: StringPercentSpec,
    arg: Value,
) VMError!void {
    const float_val = try coerceStringPercentFloat(vm, arg);
    const f = float_val.toFloatObject().val;

    if (std.math.isNan(f)) {
        try appendStringPercentPaddedText(vm, out, result_encoding, spec, "NaN", .{ .us_ascii = .{} });
        return;
    }
    if (std.math.isPositiveInf(f)) {
        try appendStringPercentPaddedText(vm, out, result_encoding, spec, "Infinity", .{ .us_ascii = .{} });
        return;
    }
    if (std.math.isNegativeInf(f)) {
        try appendStringPercentPaddedText(vm, out, result_encoding, spec, "-Infinity", .{ .us_ascii = .{} });
        return;
    }

    const string_val = try vm.callMethodByName(float_val, "to_s", &[_]Value{}, null);
    const string_obj = string_val.toStringObject();
    var str = string_obj.str;

    // Truncate or extend decimal places to match precision
    const precision = spec.precision orelse 6;
    if (std.mem.indexOfScalar(u8, str, '.')) |dot| {
        const actual_frac = str.len - dot - 1;
        if (actual_frac > precision) {
            str = str[0 .. dot + 1 + precision];
        } else if (actual_frac < precision) {
            var adjusted: std.ArrayList(u8) = .empty;
            defer adjusted.deinit(vm.gc_allocator_atomic);
            adjusted.appendSlice(vm.gc_allocator_atomic, str) catch return error.Fatal;
            var i: usize = actual_frac;
            while (i < precision) : (i += 1) {
                adjusted.append(vm.gc_allocator_atomic, '0') catch return error.Fatal;
            }
            str = adjusted.items;
        }
    } else if (precision > 0) {
        var adjusted: std.ArrayList(u8) = .empty;
        defer adjusted.deinit(vm.gc_allocator_atomic);
        adjusted.appendSlice(vm.gc_allocator_atomic, str) catch return error.Fatal;
        adjusted.append(vm.gc_allocator_atomic, '.') catch return error.Fatal;
        var i: usize = 0;
        while (i < precision) : (i += 1) {
            adjusted.append(vm.gc_allocator_atomic, '0') catch return error.Fatal;
        }
        str = adjusted.items;
    }

    try appendStringPercentPaddedText(vm, out, result_encoding, spec, str, string_obj.encoding);
}

fn appendStringPercentInteger(
    vm: *VM,
    out: *std.ArrayList(u8),
    result_encoding: *enc.Encoding,
    spec: StringPercentSpec,
    arg: Value,
    base: u8,
    uppercase: bool,
) VMError!void {
    const integer_value = try coerceStringPercentInteger(vm, arg);
    var base_args = [_]Value{Value.integer(base)};
    const digits_value = try vm.callMethodByName(integer_value, "to_s", base_args[0..], null);
    var digits = digits_value.toStringObject().str;

    var sign_byte: ?u8 = null;
    if (digits.len > 0 and digits[0] == '-') {
        sign_byte = '-';
        digits = digits[1..];
    } else if (spec.flags.show_sign) {
        sign_byte = '+';
    } else if (spec.flags.leading_space) {
        sign_byte = ' ';
    }

    var prefix: []const u8 = "";
    if (spec.flags.alternate_form and digits.len > 0 and !std.mem.eql(u8, digits, "0")) {
        prefix = switch (spec.conversion) {
            'B' => "0B",
            'X' => "0X",
            'b' => "0b",
            'o' => "0",
            'x' => "0x",
            else => "",
        };
    }

    const zeros_for_precision = if (spec.precision) |precision|
        if (precision > digits.len) precision - digits.len else 0
    else
        0;

    const sign_len: usize = if (sign_byte == null) 0 else 1;
    const raw_len = sign_len + prefix.len + zeros_for_precision + digits.len;
    const width = spec.width orelse 0;
    const zero_pad_width = spec.flags.zero_pad and !spec.flags.left_justify and spec.precision == null;
    const zero_pad_count = if (zero_pad_width and width > raw_len) width - raw_len else 0;
    const space_pad_count = if (!zero_pad_width and width > raw_len) width - raw_len else 0;

    if (!spec.flags.left_justify) {
        appendRepeatedByte(out, vm.gc_allocator_atomic, ' ', space_pad_count) catch return error.Fatal;
    }
    if (sign_byte) |byte| {
        out.append(vm.gc_allocator_atomic, byte) catch return error.Fatal;
    }
    out.appendSlice(vm.gc_allocator_atomic, prefix) catch return error.Fatal;
    appendRepeatedByte(out, vm.gc_allocator_atomic, '0', zero_pad_count + zeros_for_precision) catch return error.Fatal;
    if (uppercase) {
        for (digits) |byte| {
            out.append(vm.gc_allocator_atomic, std.ascii.toUpper(byte)) catch return error.Fatal;
        }
    } else {
        out.appendSlice(vm.gc_allocator_atomic, digits) catch return error.Fatal;
    }
    if (spec.flags.left_justify) {
        appendRepeatedByte(out, vm.gc_allocator_atomic, ' ', space_pad_count) catch return error.Fatal;
    }
    _ = result_encoding;
}

pub fn builtinStringTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return switch (try vm.probeToStringValue(args[0])) {
        .string => |string_value| string_value,
        .missing, .nil_result => Value.nil(),
    };
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

pub fn builtinStringInitializeCopy(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const replacement_val = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const replacement = replacement_val.toStringObject();
    const string_obj = receiver.toStringObject();

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, replacement.str) catch return error.Fatal;
    string_obj.encoding = replacement.encoding;
    string_obj.validity = .unknown;
    try vm.copyPackedPointerTargets(replacement, string_obj);
    return receiver;
}

const StringSubMatch = struct {
    start_byte: usize,
    end_byte: usize,
    matched_string: Value,
    match_data: *value.MatchDataObject,
};

fn buildLiteralStringMatchData(
    vm: *VM,
    receiver: Value,
    pattern_obj: *value.StringObject,
    start_byte: usize,
    end_byte: usize,
) VMError!*value.MatchDataObject {
    const string_obj = receiver.toStringObject();
    const escaped_pattern = try escapeRegexpLiteral(vm, pattern_obj.str);
    defer vm.allocator.free(escaped_pattern);
    const normalized = vm.normalizeRegexpEncoding(pattern_obj.str, pattern_obj.encoding, 0);
    const regexp = (try vm.newRegexpWithEncoding(escaped_pattern, normalized.options, normalized.encoding)).toRegexpObject();
    const match_str = try vm.newStringWithEncoding(string_obj.str[start_byte..end_byte], false, string_obj.encoding);
    const captures = [_]Value{match_str};
    const begins = [_]i64{@intCast(start_byte)};
    const ends = [_]i64{@intCast(end_byte)};
    return (try vm.newMatchData(regexp, string_obj, captures[0..], begins[0..], ends[0..])).toMatchDataObject();
}

fn findStringSubLiteralMatch(
    vm: *VM,
    receiver: Value,
    pattern_value: Value,
) VMError!?StringSubMatch {
    return findStringSubLiteralMatchAt(vm, receiver, pattern_value, 0);
}

fn findStringSubLiteralMatchAt(
    vm: *VM,
    receiver: Value,
    pattern_value: Value,
    search_start: usize,
) VMError!?StringSubMatch {
    const string_obj = receiver.toStringObject();
    const pattern_obj = pattern_value.toStringObject();
    const pattern = pattern_obj.str;

    if (enc.negotiate(string_obj.encoding, string_obj.str, pattern_obj.encoding, pattern) == null) {
        try vm.clearLastMatch();
        return null;
    }

    var start: usize = 0;
    var end_: usize = 0;
    if (pattern.len == 0) {
        if (search_start > string_obj.str.len) {
            try vm.clearLastMatch();
            return null;
        }
        start = search_start;
        end_ = search_start;
    } else if (pattern.len > string_obj.str.len) {
        try vm.clearLastMatch();
        return null;
    } else {
        if (search_start > string_obj.str.len - pattern.len) {
            try vm.clearLastMatch();
            return null;
        }
        var pos = search_start;
        while (pos <= string_obj.str.len - pattern.len) {
            const found = std.mem.indexOfPos(u8, string_obj.str, pos, pattern) orelse {
                try vm.clearLastMatch();
                return null;
            };
            const found_end = found + pattern.len;
            if (string_obj.encoding.isCharBoundary(string_obj.str, found) and string_obj.encoding.isCharBoundary(string_obj.str, found_end)) {
                start = found;
                end_ = found_end;
                break;
            }
            pos = found + 1;
        } else {
            try vm.clearLastMatch();
            return null;
        }
    }

    const md = try buildLiteralStringMatchData(vm, receiver, pattern_obj, start, end_);
    try vm.setLastMatch(md);
    return .{
        .start_byte = start,
        .end_byte = end_,
        .matched_string = md.captures.items[0],
        .match_data = md,
    };
}

fn findStringSubMatch(vm: *VM, receiver: Value, pattern_arg: Value) VMError!?StringSubMatch {
    return findStringSubMatchAt(vm, receiver, pattern_arg, 0);
}

fn findStringSubRegexpMatchAt(
    vm: *VM,
    receiver: Value,
    regexp_obj: *value.RegexpObject,
    start_byte: usize,
) VMError!?StringSubMatch {
    const string_obj = receiver.toStringObject();
    if (start_byte > string_obj.str.len) {
        try vm.clearLastMatch();
        return null;
    }

    const start_char_index: i64 = @intCast(string_obj.encoding.charCount(string_obj.str[0..start_byte]));
    const match_index = try regexp_builtin.regexpMatchOpAt(vm, regexp_obj, receiver, start_char_index, true);
    if (match_index.isNil()) return null;

    const md_value = vm.getGlobalValue("$~");
    if (!md_value.isMatchData()) return error.Fatal;
    const md = md_value.toMatchDataObject();
    if (md.begin_byte_offsets.items.len == 0 or md.end_byte_offsets.items.len == 0 or md.captures.items.len == 0) {
        return error.Fatal;
    }

    const begin_i64 = md.begin_byte_offsets.items[0];
    const end_i64 = md.end_byte_offsets.items[0];
    if (begin_i64 < 0 or end_i64 < 0) return error.Fatal;

    return .{
        .start_byte = @intCast(begin_i64),
        .end_byte = @intCast(end_i64),
        .matched_string = md.captures.items[0],
        .match_data = md,
    };
}

fn findStringSubMatchAt(
    vm: *VM,
    receiver: Value,
    pattern_arg: Value,
    search_start: usize,
) VMError!?StringSubMatch {
    if (pattern_arg.isRegexp()) {
        return findStringSubRegexpMatchAt(vm, receiver, pattern_arg.toRegexpObject(), search_start);
    }

    const pattern_value = try pattern_arg.coerceToStringValue(vm, "wrong argument type");
    return findStringSubLiteralMatchAt(vm, receiver, pattern_value, search_start);
}

fn appendSubReplacementSegment(
    vm: *VM,
    out: *std.ArrayList(u8),
    current_encoding: *enc.Encoding,
    segment_encoding: enc.Encoding,
    segment_bytes: []const u8,
) VMError!void {
    const resolved_encoding = resolveStringConcatEncoding(current_encoding.*, out.items, segment_encoding, segment_bytes) orelse {
        return vm.raiseEncodingCompatibilityError(current_encoding.*, segment_encoding);
    };
    out.appendSlice(vm.allocator, segment_bytes) catch return error.Fatal;
    current_encoding.* = resolved_encoding;
}

fn appendSubReplacementCapture(
    vm: *VM,
    out: *std.ArrayList(u8),
    current_encoding: *enc.Encoding,
    md: *value.MatchDataObject,
    capture_index: usize,
) VMError!void {
    if (capture_index >= md.captures.items.len) return;
    const capture = md.captures.items[capture_index];
    if (!capture.isString()) return;
    const capture_obj = capture.toStringObject();
    try appendSubReplacementSegment(vm, out, current_encoding, capture_obj.encoding, capture_obj.str);
}

fn appendSubReplacementLastCapture(
    vm: *VM,
    out: *std.ArrayList(u8),
    current_encoding: *enc.Encoding,
    md: *value.MatchDataObject,
) VMError!void {
    if (md.captures.items.len <= 1) return;

    var idx = md.captures.items.len;
    while (idx > 1) {
        idx -= 1;
        if (idx >= md.begin_byte_offsets.items.len or idx >= md.end_byte_offsets.items.len) continue;
        if (md.begin_byte_offsets.items[idx] < 0 or md.end_byte_offsets.items[idx] < 0) continue;
        try appendSubReplacementCapture(vm, out, current_encoding, md, idx);
        return;
    }
}

fn appendSubReplacementNamedCapture(
    vm: *VM,
    out: *std.ArrayList(u8),
    current_encoding: *enc.Encoding,
    md: *value.MatchDataObject,
    capture_name: []const u8,
) VMError!void {
    const capture_index = onigmo.nameToBackrefNumber(md.regexp.regex, md.source.str, capture_name);
    if (capture_index <= 0) return;
    try appendSubReplacementCapture(vm, out, current_encoding, md, @intCast(capture_index));
}

fn expandStringSubReplacement(vm: *VM, md: *value.MatchDataObject, replacement_value: Value) VMError!Value {
    const replacement_obj = replacement_value.toStringObject();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    var result_encoding = replacement_obj.encoding;

    const source_bytes = md.source.str;
    const source_encoding = md.source.encoding;
    const match_begin = if (md.begin_byte_offsets.items.len > 0) md.begin_byte_offsets.items[0] else -1;
    const match_end = if (md.end_byte_offsets.items.len > 0) md.end_byte_offsets.items[0] else -1;

    var index: usize = 0;
    while (index < replacement_obj.str.len) {
        if (replacement_obj.str[index] != '\\') {
            const segment_start = index;
            while (index < replacement_obj.str.len and replacement_obj.str[index] != '\\') : (index += 1) {}
            try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, replacement_obj.str[segment_start..index]);
            continue;
        }

        if (index + 1 >= replacement_obj.str.len) {
            try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, "\\");
            break;
        }

        const escape = replacement_obj.str[index + 1];
        if (escape == 'k' and index + 2 < replacement_obj.str.len and replacement_obj.str[index + 2] == '<') {
            const name_start = index + 3;
            const name_end = std.mem.indexOfScalarPos(u8, replacement_obj.str, name_start, '>') orelse {
                try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, replacement_obj.str[index .. index + 2]);
                index += 2;
                continue;
            };
            try appendSubReplacementNamedCapture(vm, &out, &result_encoding, md, replacement_obj.str[name_start..name_end]);
            index = name_end + 1;
            continue;
        }

        switch (escape) {
            '\\' => try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, "\\"),
            '&', '0' => try appendSubReplacementCapture(vm, &out, &result_encoding, md, 0),
            '`' => {
                if (match_begin >= 0) {
                    try appendSubReplacementSegment(vm, &out, &result_encoding, source_encoding, source_bytes[0..@intCast(match_begin)]);
                }
            },
            '\'' => {
                if (match_end >= 0) {
                    try appendSubReplacementSegment(vm, &out, &result_encoding, source_encoding, source_bytes[@intCast(match_end)..]);
                }
            },
            '+' => try appendSubReplacementLastCapture(vm, &out, &result_encoding, md),
            '1'...'9' => try appendSubReplacementCapture(vm, &out, &result_encoding, md, escape - '0'),
            else => try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, replacement_obj.str[index .. index + 2]),
        }
        index += 2;
    }

    const replaced = out.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(replaced);
    return try vm.newStringWithEncoding(replaced, false, result_encoding);
}

fn hashStringSubReplacement(vm: *VM, hash: Value, matched_string: Value) VMError!Value {
    var hash_args = [_]Value{matched_string};
    const replacement = try vm.callMethodByName(hash, "[]", hash_args[0..], null);
    const to_s_value = try vm.callMethodByName(replacement, "to_s", &.{}, null);
    if (!to_s_value.isString()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to String ({s}#to_s gives {s})",
            .{ vm.className(replacement), vm.className(replacement), vm.className(to_s_value) },
        );
    }
    return to_s_value;
}

fn yieldStringSubReplacement(vm: *VM, receiver: Value, snapshot: value.StringObject, matched_string: Value, match_data: *value.MatchDataObject, blk: Block, bang: bool) VMError!Value {
    const yielded = try vm.yieldToBlock(blk, &[_]Value{matched_string});
    if (yielded.controlFlowValue()) |return_value| return return_value;

    if (bang) {
        const current = receiver.toStringObject();
        if (!current.encoding.eql(snapshot.encoding) or !std.mem.eql(u8, current.str, snapshot.str)) {
            return vm.raiseExceptionFmt(vm.runtime_error_class, "string modified", .{});
        }
    }

    try vm.setLastMatch(match_data);
    const to_s_value = try vm.callMethodByName(yielded.value, "to_s", &.{}, null);
    if (!to_s_value.isString()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to String ({s}#to_s gives {s})",
            .{ vm.className(yielded.value), vm.className(yielded.value), vm.className(to_s_value) },
        );
    }
    return to_s_value;
}

fn advanceStringSubSearchOffset(bytes: []const u8, string_encoding: enc.Encoding, base_offset: usize, match_end: usize) usize {
    if (match_end > base_offset) return match_end;
    if (base_offset >= bytes.len) return bytes.len + 1;

    var next = base_offset;
    const ch = string_encoding.nextChar(bytes, &next);
    return if (ch.len > 0 and next > base_offset) next else base_offset + 1;
}

fn stringSub(vm: *VM, receiver: Value, args: []Value, block: ?Block, bang: bool) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (args.len == 1 and block == null) {
        return vm.raiseArgumentErrorWrongArgCount(args.len, 2);
    }
    if (bang and receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const snapshot = receiver.toStringObject().*;
    const match = (try findStringSubMatch(vm, receiver, args[0])) orelse {
        if (bang) return Value.nil();
        return try vm.newStringWithEncoding(snapshot.str, false, snapshot.encoding);
    };

    const replacement = if (args.len == 2) blk: {
        if (args[1].isHash()) {
            break :blk try hashStringSubReplacement(vm, args[1], match.matched_string);
        }

        const replacement_value = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
        break :blk try expandStringSubReplacement(vm, match.match_data, replacement_value);
    } else blk: {
        break :blk try yieldStringSubReplacement(vm, receiver, snapshot, match.matched_string, match.match_data, block.?, bang);
    };

    const result = try vm.newStringWithEncoding(snapshot.str, false, snapshot.encoding);
    try spliceStringBytes(vm, result, match.start_byte, match.end_byte, replacement);
    const result_obj = result.toStringObject();
    const modified = !result_obj.encoding.eql(snapshot.encoding) or !std.mem.eql(u8, result_obj.str, snapshot.str);

    if (!bang) return result;
    if (!modified) return Value.nil();

    const receiver_obj = receiver.toStringObject();
    try warnSymbolToSMutation(vm, receiver_obj);
    receiver_obj.str = result_obj.str;
    receiver_obj.encoding = result_obj.encoding;
    receiver_obj.validity = .unknown;
    receiver_obj.symbol_to_s_source = null;
    return receiver;
}

pub fn builtinStringSub(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return stringSub(vm, receiver, args, block, false);
}

pub fn builtinStringSubBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return stringSub(vm, receiver, args, block, true);
}

fn stringGsub(vm: *VM, receiver: Value, args: []Value, block: ?Block, bang: bool) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (args.len == 1 and block == null) {
        return vm.createMethodEnumerator(receiver, try vm.intern(if (bang) "gsub!" else "gsub"), args);
    }
    if (bang and receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const snapshot = receiver.toStringObject().*;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    var result_encoding = snapshot.encoding;
    var search_offset: usize = 0;
    var copy_offset: usize = 0;
    var last_success_md: ?*value.MatchDataObject = null;
    var matched = false;
    var replacement_cache: ?Value = null;

    while (try findStringSubMatchAt(vm, receiver, args[0], search_offset)) |match| {
        matched = true;
        last_success_md = match.match_data;

        try appendSubReplacementSegment(vm, &out, &result_encoding, snapshot.encoding, snapshot.str[copy_offset..match.start_byte]);
        copy_offset = match.end_byte;

        const replacement = if (args.len == 2) blk: {
            if (args[1].isHash()) {
                break :blk try hashStringSubReplacement(vm, args[1], match.matched_string);
            }

            const replacement_value = replacement_cache orelse blk2: {
                const coerced = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
                replacement_cache = coerced;
                break :blk2 coerced;
            };
            break :blk try expandStringSubReplacement(vm, match.match_data, replacement_value);
        } else blk: {
            break :blk try yieldStringSubReplacement(vm, receiver, snapshot, match.matched_string, match.match_data, block.?, bang);
        };

        const replacement_obj = replacement.toStringObject();
        try appendSubReplacementSegment(vm, &out, &result_encoding, replacement_obj.encoding, replacement_obj.str);
        search_offset = advanceStringSubSearchOffset(snapshot.str, snapshot.encoding, match.start_byte, match.end_byte);
    }

    if (last_success_md) |md| {
        try vm.setLastMatch(md);
    } else {
        try vm.clearLastMatch();
    }

    if (!matched) {
        if (bang) return Value.nil();
        return try vm.newStringWithEncoding(snapshot.str, false, snapshot.encoding);
    }

    try appendSubReplacementSegment(vm, &out, &result_encoding, snapshot.encoding, snapshot.str[copy_offset..]);
    const replaced = out.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(replaced);

    const result = try vm.newStringWithEncoding(replaced, false, result_encoding);
    if (!bang) return result;

    const result_obj = result.toStringObject();
    const modified = !result_obj.encoding.eql(snapshot.encoding) or !std.mem.eql(u8, result_obj.str, snapshot.str);
    if (!modified) return Value.nil();

    const receiver_obj = receiver.toStringObject();
    try warnSymbolToSMutation(vm, receiver_obj);
    receiver_obj.str = result_obj.str;
    receiver_obj.encoding = result_obj.encoding;
    receiver_obj.validity = .unknown;
    receiver_obj.symbol_to_s_source = null;
    return receiver;
}

pub fn builtinStringGsub(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return stringGsub(vm, receiver, args, block, false);
}

pub fn builtinStringGsubBang(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return stringGsub(vm, receiver, args, block, true);
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
        return vm.raiseEncodingCompatibilityError(lhs.encoding, rhs.encoding);
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

pub fn builtinStringPercent(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const format_string = receiver.toStringObject();
    var single_arg = [_]Value{args[0]};
    const arg_values = switch (try vm.probeToAry(args[0])) {
        .array => |array_value| array_value.toArrayObject().elements.items,
        .missing, .nil_result => single_arg[0..],
    };
    var next_arg_index: usize = 0;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);
    var result_encoding = format_string.encoding;

    var index: usize = 0;
    while (index < format_string.str.len) {
        if (format_string.str[index] != '%') {
            out.append(vm.gc_allocator_atomic, format_string.str[index]) catch return error.Fatal;
            index += 1;
            continue;
        }

        index += 1;
        const spec = try parseStringPercentSpec(vm, format_string.str, &index);
        if (spec.conversion == '%') {
            out.append(vm.gc_allocator_atomic, '%') catch return error.Fatal;
            continue;
        }

        if (next_arg_index >= arg_values.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        }
        const arg = arg_values[next_arg_index];
        next_arg_index += 1;

        switch (spec.conversion) {
            'B' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 2, true),
            'X' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 16, true),
            'b' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 2, false),
            'd', 'i', 'u' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 10, false),
            'o' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 8, false),
            'x' => try appendStringPercentInteger(vm, &out, &result_encoding, spec, arg, 16, false),
            'p', 's', 'c' => {
                const string_value = switch (spec.conversion) {
                    'c' => switch (try vm.probeToStringValue(arg)) {
                        .string => |string_value| string_value,
                        .missing, .nil_result => blk: {
                            const integer_value = try coerceStringPercentInteger(vm, arg);
                            break :blk try vm.callMethodByName(integer_value, "chr", &[_]Value{}, null);
                        },
                    },
                    'p' => try vm.callMethodByName(arg, "inspect", &[_]Value{}, null),
                    's' => if (arg.isString()) arg else try vm.callMethodByName(arg, "to_s", &[_]Value{}, null),
                    else => unreachable,
                };
                if (!string_value.isString()) {
                    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into String", .{vm.className(string_value)});
                }

                const string_obj = string_value.toStringObject();
                const bytes = switch (spec.conversion) {
                    'c' => blk: {
                        if (string_obj.str.len == 0) break :blk "";
                        var next_byte: usize = 0;
                        const char = string_obj.encoding.nextChar(string_obj.str, &next_byte);
                        if (char.len == 0) break :blk "";
                        break :blk string_obj.str[0..char.len];
                    },
                    else => if (spec.precision) |precision|
                        string_obj.str[0..@min(string_obj.str.len, precision)]
                    else
                        string_obj.str,
                };
                try appendStringPercentPaddedText(vm, &out, &result_encoding, spec, bytes, string_obj.encoding);
            },
            'e', 'E', 'f', 'g', 'G' => try appendStringPercentFloat(vm, &out, &result_encoding, spec, arg),
            else => return malformedStringPercent(vm),
        }
    }

    return try vm.newStringWithEncoding(out.items, false, result_encoding);
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

    if (try vm.respondsToMethodByName(other, "to_str", false)) {
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

    switch (try vm.probeToStringValue(other)) {
        .string => |coerced_value| return compareStringObjects(lhs, coerced_value.toStringObject()),
        .missing, .nil_result => {},
    }

    if (try vm.enterRecursionGuard(.string_compare_fallback, receiver, other)) return Value.nil();
    defer vm.leaveRecursionGuard(.string_compare_fallback, receiver, other);

    var reverse_args = [_]Value{receiver};
    const maybe_reversed = try vm.checkCallMethodByName(other, "<=>", false, reverse_args[0..], null);
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

pub fn compareStringObjects(lhs: *const value.StringObject, rhs: *const value.StringObject) Value {
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

fn coerceStringMatchPattern(vm: *VM, pattern: Value) VMError!Value {
    if (pattern.isRegexp()) return pattern;

    const pattern_value = try pattern.coerceToStringValue(vm, "wrong argument type");
    const pattern_obj = pattern_value.toStringObject();
    const normalized = vm.normalizeRegexpEncoding(pattern_obj.str, pattern_obj.encoding, 0);
    return try vm.newRegexpWithEncoding(pattern_obj.str, normalized.options, normalized.encoding);
}

fn stringMatchArgs(receiver: Value, args: []Value, match_args: *[2]Value) []Value {
    match_args.* = .{ receiver, Value.nil() };
    if (args.len == 2) {
        match_args[1] = args[1];
        return match_args[0..2];
    }
    return match_args[0..1];
}

fn callStringMatch(
    vm: *VM,
    receiver: Value,
    args: []Value,
    method_name: []const u8,
    block: ?Block,
) VMError!Value {
    const pattern_receiver = try coerceStringMatchPattern(vm, args[0]);
    var match_args: [2]Value = undefined;
    return vm.callMethodByName(pattern_receiver, method_name, stringMatchArgs(receiver, args, &match_args), block);
}

pub fn casecmpOrder(
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

    const rhs_value = if (other.isString()) other else switch (try vm.probeToStringValue(other)) {
        .string => |string_value| string_value,
        .missing, .nil_result => return Value.nil(),
    };
    const rhs = rhs_value.toStringObject();

    const order = try casecmpOrder(vm, lhs, rhs, false) orelse return Value.nil();
    return Value.integer(order);
}

pub fn builtinStringCasecmpQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const other = args[0];

    const rhs_value = if (other.isString()) other else switch (try vm.probeToStringValue(other)) {
        .string => |string_value| string_value,
        .missing, .nil_result => return Value.nil(),
    };
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

fn prependBomForEncodedString(vm: *VM, target_encoding: enc.Encoding, bytes: []const u8) VMError![]const u8 {
    if (bytes.len == 0) return bytes;

    const bom = switch (target_encoding) {
        .utf16 => "\xFE\xFF",
        .utf32 => "\x00\x00\xFE\xFF",
        else => return bytes,
    };

    const out = vm.gc_allocator_atomic.alloc(u8, bom.len + bytes.len) catch return error.Fatal;
    @memcpy(out[0..bom.len], bom);
    @memcpy(out[bom.len..], bytes);
    return out;
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

const TranscodeOptions = struct {
    kw_invalid: ?Value = null,
    kw_undef: ?Value = null,
    kw_replace: ?Value = null,
    kw_fallback: ?Value = null,
    xml_mode: EncodeXmlMode = .none,
};

fn transcodeWithEncodeOptions(
    vm: *VM,
    receiver: Value,
    source_bytes: []const u8,
    from_encoding: enc.Encoding,
    target_encoding: enc.Encoding,
    opts: TranscodeOptions,
) VMError![]u8 {
    const effective_target_encoding = enc.effectiveTranscodeTargetEncoding(target_encoding);

    if (isTag(effective_target_encoding, .iso_2022_jp) and
        opts.kw_invalid == null and
        opts.kw_undef == null and
        opts.kw_replace == null and
        opts.kw_fallback == null and
        opts.xml_mode == .none)
    {
        return transcodeToIso2022JpSimple(vm, source_bytes, from_encoding, effective_target_encoding);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);

    const kw_invalid = opts.kw_invalid;
    const kw_undef = opts.kw_undef;
    const kw_replace = opts.kw_replace;
    const kw_fallback = opts.kw_fallback;
    const xml_mode = opts.xml_mode;
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
                    fallback_result = try vm.callProcObject(fallback.toProcObject(), fallback_args[0..], null, null, null);
                } else if (try vm.checkCallMethodByName(fallback, "call", false, fallback_args[0..], null)) |result| {
                    fallback_result = result;
                } else if (try vm.checkCallMethodByName(fallback, "[]", false, fallback_args[0..], null)) |result| {
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
                fallback_result = try vm.callProcObject(fallback.toProcObject(), fallback_args[0..], null, null, null);
            } else if (try vm.checkCallMethodByName(fallback, "call", false, fallback_args[0..], null)) |result| {
                fallback_result = result;
            } else if (try vm.checkCallMethodByName(fallback, "[]", false, fallback_args[0..], null)) |result| {
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

    const transcoded = try transcodeWithEncodeOptions(vm, receiver, source_bytes, from_encoding, target_encoding, .{
        .kw_invalid = kw_invalid,
        .kw_undef = kw_undef,
        .kw_replace = kw_replace,
        .kw_fallback = kw_fallback,
        .xml_mode = xml_mode,
    });
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
    const encoded_with_bom = try prependBomForEncodedString(vm, target_encoding, encoded.toStringObject().str);
    if (!std.mem.eql(u8, encoded_with_bom, encoded.toStringObject().str)) {
        encoded = try vm.newStringWithEncoding(encoded_with_bom, false, target_encoding);
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

fn parseUnicodeNormalizeForm(vm: *VM, value_arg: Value) VMError!void {
    const form_name = if (value_arg.isSymbol())
        value_arg.toSymbolObject().name
    else if (value_arg.isString())
        value_arg.toStringObject().str
    else
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into String", .{vm.className(value_arg)});

    if (std.ascii.eqlIgnoreCase(form_name, "nfc")) return;
    if (std.ascii.eqlIgnoreCase(form_name, "nfd")) return;
    if (std.ascii.eqlIgnoreCase(form_name, "nfkc")) return;
    if (std.ascii.eqlIgnoreCase(form_name, "nfkd")) return;
    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid normalization form", .{});
}

pub fn builtinStringUnicodeNormalize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 1) {
        try parseUnicodeNormalizeForm(vm, args[0]);
    }
    return builtinStringDup(vm, receiver, &.{}, null);
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
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    var initialize_copy_args = [_]Value{receiver};
    _ = try vm.callMethodByName(duplicate, "initialize_copy", initialize_copy_args[0..], null);

    try vm.copyPackedPointerTargets(receiver.toStringObject(), duplicate.toStringObject());

    return duplicate;
}

pub fn builtinStringClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const kwfreeze = try vm.consumeCloneFreezeOpt();

    const string_obj = receiver.toStringObject();
    const duplicate = try vm.newStringForClassWithEncoding(vm.getClass(receiver), string_obj.str, false, string_obj.encoding);

    const src_obj = receiver.getObjectPointer().?;
    const dst_obj = duplicate.getObjectPointer().?;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    try vm.callInitializeClone(duplicate, receiver, kwfreeze);
    vm.applyCloneFreeze(receiver, duplicate, kwfreeze);
    try vm.copyPackedPointerTargets(receiver.toStringObject(), duplicate.toStringObject());
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

pub fn builtinStringCount(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountAtLeast(args, 1);
    const string_obj = receiver.toStringObject();

    const selectors = vm.allocator.alloc(StringDeleteSelector, args.len) catch return error.Fatal;
    defer vm.allocator.free(selectors);
    const selector_count = try buildStringDeleteSelectors(vm, string_obj, args, selectors);
    defer {
        for (selectors[0..selector_count]) |*selector| {
            selector.deinit(vm.allocator);
        }
    }

    var count: usize = 0;
    var index: usize = 0;
    while (index < string_obj.str.len) {
        const parsed = string_obj.encoding.nextCodepoint(string_obj.str, &index);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{string_obj.encoding.name()});
        }

        var matched_all = true;
        for (selectors[0..selector_count]) |selector| {
            if (!stringDeleteSelectorContains(selector, parsed.codepoint)) {
                matched_all = false;
                break;
            }
        }
        if (matched_all) count += 1;
    }

    return Value.integer(@intCast(count));
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
    const selection = try stringSliceSelection(vm, receiver, args);
    return selection.value;
}

pub fn builtinStringSlice(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinStringBracket(vm, receiver, args, block);
}

pub fn builtinStringSliceBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const selection = try stringSliceSelection(vm, receiver, args);
    if (selection.start_byte == null or selection.end_byte == null) return Value.nil();

    const replacement = try vm.newStringWithEncoding("", false, receiver.toStringObject().encoding);
    try spliceStringBytes(vm, receiver, selection.start_byte.?, selection.end_byte.?, replacement);
    return selection.value;
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

        const md_val = vm.getGlobalValue("$~");
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

        const md_val = vm.getGlobalValue("$~");
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
            if (yield_result.controlFlowValue()) |return_value| return return_value;
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

    return Value.fromObject(&array_obj.object);
}

const StringEachLineOptions = struct {
    separator: ?*value.StringObject,
    chomp: bool,
};

fn parseStringEachLineOptions(vm: *VM, args: []Value) VMError!StringEachLineOptions {
    try vm.requireArgCountRange(args, 0, 1);

    var chomp_value: ?Value = null;
    try vm.consumeKeywordArgs(.{"chomp"}, .{&chomp_value});
    try vm.validateKeywordArgsConsumed();

    const raw_separator = if (args.len == 0)
        vm.globals.get("$/") orelse Value.nil()
    else
        args[0];

    return .{
        .separator = if (raw_separator.isNil()) null else (try raw_separator.coerceToStringValue(vm, "no implicit conversion into String")).toStringObject(),
        .chomp = if (chomp_value) |value_| value_.is_truthy() else false,
    };
}

fn stringEachLineChomp(bytes: []const u8, separator: ?*value.StringObject) []const u8 {
    const separator_obj = separator orelse return bytes;
    if (separator_obj.str.len == 0) {
        if (std.mem.endsWith(u8, bytes, "\n\n")) return bytes[0 .. bytes.len - 2];
        return bytes;
    }

    if (std.mem.eql(u8, separator_obj.str, "\n")) {
        if (std.mem.endsWith(u8, bytes, "\r\n")) return bytes[0 .. bytes.len - 2];
        if (std.mem.endsWith(u8, bytes, "\n")) return bytes[0 .. bytes.len - 1];
        return bytes;
    }

    if (std.mem.endsWith(u8, bytes, separator_obj.str)) {
        return bytes[0 .. bytes.len - separator_obj.str.len];
    }
    return bytes;
}

fn stringEachLineAppendOrYield(
    vm: *VM,
    result_array: ?*value.ArrayObject,
    blk: ?Block,
    receiver: Value,
    encoding: enc.Encoding,
    segment: []const u8,
    options: StringEachLineOptions,
) VMError!Value {
    const output_bytes = if (options.chomp) stringEachLineChomp(segment, options.separator) else segment;
    const line_value = try vm.newStringWithEncoding(output_bytes, false, encoding);

    if (blk) |block_| {
        const yield_args = [_]Value{line_value};
        const yield_result = try vm.yieldToBlock(block_, &yield_args);
        if (yield_result.controlFlowValue()) |return_value| return return_value;
        return receiver;
    }

    result_array.?.elements.append(vm.gc_allocator, line_value) catch return error.Fatal;
    return receiver;
}

fn stringEachLineDummyBehavior(encoding: enc.Encoding) enum { whole_string, raise_converter } {
    return switch (encoding) {
        .utf16, .utf16le, .utf16be, .utf32, .utf32le, .utf32be => .whole_string,
        else => .raise_converter,
    };
}

fn stringEachLineSeparatorCompatible(
    receiver_encoding: enc.Encoding,
    separator_encoding: enc.Encoding,
    separator_bytes: []const u8,
) bool {
    if (receiver_encoding.eql(separator_encoding)) return true;
    if (separator_bytes.len == 0) return true;
    if (receiver_encoding.isDummy() or separator_encoding.isDummy()) return false;
    return receiver_encoding.isAsciiCompatible() and
        separator_encoding.isAsciiCompatible() and
        enc.isAsciiOnly(separator_bytes);
}

fn stringEachLineImpl(vm: *VM, receiver: Value, args: []Value, block: ?Block, return_array_without_block: bool) VMError!Value {
    const blk = if (return_array_without_block) null else block;
    if (blk == null and !return_array_without_block) {
        return vm.createMethodEnumerator(receiver, try vm.intern("each_line"), args);
    }

    const options = try parseStringEachLineOptions(vm, args);
    const string_obj = receiver.toStringObject();
    const snapshot_bytes = string_obj.str;
    const snapshot_encoding = string_obj.encoding;

    var result_array: ?*value.ArrayObject = null;
    if (return_array_without_block) {
        result_array = try vm.createArray();
    }

    if (options.separator) |separator_obj| {
        if (snapshot_encoding.isDummy() and std.mem.eql(u8, separator_obj.str, "\n")) {
            switch (stringEachLineDummyBehavior(snapshot_encoding)) {
                .whole_string => {
                    if (snapshot_bytes.len != 0) {
                        const control = try stringEachLineAppendOrYield(vm, result_array, blk, receiver, snapshot_encoding, snapshot_bytes, options);
                        if (control.raw != receiver.raw) return control;
                    }
                    return if (return_array_without_block) Value.fromObject(&result_array.?.object) else receiver;
                },
                .raise_converter => {
                    return vm.raiseExceptionFmt(vm.encoding_converter_not_found_error_class, "code converter not found", .{});
                },
            }
        }

        if (!stringEachLineSeparatorCompatible(snapshot_encoding, separator_obj.encoding, separator_obj.str)) {
            return vm.raiseEncodingCompatibilityError(snapshot_encoding, separator_obj.encoding);
        }
    }

    if (options.separator == null) {
        const control = try stringEachLineAppendOrYield(vm, result_array, blk, receiver, snapshot_encoding, snapshot_bytes, options);
        if (control.raw != receiver.raw) return control;
        return if (return_array_without_block) Value.fromObject(&result_array.?.object) else receiver;
    }

    const separator_obj = options.separator.?;
    if (separator_obj.str.len == 0) {
        var start: usize = 0;
        while (start < snapshot_bytes.len) {
            const segment = if (std.mem.indexOfPos(u8, snapshot_bytes, start, "\n\n")) |idx| blk_segment: {
                var next_start = idx + 2;
                while (next_start < snapshot_bytes.len and snapshot_bytes[next_start] == '\n') : (next_start += 1) {}
                const out = snapshot_bytes[start .. idx + 2];
                start = next_start;
                break :blk_segment out;
            } else blk_segment: {
                const out = snapshot_bytes[start..];
                start = snapshot_bytes.len;
                break :blk_segment out;
            };

            const control = try stringEachLineAppendOrYield(vm, result_array, blk, receiver, snapshot_encoding, segment, options);
            if (control.raw != receiver.raw) return control;
        }
        return if (return_array_without_block) Value.fromObject(&result_array.?.object) else receiver;
    }

    var start: usize = 0;
    while (start < snapshot_bytes.len) {
        const segment = if (std.mem.eql(u8, separator_obj.str, "\n")) blk_segment: {
            if (std.mem.indexOfScalarPos(u8, snapshot_bytes, start, '\n')) |idx| {
                const out = snapshot_bytes[start .. idx + 1];
                start = idx + 1;
                break :blk_segment out;
            }

            const out = snapshot_bytes[start..];
            start = snapshot_bytes.len;
            break :blk_segment out;
        } else blk_segment: {
            if (std.mem.indexOfPos(u8, snapshot_bytes, start, separator_obj.str)) |idx| {
                const out = snapshot_bytes[start .. idx + separator_obj.str.len];
                start = idx + separator_obj.str.len;
                break :blk_segment out;
            }

            const out = snapshot_bytes[start..];
            start = snapshot_bytes.len;
            break :blk_segment out;
        };

        const control = try stringEachLineAppendOrYield(vm, result_array, blk, receiver, snapshot_encoding, segment, options);
        if (control.raw != receiver.raw) return control;
    }

    return if (return_array_without_block) Value.fromObject(&result_array.?.object) else receiver;
}

pub fn builtinStringEachLine(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return stringEachLineImpl(vm, receiver, args, block, false);
}

pub fn builtinStringLines(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (block != null) {
        return vm.callMethodByNameForwardingKeywords(receiver, "each_line", args, block);
    }
    return stringEachLineImpl(vm, receiver, args, null, true);
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
            if (yield_result.controlFlowValue()) |return_value| return return_value;
        }
        return receiver;
    }

    const array_obj = try vm.createArray();
    for (bytes) |b| {
        array_obj.elements.append(vm.gc_allocator, Value.integer(b)) catch return error.Fatal;
    }
    return Value.fromObject(&array_obj.object);
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
        if (yield_result.controlFlowValue()) |return_value| return return_value;
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
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, insert_encoding);
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
            if (yield_result.controlFlowValue()) |return_value| return return_value;
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

    return Value.fromObject(&array_obj.object);
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

const StringBoundaryKind = enum {
    prefix,
    suffix,
};

const StringBoundaryMatch = struct {
    matched: bool,
    start: usize,
    end: usize,
};

fn matchStringBoundary(
    vm: *VM,
    receiver_bytes: []const u8,
    receiver_encoding: enc.Encoding,
    arg: Value,
    kind: StringBoundaryKind,
) VMError!StringBoundaryMatch {
    const boundary_val = try arg.coerceToStringValue(vm, "no implicit conversion into String");
    const boundary_obj = boundary_val.toStringObject();
    return switch (kind) {
        .prefix => blk: {
            if (boundary_obj.str.len > receiver_bytes.len) {
                break :blk .{ .matched = false, .start = 0, .end = 0 };
            }
            const prefix_bytes = receiver_bytes[0..boundary_obj.str.len];
            if (receiver_encoding == .ascii_8bit and boundary_obj.encoding.isAsciiCompatible()) {
                if (!std.mem.startsWith(u8, receiver_bytes, boundary_obj.str)) {
                    break :blk .{ .matched = false, .start = 0, .end = 0 };
                }
                if (enc.negotiate(receiver_encoding, prefix_bytes, boundary_obj.encoding, boundary_obj.str) == null) {
                    return vm.raiseEncodingCompatibilityError(receiver_encoding, boundary_obj.encoding);
                }
            } else {
                if (enc.negotiate(receiver_encoding, prefix_bytes, boundary_obj.encoding, boundary_obj.str) == null) {
                    return vm.raiseEncodingCompatibilityError(receiver_encoding, boundary_obj.encoding);
                }
                if (!std.mem.startsWith(u8, receiver_bytes, boundary_obj.str)) {
                    break :blk .{ .matched = false, .start = 0, .end = 0 };
                }
            }
            break :blk .{
                .matched = receiver_encoding.isCharBoundary(receiver_bytes, boundary_obj.str.len),
                .start = 0,
                .end = boundary_obj.str.len,
            };
        },
        .suffix => blk: {
            if (boundary_obj.str.len > receiver_bytes.len) {
                break :blk .{ .matched = false, .start = 0, .end = 0 };
            }
            const start = receiver_bytes.len - boundary_obj.str.len;
            if (enc.negotiate(receiver_encoding, receiver_bytes[start..], boundary_obj.encoding, boundary_obj.str) == null) {
                return vm.raiseEncodingCompatibilityError(receiver_encoding, boundary_obj.encoding);
            }
            if (!std.mem.endsWith(u8, receiver_bytes, boundary_obj.str)) {
                break :blk .{ .matched = false, .start = 0, .end = 0 };
            }
            break :blk .{
                .matched = receiver_encoding.isCharBoundary(receiver_bytes, start),
                .start = start,
                .end = receiver_bytes.len,
            };
        },
    };
}

pub fn stringLikeStartWith(
    vm: *VM,
    receiver: Value,
    receiver_bytes: []const u8,
    receiver_encoding: enc.Encoding,
    args: []Value,
) VMError!Value {
    if (args.len == 0) return Value.boolean(false);

    for (args) |arg| {
        if (arg.isRegexp()) {
            const match_val = try regexp_builtin.regexpMatchOp(vm, arg.toRegexpObject(), receiver);
            if (match_val.isInteger() and match_val.toInteger() == 0) {
                return Value.boolean(true);
            }
            try vm.clearLastMatch();
            continue;
        }

        if ((try matchStringBoundary(vm, receiver_bytes, receiver_encoding, arg, .prefix)).matched) {
            return Value.boolean(true);
        }
    }

    return Value.boolean(false);
}

pub fn stringLikeEndWith(
    vm: *VM,
    receiver_bytes: []const u8,
    receiver_encoding: enc.Encoding,
    args: []Value,
) VMError!Value {
    if (args.len == 0) return Value.boolean(false);

    for (args) |arg| {
        if ((try matchStringBoundary(vm, receiver_bytes, receiver_encoding, arg, .suffix)).matched) {
            return Value.boolean(true);
        }
    }

    return Value.boolean(false);
}

pub fn builtinStringStartWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    return stringLikeStartWith(vm, receiver, string_obj.str, string_obj.encoding, args);
}

pub fn builtinStringEndWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    return stringLikeEndWith(vm, string_obj.str, string_obj.encoding, args);
}

pub fn builtinStringDeletePrefix(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();
    const match = try matchStringBoundary(vm, string_obj.str, string_obj.encoding, args[0], .prefix);
    if (match.matched) {
        return try vm.newStringWithEncoding(string_obj.str[match.end..], false, string_obj.encoding);
    }

    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringDeletePrefixBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const match = try matchStringBoundary(vm, string_obj.str, string_obj.encoding, args[0], .prefix);
    if (!match.matched) {
        return Value.nil();
    }
    if (match.end == match.start) {
        return Value.nil();
    }

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[match.end..]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringDeleteSuffix(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();
    const match = try matchStringBoundary(vm, string_obj.str, string_obj.encoding, args[0], .suffix);
    if (match.matched) {
        return try vm.newStringWithEncoding(string_obj.str[0..match.start], false, string_obj.encoding);
    }

    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringDeleteSuffixBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const match = try matchStringBoundary(vm, string_obj.str, string_obj.encoding, args[0], .suffix);
    if (!match.matched) {
        return Value.nil();
    }
    if (match.end == match.start) {
        return Value.nil();
    }

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[0..match.start]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

const StringDeleteRange = struct {
    start: u32,
    end: u32,
};

const StringDeleteSelector = struct {
    negated: bool = false,
    ranges: std.ArrayList(StringDeleteRange) = .empty,

    fn deinit(self: *StringDeleteSelector, allocator: std.mem.Allocator) void {
        self.ranges.deinit(allocator);
    }
};

fn stringDeleteParseChar(
    vm: *VM,
    encoding: enc.Encoding,
    selector: []const u8,
    index: *usize,
    escaped: *bool,
) VMError!?u32 {
    if (index.* >= selector.len) return null;

    if (selector[index.*] == '\\') {
        index.* += 1;
        if (index.* >= selector.len) {
            escaped.* = false;
            return '\\';
        }
        escaped.* = true;
        const parsed = encoding.nextCodepoint(selector, index);
        if (parsed.len == 0 or !parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid character set", .{});
        }
        return parsed.codepoint;
    }

    escaped.* = false;
    const parsed = encoding.nextCodepoint(selector, index);
    if (parsed.len == 0 or !parsed.valid) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid character set", .{});
    }
    return parsed.codepoint;
}

fn stringDeleteParseSelector(
    vm: *VM,
    selector_value: Value,
) VMError!StringDeleteSelector {
    const selector_obj = selector_value.toStringObject();
    const selector = selector_obj.str;
    const encoding = selector_obj.encoding;

    var parsed_selector = StringDeleteSelector{};
    errdefer parsed_selector.deinit(vm.allocator);

    var index: usize = 0;
    if (selector.len > 0 and selector[0] == '^') {
        parsed_selector.negated = true;
        index = 1;
    }

    // A sole '^' is treated as a literal character, not negation.
    if (parsed_selector.negated and index >= selector.len) {
        parsed_selector.negated = false;
        index = 0;
    }

    while (index < selector.len) {
        var first_escaped = false;
        const first = (try stringDeleteParseChar(vm, encoding, selector, &index, &first_escaped)) orelse break;

        if (!first_escaped and index < selector.len and selector[index] == '-' and index + 1 < selector.len) {
            index += 1;
            var last_escaped = false;
            const last = (try stringDeleteParseChar(vm, encoding, selector, &index, &last_escaped)) orelse {
                parsed_selector.ranges.append(vm.allocator, .{ .start = first, .end = first }) catch return error.Fatal;
                parsed_selector.ranges.append(vm.allocator, .{ .start = '-', .end = '-' }) catch return error.Fatal;
                break;
            };
            if (first > last) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "invalid range in string transliteration", .{});
            }
            parsed_selector.ranges.append(vm.allocator, .{ .start = first, .end = last }) catch return error.Fatal;
            continue;
        }

        parsed_selector.ranges.append(vm.allocator, .{ .start = first, .end = first }) catch return error.Fatal;
    }

    return parsed_selector;
}

fn stringDeleteSelectorContains(selector: StringDeleteSelector, codepoint: u32) bool {
    if (selector.negated and selector.ranges.items.len == 0) return false;
    const matched = for (selector.ranges.items) |range| {
        if (codepoint >= range.start and codepoint <= range.end) break true;
    } else false;

    return if (selector.negated) !matched else matched;
}

const StringDeleteResult = struct {
    bytes: []const u8,
    modified: bool,
};

fn buildStringDeleteSelectors(
    vm: *VM,
    string_obj: *value.StringObject,
    args: []Value,
    selectors: []StringDeleteSelector,
) VMError!usize {
    var selector_count: usize = 0;
    for (args) |arg| {
        const selector = try arg.coerceToStringValue(vm, "no implicit conversion into String");
        const selector_obj = selector.toStringObject();
        if (enc.negotiate(string_obj.encoding, string_obj.str, selector_obj.encoding, selector_obj.str) == null) {
            return vm.raiseEncodingCompatibilityError(string_obj.encoding, selector_obj.encoding);
        }
        selectors[selector_count] = try stringDeleteParseSelector(vm, selector);
        selector_count += 1;
    }

    return selector_count;
}

fn stringDeleteCompute(vm: *VM, string_obj: *value.StringObject, args: []Value) VMError!StringDeleteResult {
    const selectors = vm.allocator.alloc(StringDeleteSelector, args.len) catch return error.Fatal;
    defer vm.allocator.free(selectors);
    const selector_count = try buildStringDeleteSelectors(vm, string_obj, args, selectors);
    defer {
        for (selectors[0..selector_count]) |*selector| {
            selector.deinit(vm.allocator);
        }
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);

    var modified = false;
    var index: usize = 0;
    while (index < string_obj.str.len) {
        const start = index;
        const parsed = string_obj.encoding.nextCodepoint(string_obj.str, &index);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{string_obj.encoding.name()});
        }

        const char_bytes = string_obj.str[start..index];
        var matched_all = true;
        for (selectors[0..selector_count]) |selector| {
            if (!stringDeleteSelectorContains(selector, parsed.codepoint)) {
                matched_all = false;
                break;
            }
        }

        if (matched_all) {
            modified = true;
            continue;
        }
        out.appendSlice(vm.gc_allocator_atomic, char_bytes) catch return error.Fatal;
    }

    return .{
        .bytes = out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal,
        .modified = modified,
    };
}

pub fn builtinStringDelete(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountAtLeast(args, 1);
    const string_obj = receiver.toStringObject();
    const result = try stringDeleteCompute(vm, string_obj, args);
    return try vm.newStringWithEncoding(result.bytes, false, string_obj.encoding);
}

pub fn builtinStringDeleteBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountAtLeast(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const result = try stringDeleteCompute(vm, string_obj, args);
    if (!result.modified) return Value.nil();

    try warnSymbolToSMutation(vm, string_obj);
    string_obj.str = result.bytes;
    string_obj.validity = .unknown;
    string_obj.symbol_to_s_source = null;
    return receiver;
}

fn stringSqueezeCompute(vm: *VM, string_obj: *value.StringObject, args: []Value) VMError!StringDeleteResult {
    const selectors = vm.allocator.alloc(StringDeleteSelector, args.len) catch return error.Fatal;
    defer vm.allocator.free(selectors);
    const selector_count = if (args.len > 0) try buildStringDeleteSelectors(vm, string_obj, args, selectors) else 0;
    defer {
        for (selectors[0..selector_count]) |*selector| {
            selector.deinit(vm.allocator);
        }
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);

    var modified = false;
    var index: usize = 0;
    var prev_codepoint: ?u32 = null;
    var prev_matched: bool = false;

    while (index < string_obj.str.len) {
        const start = index;
        const parsed = string_obj.encoding.nextCodepoint(string_obj.str, &index);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{string_obj.encoding.name()});
        }

        const char_bytes = string_obj.str[start..index];
        var matched_all = true;
        for (selectors[0..selector_count]) |selector| {
            if (!stringDeleteSelectorContains(selector, parsed.codepoint)) {
                matched_all = false;
                break;
            }
        }

        if (matched_all and prev_matched and prev_codepoint != null and prev_codepoint.? == parsed.codepoint) {
            modified = true;
            continue;
        }

        out.appendSlice(vm.gc_allocator_atomic, char_bytes) catch return error.Fatal;
        prev_codepoint = parsed.codepoint;
        prev_matched = matched_all;
    }

    return .{
        .bytes = out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal,
        .modified = modified,
    };
}

pub fn builtinStringSqueeze(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    const result = try stringSqueezeCompute(vm, string_obj, args);
    return try vm.newStringWithEncoding(result.bytes, false, string_obj.encoding);
}

pub fn builtinStringSqueezeBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const result = try stringSqueezeCompute(vm, string_obj, args);
    if (!result.modified) return Value.nil();

    try warnSymbolToSMutation(vm, string_obj);
    string_obj.str = result.bytes;
    string_obj.validity = .unknown;
    string_obj.symbol_to_s_source = null;
    return receiver;
}

const TrResult = struct {
    bytes: []const u8,
    modified: bool,
};

fn trParseArg(
    vm: *VM,
    arg: Value,
) VMError![]const u8 {
    const coerced = try arg.coerceToStringValue(vm, "no implicit conversion into String");
    return coerced.toStringObject().str;
}

fn trExpandSource(
    vm: *VM,
    source: []const u8,
) VMError!std.ArrayList(u32) {
    var chars: std.ArrayList(u32) = .empty;
    errdefer chars.deinit(vm.allocator);

    var negated = false;
    var i: usize = 0;

    if (source.len > 1 and source[0] == '^') {
        negated = true;
        i = 1;
    }

    while (i < source.len) {
        var next_i = i;
        const first_cp = nextCodepointSimple(source, &next_i);
        if (first_cp == null) break;
        i = next_i;

        if (i < source.len and source[i] == '-' and i + 1 < source.len) {
            i += 1;
            const last_cp_opt = nextCodepointSimple(source, &i);
            if (last_cp_opt) |last_cp| {
                if (first_cp.? <= last_cp) {
                    var cp = first_cp.?;
                    while (cp <= last_cp) : (cp += 1) {
                        chars.append(vm.allocator, cp) catch return error.Fatal;
                    }
                    continue;
                } else {
                    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid range in string transliteration", .{});
                }
            } else {
                chars.append(vm.allocator, first_cp.?) catch return error.Fatal;
                chars.append(vm.allocator, '-') catch return error.Fatal;
                break;
            }
        }

        chars.append(vm.allocator, first_cp.?) catch return error.Fatal;
    }

    if (negated) {
        var negated_result: std.ArrayList(u32) = .empty;
        errdefer negated_result.deinit(vm.allocator);
        negated_result.append(vm.allocator, std.math.maxInt(u32)) catch return error.Fatal;
        for (chars.items) |cp| {
            negated_result.append(vm.allocator, cp) catch return error.Fatal;
        }
        chars.deinit(vm.allocator);
        return negated_result;
    }

    return chars;
}

fn nextCodepointSimple(bytes: []const u8, index: *usize) ?u32 {
    if (index.* >= bytes.len) return null;
    const start = index.*;
    const b = bytes[start];
    var cp: u32 = undefined;
    var len: usize = 0;

    if (b < 0x80) {
        cp = b;
        len = 1;
    } else if (b & 0xE0 == 0xC0) {
        len = 2;
        cp = b & 0x1F;
    } else if (b & 0xF0 == 0xE0) {
        len = 3;
        cp = b & 0x0F;
    } else if (b & 0xF8 == 0xF0) {
        len = 4;
        cp = b & 0x07;
    } else {
        index.* += 1;
        return b;
    }

    if (start + len > bytes.len) {
        index.* = bytes.len;
        return b;
    }

    var j: usize = 1;
    while (j < len) : (j += 1) {
        cp = (cp << 6) | (bytes[start + j] & 0x3F);
    }
    index.* = start + len;
    return cp;
}

fn cpToUtf8(cp: u32, buf: *[4]u8) usize {
    if (cp < 0x80) {
        buf[0] = @intCast(cp);
        return 1;
    } else if (cp < 0x800) {
        buf[0] = @intCast(0xC0 | (cp >> 6));
        buf[1] = @intCast(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp < 0x10000) {
        buf[0] = @intCast(0xE0 | (cp >> 12));
        buf[1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = @intCast(0x80 | (cp & 0x3F));
        return 3;
    } else {
        buf[0] = @intCast(0xF0 | (cp >> 18));
        buf[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = @intCast(0x80 | (cp & 0x3F));
        return 4;
    }
}

fn trBuildTranslationTable(
    vm: *VM,
    from_expanded: std.ArrayList(u32),
    to_expanded: std.ArrayList(u32),
) VMError!std.AutoHashMap(u32, u32) {
    var table: std.AutoHashMap(u32, u32) = .init(vm.allocator);
    errdefer table.deinit();

    if (to_expanded.items.len == 0) return table;

    const last_to = to_expanded.items[to_expanded.items.len - 1];

    for (from_expanded.items, 0..) |from_cp, idx| {
        const to_cp = if (idx < to_expanded.items.len) to_expanded.items[idx] else last_to;
        table.put(from_cp, to_cp) catch return error.Fatal;
    }

    return table;
}

fn stringTrCompute(vm: *VM, string_obj: *value.StringObject, from_arg: Value, to_arg: Value) VMError!TrResult {
    const from_str = try trParseArg(vm, from_arg);
    const to_str = try trParseArg(vm, to_arg);

    if (from_str.len == 0) {
        return .{ .bytes = string_obj.str, .modified = false };
    }

    var from_expanded = try trExpandSource(vm, from_str);
    defer from_expanded.deinit(vm.allocator);
    var to_expanded = try trExpandSource(vm, to_str);
    defer to_expanded.deinit(vm.allocator);

    const is_negated = from_str[0] == '^' and from_expanded.items.len > 1;

    if (is_negated) {
        if (from_expanded.items.len == 0) return .{ .bytes = string_obj.str, .modified = false };

        const fill_cp = if (to_expanded.items.len > 0) to_expanded.items[to_expanded.items.len - 1] else return .{ .bytes = string_obj.str, .modified = false };

        var excluded: std.AutoHashMap(u32, void) = .init(vm.allocator);
        defer excluded.deinit();
        for (from_expanded.items[1..]) |cp| {
            excluded.put(cp, {}) catch return error.Fatal;
        }

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(vm.gc_allocator_atomic);
        var modified = false;
        var idx: usize = 0;
        while (idx < string_obj.str.len) {
            const cp_opt = nextCodepointSimple(string_obj.str, &idx);
            if (cp_opt == null) break;
            const cp = cp_opt.?;

            if (excluded.contains(cp)) {
                var buf: [4]u8 = undefined;
                const len = cpToUtf8(cp, &buf);
                out.appendSlice(vm.gc_allocator_atomic, buf[0..len]) catch return error.Fatal;
            } else {
                var buf: [4]u8 = undefined;
                const len = cpToUtf8(fill_cp, &buf);
                out.appendSlice(vm.gc_allocator_atomic, buf[0..len]) catch return error.Fatal;
                modified = true;
            }
        }
        return .{
            .bytes = out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal,
            .modified = modified,
        };
    }

    var table = try trBuildTranslationTable(vm, from_expanded, to_expanded);
    defer table.deinit();

    if (table.count() == 0) {
        return .{ .bytes = string_obj.str, .modified = false };
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);
    var modified = false;
    var idx: usize = 0;
    while (idx < string_obj.str.len) {
        const start = idx;
        const cp_opt = nextCodepointSimple(string_obj.str, &idx);
        if (cp_opt == null) break;
        const cp = cp_opt.?;

        if (table.get(cp)) |mapped| {
            var buf: [4]u8 = undefined;
            const len = cpToUtf8(mapped, &buf);
            out.appendSlice(vm.gc_allocator_atomic, buf[0..len]) catch return error.Fatal;
            modified = true;
        } else {
            const char_bytes = string_obj.str[start..idx];
            out.appendSlice(vm.gc_allocator_atomic, char_bytes) catch return error.Fatal;
        }
    }

    return .{
        .bytes = out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal,
        .modified = modified,
    };
}

fn stringTrSCompute(vm: *VM, string_obj: *value.StringObject, from_arg: Value, to_arg: Value) VMError!TrResult {
    const from_str = try trParseArg(vm, from_arg);
    const to_str = try trParseArg(vm, to_arg);

    if (from_str.len == 0) {
        return .{ .bytes = string_obj.str, .modified = false };
    }

    var from_expanded = try trExpandSource(vm, from_str);
    defer from_expanded.deinit(vm.allocator);
    var to_expanded = try trExpandSource(vm, to_str);
    defer to_expanded.deinit(vm.allocator);

    const is_negated = from_str[0] == '^' and from_expanded.items.len > 1;

    var table: std.AutoHashMap(u32, u32) = .init(vm.allocator);
    defer table.deinit();

    if (!is_negated) {
        table = try trBuildTranslationTable(vm, from_expanded, to_expanded);
        if (table.count() == 0) {
            return .{ .bytes = string_obj.str, .modified = false };
        }
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc_allocator_atomic);
    var modified = false;
    var idx: usize = 0;
    var last_mapped_cp: u32 = undefined;
    var has_last_mapped = false;

    while (idx < string_obj.str.len) {
        const start = idx;
        const cp_opt = nextCodepointSimple(string_obj.str, &idx);
        if (cp_opt == null) break;
        const cp = cp_opt.?;

        var mapped_cp: u32 = undefined;
        var should_replace = false;

        if (is_negated) {
            var excluded: std.AutoHashMap(u32, void) = .init(vm.allocator);
            defer excluded.deinit();
            for (from_expanded.items[1..]) |exc_cp| {
                excluded.put(exc_cp, {}) catch return error.Fatal;
            }
            should_replace = !excluded.contains(cp);
            if (should_replace) {
                mapped_cp = if (to_expanded.items.len > 0) to_expanded.items[to_expanded.items.len - 1] else cp;
            }
        } else {
            if (table.get(cp)) |mp| {
                should_replace = true;
                mapped_cp = mp;
            }
        }

        if (should_replace) {
            if (!has_last_mapped or last_mapped_cp != mapped_cp) {
                var buf: [4]u8 = undefined;
                const len = cpToUtf8(mapped_cp, &buf);
                out.appendSlice(vm.gc_allocator_atomic, buf[0..len]) catch return error.Fatal;
                last_mapped_cp = mapped_cp;
                has_last_mapped = true;
                modified = true;
            }
        } else {
            const char_bytes = string_obj.str[start..idx];
            out.appendSlice(vm.gc_allocator_atomic, char_bytes) catch return error.Fatal;
            has_last_mapped = false;
        }
    }

    return .{
        .bytes = out.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal,
        .modified = modified,
    };
}

pub fn builtinStringTr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const string_obj = receiver.toStringObject();
    const result = try stringTrCompute(vm, string_obj, args[0], args[1]);
    return try vm.newStringWithEncoding(result.bytes, false, string_obj.encoding);
}

pub fn builtinStringTrBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const result = try stringTrCompute(vm, string_obj, args[0], args[1]);
    if (!result.modified) return Value.nil();

    try warnSymbolToSMutation(vm, string_obj);
    string_obj.str = result.bytes;
    string_obj.validity = .unknown;
    string_obj.symbol_to_s_source = null;
    return receiver;
}

pub fn builtinStringTrS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const string_obj = receiver.toStringObject();
    const result = try stringTrSCompute(vm, string_obj, args[0], args[1]);
    return try vm.newStringWithEncoding(result.bytes, false, string_obj.encoding);
}

pub fn builtinStringTrSBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const result = try stringTrSCompute(vm, string_obj, args[0], args[1]);
    if (!result.modified) return Value.nil();

    try warnSymbolToSMutation(vm, string_obj);
    string_obj.str = result.bytes;
    string_obj.validity = .unknown;
    string_obj.symbol_to_s_source = null;
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
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, needle_enc);
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

fn splitAppendBytes(vm: *VM, array_obj: *value.ArrayObject, bytes: []const u8, encoding: enc.Encoding) VMError!void {
    const str_value = try vm.newStringWithEncoding(bytes, false, encoding);
    array_obj.elements.append(vm.gc_allocator, str_value) catch return error.Fatal;
}

fn splitAppendCaptureValues(vm: *VM, array_obj: *value.ArrayObject, source_obj: *value.StringObject, begins: []const i64, ends: []const i64) VMError!void {
    var capture_index: usize = 1;
    while (capture_index < begins.len and capture_index < ends.len) : (capture_index += 1) {
        const begin_i64 = begins[capture_index];
        const end_i64 = ends[capture_index];
        if (begin_i64 < 0 or end_i64 < 0) continue;

        const begin_usize: usize = @intCast(begin_i64);
        const end_usize: usize = @intCast(end_i64);
        if (begin_usize > source_obj.str.len or end_usize > source_obj.str.len or begin_usize > end_usize) {
            return error.Fatal;
        }
        try splitAppendBytes(vm, array_obj, source_obj.str[begin_usize..end_usize], source_obj.encoding);
    }
}

fn splitTrimTrailingEmptyFields(array_obj: *value.ArrayObject) void {
    while (array_obj.elements.items.len > 0) {
        const last = array_obj.elements.items[array_obj.elements.items.len - 1];
        if (!last.isString()) break;
        if (last.toStringObject().str.len != 0) break;
        _ = array_obj.elements.pop();
    }
}

fn splitYieldOrReturn(vm: *VM, receiver: Value, array_obj: *value.ArrayObject, block: ?Block) VMError!Value {
    if (block) |blk| {
        for (array_obj.elements.items) |item| {
            const yielded = try vm.yieldToBlock(blk, &[_]Value{item});
            if (yielded.controlFlowValue()) |return_value| return return_value;
        }
        return receiver;
    }
    return Value.fromObject(&array_obj.object);
}

fn splitRaiseInvalidSource(vm: *VM, encoding: enc.Encoding) VMError!Value {
    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{encoding.name()});
}

fn splitParseLimit(vm: *VM, args: []Value) VMError!i64 {
    if (args.len < 2) return 0;

    const limit = try args[1].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    if (limit > std.math.maxInt(i32) or limit < std.math.minInt(i32)) {
        return vm.raiseExceptionFmt(vm.range_error_class, "bignum too big to convert into `long`", .{});
    }
    return limit;
}

fn splitNextCharBoundary(bytes: []const u8, encoding: enc.Encoding, offset: usize) usize {
    if (offset >= bytes.len) return bytes.len;

    var next = offset;
    const parsed = encoding.nextChar(bytes, &next);
    if (parsed.len > 0 and next > offset) return next;
    return offset + 1;
}

fn splitDefaultWhitespace(vm: *VM, array_obj: *value.ArrayObject, source_obj: *value.StringObject, limit: i64) VMError!void {
    const source = source_obj.str;
    if (!source_obj.encoding.isValid(source)) {
        _ = try splitRaiseInvalidSource(vm, source_obj.encoding);
        return;
    }

    if (limit == 1) {
        try splitAppendBytes(vm, array_obj, source, source_obj.encoding);
        return;
    }

    var i: usize = 0;
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

    while (i < source.len) {
        if (limit > 0 and array_obj.elements.items.len == @as(usize, @intCast(limit - 1))) {
            try splitAppendBytes(vm, array_obj, source[i..], source_obj.encoding);
            return;
        }

        const token_start = i;
        while (i < source.len and !std.ascii.isWhitespace(source[i])) : (i += 1) {}
        try splitAppendBytes(vm, array_obj, source[token_start..i], source_obj.encoding);

        var saw_separator = false;
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {
            saw_separator = true;
        }
        if (i >= source.len and saw_separator and (limit < 0 or (limit > 0 and array_obj.elements.items.len < @as(usize, @intCast(limit))))) {
            try splitAppendBytes(vm, array_obj, "", source_obj.encoding);
        }
    }
}

fn splitByCharacters(vm: *VM, array_obj: *value.ArrayObject, source_obj: *value.StringObject, limit: i64) VMError!void {
    const source = source_obj.str;
    if (!source_obj.encoding.isValid(source)) {
        _ = try splitRaiseInvalidSource(vm, source_obj.encoding);
        return;
    }

    if (limit == 1) {
        try splitAppendBytes(vm, array_obj, source, source_obj.encoding);
        return;
    }

    var i: usize = 0;
    while (i < source.len) {
        if (limit > 0 and array_obj.elements.items.len == @as(usize, @intCast(limit - 1))) {
            try splitAppendBytes(vm, array_obj, source[i..], source_obj.encoding);
            return;
        }

        const start = i;
        i = splitNextCharBoundary(source, source_obj.encoding, i);
        try splitAppendBytes(vm, array_obj, source[start..i], source_obj.encoding);
    }

    if (array_obj.elements.items.len > 0 and (limit < 0 or limit > @as(i64, @intCast(array_obj.elements.items.len)))) {
        try splitAppendBytes(vm, array_obj, "", source_obj.encoding);
    }
}

fn splitByLiteral(vm: *VM, array_obj: *value.ArrayObject, source_obj: *value.StringObject, separator_obj: *value.StringObject, limit: i64) VMError!void {
    const source = source_obj.str;
    const separator = separator_obj.str;

    if (!source_obj.encoding.isValid(source)) {
        _ = try splitRaiseInvalidSource(vm, source_obj.encoding);
        return;
    }
    if (!separator_obj.encoding.isValid(separator)) {
        _ = try splitRaiseInvalidSource(vm, separator_obj.encoding);
        return;
    }

    if (separator.len == 0) {
        try splitByCharacters(vm, array_obj, source_obj, limit);
        return;
    }
    if (limit == 1) {
        try splitAppendBytes(vm, array_obj, source, source_obj.encoding);
        return;
    }
    if (separator.len == 1 and separator[0] == ' ') {
        try splitDefaultWhitespace(vm, array_obj, source_obj, limit);
        return;
    }

    var start: usize = 0;
    while (true) {
        if (limit > 0 and array_obj.elements.items.len == @as(usize, @intCast(limit - 1))) break;

        const idx = std.mem.indexOfPos(u8, source, start, separator) orelse break;
        try splitAppendBytes(vm, array_obj, source[start..idx], source_obj.encoding);
        start = idx + separator.len;
    }

    try splitAppendBytes(vm, array_obj, source[start..], source_obj.encoding);
    if (limit == 0) splitTrimTrailingEmptyFields(array_obj);
}

fn splitByRegexp(vm: *VM, array_obj: *value.ArrayObject, source_obj: *value.StringObject, regexp_obj: *value.RegexpObject, limit: i64) VMError!void {
    const source = source_obj.str;
    if (!source_obj.encoding.isValid(source)) {
        _ = try splitRaiseInvalidSource(vm, source_obj.encoding);
        return;
    }
    if (source.len == 0) return;

    if (limit == 1) {
        try splitAppendBytes(vm, array_obj, source, source_obj.encoding);
        return;
    }

    var start: usize = 0;
    var search_offset: usize = 0;
    var field_count: usize = 0;

    while (search_offset <= source.len) {
        if (limit > 0 and field_count == @as(usize, @intCast(limit - 1))) break;

        const search_result = onigmo.searchWithCaptures(vm.gc_allocator, regexp_obj.regex, source[search_offset..]) catch return error.Fatal;
        defer vm.gc_allocator.free(search_result.begin_offsets);
        defer vm.gc_allocator.free(search_result.end_offsets);
        if (!search_result.matched) break;

        for (search_result.begin_offsets, search_result.end_offsets) |*begin_pos, *end_pos| {
            if (begin_pos.* >= 0) begin_pos.* += @as(i64, @intCast(search_offset));
            if (end_pos.* >= 0) end_pos.* += @as(i64, @intCast(search_offset));
        }

        if (search_result.begin_offsets.len == 0 or search_result.end_offsets.len == 0) return error.Fatal;

        const match_start_i64 = search_result.begin_offsets[0];
        const match_end_i64 = search_result.end_offsets[0];
        if (match_start_i64 < 0 or match_end_i64 < 0) return error.Fatal;

        const match_start: usize = @intCast(match_start_i64);
        const match_end: usize = @intCast(match_end_i64);
        if (match_start > source.len or match_end > source.len or match_start > match_end) return error.Fatal;

        if (match_start == match_end) {
            if (match_start == source.len) {
                if (limit == 0) break;
                if (limit > 0 and field_count == @as(usize, @intCast(limit - 1))) break;
            }
            if (match_start == 0 and start == 0) {
                search_offset = splitNextCharBoundary(source, source_obj.encoding, match_start);
                continue;
            }
            if (match_start == start) {
                search_offset = splitNextCharBoundary(source, source_obj.encoding, match_start);
                continue;
            }
        }

        try splitAppendBytes(vm, array_obj, source[start..match_start], source_obj.encoding);
        field_count += 1;
        try splitAppendCaptureValues(vm, array_obj, source_obj, search_result.begin_offsets, search_result.end_offsets);
        start = match_end;
        search_offset = if (match_start == match_end and match_end == source.len)
            source.len + 1
        else if (match_start == match_end)
            splitNextCharBoundary(source, source_obj.encoding, match_end)
        else
            match_end;
    }

    try splitAppendBytes(vm, array_obj, source[start..], source_obj.encoding);
    field_count += 1;
    if (limit == 0) splitTrimTrailingEmptyFields(array_obj);
}

pub fn builtinStringSplit(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 2);

    const string_obj = receiver.toStringObject();
    const result = try vm.createArray();
    const limit = try splitParseLimit(vm, args);

    var effective_separator: Value = Value.nil();
    var use_default_separator = false;

    if (args.len == 0 or args[0].isNil()) {
        const field_separator = vm.globals.get("$;") orelse Value.nil();
        if (!field_separator.isNil()) {
            try warning_builtin.writeWarning(vm, "warning: $; is set to non-nil value\n");
            effective_separator = field_separator;
        } else {
            use_default_separator = true;
        }
    } else {
        effective_separator = args[0];
    }

    if (use_default_separator) {
        try splitDefaultWhitespace(vm, result, string_obj, limit);
        return splitYieldOrReturn(vm, receiver, result, block);
    }

    if (effective_separator.isRegexp()) {
        try splitByRegexp(vm, result, string_obj, effective_separator.toRegexpObject(), limit);
        return splitYieldOrReturn(vm, receiver, result, block);
    }

    const separator_value = try effective_separator.coerceToStringValue(vm, "no implicit conversion into String");
    try splitByLiteral(vm, result, string_obj, separator_value.toStringObject(), limit);
    return splitYieldOrReturn(vm, receiver, result, block);
}

fn stringChopEnd(bytes: []const u8, encoding: enc.Encoding) usize {
    if (bytes.len == 0) return 0;

    var i: usize = 0;
    var second_last_start: ?usize = null;
    var last_start: usize = 0;
    while (i < bytes.len) {
        second_last_start = last_start;
        last_start = i;
        const parsed = encoding.nextChar(bytes, &i);
        if (parsed.len == 0 or i <= last_start) {
            i = last_start + 1;
        }
    }

    if (second_last_start) |prev_start| {
        const last_codepoint = encoding.toUnicodeCodepoint(bytes[last_start..]) orelse return last_start;
        const prev_codepoint = encoding.toUnicodeCodepoint(bytes[prev_start..last_start]) orelse return last_start;
        if (prev_codepoint == '\r' and last_codepoint == '\n') return prev_start;
    }

    return last_start;
}

const TrailingLineEnding = enum {
    none,
    lf,
    cr,
    crlf,
};

fn stringTrailingLineEnding(bytes: []const u8, encoding: enc.Encoding) TrailingLineEnding {
    if (bytes.len == 0) return .none;

    var i: usize = 0;
    var second_last_start: ?usize = null;
    var last_start: usize = 0;
    while (i < bytes.len) {
        second_last_start = last_start;
        last_start = i;
        const parsed = encoding.nextChar(bytes, &i);
        if (parsed.len == 0 or i <= last_start) {
            i = last_start + 1;
        }
    }

    const last_codepoint = encoding.toUnicodeCodepoint(bytes[last_start..]) orelse return .none;
    if (last_codepoint == '\r') return .cr;
    if (last_codepoint != '\n') return .none;

    if (second_last_start) |prev_start| {
        const prev_codepoint = encoding.toUnicodeCodepoint(bytes[prev_start..last_start]) orelse return .lf;
        if (prev_codepoint == '\r') return .crlf;
    }

    return .lf;
}

fn stringChompLineEndingEnd(bytes: []const u8, encoding: enc.Encoding) usize {
    return switch (stringTrailingLineEnding(bytes, encoding)) {
        .none => bytes.len,
        .lf, .cr, .crlf => stringChopEnd(bytes, encoding),
    };
}

fn stringChompEnd(vm: *VM, bytes: []const u8, encoding: enc.Encoding, args: []Value) VMError!usize {
    try vm.requireArgCountRange(args, 0, 1);
    if (bytes.len == 0) return 0;

    var separator_value: Value = undefined;
    if (args.len == 0) {
        separator_value = vm.globals.get("$/") orelse Value.nil();
    } else {
        separator_value = args[0];
    }

    if (separator_value.isNil()) return bytes.len;

    const separator_string = try separator_value.coerceToStringValue(vm, "no implicit conversion into String");
    const separator = separator_string.toStringObject().str;
    if (separator.len == 0) {
        var end = bytes.len;
        while (end > 0) {
            switch (stringTrailingLineEnding(bytes[0..end], encoding)) {
                .lf, .crlf => end = stringChopEnd(bytes[0..end], encoding),
                .none, .cr => break,
            }
        }
        return end;
    }

    if (separator_string.toStringObject().encoding.toUnicodeCodepoint(separator) == '\n' and
        separator_string.toStringObject().encoding.charCount(separator) == 1)
    {
        return stringChompLineEndingEnd(bytes, encoding);
    }

    if (std.mem.endsWith(u8, bytes, separator)) return bytes.len - separator.len;
    return bytes.len;
}

inline fn isStringStripByte(byte: u8) bool {
    return switch (byte) {
        0, ' ', '\t', '\n', '\r', 0x0B, 0x0C => true,
        else => false,
    };
}

const StringStripBounds = struct {
    start: usize,
    end: usize,
};

fn stringStripBounds(bytes: []const u8) StringStripBounds {
    var start: usize = 0;
    while (start < bytes.len and isStringStripByte(bytes[start])) : (start += 1) {}

    var end = bytes.len;
    while (end > start and isStringStripByte(bytes[end - 1])) : (end -= 1) {}

    return .{ .start = start, .end = end };
}

pub fn builtinStringStrip(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);
    return vm.newStringWithEncoding(string_obj.str[bounds.start..bounds.end], false, string_obj.encoding);
}

pub fn builtinStringStripBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);
    if (bounds.start == 0 and bounds.end == string_obj.str.len) return Value.nil();

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[bounds.start..bounds.end]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringLstrip(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);
    return vm.newStringWithEncoding(string_obj.str[bounds.start..string_obj.str.len], false, string_obj.encoding);
}

pub fn builtinStringLstripBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);

    const check_encoding_valid = bounds.start > 0 or string_obj.str.len > 0;
    if (check_encoding_valid and !string_obj.encoding.isValid(string_obj.str)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid encoding", .{});
    }

    if (bounds.start == 0) return Value.nil();

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[bounds.start..]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringRstrip(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);
    if (bounds.end <= bounds.start) return vm.newStringWithEncoding("", false, string_obj.encoding);
    return vm.newStringWithEncoding(string_obj.str[0..bounds.end], false, string_obj.encoding);
}

pub fn builtinStringRstripBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const bounds = stringStripBounds(string_obj.str);

    if (bounds.end < string_obj.str.len or (bounds.end > 0 and bounds.end > bounds.start)) {
        if (!string_obj.encoding.isValid(string_obj.str[0..bounds.end])) {
            return vm.raiseExceptionFmt(vm.encoding_compatibility_error_class, "invalid byte sequence in {s}", .{string_obj.encoding.name()});
        }
    }

    if (bounds.end == string_obj.str.len and bounds.start == 0) return Value.nil();

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, string_obj.str[0..bounds.end]) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringChop(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const chop_end = stringChopEnd(string_obj.str, string_obj.encoding);
    return vm.newStringWithEncoding(string_obj.str[0..chop_end], false, string_obj.encoding);
}

pub fn builtinStringChopBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    if (string_obj.str.len == 0) return Value.nil();

    const chop_end = stringChopEnd(string_obj.str, string_obj.encoding);
    string_obj.str = string_obj.str[0..chop_end];
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringChomp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    const chomp_end = try stringChompEnd(vm, string_obj.str, string_obj.encoding, args);
    return vm.newStringWithEncoding(string_obj.str[0..chomp_end], false, string_obj.encoding);
}

pub fn builtinStringChompBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }

    const string_obj = receiver.toStringObject();
    const chomp_end = try stringChompEnd(vm, string_obj.str, string_obj.encoding, args);
    if (chomp_end == string_obj.str.len) return Value.nil();

    string_obj.str = string_obj.str[0..chomp_end];
    string_obj.validity = .unknown;
    return receiver;
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
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCase(vm, string_obj.str, string_obj.encoding, args, .upcase);
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringUpcaseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .upcase);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCaseWithOptions(vm, string_obj.str, string_obj.encoding, options, .upcase);
    return applyMappedStringCaseBang(vm, receiver, string_obj, mapped, true);
}

pub fn builtinStringDowncase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCase(vm, string_obj.str, string_obj.encoding, args, .downcase);
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringDowncaseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .downcase);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCaseWithOptions(vm, string_obj.str, string_obj.encoding, options, .downcase);
    return applyMappedStringCaseBang(vm, receiver, string_obj, mapped, false);
}

pub fn builtinStringSwapcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCase(vm, string_obj.str, string_obj.encoding, args, .swapcase);
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringSwapcaseBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .swapcase);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCaseWithOptions(vm, string_obj.str, string_obj.encoding, options, .swapcase);
    return applyMappedStringCaseBang(vm, receiver, string_obj, mapped, false);
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
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCase(vm, string_obj.str, string_obj.encoding, args, .capitalize);
    return try vm.newStringWithEncoding(mapped.bytes, false, mapped.encoding);
}

pub fn builtinStringCapitalizeBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const options = try parseCaseMapOptions(vm, args, .capitalize);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.toStringObject();
    const mapped = try mapStringCaseWithOptions(vm, string_obj.str, string_obj.encoding, options, .capitalize);
    return applyMappedStringCaseBang(vm, receiver, string_obj, mapped, false);
}

fn applyMappedStringCaseBang(
    vm: *VM,
    receiver: Value,
    string_obj: *value.StringObject,
    mapped: enc.CaseMapResult,
    clear_symbol_to_s_source: bool,
) VMError!Value {
    if (!mapped.modified) return Value.nil();

    if (clear_symbol_to_s_source) {
        try warnSymbolToSMutation(vm, string_obj);
        string_obj.symbol_to_s_source = null;
    }

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

pub fn stringNextBytes(vm: *VM, bytes: []const u8) VMError![]u8 {
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

pub fn builtinStringToR(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const parsed = try rational_builtin.parseStringToRational(vm, receiver.toStringObject().str) orelse {
        return vm.newRational(0, 1);
    };
    return vm.newRationalValues(parsed.numerator, parsed.denominator);
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
                    try writer.print("\\x{X:0>2}", .{c});
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
        var escaped_bytes: std.Io.Writer.Allocating = .init(vm.allocator);
        defer escaped_bytes.deinit();
        const writer = &escaped_bytes.writer;
        appendSymbolErrorEscapedBytes(writer, string_obj.str) catch return error.Fatal;
        const escaped = escaped_bytes.toOwnedSlice() catch return error.Fatal;
        defer vm.allocator.free(escaped);
        return vm.raiseExceptionFmt(vm.encoding_error_class, "invalid symbol in encoding {s} :\"{s}\"", .{ string_obj.encoding.name(), escaped });
    }

    const symbol_encoding: enc.Encoding = if (!string_obj.encoding.isDummy() and string_obj.encoding.isAsciiCompatible() and enc.isAsciiOnly(string_obj.str))
        .{ .us_ascii = .{} }
    else
        string_obj.encoding;
    const sym = try vm.internWithEncoding(string_obj.str, symbol_encoding);
    return Value.fromObject(&sym.object);
}

pub fn builtinStringInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const str = inspect_util.inspectStringBytes(vm.allocator, string_obj.str, string_obj.encoding, vm.inspectTargetEncoding()) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, vm.inspectTargetEncoding());
}

pub fn builtinStringDump(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const str = inspect_util.dumpStringBytes(vm.allocator, string_obj.str, string_obj.encoding) catch return error.Fatal;
    defer vm.allocator.free(str);
    const result_encoding: enc.Encoding = if (string_obj.encoding.isAsciiCompatible())
        string_obj.encoding
    else
        .{ .ascii_8bit = .{} };
    return try vm.newStringWithEncoding(str, false, result_encoding);
}

pub fn builtinStringSum(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const string_obj = receiver.toStringObject();
    var sum: u64 = 0;
    for (string_obj.str) |byte| {
        sum += byte;
    }
    if (args.len == 1 and args[0].isInteger()) {
        const n = args[0].toInteger();
        if (n > 0) {
            const mask: u64 = (@as(u64, 1) << @as(u6, @intCast(n))) - 1;
            sum = sum & mask;
        }
    } else if (args.len == 1) {
        const n = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (n > 0) {
            const mask: u64 = (@as(u64, 1) << @as(u6, @intCast(n))) - 1;
            sum = sum & mask;
        }
    }
    return Value.integer(@intCast(sum));
}

pub fn builtinStringMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "type mismatch: String given", .{});
    }
    var match_args = [_]Value{receiver};
    return vm.callMethodByName(args[0], "=~", match_args[0..], null);
}

pub fn builtinStringMatch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    return callStringMatch(vm, receiver, args, "match", block);
}

pub fn builtinStringMatchQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    return callStringMatch(vm, receiver, args, "match?", null);
}

pub fn builtinStringIndex(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();

    const start_pos = if (args.len == 2)
        try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        )
    else
        null;

    const char_len_i64: i64 = @intCast(string_obj.encoding.charCount(string_obj.str));
    const normalized_start_pos = blk: {
        var pos = start_pos orelse 0;
        if (pos < 0) pos += char_len_i64;
        if (pos < 0 or pos > char_len_i64) {
            if (args[0].isRegexp()) try vm.clearLastMatch();
            return Value.nil();
        }
        break :blk pos;
    };

    const start_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(normalized_start_pos)) orelse {
        if (args[0].isRegexp()) try vm.clearLastMatch();
        return Value.nil();
    };

    if (args[0].isRegexp()) {
        return regexp_builtin.regexpMatchOpAt(vm, args[0].toRegexpObject(), receiver, normalized_start_pos, true);
    }

    const needle_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const needle_obj = needle_value.toStringObject();
    const needle = needle_obj.str;

    if (enc.negotiate(string_obj.encoding, string_obj.str, needle_obj.encoding, needle) == null) {
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, needle_obj.encoding);
    }

    if (needle.len == 0) {
        return Value.integer(normalized_start_pos);
    }

    if (needle.len > string_obj.str.len or start_byte > string_obj.str.len - needle.len) {
        return Value.nil();
    }

    var pos = start_byte;
    while (pos <= string_obj.str.len - needle.len) {
        const found = std.mem.indexOfPos(u8, string_obj.str, pos, needle) orelse return Value.nil();
        const end = found + needle.len;
        if (string_obj.encoding.isCharBoundary(string_obj.str, found) and string_obj.encoding.isCharBoundary(string_obj.str, end)) {
            return Value.integer(@intCast(string_obj.encoding.charCount(string_obj.str[0..found])));
        }
        pos = found + 1;
    }

    return Value.nil();
}

pub fn builtinStringRindex(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const char_len_i64: i64 = @intCast(string_obj.encoding.charCount(string_obj.str));

    const raw_pos = if (args.len == 2)
        try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        )
    else
        null;

    // Normalize the search position (max char index where match may start).
    const max_char_pos: i64 = blk: {
        var pos = raw_pos orelse char_len_i64;
        if (pos < 0) pos += char_len_i64;
        if (pos < 0) {
            if (args[0].isRegexp()) try vm.clearLastMatch();
            return Value.nil();
        }
        // Clamp to char_len (matching that allows empty match at end).
        if (pos > char_len_i64) pos = char_len_i64;
        break :blk pos;
    };

    // Regexp case: delegate to backward regexp search.
    if (args[0].isRegexp()) {
        return regexp_builtin.regexpRindexAt(vm, args[0].toRegexpObject(), receiver, max_char_pos, true);
    }

    // String/to_str case.
    const needle_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const needle_obj = needle_value.toStringObject();
    const needle = needle_obj.str;

    if (enc.negotiate(string_obj.encoding, string_obj.str, needle_obj.encoding, needle) == null) {
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, needle_obj.encoding);
    }

    // Empty needle: return max_char_pos (already clamped to char_len).
    if (needle.len == 0) {
        return Value.integer(max_char_pos);
    }

    if (needle.len > string_obj.str.len) {
        return Value.nil();
    }

    // Convert max_char_pos to a byte position.  The last match of needle must
    // start at or before this byte.
    const max_start_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(max_char_pos)) orelse string_obj.str.len;

    // Search backward: find the rightmost occurrence starting at byte <= max_start_byte.
    // We work in the window string[0..max_start_byte + needle.len] (capped at str.len)
    // so that a match beginning exactly at max_start_byte can still be found.
    const window_end = @min(max_start_byte + needle.len, string_obj.str.len);
    const haystack = string_obj.str[0..window_end];

    var result_char_pos: ?i64 = null;
    var pos: usize = 0;
    while (pos + needle.len <= haystack.len) {
        const found = std.mem.indexOfPos(u8, haystack, pos, needle) orelse break;
        const found_end = found + needle.len;
        if (string_obj.encoding.isCharBoundary(string_obj.str, found) and
            string_obj.encoding.isCharBoundary(string_obj.str, found_end))
        {
            const char_pos: i64 = @intCast(string_obj.encoding.charCount(string_obj.str[0..found]));
            if (char_pos <= max_char_pos) {
                result_char_pos = char_pos;
            }
        }
        pos = found + 1;
    }

    return if (result_char_pos) |cp| Value.integer(cp) else Value.nil();
}

pub fn builtinStringPartition(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    if (args[0].isRegexp()) {
        const match_idx = try regexp_builtin.regexpMatchOp(vm, args[0].toRegexpObject(), receiver);
        if (match_idx.isNil()) {
            const whole = try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
            const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
            return newArrayWith3Values(vm, .{ whole, empty, empty });
        }
        const md_val = vm.getGlobalValue("$~");
        if (!md_val.isMatchData()) return error.Fatal;
        const md = md_val.toMatchDataObject();
        if (md.begin_byte_offsets.items.len == 0) return error.Fatal;
        const match_byte = md.begin_byte_offsets.items[0];
        if (match_byte < 0) return error.Fatal;
        const end_byte = md.end_byte_offsets.items[0];
        if (end_byte < 0) return error.Fatal;
        const match_byte_usize: usize = @intCast(match_byte);
        const end_byte_usize: usize = @intCast(end_byte);
        const before = try vm.newStringWithEncoding(string_obj.str[0..match_byte_usize], false, string_obj.encoding);
        const separator = try vm.newStringWithEncoding(string_obj.str[match_byte_usize..end_byte_usize], false, string_obj.encoding);
        const after = try vm.newStringWithEncoding(string_obj.str[end_byte_usize..], false, string_obj.encoding);
        return newArrayWith3Values(vm, .{ before, separator, after });
    }

    const needle_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const needle_obj = needle_value.toStringObject();
    const needle = needle_obj.str;

    if (enc.negotiate(string_obj.encoding, string_obj.str, needle_obj.encoding, needle) == null) {
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, needle_obj.encoding);
    }

    if (needle.len == 0) {
        const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
        const whole = try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
        return newArrayWith3Values(vm, .{ empty, empty, whole });
    }

    const idx = std.mem.indexOf(u8, string_obj.str, needle) orelse {
        const whole = try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
        const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
        return newArrayWith3Values(vm, .{ whole, empty, empty });
    };
    const before = try vm.newStringWithEncoding(string_obj.str[0..idx], false, string_obj.encoding);
    const separator = try vm.newStringWithEncoding(needle, false, needle_obj.encoding);
    const after = try vm.newStringWithEncoding(string_obj.str[idx + needle.len ..], false, string_obj.encoding);
    return newArrayWith3Values(vm, .{ before, separator, after });
}

fn newArrayWith3Values(vm: *VM, values: [3]Value) VMError!Value {
    const array_obj = try vm.createArray();
    for (values) |item| {
        array_obj.elements.append(vm.gc_allocator, item) catch return error.Fatal;
    }
    return Value.fromObject(&array_obj.object);
}

fn newEmptyStringWithEncoding(vm: *VM, encoding: enc.Encoding) VMError!Value {
    return vm.newStringWithEncoding("", false, encoding);
}

pub fn builtinStringRpartition(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const string_obj = receiver.toStringObject();

    if (args[0].isRegexp()) {
        const match_idx = try regexp_builtin.regexpMatchOp(vm, args[0].toRegexpObject(), receiver);
        if (match_idx.isNil()) {
            const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
            const whole = try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
            return newArrayWith3Values(vm, .{ empty, empty, whole });
        }
        const md_val = vm.getGlobalValue("$~");
        if (!md_val.isMatchData()) return error.Fatal;
        const md = md_val.toMatchDataObject();
        if (md.begin_byte_offsets.items.len == 0) return error.Fatal;
        const match_byte = md.begin_byte_offsets.items[0];
        if (match_byte < 0) return error.Fatal;
        const end_byte = md.end_byte_offsets.items[0];
        if (end_byte < 0) return error.Fatal;
        const match_byte_usize: usize = @intCast(match_byte);
        const end_byte_usize: usize = @intCast(end_byte);
        const before = try vm.newStringWithEncoding(string_obj.str[0..match_byte_usize], false, string_obj.encoding);
        const separator = try vm.newStringWithEncoding(string_obj.str[match_byte_usize..end_byte_usize], false, string_obj.encoding);
        const after = try vm.newStringWithEncoding(string_obj.str[end_byte_usize..], false, string_obj.encoding);
        return newArrayWith3Values(vm, .{ before, separator, after });
    }

    const needle_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const needle_obj = needle_value.toStringObject();
    const needle = needle_obj.str;

    if (enc.negotiate(string_obj.encoding, string_obj.str, needle_obj.encoding, needle) == null) {
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, needle_obj.encoding);
    }

    if (needle.len == 0) {
        const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
        if (string_obj.str.len == 0) {
            return newArrayWith3Values(vm, .{ empty, empty, empty });
        }
        const split_at = string_obj.str.len - 1;
        const before = try vm.newStringWithEncoding(string_obj.str[0..split_at], false, string_obj.encoding);
        const after = try vm.newStringWithEncoding(string_obj.str[split_at..], false, string_obj.encoding);
        return newArrayWith3Values(vm, .{ before, empty, after });
    }

    const idx = std.mem.lastIndexOf(u8, string_obj.str, needle) orelse {
        const empty = try newEmptyStringWithEncoding(vm, string_obj.encoding);
        const whole = try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
        return newArrayWith3Values(vm, .{ empty, empty, whole });
    };
    const before = try vm.newStringWithEncoding(string_obj.str[0..idx], false, string_obj.encoding);
    const separator = try vm.newStringWithEncoding(needle, false, needle_obj.encoding);
    const after = try vm.newStringWithEncoding(string_obj.str[idx + needle.len ..], false, string_obj.encoding);
    return newArrayWith3Values(vm, .{ before, separator, after });
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

            const last_match = vm.getGlobalValue("$~");
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
                break :blk Value.fromObject(&captures.object);
            };

            if (block) |blk| {
                const yielded = try vm.yieldToBlock(blk, &[_]Value{yielded_value});
                if (yielded.controlFlowValue()) |return_value| return return_value;
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
        const pattern_obj = pattern_value.toStringObject();
        const pattern = pattern_obj.str;
        const escaped_pattern = try escapeRegexpLiteral(vm, pattern);
        defer vm.allocator.free(escaped_pattern);
        const normalized = vm.normalizeRegexpEncoding(pattern, pattern_obj.encoding, 0);
        const pattern_regexp = (try vm.newRegexpWithEncoding(escaped_pattern, normalized.options, normalized.encoding)).toRegexpObject();

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
                if (yielded.controlFlowValue()) |return_value| return return_value;
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
    return Value.fromObject(&out.?.object);
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
    const span = try charSpanByRange(vm, bytes, encoding, begin_val, end_val, exclude_end);
    if (span == null) return null;
    return bytes[span.?.start_byte..span.?.end_byte];
}

const StringSliceSelection = struct {
    value: Value,
    start_byte: ?usize = null,
    end_byte: ?usize = null,
};

const ByteSpan = struct {
    start_byte: usize,
    end_byte: usize,
};

fn stringSliceSelection(vm: *VM, receiver: Value, args: []Value) VMError!StringSliceSelection {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const bytes = string_obj.str;
    const encoding = string_obj.encoding;

    if (args.len == 1) {
        if (args[0].isRange()) {
            const range_obj = args[0].toRangeObject();
            const span = try charSpanByRange(vm, bytes, encoding, range_obj.begin, range_obj.end, range_obj.exclude_end);
            return sliceSelectionFromOptionalSpan(vm, string_obj, span);
        }
        if (args[0].isRegexp()) {
            return regexpSliceSelection(vm, receiver, args[0].toRegexpObject(), null);
        }
        if (args[0].isString()) {
            return stringNeedleSliceSelection(vm, string_obj, args[0].toStringObject().str);
        }
        return charIndexSliceSelection(vm, string_obj, args[0]);
    }

    if (args[0].isRange()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Range into Integer", .{});
    }

    if (args[0].isRegexp()) {
        return regexpSliceSelection(vm, receiver, args[0].toRegexpObject(), args[1]);
    }

    return charIndexLengthSliceSelection(vm, string_obj, args[0], args[1]);
}

fn sliceSelectionFromOptionalSpan(
    vm: *VM,
    string_obj: *value.StringObject,
    span: ?ByteSpan,
) VMError!StringSliceSelection {
    if (span == null) {
        return .{ .value = Value.nil() };
    }

    const actual = span.?;
    const slice_value = try vm.newStringWithEncoding(string_obj.str[actual.start_byte..actual.end_byte], false, string_obj.encoding);
    return .{
        .value = slice_value,
        .start_byte = actual.start_byte,
        .end_byte = actual.end_byte,
    };
}

fn charIndexSliceSelection(vm: *VM, string_obj: *value.StringObject, index_arg: Value) VMError!StringSliceSelection {
    var index = try index_arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const char_len_i64: i64 = @intCast(string_obj.encoding.charCount(string_obj.str));
    if (index < 0) index += char_len_i64;
    if (index < 0 or index >= char_len_i64) {
        return .{ .value = Value.nil() };
    }

    const start_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(index)) orelse string_obj.str.len;
    const end_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(index + 1)) orelse string_obj.str.len;
    return sliceSelectionFromOptionalSpan(vm, string_obj, .{ .start_byte = start_byte, .end_byte = end_byte });
}

fn charIndexLengthSliceSelection(vm: *VM, string_obj: *value.StringObject, index_arg: Value, length_arg: Value) VMError!StringSliceSelection {
    var index = try index_arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );
    const length = try length_arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    const char_len_i64: i64 = @intCast(string_obj.encoding.charCount(string_obj.str));
    if (index < 0) index += char_len_i64;
    if (index < 0 or index > char_len_i64 or length < 0) {
        return .{ .value = Value.nil() };
    }

    const finish = @min(index + length, char_len_i64);
    const start_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(index)) orelse string_obj.str.len;
    const end_byte = string_obj.encoding.byteOffsetForCharIndex(string_obj.str, @intCast(finish)) orelse string_obj.str.len;
    return sliceSelectionFromOptionalSpan(vm, string_obj, .{ .start_byte = start_byte, .end_byte = end_byte });
}

fn stringNeedleSliceSelection(vm: *VM, string_obj: *value.StringObject, needle: []const u8) VMError!StringSliceSelection {
    const start = std.mem.indexOf(u8, string_obj.str, needle) orelse return .{ .value = Value.nil() };
    return sliceSelectionFromOptionalSpan(vm, string_obj, .{ .start_byte = start, .end_byte = start + needle.len });
}

fn regexpSliceSelection(
    vm: *VM,
    receiver: Value,
    regexp: *value.RegexpObject,
    capture_arg: ?Value,
) VMError!StringSliceSelection {
    const string_obj = receiver.toStringObject();
    const match_index = try regexp_builtin.regexpMatchOp(vm, regexp, receiver);
    if (match_index.isNil()) {
        return .{ .value = Value.nil() };
    }

    const md_val = vm.getGlobalValue("$~");
    if (!md_val.isMatchData()) return error.Fatal;
    const md = md_val.toMatchDataObject();

    const capture_index = if (capture_arg) |arg|
        try resolveRegexpCaptureIndex(vm, md, arg)
    else
        0;
    if (capture_index == null) {
        return .{ .value = Value.nil() };
    }

    const idx = capture_index.?;
    if (idx >= md.captures.items.len or idx >= md.begin_byte_offsets.items.len or idx >= md.end_byte_offsets.items.len) {
        return .{ .value = Value.nil() };
    }

    const begin_i64 = md.begin_byte_offsets.items[idx];
    const end_i64 = md.end_byte_offsets.items[idx];
    if (begin_i64 < 0 or end_i64 < 0) {
        return .{ .value = Value.nil() };
    }

    const begin: usize = @intCast(begin_i64);
    const end_: usize = @intCast(end_i64);
    if (begin > string_obj.str.len or end_ > string_obj.str.len or begin > end_) return error.Fatal;

    return .{
        .value = md.captures.items[idx],
        .start_byte = begin,
        .end_byte = end_,
    };
}

fn resolveRegexpCaptureIndex(vm: *VM, md: *value.MatchDataObject, capture_arg: Value) VMError!?usize {
    if (capture_arg.isString()) {
        const name = capture_arg.toStringObject().str;
        if (name.len == 0) {
            return vm.raiseExceptionFmt(vm.index_error_class, "undefined group name reference: ", .{});
        }

        const backref = onigmo.nameToBackrefNumber(md.regexp.regex, md.source.str, name);
        if (backref < 0) {
            return vm.raiseExceptionFmt(vm.index_error_class, "undefined group name reference: {s}", .{name});
        }
        return @intCast(backref);
    }

    const capture_ref = try capture_arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    const captures_total_i64: i64 = @intCast(md.captures.items.len);
    if (captures_total_i64 == 0) return null;
    const capture_groups_i64 = captures_total_i64 - 1;

    var capture_idx = capture_ref;
    if (capture_idx > 0) {
        if (capture_idx > capture_groups_i64) return null;
    } else if (capture_idx < 0) {
        capture_idx = capture_groups_i64 + capture_idx + 1;
        if (capture_idx <= 0 or capture_idx > capture_groups_i64) return null;
    } else {
        capture_idx = 0;
    }

    if (capture_idx < 0 or capture_idx >= captures_total_i64) return null;
    return @intCast(capture_idx);
}

fn charSpanByRange(
    vm: *VM,
    bytes: []const u8,
    encoding: enc.Encoding,
    begin_val: Value,
    end_val: Value,
    exclude_end: bool,
) VMError!?ByteSpan {
    const char_len_i64: i64 = @intCast(encoding.charCount(bytes));

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
    if (start_idx < 0) start_idx += char_len_i64;
    if (start_idx < 0 or start_idx > char_len_i64) return null;

    var finish_exclusive: i64 = if (end_val.isNil())
        char_len_i64
    else blk: {
        var end_i64 = try end_val.coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        if (end_i64 < 0) end_i64 += char_len_i64;
        break :blk if (exclude_end) end_i64 else end_i64 + 1;
    };

    if (finish_exclusive < start_idx) {
        const start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(start_idx)) orelse bytes.len;
        return .{ .start_byte = start_byte, .end_byte = start_byte };
    }

    if (finish_exclusive < 0) finish_exclusive = 0;
    if (finish_exclusive > char_len_i64) finish_exclusive = char_len_i64;

    const start_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(start_idx)) orelse bytes.len;
    const end_byte = encoding.byteOffsetForCharIndex(bytes, @intCast(finish_exclusive)) orelse bytes.len;
    return .{ .start_byte = start_byte, .end_byte = end_byte };
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
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, replacement_obj.encoding);
    };

    const interim_encoding = resolveStringConcatEncoding(
        string_obj.encoding,
        prefix,
        replacement_obj.encoding,
        replacement_obj.str,
    ) orelse {
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, replacement_obj.encoding);
    };

    const prefix_with_replacement = try concatBytes(vm, prefix, replacement_obj.str);
    const result_encoding = resolveStringConcatEncoding(
        interim_encoding,
        prefix_with_replacement,
        string_obj.encoding,
        suffix,
    ) orelse {
        return vm.raiseEncodingCompatibilityError(interim_encoding, string_obj.encoding);
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
        return vm.raiseEncodingCompatibilityError(string_obj.encoding, rhs_encoding);
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

pub const CaseOperation = enum {
    upcase,
    downcase,
    swapcase,
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

pub fn mapStringCase(
    vm: *VM,
    bytes: []const u8,
    source_encoding: enc.Encoding,
    args: []Value,
    operation: CaseOperation,
) VMError!enc.CaseMapResult {
    const options = try parseCaseMapOptions(vm, args, operation);
    return mapStringCaseWithOptions(vm, bytes, source_encoding, options, operation);
}

fn mapStringCaseWithOptions(
    vm: *VM,
    bytes: []const u8,
    source_encoding: enc.Encoding,
    options: enc.CaseMapOptions,
    operation: CaseOperation,
) VMError!enc.CaseMapResult {
    return switch (operation) {
        .upcase => enc.caseMap(vm.gc_allocator_atomic, bytes, source_encoding, .upcase, options) catch |err| switch (err) {
            error.OutOfMemory => error.Fatal,
            error.InvalidByteSequence => vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
        },
        .downcase => enc.caseMap(vm.gc_allocator_atomic, bytes, source_encoding, .downcase, options) catch |err| switch (err) {
            error.OutOfMemory => error.Fatal,
            error.InvalidByteSequence => vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
        },
        .swapcase => enc.caseMap(vm.gc_allocator_atomic, bytes, source_encoding, .swapcase, options) catch |err| switch (err) {
            error.OutOfMemory => error.Fatal,
            error.InvalidByteSequence => vm.raiseExceptionFmt(vm.argument_error_class, "input string invalid", .{}),
        },
        .capitalize => mapStringCapitalize(vm, bytes, source_encoding, options),
    };
}

fn digitValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'z') return c - 'a' + 10;
    if (c >= 'A' and c <= 'Z') return c - 'A' + 10;
    return null;
}

pub fn builtinStringCenter(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const recv_encoding = string_obj.encoding;

    const length = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    var padstr_obj: ?*value.StringObject = null;
    var padstr_encoding: enc.Encoding = .{ .utf8 = .{} };
    if (args.len >= 2) {
        if (!args[1].isString()) {
            const padstr_val = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
            padstr_obj = padstr_val.toStringObject();
        } else {
            padstr_obj = args[1].toStringObject();
        }
        padstr_encoding = padstr_obj.?.encoding;
        if (padstr_obj.?.str.len == 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "zero width padding", .{});
        }
    }

    const char_len = recv_encoding.charCount(string_obj.str);

    if (length <= 0 or @as(usize, @intCast(length)) <= char_len) {
        return vm.newStringWithEncoding(string_obj.str, false, recv_encoding);
    }

    const target_len: usize = @intCast(length);
    const pad_chars = target_len - char_len;
    const left_pad_chars = pad_chars / 2;
    const right_pad_chars = pad_chars - left_pad_chars;

    const pad_str = if (padstr_obj) |p| p.str else " ";
    const pad_encoding = if (padstr_obj) |_| blk: {
        const result_encoding = resolveStringConcatEncoding(recv_encoding, string_obj.str, padstr_encoding, pad_str) orelse {
            return vm.raiseEncodingCompatibilityError(recv_encoding, padstr_encoding);
        };
        break :blk result_encoding;
    } else recv_encoding;

    const pad_char_count = pad_encoding.charCount(pad_str);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(vm.gc_allocator_atomic);

    var i: usize = 0;
    while (i < left_pad_chars) : (i += 1) {
        const byte_start = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count) orelse break;
        const byte_end = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count + 1) orelse pad_str.len;
        result.appendSlice(vm.gc_allocator_atomic, pad_str[byte_start..byte_end]) catch return error.Fatal;
    }

    result.appendSlice(vm.gc_allocator_atomic, string_obj.str) catch return error.Fatal;

    i = 0;
    while (i < right_pad_chars) : (i += 1) {
        const byte_start = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count) orelse break;
        const byte_end = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count + 1) orelse pad_str.len;
        result.appendSlice(vm.gc_allocator_atomic, pad_str[byte_start..byte_end]) catch return error.Fatal;
    }

    const out = result.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
    return vm.newStringWithEncoding(out, false, pad_encoding);
}

pub fn builtinStringLjust(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const recv_encoding = string_obj.encoding;

    const length = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    var padstr_obj: ?*value.StringObject = null;
    var padstr_encoding: enc.Encoding = .{ .utf8 = .{} };
    if (args.len >= 2) {
        if (!args[1].isString()) {
            const padstr_val = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
            padstr_obj = padstr_val.toStringObject();
        } else {
            padstr_obj = args[1].toStringObject();
        }
        padstr_encoding = padstr_obj.?.encoding;
        if (padstr_obj.?.str.len == 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "zero width padding", .{});
        }
    }

    const char_len = recv_encoding.charCount(string_obj.str);

    if (length <= 0 or @as(usize, @intCast(length)) <= char_len) {
        return vm.newStringWithEncoding(string_obj.str, false, recv_encoding);
    }

    const target_len: usize = @intCast(length);
    const pad_chars = target_len - char_len;

    const pad_str = if (padstr_obj) |p| p.str else " ";
    const pad_encoding = if (padstr_obj) |_| blk: {
        const result_encoding = resolveStringConcatEncoding(recv_encoding, string_obj.str, padstr_encoding, pad_str) orelse {
            return vm.raiseEncodingCompatibilityError(recv_encoding, padstr_encoding);
        };
        break :blk result_encoding;
    } else recv_encoding;

    const pad_char_count = pad_encoding.charCount(pad_str);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(vm.gc_allocator_atomic);

    result.appendSlice(vm.gc_allocator_atomic, string_obj.str) catch return error.Fatal;

    var i: usize = 0;
    while (i < pad_chars) : (i += 1) {
        const byte_start = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count) orelse break;
        const byte_end = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count + 1) orelse pad_str.len;
        result.appendSlice(vm.gc_allocator_atomic, pad_str[byte_start..byte_end]) catch return error.Fatal;
    }

    const out = result.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
    return vm.newStringWithEncoding(out, false, pad_encoding);
}

pub fn builtinStringRjust(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const string_obj = receiver.toStringObject();
    const recv_encoding = string_obj.encoding;

    const length = try args[0].coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "no implicit conversion into Integer",
        "bignum too big to convert into `long`",
    );

    var padstr_obj: ?*value.StringObject = null;
    var padstr_encoding: enc.Encoding = .{ .utf8 = .{} };
    if (args.len >= 2) {
        if (!args[1].isString()) {
            const padstr_val = try args[1].coerceToStringValue(vm, "no implicit conversion into String");
            padstr_obj = padstr_val.toStringObject();
        } else {
            padstr_obj = args[1].toStringObject();
        }
        padstr_encoding = padstr_obj.?.encoding;
        if (padstr_obj.?.str.len == 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "zero width padding", .{});
        }
    }

    const char_len = recv_encoding.charCount(string_obj.str);

    if (length <= 0 or @as(usize, @intCast(length)) <= char_len) {
        return vm.newStringWithEncoding(string_obj.str, false, recv_encoding);
    }

    const target_len: usize = @intCast(length);
    const pad_chars = target_len - char_len;

    const pad_str = if (padstr_obj) |p| p.str else " ";
    const pad_encoding = if (padstr_obj) |_| blk: {
        const result_encoding = resolveStringConcatEncoding(recv_encoding, string_obj.str, padstr_encoding, pad_str) orelse {
            return vm.raiseEncodingCompatibilityError(recv_encoding, padstr_encoding);
        };
        break :blk result_encoding;
    } else recv_encoding;

    const pad_char_count = pad_encoding.charCount(pad_str);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(vm.gc_allocator_atomic);

    var i: usize = 0;
    while (i < pad_chars) : (i += 1) {
        const byte_start = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count) orelse break;
        const byte_end = pad_encoding.byteOffsetForCharIndex(pad_str, i % pad_char_count + 1) orelse pad_str.len;
        result.appendSlice(vm.gc_allocator_atomic, pad_str[byte_start..byte_end]) catch return error.Fatal;
    }

    result.appendSlice(vm.gc_allocator_atomic, string_obj.str) catch return error.Fatal;

    const out = result.toOwnedSlice(vm.gc_allocator_atomic) catch return error.Fatal;
    return vm.newStringWithEncoding(out, false, pad_encoding);
}
