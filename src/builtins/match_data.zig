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

    const names_sym = try vm.intern("names");
    try vm.match_data_class.module.methods.put(names_sym, value.MethodEntry.builtin(&builtinMatchDataNames, .{ .exact = 0 }));

    const named_captures_sym = try vm.intern("named_captures");
    try vm.match_data_class.module.methods.put(named_captures_sym, value.MethodEntry.builtin(&builtinMatchDataNamedCaptures, .{ .variadic = 0 }));
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
    return Value.fromObject(&md.source.object);
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

fn builtinMatchDataOffset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const md = try getMatchData(receiver);
    var idx = args[0].toInteger();
    const len: i64 = @intCast(md.captures.items.len);
    if (idx < 0) idx += len;
    if (idx < 0 or idx >= len) return Value.nil();

    const index: usize = @intCast(idx);
    if (index >= md.begin_byte_offsets.items.len or index >= md.end_byte_offsets.items.len) return Value.nil();
    const begin_pos = md.begin_byte_offsets.items[index];
    const end_pos = md.end_byte_offsets.items[index];
    if (begin_pos < 0 or end_pos < 0) return Value.nil();

    const arr = try vm.createArray();
    arr.elements.append(vm.gc_allocator, Value.integer(begin_pos)) catch return error.Fatal;
    arr.elements.append(vm.gc_allocator, Value.integer(end_pos)) catch return error.Fatal;
    return Value.fromObject(&arr.object);
}

fn builtinMatchDataBegin(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const md = try getMatchData(receiver);
    var idx = args[0].toInteger();
    const len: i64 = @intCast(md.begin_byte_offsets.items.len);
    if (idx < 0) idx += len;
    if (idx < 0 or idx >= len) return Value.nil();

    const begin_pos = md.begin_byte_offsets.items[@intCast(idx)];
    if (begin_pos < 0) return Value.nil();
    return Value.integer(begin_pos);
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
