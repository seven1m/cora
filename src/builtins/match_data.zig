const std = @import("std");
const onigmo = @import("../onigmo.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const bracket_sym = try vm.intern("[]");
    try vm.match_data_class.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinMatchDataBracket, .{ .variadic = 0 }));

    const match_sym = try vm.intern("match");
    try vm.match_data_class.module.methods.put(match_sym, value.MethodEntry.builtin(&builtinMatchDataMatch, .{ .exact = 1 }));

    const captures_sym = try vm.intern("captures");
    try vm.match_data_class.module.methods.put(captures_sym, value.MethodEntry.builtin(&builtinMatchDataCaptures, .{ .exact = 0 }));

    const deconstruct_sym = try vm.intern("deconstruct");
    try vm.match_data_class.module.methods.put(deconstruct_sym, value.MethodEntry.builtin(&builtinMatchDataCaptures, .{ .exact = 0 }));

    const deconstruct_keys_sym = try vm.intern("deconstruct_keys");
    try vm.match_data_class.module.methods.put(deconstruct_keys_sym, value.MethodEntry.builtin(&builtinMatchDataDeconstructKeys, .{ .exact = 1 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.match_data_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinMatchDataToA, .{ .exact = 0 }));

    const length_sym = try vm.intern("length");
    try vm.match_data_class.module.methods.put(length_sym, value.MethodEntry.builtin(&builtinMatchDataLength, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.match_data_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinMatchDataLength, .{ .exact = 0 }));

    const regexp_sym = try vm.intern("regexp");
    try vm.match_data_class.module.methods.put(regexp_sym, value.MethodEntry.builtin(&builtinMatchDataRegexp, .{ .exact = 0 }));

    const string_sym = try vm.intern("string");
    try vm.match_data_class.module.methods.put(string_sym, value.MethodEntry.builtin(&builtinMatchDataString, .{ .exact = 0 }));

    const pre_match_sym = try vm.intern("pre_match");
    try vm.match_data_class.module.methods.put(pre_match_sym, value.MethodEntry.builtin(&builtinMatchDataPreMatch, .{ .exact = 0 }));

    const post_match_sym = try vm.intern("post_match");
    try vm.match_data_class.module.methods.put(post_match_sym, value.MethodEntry.builtin(&builtinMatchDataPostMatch, .{ .exact = 0 }));

    const offset_sym = try vm.intern("offset");
    try vm.match_data_class.module.methods.put(offset_sym, value.MethodEntry.builtin(&builtinMatchDataOffset, .{ .exact = 1 }));

    const begin_sym = try vm.intern("begin");
    try vm.match_data_class.module.methods.put(begin_sym, value.MethodEntry.builtin(&builtinMatchDataBegin, .{ .exact = 1 }));

    const end_sym = try vm.intern("end");
    try vm.match_data_class.module.methods.put(end_sym, value.MethodEntry.builtin(&builtinMatchDataEnd, .{ .exact = 1 }));

    const names_sym = try vm.intern("names");
    try vm.match_data_class.module.methods.put(names_sym, value.MethodEntry.builtin(&builtinMatchDataNames, .{ .exact = 0 }));

    const named_captures_sym = try vm.intern("named_captures");
    try vm.match_data_class.module.methods.put(named_captures_sym, value.MethodEntry.keywordBuiltin(&builtinMatchDataNamedCaptures, .{ .variadic = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.match_data_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinMatchDataToS, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.match_data_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinMatchDataEqual, .{ .exact = 1 }));

    const match_length_sym = try vm.intern("match_length");
    try vm.match_data_class.module.methods.put(match_length_sym, value.MethodEntry.builtin(&builtinMatchDataMatchLength, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.match_data_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinMatchDataEqual, .{ .exact = 1 }));

    const byteoffset_sym = try vm.intern("byteoffset");
    try vm.match_data_class.module.methods.put(byteoffset_sym, value.MethodEntry.builtin(&builtinMatchDataByteoffset, .{ .exact = 1 }));

    const bytebegin_sym = try vm.intern("bytebegin");
    try vm.match_data_class.module.methods.put(bytebegin_sym, value.MethodEntry.builtin(&builtinMatchDataBytebegin, .{ .exact = 1 }));

    const byteend_sym = try vm.intern("byteend");
    try vm.match_data_class.module.methods.put(byteend_sym, value.MethodEntry.builtin(&builtinMatchDataByteend, .{ .exact = 1 }));

    const values_at_sym = try vm.intern("values_at");
    try vm.match_data_class.module.methods.put(values_at_sym, value.MethodEntry.builtin(&builtinMatchDataValuesAt, .{ .variadic = 0 }));

    const allocate_sym = try vm.intern("allocate");
    const singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.match_data_class.module.object));
    try singleton.module.methods.put(allocate_sym, .{ .method = .{ .undefined = {} } });

    const inspect_sym = try vm.intern("inspect");
    try vm.match_data_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinMatchDataInspect, .{ .exact = 0 }));

    const dup_sym = try vm.intern("dup");
    try vm.match_data_class.module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinMatchDataDup, .{ .exact = 0 }));
}

fn getMatchData(receiver: Value) VMError!*value.MatchDataObject {
    if (!receiver.isMatchData()) return error.Fatal;
    return receiver.toMatchDataObject();
}

fn captureAt(md: *value.MatchDataObject, index: i64) Value {
    const len: i64 = @intCast(md.captures.items.len);
    var actual = index;
    if (actual < 0) actual += len;
    if (actual < 0 or actual >= len) return Value.nil();
    return md.captures.items[@intCast(actual)];
}

fn buildArray(vm: *VM, items: []const Value) VMError!Value {
    const arr = try vm.createArray();
    for (items) |item| {
        arr.elements.append(vm.gc_allocator, item) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

fn buildCaptureSlice(vm: *VM, md: *value.MatchDataObject, start: i64, end_exclusive: i64) VMError!Value {
    const arr = try vm.createArray();
    var i = start;
    while (i < end_exclusive) : (i += 1) {
        arr.elements.append(vm.gc_allocator, md.captures.items[@intCast(i)]) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

fn resolveNamedCaptureIndex(vm: *VM, md: *value.MatchDataObject, name: []const u8) VMError!?usize {
    const groups = onigmo.collectNamedCaptureGroups(vm.allocator, md.regexp.regex) catch return error.Fatal;
    defer onigmo.freeNamedCaptureGroups(vm.allocator, groups);

    for (groups) |group| {
        if (!std.mem.eql(u8, group.name, name)) continue;

        var i = group.group_numbers.len;
        while (i > 0) {
            i -= 1;
            const group_index: usize = @intCast(group.group_numbers[i]);
            if (group_index >= md.begin_byte_offsets.items.len) continue;
            if (md.begin_byte_offsets.items[group_index] >= 0) return group_index;
        }

        return null;
    }

    return vm.raiseExceptionFmt(vm.index_error_class, "undefined group name reference: {s}", .{name});
}

fn captureByName(vm: *VM, md: *value.MatchDataObject, name: []const u8) VMError!Value {
    const maybe_index = try resolveNamedCaptureIndex(vm, md, name);
    if (maybe_index) |index| return md.captures.items[index];
    return Value.nil();
}

fn buildNamesArray(vm: *VM, regexp: *value.RegexpObject) VMError!Value {
    const groups = onigmo.collectNamedCaptureGroups(vm.allocator, regexp.regex) catch return error.Fatal;
    defer onigmo.freeNamedCaptureGroups(vm.allocator, groups);

    const arr = try vm.createArray();
    for (groups) |group| {
        arr.elements.append(vm.gc_allocator, try vm.newString(group.name, false)) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

fn builtinMatchDataBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const md = try getMatchData(receiver);
    const len: i64 = @intCast(md.captures.items.len);

    if (args.len == 1) {
        if (args[0].isRange()) {
            const range_obj = args[0].toRangeObject();
            var actual_start: i64 = 0;
            if (!range_obj.begin.isNil()) {
                actual_start = try range_obj.begin.coerceToI64ViaToInt(
                    vm,
                    "no implicit conversion into Integer",
                    "no implicit conversion into Integer",
                    "bignum too big to convert into `long`",
                );
                if (actual_start < 0) actual_start += len;
            }
            if (actual_start < 0 or actual_start > len) return Value.nil();

            var finish: i64 = len;
            if (!range_obj.end.isNil()) {
                finish = try range_obj.end.coerceToI64ViaToInt(
                    vm,
                    "no implicit conversion into Integer",
                    "no implicit conversion into Integer",
                    "bignum too big to convert into `long`",
                );
                if (finish < 0) finish += len;
                if (!range_obj.exclude_end) finish += 1;
            }

            if (finish < actual_start) {
                const empty = try vm.createArray();
                return Value.fromObject(&empty.object);
            }

            const clamped_end = @max(actual_start, @min(finish, len));
            return buildCaptureSlice(vm, md, actual_start, clamped_end);
        }

        if (args[0].isSymbol()) {
            return captureByName(vm, md, args[0].toSymbolObject().name);
        }

        if (args[0].isString()) {
            return captureByName(vm, md, args[0].toStringObject().str);
        }

        const index = try args[0].coerceToI64ViaToInt(
            vm,
            "no implicit conversion into Integer",
            "no implicit conversion into Integer",
            "bignum too big to convert into `long`",
        );
        return captureAt(md, index);
    }

    const start = try args[0].coerceToI64ViaToInt(
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

    var actual_start = start;
    if (actual_start < 0) actual_start += len;
    if (actual_start < 0 or actual_start > len) return Value.nil();
    if (length < 0) return Value.nil();

    const end_exclusive = @min(actual_start + length, len);
    return buildCaptureSlice(vm, md, actual_start, end_exclusive);
}

fn builtinMatchDataMatch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return builtinMatchDataBracket(vm, receiver, args, block);
}

fn builtinMatchDataCaptures(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    if (md.captures.items.len <= 1) {
        return buildArray(vm, &[_]Value{});
    }
    return buildArray(vm, md.captures.items[1..]);
}

fn builtinMatchDataToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    return buildArray(vm, md.captures.items);
}

fn builtinMatchDataLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    return Value.integer(@intCast(md.captures.items.len));
}

fn builtinMatchDataRegexp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    return Value.fromObject(&md.regexp.object);
}

fn builtinMatchDataString(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    // Return a frozen copy of the matched string, caching it on the
    // MatchData so repeated calls return the same object.
    if (!Value.fromObject(&md.source.object).isFrozen()) {
        const frozen_copy = try vm.newStringWithEncoding(md.source.str, true, md.source.encoding);
        md.source = frozen_copy.toStringObject();
    }
    return Value.fromObject(&md.source.object);
}

fn builtinMatchDataToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    if (md.begin_byte_offsets.items.len == 0 or md.begin_byte_offsets.items[0] < 0) {
        return vm.newString("", false);
    }
    const begin_idx: usize = @intCast(md.begin_byte_offsets.items[0]);
    const end_idx: usize = @intCast(md.end_byte_offsets.items[0]);
    if (begin_idx > end_idx or end_idx > md.source.str.len) return error.Fatal;
    return vm.newStringWithEncoding(md.source.str[begin_idx..end_idx], false, md.source.encoding);
}

fn builtinMatchDataPreMatch(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    if (md.begin_byte_offsets.items.len == 0 or md.begin_byte_offsets.items[0] < 0) {
        return Value.nil();
    }
    const begin_idx: usize = @intCast(md.begin_byte_offsets.items[0]);
    if (begin_idx > md.source.str.len) return error.Fatal;
    return vm.newStringWithEncoding(md.source.str[0..begin_idx], false, md.source.encoding);
}

fn builtinMatchDataPostMatch(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    if (md.end_byte_offsets.items.len == 0 or md.end_byte_offsets.items[0] < 0) {
        return Value.nil();
    }
    const end_idx: usize = @intCast(md.end_byte_offsets.items[0]);
    if (end_idx > md.source.str.len) return error.Fatal;
    return vm.newStringWithEncoding(md.source.str[end_idx..], false, md.source.encoding);
}

fn charOffsetAt(vm: *VM, md: *value.MatchDataObject, index: usize) VMError!Value {
    if (index >= md.begin_byte_offsets.items.len or index >= md.end_byte_offsets.items.len) {
        return nilOffsetPair(vm);
    }
    const begin_pos = md.begin_byte_offsets.items[index];
    const end_pos = md.end_byte_offsets.items[index];
    if (begin_pos < 0 or end_pos < 0) {
        return nilOffsetPair(vm);
    }
    const byte_begin: usize = @intCast(begin_pos);
    const byte_end: usize = @intCast(end_pos);
    if (byte_begin > md.source.str.len or byte_end > md.source.str.len) return error.Fatal;
    const begin_char = md.source.encoding.charCount(md.source.str[0..byte_begin]);
    const end_char = md.source.encoding.charCount(md.source.str[0..byte_end]);
    const arr = try vm.createArray();
    arr.elements.append(vm.gc_allocator, Value.integer(@intCast(begin_char))) catch return error.Fatal;
    arr.elements.append(vm.gc_allocator, Value.integer(@intCast(end_char))) catch return error.Fatal;
    return Value.fromObject(&arr.object);
}

fn builtinMatchDataOffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return charOffsetAt(vm, md, index);
        return nilOffsetPair(vm);
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return charOffsetAt(vm, md, index);
        return nilOffsetPair(vm);
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return charOffsetAt(vm, md, @intCast(idx));
}

fn beginCharOffsetAt(md: *value.MatchDataObject, index: usize) VMError!Value {
    if (index >= md.begin_byte_offsets.items.len) return Value.nil();
    const begin_pos = md.begin_byte_offsets.items[index];
    if (begin_pos < 0) return Value.nil();
    const byte_begin: usize = @intCast(begin_pos);
    if (byte_begin > md.source.str.len) return error.Fatal;
    const char_off = md.source.encoding.charCount(md.source.str[0..byte_begin]);
    return Value.integer(@intCast(char_off));
}

fn builtinMatchDataBegin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return beginCharOffsetAt(md, index);
        return Value.nil();
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return beginCharOffsetAt(md, index);
        return Value.nil();
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return beginCharOffsetAt(md, @intCast(idx));
}

fn endCharOffsetAt(md: *value.MatchDataObject, index: usize) VMError!Value {
    if (index >= md.end_byte_offsets.items.len) return Value.nil();
    const end_pos = md.end_byte_offsets.items[index];
    if (end_pos < 0) return Value.nil();
    const byte_end: usize = @intCast(end_pos);
    if (byte_end > md.source.str.len) return error.Fatal;
    const char_off = md.source.encoding.charCount(md.source.str[0..byte_end]);
    return Value.integer(@intCast(char_off));
}

fn builtinMatchDataEnd(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return endCharOffsetAt(md, index);
        return Value.nil();
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return endCharOffsetAt(md, index);
        return Value.nil();
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.end_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return endCharOffsetAt(md, @intCast(idx));
}

fn builtinMatchDataNames(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    return buildNamesArray(vm, md.regexp);
}

fn builtinMatchDataNamedCaptures(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    var symbolize_names = Value.nil();
    try vm.consumeKeywordArgs(.{"symbolize_names"}, .{&symbolize_names});

    const md = try getMatchData(receiver);
    const groups = onigmo.collectNamedCaptureGroups(vm.allocator, md.regexp.regex) catch return error.Fatal;
    defer onigmo.freeNamedCaptureGroups(vm.allocator, groups);

    const hash = try vm.createHash();
    for (groups) |group| {
        const key = if (symbolize_names.isTruthy())
            Value.fromObject(&(try vm.intern(group.name)).object)
        else
            try vm.newString(group.name, false);
        try vm.hashSetEntry(hash, key, try captureByName(vm, md, group.name));
    }

    return Value.fromObject(&hash.object);
}

fn builtinMatchDataEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isMatchData()) return Value.boolean(false);
    const self_md = try getMatchData(receiver);
    const other_md = other.toMatchDataObject();
    if (!std.mem.eql(u8, self_md.source.str, other_md.source.str)) return Value.boolean(false);
    if (!std.mem.eql(u8, self_md.regexp.pattern, other_md.regexp.pattern)) return Value.boolean(false);
    if (self_md.regexp.options != other_md.regexp.options) return Value.boolean(false);
    if (!std.mem.eql(i64, self_md.begin_byte_offsets.items, other_md.begin_byte_offsets.items)) return Value.boolean(false);
    if (!std.mem.eql(i64, self_md.end_byte_offsets.items, other_md.end_byte_offsets.items)) return Value.boolean(false);
    return Value.boolean(true);
}

fn builtinMatchDataDeconstructKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const groups = onigmo.collectNamedCaptureGroups(vm.allocator, md.regexp.regex) catch return error.Fatal;
    defer onigmo.freeNamedCaptureGroups(vm.allocator, groups);

    const hash = try vm.createHash();
    const result = Value.fromObject(&hash.object);

    if (args[0].isNil()) {
        for (groups) |group| {
            const sym = try vm.intern(group.name);
            try vm.hashSetEntry(hash, Value.fromObject(&sym.object), try captureByName(vm, md, group.name));
        }
        return result;
    }

    if (!args[0].isArray()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Array)", .{vm.className(args[0])});
    }
    const keys = args[0].toArrayObject().elements.items;

    if (keys.len > groups.len) return result;

    for (keys) |key| {
        if (!key.isSymbol()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Symbol)", .{vm.className(key)});
        }
        const name = key.toSymbolObject().name;
        var found = false;
        for (groups) |group| {
            if (std.mem.eql(u8, group.name, name)) {
                found = true;
                break;
            }
        }
        if (!found) return result;
        try vm.hashSetEntry(hash, key, try captureByName(vm, md, name));
    }

    return result;
}

fn matchLengthAt(vm: *VM, md: *value.MatchDataObject, index: usize) VMError!Value {
    if (index >= md.begin_byte_offsets.items.len or index >= md.end_byte_offsets.items.len) return Value.nil();
    const begin_pos = md.begin_byte_offsets.items[index];
    const end_pos = md.end_byte_offsets.items[index];
    if (begin_pos < 0 or end_pos < 0) return Value.nil();
    _ = vm;
    return Value.integer(end_pos - begin_pos);
}

fn byteOffsetAt(vm: *VM, md: *value.MatchDataObject, index: usize) VMError!Value {
    const arr = try vm.createArray();
    if (index >= md.begin_byte_offsets.items.len or index >= md.end_byte_offsets.items.len) {
        arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
        arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
        return Value.fromObject(&arr.object);
    }
    const begin_pos = md.begin_byte_offsets.items[index];
    const end_pos = md.end_byte_offsets.items[index];
    if (begin_pos < 0 or end_pos < 0) {
        arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
        arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
        return Value.fromObject(&arr.object);
    }
    arr.elements.append(vm.gc_allocator, Value.integer(begin_pos)) catch return error.Fatal;
    arr.elements.append(vm.gc_allocator, Value.integer(end_pos)) catch return error.Fatal;
    return Value.fromObject(&arr.object);
}

fn nilOffsetPair(vm: *VM) VMError!Value {
    const arr = try vm.createArray();
    arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    arr.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    return Value.fromObject(&arr.object);
}

fn builtinMatchDataByteoffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return byteOffsetAt(vm, md, index);
        return nilOffsetPair(vm);
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return byteOffsetAt(vm, md, index);
        return nilOffsetPair(vm);
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return byteOffsetAt(vm, md, @intCast(idx));
}

fn builtinMatchDataMatchLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return matchLengthAt(vm, md, index);
        return Value.nil();
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return matchLengthAt(vm, md, index);
        return Value.nil();
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return matchLengthAt(vm, md, @intCast(idx));
}

fn coerceMatchDataIndex(vm: *VM, arg: Value) VMError!i64 {
    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    return arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );
}

fn builtinMatchDataValuesAt(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const md = try getMatchData(receiver);
    const len: i64 = @intCast(md.captures.items.len);
    const result = try vm.createArray();

    for (args) |arg| {
        if (arg.isSymbol()) {
            result.elements.append(vm.gc_allocator, try captureByName(vm, md, arg.toSymbolObject().name)) catch return error.Fatal;
            continue;
        }

        if (arg.isString()) {
            result.elements.append(vm.gc_allocator, try captureByName(vm, md, arg.toStringObject().str)) catch return error.Fatal;
            continue;
        }

        if (arg.isRange()) {
            const range_obj = arg.toRangeObject();

            var beg: i64 = 0;
            if (!range_obj.begin.isNil()) {
                beg = try coerceMatchDataIndex(vm, range_obj.begin);
                if (beg < 0) {
                    beg += len;
                    if (beg < 0) {
                        const range_str = try vm.callMethodByName(arg, "to_s", &.{}, null);
                        return vm.raiseExceptionFmt(vm.range_error_class, "{s} out of range", .{range_str.toStringObject().str});
                    }
                }
            }

            var count: i64 = len - beg;
            if (!range_obj.end.isNil()) {
                var end_raw = try coerceMatchDataIndex(vm, range_obj.end);
                if (end_raw < 0) end_raw += len;
                if (range_obj.exclude_end) {
                    count = end_raw - beg;
                } else {
                    count = end_raw - beg + 1;
                }
                if (count < 0) count = 0;
            }

            var i: i64 = beg;
            while (i < beg + count) : (i += 1) {
                result.elements.append(vm.gc_allocator, captureAt(md, i)) catch return error.Fatal;
            }
            continue;
        }

        const index = try coerceMatchDataIndex(vm, arg);
        result.elements.append(vm.gc_allocator, captureAt(md, index)) catch return error.Fatal;
    }

    return Value.fromObject(&result.object);
}

fn appendInspectedCapture(vm: *VM, buf: *std.Io.Writer.Allocating, val: Value) VMError!void {
    if (val.isNil()) {
        buf.writer.writeAll("nil") catch return error.Fatal;
        return;
    }
    const inspected = try vm.callMethodByName(val, "inspect", &.{}, null);
    if (!inspected.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "inspect did not return String", .{});
    }
    buf.writer.writeAll(inspected.toStringObject().str) catch return error.Fatal;
}

fn builtinMatchDataInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);

    var buf: std.Io.Writer.Allocating = .init(vm.allocator);
    defer buf.deinit();
    buf.writer.writeAll("#<MatchData ") catch return error.Fatal;

    if (md.captures.items.len > 0) {
        try appendInspectedCapture(vm, &buf, md.captures.items[0]);
    }

    const groups = onigmo.collectNamedCaptureGroups(vm.allocator, md.regexp.regex) catch return error.Fatal;
    defer onigmo.freeNamedCaptureGroups(vm.allocator, groups);

    if (groups.len > 0) {
        for (groups) |group| {
            buf.writer.writeByte(' ') catch return error.Fatal;
            buf.writer.writeAll(group.name) catch return error.Fatal;
            buf.writer.writeByte(':') catch return error.Fatal;
            try appendInspectedCapture(vm, &buf, try captureByName(vm, md, group.name));
        }
    } else {
        var i: usize = 1;
        while (i < md.captures.items.len) : (i += 1) {
            var num_buf: [32]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, " {d}:", .{i}) catch return error.Fatal;
            buf.writer.writeAll(num_str) catch return error.Fatal;
            try appendInspectedCapture(vm, &buf, md.captures.items[i]);
        }
    }

    buf.writer.writeByte('>') catch return error.Fatal;

    const str = buf.toOwnedSlice() catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

fn builtinMatchDataDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    const duplicate = try vm.newMatchData(
        md.regexp,
        md.source,
        md.captures.items,
        md.begin_byte_offsets.items,
        md.end_byte_offsets.items,
    );
    duplicate.getObjectPointer().?.class = vm.getClass(receiver);

    const src_obj = receiver.getObjectPointer() orelse return error.Fatal;
    const dst_obj = duplicate.getObjectPointer() orelse return error.Fatal;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);
    return duplicate;
}

fn byteBeginAt(md: *value.MatchDataObject, index: usize) Value {
    if (index >= md.begin_byte_offsets.items.len) return Value.nil();
    const begin_pos = md.begin_byte_offsets.items[index];
    if (begin_pos < 0) return Value.nil();
    return Value.integer(begin_pos);
}

fn builtinMatchDataBytebegin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return byteBeginAt(md, index);
        return Value.nil();
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return byteBeginAt(md, index);
        return Value.nil();
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return byteBeginAt(md, @intCast(idx));
}

fn byteEndAt(md: *value.MatchDataObject, index: usize) Value {
    if (index >= md.end_byte_offsets.items.len) return Value.nil();
    const end_pos = md.end_byte_offsets.items[index];
    if (end_pos < 0) return Value.nil();
    return Value.integer(end_pos);
}

fn builtinMatchDataByteend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const md = try getMatchData(receiver);
    const arg = args[0];

    if (arg.isSymbol()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toSymbolObject().name);
        if (maybe_index) |index| return byteEndAt(md, index);
        return Value.nil();
    }

    if (arg.isString()) {
        const maybe_index = try resolveNamedCaptureIndex(vm, md, arg.toStringObject().str);
        if (maybe_index) |index| return byteEndAt(md, index);
        return Value.nil();
    }

    const message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{vm.className(arg)}) catch return error.Fatal;
    defer vm.allocator.free(message);
    const idx = try arg.coerceToI64ViaToInt(
        vm,
        message,
        message,
        "bignum too big to convert into `long`",
    );

    const len: i64 = @intCast(md.end_byte_offsets.items.len);
    if (idx < 0 or idx >= len) {
        return vm.raiseExceptionFmt(vm.index_error_class, "index {d} out of matches", .{idx});
    }
    return byteEndAt(md, @intCast(idx));
}
