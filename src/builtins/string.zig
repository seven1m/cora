const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const enc = @import("../encoding.zig");
const encoding_builtin = @import("encoding.zig");
const regexp_builtin = @import("regexp.zig");
const pack_runtime = @import("../pack.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const BigInt = std.math.big.int.Managed;

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

    const string_plus_sym = try vm.intern("+");
    try vm.string_class.module.methods.put(string_plus_sym, .{ .method = .{ .builtin = &builtinStringPlus } });

    const string_multiply_sym = try vm.intern("*");
    try vm.string_class.module.methods.put(string_multiply_sym, .{ .method = .{ .builtin = &builtinStringMultiply } });

    const string_append_sym = try vm.intern("<<");
    try vm.string_class.module.methods.put(string_append_sym, .{ .method = .{ .builtin = &builtinStringAppend } });

    const string_concat_sym = try vm.intern("concat");
    try vm.string_class.module.methods.put(string_concat_sym, .{ .method = .{ .builtin = &builtinStringConcat } });

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

    const string_bracket_sym = try vm.intern("[]");
    try vm.string_class.module.methods.put(string_bracket_sym, .{ .method = .{ .builtin = &builtinStringBracket } });

    const string_bracket_set_sym = try vm.intern("[]=");
    try vm.string_class.module.methods.put(string_bracket_set_sym, .{ .method = .{ .builtin = &builtinStringBracketSet } });

    const string_chars_sym = try vm.intern("chars");
    try vm.string_class.module.methods.put(string_chars_sym, .{ .method = .{ .builtin = &builtinStringChars } });

    const string_bytes_sym = try vm.intern("bytes");
    try vm.string_class.module.methods.put(string_bytes_sym, .{ .method = .{ .builtin = &builtinStringBytes } });

    const string_getbyte_sym = try vm.intern("getbyte");
    try vm.string_class.module.methods.put(string_getbyte_sym, .{ .method = .{ .builtin = &builtinStringGetbyte } });

    const string_setbyte_sym = try vm.intern("setbyte");
    try vm.string_class.module.methods.put(string_setbyte_sym, .{ .method = .{ .builtin = &builtinStringSetbyte } });

    const string_codepoints_sym = try vm.intern("codepoints");
    try vm.string_class.module.methods.put(string_codepoints_sym, .{ .method = .{ .builtin = &builtinStringCodepoints } });

    const string_start_with_sym = try vm.intern("start_with?");
    try vm.string_class.module.methods.put(string_start_with_sym, .{ .method = .{ .builtin = &builtinStringStartWith } });

    const string_end_with_sym = try vm.intern("end_with?");
    try vm.string_class.module.methods.put(string_end_with_sym, .{ .method = .{ .builtin = &builtinStringEndWith } });

    const string_include_sym = try vm.intern("include?");
    try vm.string_class.module.methods.put(string_include_sym, .{ .method = .{ .builtin = &builtinStringInclude } });

    const string_prepend_sym = try vm.intern("prepend");
    try vm.string_class.module.methods.put(string_prepend_sym, .{ .method = .{ .builtin = &builtinStringPrepend } });

    const string_split_sym = try vm.intern("split");
    try vm.string_class.module.methods.put(string_split_sym, .{ .method = .{ .builtin = &builtinStringSplit } });

    const string_upcase_sym = try vm.intern("upcase");
    try vm.string_class.module.methods.put(string_upcase_sym, .{ .method = .{ .builtin = &builtinStringUpcase } });

    const string_to_i_sym = try vm.intern("to_i");
    try vm.string_class.module.methods.put(string_to_i_sym, .{ .method = .{ .builtin = &builtinStringToI } });

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

    const scan_sym = try vm.intern("scan");
    try vm.string_class.module.methods.put(scan_sym, .{ .method = .{ .builtin = &builtinStringScan } });

    const unpack_sym = try vm.intern("unpack");
    try vm.string_class.module.methods.put(unpack_sym, .{ .method = .{ .builtin = &builtinStringUnpack } });
}

pub fn builtinStringTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];
    if (arg.isString()) return arg;

    var no_args = [_]Value{};
    const converted = vm.callMethodByName(arg, "to_str", no_args[0..], null) catch |err| {
        if (err == error.Unwind and
            vm.pending_exception != null and
            std.mem.indexOf(u8, vm.pending_exception.?.message.str, "undefined method 'to_str'") != null)
        {
            vm.pending_exception = null;
            return Value.nil();
        }
        return err;
    };
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
    if (!receiver.isFrozen()) {
        return receiver;
    }
    const string_obj = receiver.toStringObject();
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringPlus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toStringObject();
    const rhs_value = try coerceConcatArgumentToStringValue(vm, args[0], "no implicit conversion into String");
    const rhs = rhs_value.toStringObject();

    const result_encoding = resolveStringConcatEncoding(lhs.encoding, lhs.str, rhs.encoding, rhs.str) orelse {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
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
    if ((try vm.findMethod(other, to_str_sym)) != null) {
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
pub fn builtinStringEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    return vm.encodingToValue(string_obj.encoding);
}

pub fn builtinStringEncode(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const target_encoding: enc.Encoding = if (args[0].isEncoding())
        args[0].toEncodingObject().encoding
    else blk: {
        const result = try encoding_builtin.builtinEncodingFind(vm, receiver, args, null);
        break :blk result.toEncodingObject().encoding;
    };

    const string_obj = receiver.toStringObject();
    const transcoded = enc.transcode(vm.gc_allocator_atomic, string_obj.str, string_obj.encoding, target_encoding) catch |err| {
        switch (err) {
            error.InvalidByteSequence => {
                const src_name = string_obj.encoding.name();
                return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{src_name});
            },
            error.UndefinedConversion => {
                const src_name = string_obj.encoding.name();
                const dst_name = target_encoding.name();
                return vm.raiseExceptionFmt(vm.argument_error_class, "undefined conversion from {s} to {s}", .{ src_name, dst_name });
            },
            else => return error.Fatal,
        }
    };

    return try vm.newStringWithEncoding(transcoded, false, target_encoding);
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

    const replacement = try coerceConcatArgumentToStringValue(vm, replacement_arg, "no implicit conversion into String");
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
                vm.argument_error_class,
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
                vm.argument_error_class,
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
            vm.argument_error_class,
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

pub fn builtinStringUpcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.toStringObject();
    const new_bytes = vm.gc_allocator_atomic.dupe(u8, string_obj.str) catch return error.Fatal;
    for (new_bytes) |*b| {
        if (b.* >= 'a' and b.* <= 'z') {
            b.* -= 32;
        }
    }
    return try vm.newStringWithEncoding(new_bytes, false, string_obj.encoding);
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
        if ((requested_base < 2 or requested_base > 36) and requested_base != 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid radix {d}", .{requested_base});
        }
    }

    var base: u8 = if (requested_base == 0) 10 else @intCast(requested_base);
    const s = receiver.toStringObject().str;
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
    const input = receiver.toStringObject().str;
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

pub fn builtinStringMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isRegexp()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "type mismatch: String given", .{});
    }
    return regexp_builtin.regexpMatchOp(vm, args[0].toRegexpObject(), receiver);
}

pub fn builtinStringScan(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isRegexp()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type", .{});
    }

    const regexp_obj = args[0].toRegexpObject();
    const string_obj = receiver.toStringObject();

    const out = if (block == null) try vm.createArray() else null;
    var offset: usize = 0;

    while (offset <= string_obj.str.len) {
        const sub = try vm.newStringWithEncoding(string_obj.str[offset..], false, string_obj.encoding);
        const match_idx = try regexp_builtin.regexpMatchOp(vm, regexp_obj, sub);
        if (match_idx.isNil()) break;

        const last_match = vm.globals.get("$~") orelse Value.nil();
        if (!last_match.isMatchData()) break;
        const md = last_match.toMatchDataObject();

        const yielded_value = if (md.captures.items.len <= 1)
            md.captures.items[0]
        else if (md.captures.items.len == 2)
            md.captures.items[1]
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
        } else {
            out.?.elements.append(vm.gc_allocator, yielded_value) catch return error.Fatal;
        }

        const end_offset_i64 = if (md.end_byte_offsets.items.len > 0) md.end_byte_offsets.items[0] else 0;
        const end_offset: usize = if (end_offset_i64 > 0) @intCast(end_offset_i64) else 0;
        offset += if (end_offset > 0) end_offset else 1;
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
    return pack_runtime.stringUnpack(vm, receiver.toStringObject().str[offset..], format);
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
            vm.argument_error_class,
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
            vm.argument_error_class,
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
            vm.argument_error_class,
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
        const rhs_value = try coerceConcatArgumentToStringValue(vm, arg, "no implicit conversion into String");
        const rhs = rhs_value.toStringObject();
        rhs_bytes = rhs.str;
        rhs_encoding = rhs.encoding;
    }

    const result_encoding = resolveStringConcatEncoding(string_obj.encoding, string_obj.str, rhs_encoding, rhs_bytes) orelse {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ string_obj.encoding.name(), rhs_encoding.name() },
        );
    };

    string_obj.str = try concatBytes(vm, string_obj.str, rhs_bytes);
    string_obj.encoding = result_encoding;
    string_obj.validity = .unknown;
}

fn coerceConcatArgumentToStringValue(vm: *VM, arg: Value, type_error_message: []const u8) VMError!Value {
    if (arg.isString()) return arg;

    const to_str_sym = try vm.intern("to_str");
    const has_to_str = (try vm.findMethod(arg, to_str_sym)) != null;
    const coerced = if (has_to_str)
        try vm.callMethodByName(arg, "to_str", &[_]Value{}, null)
    else
        vm.callMethodByName(arg, "to_str", &[_]Value{}, null) catch |err| {
            if (err == error.Unwind and
                vm.pending_exception != null and
                vm.pending_exception.?.object.class == vm.no_method_error_class)
            {
                const missing_message = vm.pending_exception.?.message.str;
                if (std.mem.indexOf(u8, missing_message, "undefined method 'to_str'") != null) {
                    const exc = try vm.createException(vm.type_error_class, type_error_message);
                    vm.pending_exception = exc;
                    return error.Unwind;
                }
            }
            return err;
        };

    if (!coerced.isString()) {
        const exc = try vm.createException(vm.type_error_class, type_error_message);
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return coerced;
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

fn digitValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'z') return c - 'a' + 10;
    if (c >= 'A' and c <= 'Z') return c - 'A' + 10;
    return null;
}
