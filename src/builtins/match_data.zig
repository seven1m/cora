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

fn builtinMatchDataBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const md = try getMatchData(receiver);
    return captureAt(md, args[0].toInteger());
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
