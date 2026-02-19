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
    const initialize_sym = try vm.intern("initialize");
    try vm.string_class.module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinStringInitialize } });

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

    const string_length_sym = try vm.intern("length");
    try vm.string_class.module.methods.put(string_length_sym, .{ .method = .{ .builtin = &builtinStringLength } });

    const string_size_sym = try vm.intern("size");
    try vm.string_class.module.methods.put(string_size_sym, .{ .method = .{ .builtin = &builtinStringLength } });

    const string_empty_sym = try vm.intern("empty?");
    try vm.string_class.module.methods.put(string_empty_sym, .{ .method = .{ .builtin = &builtinStringEmpty } });

    const string_ord_sym = try vm.intern("ord");
    try vm.string_class.module.methods.put(string_ord_sym, .{ .method = .{ .builtin = &builtinStringOrd } });

    const string_bracket_sym = try vm.intern("[]");
    try vm.string_class.module.methods.put(string_bracket_sym, .{ .method = .{ .builtin = &builtinStringBracket } });

    const string_chars_sym = try vm.intern("chars");
    try vm.string_class.module.methods.put(string_chars_sym, .{ .method = .{ .builtin = &builtinStringChars } });

    const string_start_with_sym = try vm.intern("start_with?");
    try vm.string_class.module.methods.put(string_start_with_sym, .{ .method = .{ .builtin = &builtinStringStartWith } });

    const string_end_with_sym = try vm.intern("end_with?");
    try vm.string_class.module.methods.put(string_end_with_sym, .{ .method = .{ .builtin = &builtinStringEndWith } });

    const string_prepend_sym = try vm.intern("prepend");
    try vm.string_class.module.methods.put(string_prepend_sym, .{ .method = .{ .builtin = &builtinStringPrepend } });

    const string_upcase_sym = try vm.intern("upcase");
    try vm.string_class.module.methods.put(string_upcase_sym, .{ .method = .{ .builtin = &builtinStringUpcase } });

    const string_to_i_sym = try vm.intern("to_i");
    try vm.string_class.module.methods.put(string_to_i_sym, .{ .method = .{ .builtin = &builtinStringToI } });

    const string_to_sym_sym = try vm.intern("to_sym");
    try vm.string_class.module.methods.put(string_to_sym_sym, .{ .method = .{ .builtin = &builtinStringToSym } });

    const to_s_sym = try vm.intern("to_s");
    try vm.string_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinStringToS } });

    const to_str_sym = try vm.intern("to_str");
    try vm.string_class.module.methods.put(to_str_sym, .{ .method = .{ .builtin = &builtinStringToStr } });

    const inspect_sym = try vm.intern("inspect");
    try vm.string_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinStringInspect } });

    const match_op_sym = try vm.intern("=~");
    try vm.string_class.module.methods.put(match_op_sym, .{ .method = .{ .builtin = &builtinStringMatchOp } });

    const unpack_sym = try vm.intern("unpack");
    try vm.string_class.module.methods.put(unpack_sym, .{ .method = .{ .builtin = &builtinStringUnpack } });
}

pub fn builtinStringToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    if (string_obj.object.class == vm.string_class) {
        return receiver;
    }
    return try vm.newStringWithEncoding(string_obj.str, false, string_obj.encoding);
}

pub fn builtinStringInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const string_obj = receiver.data.string;

    if (args.len == 0) {
        return receiver;
    }

    const new_bytes: []const u8 = switch (args[0].data) {
        .string => |s| blk: {
            string_obj.encoding = s.encoding;
            break :blk s.str;
        },
        else => try args[0].coerceToStr(vm, "no implicit conversion into String"),
    };

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, new_bytes) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
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
    const other_str = try args[0].coerceToStr(vm, "no implicit conversion into String");
    const combined_str = std.fmt.allocPrint(
        vm.gc_allocator,
        "{s}{s}",
        .{ receiver.data.string.str, other_str },
    ) catch return error.Fatal;

    return try vm.newString(combined_str, false);
}

pub fn builtinStringMultiply(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const times = switch (args[0].data) {
        .integer => |n| n,
        else => return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{}),
    };
    if (times < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative argument", .{});
    }

    const string_obj = receiver.data.string;
    const n: usize = @intCast(times);
    const out_len = string_obj.str.len * n;
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
    const string_obj = receiver.data.string;

    const bytes_to_append: []const u8 = switch (args[0].data) {
        .integer => |cp| blk: {
            if (cp < 0) {
                return vm.raiseExceptionFmt(vm.range_error_class, "{d} out of char range", .{cp});
            }
            var buf: [4]u8 = undefined;
            const encoded = try encodeCodepointForEncoding(vm, cp, string_obj.encoding, &buf);
            break :blk encoded;
        },
        else => try args[0].coerceToStr(vm, "no implicit conversion into String"),
    };

    const new_bytes = try concatBytes(vm, string_obj.str, bytes_to_append);
    string_obj.str = new_bytes;
    return receiver;
}

pub fn builtinStringConcat(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinStringAppend(vm, receiver, args, block);
}

pub fn builtinStringReplace(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.data.string;
    const other = args[0];

    const replacement_val = try coerceToStringValueViaCall(vm, other);
    const replacement = replacement_val.data.string.str;
    string_obj.encoding = replacement_val.data.string.encoding;

    string_obj.str = vm.gc_allocator_atomic.dupe(u8, replacement) catch return error.Fatal;
    string_obj.validity = .unknown;
    return receiver;
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

    const string_obj = receiver.data.string;
    string_obj.encoding = new_encoding;
    string_obj.validity = .unknown;
    return receiver;
}

pub fn builtinStringValidEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return Value.boolean(string_obj.encoding.isValid(string_obj.str));
}

pub fn builtinStringAsciiOnly(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    if (!string_obj.encoding.isAsciiCompatible()) {
        return Value.boolean(false);
    }
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

pub fn builtinStringLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
    return Value.integer(@intCast(string_obj.encoding.charCount(string_obj.str)));
}

pub fn builtinStringEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.data.string.str.len == 0);
}

pub fn builtinStringOrd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
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
    const string_obj = receiver.data.string;

    switch (args[0].data) {
        .integer => |idx| {
            const slice = string_obj.encoding.charSliceAtIndex(string_obj.str, idx);
            if (slice == null) return Value.nil();
            return try vm.newStringWithEncoding(slice.?, false, string_obj.encoding);
        },
        .range => |range_obj| {
            const slice = try charSliceByRange(vm, string_obj.str, string_obj.encoding, range_obj.begin, range_obj.end, range_obj.exclude_end);
            if (slice == null) return Value.nil();
            return try vm.newStringWithEncoding(slice.?, false, string_obj.encoding);
        },
        else => return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{}),
    }
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

    return Value{ .data = .{ .array = array_obj } };
}

pub fn builtinStringStartWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) return Value.boolean(false);
    const string_obj = receiver.data.string;

    for (args) |arg| {
        if (arg.data == .regexp) {
            const match_val = try regexp_builtin.regexpMatchOp(vm, arg.data.regexp, receiver);
            switch (match_val.data) {
                .integer => |idx| {
                    if (idx == 0) return Value.boolean(true);
                    try vm.clearLastMatch();
                    continue;
                },
                else => {
                    try vm.clearLastMatch();
                    continue;
                },
            }
        }

        const prefix_val = try coerceToStringValueViaCall(vm, arg);
        const prefix = prefix_val.data.string.str;
        const prefix_enc = prefix_val.data.string.encoding;
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
    const string_obj = receiver.data.string;

    for (args) |arg| {
        const suffix_val = try coerceToStringValueViaCall(vm, arg);
        const suffix = suffix_val.data.string.str;
        const suffix_enc = suffix_val.data.string.encoding;
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

pub fn builtinStringPrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) return receiver;
    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen String", .{});
    }
    const string_obj = receiver.data.string;

    var result = string_obj.str;
    var i: usize = args.len;
    while (i > 0) {
        i -= 1;
        const arg = args[i];
        const part = try coerceToStringValueViaCall(vm, arg);
        result = try concatBytes(vm, part.data.string.str, result);
    }

    string_obj.str = result;
    return receiver;
}

pub fn builtinStringUpcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const string_obj = receiver.data.string;
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

    var base: u8 = 10;
    if (args.len == 1) {
        const base_int = try args[0].integerArgToI64(vm, "argument is not an Integer", "base is too large");
        if (base_int < 2 or base_int > 36) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid radix {d}", .{base_int});
        }
        base = @intCast(base_int);
    }

    const s = receiver.data.string.str;
    var i: usize = 0;
    while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {}

    var negative = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        negative = s[i] == '-';
        i += 1;
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

pub fn builtinStringToSym(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = try vm.intern(receiver.data.string.str);
    return Value{ .data = .{ .symbol = sym } };
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

pub fn builtinStringMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .regexp) {
        return vm.raiseExceptionFmt(vm.type_error_class, "type mismatch: String given", .{});
    }
    return regexp_builtin.regexpMatchOp(vm, args[0].data.regexp, receiver);
}

pub fn builtinStringUnpack(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const format = try args[0].coerceToStr(vm, "no implicit conversion into String");
    return pack_runtime.stringUnpack(vm, receiver.data.string.str, format);
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

    const begin_i64: i64 = switch (begin_val.data) {
        .integer => |i| i,
        .nil => 0,
        else => return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{}),
    };

    var start_idx = begin_i64;
    if (start_idx < 0) start_idx += char_len_i64;
    if (start_idx < 0 or start_idx > char_len_i64) return null;

    var finish_exclusive = switch (end_val.data) {
        .integer => |i| blk: {
            var end_i64 = i;
            if (end_i64 < 0) end_i64 += char_len_i64;
            break :blk if (exclude_end) end_i64 else end_i64 + 1;
        },
        .nil => char_len_i64,
        else => return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{}),
    };

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

fn concatBytes(vm: *VM, left: []const u8, right: []const u8) VMError![]const u8 {
    const new_len = left.len + right.len;
    const out = vm.gc_allocator_atomic.alloc(u8, new_len) catch return error.Fatal;
    @memcpy(out[0..left.len], left);
    @memcpy(out[left.len..], right);
    return out;
}

fn coerceToStringValueViaCall(vm: *VM, arg: Value) VMError!Value {
    if (arg.data == .string) return arg;

    const coerced = vm.callMethodByName(arg, "to_str", &[_]Value{}, null) catch |err| {
        if (err == error.Unwind and vm.pending_exception != null and vm.pending_exception.?.object.class == vm.no_method_error_class) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into String", .{});
        }
        return err;
    };

    if (coerced.data != .string) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into String", .{});
    }

    return coerced;
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
