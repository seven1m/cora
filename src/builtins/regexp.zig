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
