const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const name_sym = try vm.intern("name");
    try vm.encoding_class.module.methods.put(name_sym, .{ .method = .{ .builtin = &builtinEncodingName } });

    const to_s_sym = try vm.intern("to_s");
    try vm.encoding_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinEncodingName } });

    const inspect_sym = try vm.intern("inspect");
    try vm.encoding_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinEncodingInspect } });

    const equal_sym = try vm.intern("==");
    try vm.encoding_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinEncodingEqual } });

    const ascii_compatible_sym = try vm.intern("ascii_compatible?");
    try vm.encoding_class.module.methods.put(ascii_compatible_sym, .{ .method = .{ .builtin = &builtinEncodingAsciiCompatible } });

    const find_sym = try vm.intern("find");
    const encoding_class_val = Value{ .data = .{ .class = vm.encoding_class } };
    const encoding_singleton = try vm.getOrCreateSingletonClass(encoding_class_val);
    try encoding_singleton.module.methods.put(find_sym, .{ .method = .{ .builtin = &builtinEncodingFind } });
}

pub fn builtinEncodingName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    return try vm.newString(encoding_obj.encoding.name(), true);
}

pub fn builtinEncodingInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    const str = std.fmt.allocPrint(vm.gc_allocator, "#<Encoding:{s}>", .{encoding_obj.encoding.name()}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinEncodingAsciiCompatible(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const encoding_obj = receiver.data.encoding;
    return Value.boolean(encoding_obj.encoding.isAsciiCompatible());
}

pub fn builtinEncodingEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (other.data != .encoding) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.data.encoding.encoding.eql(other.data.encoding.encoding));
}

pub fn builtinEncodingFind(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.data == .encoding) {
        return arg;
    }

    const name_str = try vm.coerceToStr(arg, "no implicit conversion into String");

    // Normalize: uppercase and replace - with _
    var normalized: [32]u8 = undefined;
    var len: usize = 0;
    for (name_str) |c| {
        if (len >= normalized.len) break;
        if (c == '-') {
            normalized[len] = '_';
        } else if (c >= 'a' and c <= 'z') {
            normalized[len] = c - 32; // uppercase
        } else {
            normalized[len] = c;
        }
        len += 1;
    }
    const lookup = normalized[0..len];

    // Match encoding name
    if (std.mem.eql(u8, lookup, "UTF_8") or std.mem.eql(u8, lookup, "UTF8")) {
        return Value{ .data = .{ .encoding = vm.encoding_utf8 } };
    } else if (std.mem.eql(u8, lookup, "ASCII_8BIT") or std.mem.eql(u8, lookup, "BINARY")) {
        return Value{ .data = .{ .encoding = vm.encoding_ascii_8bit } };
    } else if (std.mem.eql(u8, lookup, "US_ASCII") or std.mem.eql(u8, lookup, "ASCII")) {
        return Value{ .data = .{ .encoding = vm.encoding_us_ascii } };
    }

    return vm.raiseExceptionFmt(vm.argument_error_class, "unknown encoding name - {s}", .{name_str});
}
