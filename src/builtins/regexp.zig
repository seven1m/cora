const std = @import("std");
const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const onigmo = @import("../onigmo.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const initialize_sym = try vm.intern("initialize");
    try vm.regexp_class.module.methods.put(initialize_sym, .{
        .method = .{ .builtin = &builtinRegexpInitialize },
        .visibility = .private,
    });

    const source_sym = try vm.intern("source");
    try vm.regexp_class.module.methods.put(source_sym, .{ .method = .{ .builtin = &builtinRegexpSource } });

    const options_sym = try vm.intern("options");
    try vm.regexp_class.module.methods.put(options_sym, .{ .method = .{ .builtin = &builtinRegexpOptions } });

    const inspect_sym = try vm.intern("inspect");
    try vm.regexp_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinRegexpInspect } });

    const to_s_sym = try vm.intern("to_s");
    try vm.regexp_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinRegexpToS } });

    const eq_sym = try vm.intern("==");
    try vm.regexp_class.module.methods.put(eq_sym, .{ .method = .{ .builtin = &builtinRegexpEq } });

    const casefold_sym = try vm.intern("casefold?");
    try vm.regexp_class.module.methods.put(casefold_sym, .{ .method = .{ .builtin = &builtinRegexpCasefold } });

    const case_equal_sym = try vm.intern("===");
    try vm.regexp_class.module.methods.put(case_equal_sym, .{ .method = .{ .builtin = &builtinRegexpCaseEqual } });

    const match_op_sym = try vm.intern("=~");
    try vm.regexp_class.module.methods.put(match_op_sym, .{ .method = .{ .builtin = &builtinRegexpMatchOp } });

    const match_sym = try vm.intern("match");
    try vm.regexp_class.module.methods.put(match_sym, .{ .method = .{ .builtin = &builtinRegexpMatch } });

    const match_q_sym = try vm.intern("match?");
    try vm.regexp_class.module.methods.put(match_q_sym, .{ .method = .{ .builtin = &builtinRegexpMatchQ } });

    const dup_sym = try vm.intern("dup");
    try vm.regexp_class.module.methods.put(dup_sym, .{ .method = .{ .builtin = &builtinRegexpDup } });

    const clone_sym = try vm.intern("clone");
    try vm.regexp_class.module.methods.put(clone_sym, .{ .method = .{ .builtin = &builtinRegexpClone } });

    const regexp_class_val = Value.fromObject(vm.regexp_class);
    const regexp_singleton = try vm.getOrCreateSingletonClass(regexp_class_val);
    const try_convert_sym = try vm.intern("try_convert");
    try regexp_singleton.module.methods.put(try_convert_sym, .{ .method = .{ .builtin = &builtinRegexpTryConvert } });
    const new_sym = try vm.intern("new");
    try regexp_singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = &builtinRegexpNew } });
    const escape_sym = try vm.intern("escape");
    try regexp_singleton.module.methods.put(escape_sym, .{ .method = .{ .builtin = &builtinRegexpEscape } });
    const last_match_sym = try vm.intern("last_match");
    try regexp_singleton.module.methods.put(last_match_sym, .{ .method = .{ .builtin = &builtinRegexpLastMatch } });
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

    return try vm.newRegexpWithEncoding(pattern_obj.str, options, pattern_obj.encoding);
}

fn builtinRegexpEscape(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const string_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const string_obj = string_value.toStringObject();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    for (string_obj.str) |b| {
        switch (b) {
            '\\', '.', '^', '$', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}' => {
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

fn builtinRegexpOptions(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.toRegexpObject().options));
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

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    writer.writeAll("(?") catch return error.Fatal;
    if ((r.options & 1) != 0) writer.writeByte('i') catch return error.Fatal;
    if ((r.options & 4) != 0) writer.writeByte('m') catch return error.Fatal;
    if ((r.options & 2) != 0) writer.writeByte('x') catch return error.Fatal;
    // Add dash and disabled flags
    var has_disabled = false;
    if ((r.options & 1) == 0) {
        if (!has_disabled) {
            writer.writeByte('-') catch return error.Fatal;
            has_disabled = true;
        }
        writer.writeByte('i') catch return error.Fatal;
    }
    if ((r.options & 4) == 0) {
        if (!has_disabled) {
            writer.writeByte('-') catch return error.Fatal;
            has_disabled = true;
        }
        writer.writeByte('m') catch return error.Fatal;
    }
    if ((r.options & 2) == 0) {
        if (!has_disabled) {
            writer.writeByte('-') catch return error.Fatal;
            has_disabled = true;
        }
        writer.writeByte('x') catch return error.Fatal;
    }
    writer.writeByte(':') catch return error.Fatal;
    writer.writeAll(r.pattern) catch return error.Fatal;
    writer.writeByte(')') catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
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
    else
        switch (try vm.probeToStringValue(args[0])) {
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

    const search_bytes = source_obj.str[start_byte..];
    const search_result = onigmo.searchWithCaptures(vm.gc_allocator, regexp_obj.regex, search_bytes) catch return error.Fatal;
    defer vm.gc_allocator.free(search_result.begin_offsets);
    defer vm.gc_allocator.free(search_result.end_offsets);

    if (!search_result.matched) {
        if (update_last_match) try vm.clearLastMatch();
        return null;
    }

    var captures: std.ArrayList(Value) = .empty;
    defer captures.deinit(vm.gc_allocator);

    const base_i64: i64 = @intCast(start_byte);
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

        const absolute_begin = beg + base_i64;
        const absolute_end = end_ + base_i64;
        begins[idx] = absolute_begin;
        ends[idx] = absolute_end;

        const begin_usize: usize = @intCast(absolute_begin);
        const end_usize: usize = @intCast(absolute_end);
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

    const absolute_match_index: usize = start_byte + @as(usize, @intCast(search_result.match_index));
    return .{
        .char_index = @intCast(source_obj.encoding.charCount(source_obj.str[0..absolute_match_index])),
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

    const md_val = Value.fromObject(result.?.match_data);
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
    const duplicate = try vm.newRegexp(regexp.pattern, regexp.options);
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
