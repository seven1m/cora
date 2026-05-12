const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const onigmo = @import("../onigmo.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const OPTION_IGNORECASE: u16 = 1;
const OPTION_EXTENDED: u16 = 2;
const OPTION_MULTILINE: u16 = 4;
const OPTION_FIXEDENCODING: u16 = 16;
const OPTION_NOENCODING: u16 = 32;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.regexp_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinRegexpInitialize, .{ .variadic = 0 }, .private));

    const source_sym = try vm.intern("source");
    try vm.regexp_class.module.methods.put(source_sym, value.MethodEntry.builtin(&builtinRegexpSource, .{ .exact = 0 }));

    const options_sym = try vm.intern("options");
    try vm.regexp_class.module.methods.put(options_sym, value.MethodEntry.builtin(&builtinRegexpOptions, .{ .exact = 0 }));

    const encoding_sym = try vm.intern("encoding");
    try vm.regexp_class.module.methods.put(encoding_sym, value.MethodEntry.builtin(&builtinRegexpEncoding, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.regexp_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinRegexpInspect, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.regexp_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinRegexpToS, .{ .exact = 0 }));

    const eq_sym = try vm.intern("==");
    try vm.regexp_class.module.methods.put(eq_sym, value.MethodEntry.builtin(&builtinRegexpEq, .{ .exact = 1 }));

    const casefold_sym = try vm.intern("casefold?");
    try vm.regexp_class.module.methods.put(casefold_sym, value.MethodEntry.builtin(&builtinRegexpCasefold, .{ .exact = 0 }));

    const case_equal_sym = try vm.intern("===");
    try vm.regexp_class.module.methods.put(case_equal_sym, value.MethodEntry.builtin(&builtinRegexpCaseEqual, .{ .exact = 1 }));

    const match_op_sym = try vm.intern("=~");
    try vm.regexp_class.module.methods.put(match_op_sym, value.MethodEntry.builtin(&builtinRegexpMatchOp, .{ .exact = 1 }));

    const match_sym = try vm.intern("match");
    try vm.regexp_class.module.methods.put(match_sym, value.MethodEntry.builtin(&builtinRegexpMatch, .{ .variadic = 0 }));

    const match_q_sym = try vm.intern("match?");
    try vm.regexp_class.module.methods.put(match_q_sym, value.MethodEntry.builtin(&builtinRegexpMatchQ, .{ .variadic = 0 }));

    const dup_sym = try vm.intern("dup");
    try vm.regexp_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinRegexpDup, .{ .exact = 0 }));

    const clone_sym = try vm.intern("clone");
    try vm.regexp_class.module.methods.put(clone_sym, value.MethodEntry.builtin(&builtinRegexpClone, .{ .variadic = 0 }));

    const regexp_class_val = Value.fromObject(&vm.regexp_class.module.object);
    const ignorecase_sym = try vm.intern("IGNORECASE");
    try vm.regexp_class.module.constants.put(ignorecase_sym, .{ .value = Value.integer(OPTION_IGNORECASE) });
    const extended_sym = try vm.intern("EXTENDED");
    try vm.regexp_class.module.constants.put(extended_sym, .{ .value = Value.integer(OPTION_EXTENDED) });
    const multiline_sym = try vm.intern("MULTILINE");
    try vm.regexp_class.module.constants.put(multiline_sym, .{ .value = Value.integer(OPTION_MULTILINE) });
    const fixedencoding_sym = try vm.intern("FIXEDENCODING");
    try vm.regexp_class.module.constants.put(fixedencoding_sym, .{ .value = Value.integer(OPTION_FIXEDENCODING) });
    const noencoding_sym = try vm.intern("NOENCODING");
    try vm.regexp_class.module.constants.put(noencoding_sym, .{ .value = Value.integer(OPTION_NOENCODING) });

    const regexp_singleton = try vm.getOrCreateSingletonClass(regexp_class_val);
    const try_convert_sym = try vm.intern("try_convert");
    try regexp_singleton.module.methods.put(try_convert_sym, value.MethodEntry.builtin(&builtinRegexpTryConvert, .{ .exact = 1 }));
    const new_sym = try vm.intern("new");
    try regexp_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinRegexpNew, .{ .variadic = 0 }));
    const escape_sym = try vm.intern("escape");
    try regexp_singleton.module.methods.put(escape_sym, value.MethodEntry.builtin(&builtinRegexpEscape, .{ .exact = 1 }));
    const last_match_sym = try vm.intern("last_match");
    try regexp_singleton.module.methods.put(last_match_sym, value.MethodEntry.builtin(&builtinRegexpLastMatch, .{ .variadic = 0 }));
    const union_sym = try vm.intern("union");
    try regexp_singleton.module.methods.put(union_sym, value.MethodEntry.builtin(&builtinRegexpUnion, .{ .variadic = 0 }));
}

fn builtinRegexpInitialize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    return Value.nil();
}

fn builtinRegexpTryConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isRegexp()) return arg;

    const maybe_converted = try vm.checkCallMethodByName(arg, "to_regexp", false, &[_]Value{}, null);
    const converted = maybe_converted orelse return Value.nil();
    if (converted.isNil()) return Value.nil();
    if (converted.isRegexp()) return converted;

    return vm.raiseExceptionFmt(
        vm.type_error_class,
        "can't convert {s} to Regexp ({s}#to_regexp gives {s})",
        .{ vm.className(arg), vm.className(arg), vm.className(converted) },
    );
}

fn normalizeRegexpConstruction(vm: *VM, pattern: []const u8, encoding: enc.Encoding, options: u16) VMError!Value {
    const normalized = vm.normalizeRegexpEncoding(pattern, encoding, options);
    return try vm.newRegexpWithEncoding(pattern, normalized.options, normalized.encoding);
}

fn builtinRegexpNew(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    if (args[0].isRegexp() and args.len == 1) {
        const regexp = args[0].toRegexpObject();
        return try vm.newRegexpWithEncoding(regexp.pattern, regexp.options, regexp.encoding);
    }

    const pattern_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const pattern_obj = pattern_value.toStringObject();
    const options: u16 = if (args.len == 2)
        @intCast(try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        ))
    else
        0;

    return try normalizeRegexpConstruction(vm, pattern_obj.str, pattern_obj.encoding, options);
}

fn builtinRegexpEscape(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const string_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const string_obj = string_value.toStringObject();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    for (string_obj.str) |b| {
        switch (b) {
            '\\', '.', '^', '$', '|', '?', '*', '+', '-', '(', ')', '[', ']', '{', '}' => {
                out.append(vm.allocator, '\\') catch return error.Fatal;
                out.append(vm.allocator, b) catch return error.Fatal;
            },
            else => out.append(vm.allocator, b) catch return error.Fatal,
        }
    }

    const escaped = out.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(escaped);
    return try vm.newStringWithEncoding(escaped, false, string_obj.encoding);
}

fn builtinRegexpSource(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.newString(receiver.toRegexpObject().pattern, false);
}

fn builtinRegexpEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.encodingToValue(receiver.toRegexpObject().encoding);
}

fn builtinRegexpOptions(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.toRegexpObject().options));
}

fn appendEncodedAscii(out: *std.ArrayList(u8), allocator: std.mem.Allocator, target: enc.Encoding, ascii: []const u8) VMError!void {
    var buf: [4]u8 = undefined;
    for (ascii) |b| {
        const len = target.fromUnicodeCodepoint(b, &buf) orelse return error.Fatal;
        out.appendSlice(allocator, buf[0..len]) catch return error.Fatal;
    }
}

fn buildRegexpToSBytes(vm: *VM, regexp: *value.RegexpObject) VMError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(vm.allocator);

    try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "(?");
    if ((regexp.options & OPTION_IGNORECASE) != 0) try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "i");
    if ((regexp.options & OPTION_MULTILINE) != 0) try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "m");
    if ((regexp.options & OPTION_EXTENDED) != 0) try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "x");

    var has_disabled = false;
    if ((regexp.options & OPTION_MULTILINE) == 0) {
        if (!has_disabled) {
            try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "-");
            has_disabled = true;
        }
        try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "m");
    }
    if ((regexp.options & OPTION_IGNORECASE) == 0) {
        if (!has_disabled) {
            try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "-");
            has_disabled = true;
        }
        try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "i");
    }
    if ((regexp.options & OPTION_EXTENDED) == 0) {
        if (!has_disabled) {
            try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "-");
            has_disabled = true;
        }
        try appendEncodedAscii(&out, vm.allocator, regexp.encoding, "x");
    }
    try appendEncodedAscii(&out, vm.allocator, regexp.encoding, ":");
    out.appendSlice(vm.allocator, regexp.pattern) catch return error.Fatal;
    try appendEncodedAscii(&out, vm.allocator, regexp.encoding, ")");
    return out.toOwnedSlice(vm.allocator) catch return error.Fatal;
}

fn builtinRegexpInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const r = receiver.toRegexpObject();

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    writer.writeByte('/') catch return error.Fatal;
    writer.writeAll(r.pattern) catch return error.Fatal;
    writer.writeByte('/') catch return error.Fatal;
    if ((r.options & 1) != 0) writer.writeByte('i') catch return error.Fatal;
    if ((r.options & 2) != 0) writer.writeByte('x') catch return error.Fatal;
    if ((r.options & 4) != 0) writer.writeByte('m') catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

fn builtinRegexpToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const r = receiver.toRegexpObject();
    const str = try buildRegexpToSBytes(vm, r);
    defer vm.allocator.free(str);
    return try vm.newStringWithEncoding(str, false, r.encoding);
}

const UnionSegment = struct {
    bytes: []const u8,
    encoding: enc.Encoding,
    sticky: bool,
    ascii_only: bool,
};

fn raiseUnionEncodingError(vm: *VM, lhs: enc.Encoding, rhs: enc.Encoding) VMError {
    if (!lhs.isAsciiCompatible() and rhs.eql(.{ .us_ascii = .{} })) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "ASCII incompatible encoding: {s}", .{lhs.name()});
    }
    if (!rhs.isAsciiCompatible() and lhs.eql(.{ .us_ascii = .{} })) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "ASCII incompatible encoding: {s}", .{rhs.name()});
    }
    if (!lhs.isAsciiCompatible() and rhs.isAsciiCompatible()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "incompatible encodings: {s} and {s}", .{ lhs.name(), rhs.name() });
    }
    if (!rhs.isAsciiCompatible() and lhs.isAsciiCompatible()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "incompatible encodings: {s} and {s}", .{ rhs.name(), lhs.name() });
    }
    return vm.raiseExceptionFmt(vm.argument_error_class, "incompatible encodings: {s} and {s}", .{ lhs.name(), rhs.name() });
}

fn captureUnionSegment(vm: *VM, arg: Value) VMError!UnionSegment {
    if (arg.isRegexp()) {
        const regexp = arg.toRegexpObject();
        return .{
            .bytes = try buildRegexpToSBytes(vm, regexp),
            .encoding = regexp.encoding,
            .sticky = (regexp.options & OPTION_FIXEDENCODING) != 0,
            .ascii_only = if ((regexp.options & OPTION_NOENCODING) != 0)
                regexp.encoding.eql(.{ .us_ascii = .{} })
            else
                regexp.encoding.isAsciiOnlyString(regexp.pattern),
        };
    }

    const maybe_regexp = try vm.checkCallMethodByName(arg, "to_regexp", false, &[_]Value{}, null);
    if (maybe_regexp) |converted| {
        if (converted.isNil()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} to Regexp ({s}#to_regexp gives NilClass)",
                .{ vm.className(arg), vm.className(arg) },
            );
        }
        if (!converted.isRegexp()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} to Regexp ({s}#to_regexp gives {s})",
                .{ vm.className(arg), vm.className(arg), vm.className(converted) },
            );
        }
        return captureUnionSegment(vm, converted);
    }

    if (arg.isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of Array into String", .{});
    }

    const string_value = try arg.coerceToMatchSource(vm) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of nil into String", .{});
    };
    const string_obj = string_value.toStringObject();
    var escape_args = [_]Value{string_value};
    const escaped_value = try builtinRegexpEscape(vm, Value.nil(), escape_args[0..], null);
    const escaped_obj = escaped_value.toStringObject();
    const normalized = vm.normalizeRegexpEncoding(string_obj.str, string_obj.encoding, 0);

    return .{
        .bytes = vm.allocator.dupe(u8, escaped_obj.str) catch return error.Fatal,
        .encoding = normalized.encoding,
        .sticky = (normalized.options & OPTION_FIXEDENCODING) != 0,
        .ascii_only = string_obj.encoding.isAsciiOnlyString(string_obj.str),
    };
}

fn builtinRegexpUnion(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const union_args = if (args.len == 1 and args[0].isArray())
        args[0].toArrayObject().elements.items
    else
        args;

    if (union_args.len == 0) {
        return try vm.newRegexpWithEncoding("(?!)", 0, .{ .us_ascii = .{} });
    }

    if (union_args.len == 1) {
        var try_convert_args = [_]Value{union_args[0]};
        const maybe_regexp = try builtinRegexpTryConvert(vm, Value.nil(), try_convert_args[0..], null);
        if (maybe_regexp.isRegexp()) return maybe_regexp;
    }

    var segments: std.ArrayList(UnionSegment) = .empty;
    defer {
        for (segments.items) |segment| vm.allocator.free(segment.bytes);
        segments.deinit(vm.allocator);
    }

    var resolved_encoding: ?enc.Encoding = null;
    var saw_plain_ascii_only = false;
    var all_ascii_only = true;

    for (union_args) |arg| {
        const segment = try captureUnionSegment(vm, arg);
        segments.append(vm.allocator, segment) catch return error.Fatal;
        all_ascii_only = all_ascii_only and segment.ascii_only;

        if (!segment.sticky and segment.encoding.eql(.{ .us_ascii = .{} })) {
            saw_plain_ascii_only = true;
            if (resolved_encoding) |resolved| {
                if (!resolved.isAsciiCompatible()) {
                    return raiseUnionEncodingError(vm, resolved, .{ .us_ascii = .{} });
                }
            }
            continue;
        }

        if (resolved_encoding) |resolved| {
            if (!resolved.eql(segment.encoding)) {
                return raiseUnionEncodingError(vm, resolved, segment.encoding);
            }
        } else {
            if (saw_plain_ascii_only and !segment.encoding.isAsciiCompatible()) {
                return raiseUnionEncodingError(vm, segment.encoding, .{ .us_ascii = .{} });
            }
            resolved_encoding = segment.encoding;
        }
    }

    const final_encoding = if (all_ascii_only and (resolved_encoding == null or resolved_encoding.?.isAsciiCompatible()))
        enc.Encoding{ .us_ascii = .{} }
    else
        resolved_encoding orelse enc.Encoding{ .us_ascii = .{} };
    const final_options: u16 = if (final_encoding.eql(.{ .us_ascii = .{} })) 0 else OPTION_FIXEDENCODING;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    for (segments.items, 0..) |segment, idx| {
        if (idx != 0) try appendEncodedAscii(&out, vm.allocator, final_encoding, "|");
        out.appendSlice(vm.allocator, segment.bytes) catch return error.Fatal;
    }

    const pattern = out.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(pattern);
    return try vm.newRegexpWithEncoding(pattern, final_options, final_encoding);
}

fn builtinRegexpEq(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isRegexp()) {
        return Value.boolean(false);
    }
    const self_r = receiver.toRegexpObject();
    const other_r = other.toRegexpObject();
    return Value.boolean(
        std.mem.eql(u8, self_r.pattern, other_r.pattern) and self_r.options == other_r.options,
    );
}

fn builtinRegexpCasefold(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean((receiver.toRegexpObject().options & 1) != 0);
}

fn builtinRegexpCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].isNil()) return Value.boolean(false);

    const source = if (args[0].isSymbol())
        try vm.newString(args[0].toSymbolObject().name, false)
    else switch (try vm.probeToStringValue(args[0])) {
        .string => |coerced| coerced,
        .missing, .nil_result => return Value.boolean(false),
    };

    const result = try searchRegexp(vm, receiver.toRegexpObject(), source, null, true);
    return Value.boolean(result != null);
}

fn matchDataAt(md: *value.MatchDataObject, index: i64) Value {
    const len: i64 = @intCast(md.captures.items.len);
    var actual = index;
    if (actual < 0) actual += len;
    if (actual < 0 or actual >= len) return Value.nil();
    return md.captures.items[@intCast(actual)];
}

const RegexpSearchResult = struct {
    char_index: i64,
    match_data: *value.MatchDataObject,
};

fn searchRegexp(
    vm: *VM,
    regexp_obj: *value.RegexpObject,
    arg: Value,
    start_pos: ?i64,
    update_last_match: bool,
) VMError!?RegexpSearchResult {
    const source_val_opt = try arg.coerceToMatchSource(vm);
    if (source_val_opt == null) {
        if (update_last_match) try vm.clearLastMatch();
        return null;
    }
    const source_val = source_val_opt.?;
    const source_obj = source_val.toStringObject();

    if (enc.negotiate(source_obj.encoding, source_obj.str, regexp_obj.encoding, regexp_obj.pattern) == null) {
        return vm.raiseExceptionFmt(
            vm.encoding_compatibility_error_class,
            "incompatible encoding regexp match ({s} regexp with {s} string)",
            .{ regexp_obj.encoding.name(), source_obj.encoding.name() },
        );
    }

    var start_byte: usize = 0;
    if (start_pos) |raw_start| {
        const char_len_i64: i64 = @intCast(source_obj.encoding.charCount(source_obj.str));
        var normalized_start = raw_start;
        if (normalized_start < 0) normalized_start += char_len_i64;
        if (normalized_start < 0 or normalized_start > char_len_i64) {
            if (update_last_match) try vm.clearLastMatch();
            return null;
        }

        start_byte = source_obj.encoding.byteOffsetForCharIndex(source_obj.str, @intCast(normalized_start)) orelse {
            if (update_last_match) try vm.clearLastMatch();
            return null;
        };
    }

    const effective_regexp = if (regexp_obj.encoding.eql(.{ .us_ascii = .{} }) and source_obj.encoding.isAsciiCompatible() and !source_obj.encoding.eql(.{ .us_ascii = .{} }))
        (try vm.newRegexpWithEncoding(regexp_obj.pattern, regexp_obj.options, source_obj.encoding)).toRegexpObject()
    else
        regexp_obj;

    if (effective_regexp.encoding.isUnicode() and !source_obj.encoding.isValid(source_obj.str)) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{source_obj.encoding.name()});
    }

    const search_result = onigmo.searchWithCapturesAt(vm.gc_allocator, effective_regexp.regex, source_obj.str, start_byte) catch |err| switch (err) {
        error.InvalidByteSequence => {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid byte sequence in {s}", .{source_obj.encoding.name()});
        },
        else => return error.Fatal,
    };
    defer vm.gc_allocator.free(search_result.begin_offsets);
    defer vm.gc_allocator.free(search_result.end_offsets);

    if (!search_result.matched) {
        if (update_last_match) try vm.clearLastMatch();
        return null;
    }

    var captures: std.ArrayList(Value) = .empty;
    defer captures.deinit(vm.gc_allocator);

    var begins = vm.gc_allocator.alloc(i64, search_result.begin_offsets.len) catch return error.Fatal;
    defer vm.gc_allocator.free(begins);
    var ends = vm.gc_allocator.alloc(i64, search_result.end_offsets.len) catch return error.Fatal;
    defer vm.gc_allocator.free(ends);

    for (search_result.begin_offsets, search_result.end_offsets, 0..) |beg, end_, idx| {
        if (beg < 0 or end_ < 0) {
            begins[idx] = beg;
            ends[idx] = end_;
            captures.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            continue;
        }

        begins[idx] = beg;
        ends[idx] = end_;

        const begin_usize: usize = @intCast(beg);
        const end_usize: usize = @intCast(end_);
        if (begin_usize > source_obj.str.len or end_usize > source_obj.str.len or begin_usize > end_usize) {
            return error.Fatal;
        }

        const capture_str = try vm.newStringWithEncoding(source_obj.str[begin_usize..end_usize], false, source_obj.encoding);
        captures.append(vm.gc_allocator, capture_str) catch return error.Fatal;
    }

    const md_val = try vm.newMatchData(
        regexp_obj,
        source_obj,
        captures.items,
        begins,
        ends,
    );
    const md = md_val.toMatchDataObject();
    if (update_last_match) try vm.setLastMatch(md);

    return .{
        .char_index = @intCast(source_obj.encoding.charCount(source_obj.str[0..@as(usize, @intCast(search_result.match_index))])),
        .match_data = md,
    };
}

pub fn regexpMatchOpAt(
    vm: *VM,
    regexp_obj: *value.RegexpObject,
    arg: Value,
    start_pos: ?i64,
    update_last_match: bool,
) VMError!Value {
    const result = try searchRegexp(vm, regexp_obj, arg, start_pos, update_last_match);
    if (result == null) return Value.nil();
    return Value.integer(result.?.char_index);
}

pub fn regexpMatchOp(vm: *VM, regexp_obj: *value.RegexpObject, arg: Value) VMError!Value {
    return regexpMatchOpAt(vm, regexp_obj, arg, null, true);
}

fn builtinRegexpMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!receiver.isRegexp()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "uninitialized Regexp", .{});
    }
    return regexpMatchOp(vm, receiver.toRegexpObject(), args[0]);
}

fn builtinRegexpMatch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const start_pos = if (args.len == 2)
        try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        )
    else
        null;

    const result = try searchRegexp(vm, receiver.toRegexpObject(), args[0], start_pos, true);
    if (result == null) return Value.nil();

    const md_val = Value.fromObject(&result.?.match_data.object);
    if (block) |blk| {
        const yielded = try vm.yieldToBlock(blk, &[_]Value{md_val});
        if (yielded.controlFlowValue()) |return_value| return return_value;
        return yielded.value;
    }
    return md_val;
}

fn builtinRegexpMatchQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const start_pos = if (args.len == 2)
        try args[1].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        )
    else
        null;

    const result = try searchRegexp(vm, receiver.toRegexpObject(), args[0], start_pos, false);
    return Value.boolean(result != null);
}

fn builtinRegexpDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const regexp = receiver.toRegexpObject();
    const duplicate = try vm.newRegexpWithEncoding(regexp.pattern, regexp.options, regexp.encoding);
    duplicate.toRegexpObject().object.class = vm.getClass(receiver);
    duplicate.toRegexpObject().object.flags &= ~@as(u32, value.Object.FROZEN_FLAG);

    const src_obj = receiver.getObjectPointer() orelse return error.Fatal;
    const dst_obj = duplicate.getObjectPointer() orelse return error.Fatal;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);
    duplicate.toRegexpObject().object.flags = 0;
    return duplicate;
}

fn builtinRegexpClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const duplicate = try builtinRegexpDup(vm, receiver, args, null);
    if (receiver.isFrozen()) {
        var mutable_duplicate = duplicate;
        mutable_duplicate.freeze();
    }
    try vm.copySingletonClassMetadata(receiver, duplicate);
    return duplicate;
}

fn builtinRegexpLastMatch(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const current = vm.globals.get("$~") orelse Value.nil();
    if (args.len == 0) {
        return current;
    }
    if (!current.isMatchData()) {
        return Value.nil();
    }
    if (!args[0].isInteger()) {
        return Value.nil();
    }
    return matchDataAt(current.toMatchDataObject(), args[0].toInteger());
}
