const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const bracket_sym = try vm.intern("[]");
    try vm.match_data_class.module.methods.put(bracket_sym, .{ .method = .{ .builtin = &builtinMatchDataBracket } });

    const match_sym = try vm.intern("match");
    try vm.match_data_class.module.methods.put(match_sym, .{ .method = .{ .builtin = &builtinMatchDataMatch } });

    const captures_sym = try vm.intern("captures");
    try vm.match_data_class.module.methods.put(captures_sym, .{ .method = .{ .builtin = &builtinMatchDataCaptures } });

    const to_a_sym = try vm.intern("to_a");
    try vm.match_data_class.module.methods.put(to_a_sym, .{ .method = .{ .builtin = &builtinMatchDataToA } });

    const length_sym = try vm.intern("length");
    try vm.match_data_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinMatchDataLength } });

    const size_sym = try vm.intern("size");
    try vm.match_data_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinMatchDataLength } });

    const regexp_sym = try vm.intern("regexp");
    try vm.match_data_class.module.methods.put(regexp_sym, .{ .method = .{ .builtin = &builtinMatchDataRegexp } });

    const string_sym = try vm.intern("string");
    try vm.match_data_class.module.methods.put(string_sym, .{ .method = .{ .builtin = &builtinMatchDataString } });

    const pre_match_sym = try vm.intern("pre_match");
    try vm.match_data_class.module.methods.put(pre_match_sym, .{ .method = .{ .builtin = &builtinMatchDataPreMatch } });

    const post_match_sym = try vm.intern("post_match");
    try vm.match_data_class.module.methods.put(post_match_sym, .{ .method = .{ .builtin = &builtinMatchDataPostMatch } });
}

fn getMatchData(receiver: Value) VMError!*value.MatchDataObject {
    if (receiver.data != .match_data) return error.Fatal;
    return receiver.data.match_data;
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
    return Value{ .data = .{ .array = arr } };
}

fn builtinMatchDataBracket(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .integer) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    const md = try getMatchData(receiver);
    return captureAt(md, args[0].data.integer);
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
    return Value{ .data = .{ .regexp = md.regexp } };
}

fn builtinMatchDataString(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const md = try getMatchData(receiver);
    return Value{ .data = .{ .string = md.source } };
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
