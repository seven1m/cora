const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const onigmo = @import("../onigmo.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
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

    const regexp_class_val = Value{ .data = .{ .class = vm.regexp_class } };
    const regexp_singleton = try vm.getOrCreateSingletonClass(regexp_class_val);
    const last_match_sym = try vm.intern("last_match");
    try regexp_singleton.module.methods.put(last_match_sym, .{ .method = .{ .builtin = &builtinRegexpLastMatch } });
}

fn builtinRegexpSource(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.newString(receiver.data.regexp.pattern, false);
}

fn builtinRegexpOptions(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(receiver.data.regexp.options));
}

fn builtinRegexpInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const r = receiver.data.regexp;

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);
    writer.writeByte('/') catch return error.Fatal;
    writer.writeAll(r.pattern) catch return error.Fatal;
    writer.writeByte('/') catch return error.Fatal;
    if ((r.options & 1) != 0) writer.writeByte('i') catch return error.Fatal;
    if ((r.options & 2) != 0) writer.writeByte('x') catch return error.Fatal;
    if ((r.options & 4) != 0) writer.writeByte('m') catch return error.Fatal;

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

fn builtinRegexpToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const r = receiver.data.regexp;

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(vm.allocator);
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

    const str = buf.toOwnedSlice(vm.allocator) catch return error.Fatal;
    defer vm.allocator.free(str);
    return try vm.newString(str, false);
}

fn builtinRegexpEq(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (other.data != .regexp) {
        return Value.boolean(false);
    }
    const self_r = receiver.data.regexp;
    const other_r = other.data.regexp;
    return Value.boolean(
        std.mem.eql(u8, self_r.pattern, other_r.pattern) and self_r.options == other_r.options,
    );
}

fn builtinRegexpCasefold(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean((receiver.data.regexp.options & 1) != 0);
}

fn builtinRegexpCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .string) {
        return Value.boolean(false);
    }

    const text = args[0].data.string.str;
    return Value.boolean(onigmo.search(receiver.data.regexp.regex, text));
}

fn matchDataAt(md: *value.MatchDataObject, index: i64) Value {
    const len: i64 = @intCast(md.captures.items.len);
    var actual = index;
    if (actual < 0) actual += len;
    if (actual < 0 or actual >= len) return Value.nil();
    return md.captures.items[@intCast(actual)];
}

pub fn regexpMatchOp(vm: *VM, regexp_obj: *value.RegexpObject, arg: Value) VMError!Value {
    const source_val_opt = try arg.coerceToMatchSource(vm);
    if (source_val_opt == null) {
        try vm.clearLastMatch();
        return Value.nil();
    }
    const source_val = source_val_opt.?;
    const source_obj = source_val.data.string;

    const search_result = onigmo.searchWithCaptures(vm.gc_allocator, regexp_obj.regex, source_obj.str) catch return error.Fatal;
    defer vm.gc_allocator.free(search_result.begin_offsets);
    defer vm.gc_allocator.free(search_result.end_offsets);

    if (!search_result.matched) {
        try vm.clearLastMatch();
        return Value.nil();
    }

    var captures: std.ArrayList(Value) = .empty;
    defer captures.deinit(vm.gc_allocator);

    for (search_result.begin_offsets, search_result.end_offsets) |beg, end_| {
        if (beg < 0 or end_ < 0) {
            captures.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            continue;
        }

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
        search_result.begin_offsets,
        search_result.end_offsets,
    );
    try vm.setLastMatch(md_val.data.match_data);
    return Value.integer(search_result.match_index);
}

fn builtinRegexpMatchOp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (receiver.data != .regexp) {
        return vm.raiseExceptionFmt(vm.type_error_class, "uninitialized Regexp", .{});
    }
    return regexpMatchOp(vm, receiver.data.regexp, args[0]);
}

fn builtinRegexpLastMatch(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const current = vm.globals.get("$~") orelse Value.nil();
    if (args.len == 0) {
        return current;
    }
    if (current.data != .match_data) {
        return Value.nil();
    }
    if (args[0].data != .integer) {
        return Value.nil();
    }
    return matchDataAt(current.data.match_data, args[0].data.integer);
}
