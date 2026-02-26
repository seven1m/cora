const std = @import("std");
const enc = @import("encoding.zig");
const value = @import("value.zig");
const vm_mod = @import("vm.zig");

const Value = value.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

pub const Endianness = enum {
    native,
    little,
    big,
};

pub const DirectiveToken = struct {
    directive: u8,
    count: ?usize = null,
    star: bool = false,
    native_size: bool = false,
    endianness: Endianness = .native,
    err_msg: ?[]const u8 = null,
};

pub fn arrayPack(vm: *VM, items: []Value, format: []const u8) VMError!Value {
    var tokens = try tokenize(vm, format);
    defer tokens.deinit(vm.allocator);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    var arg_index: usize = 0;
    for (tokens.items) |token| {
        if (token.err_msg) |msg| {
            return vm.raiseExceptionFmt(vm.argument_error_class, "{s}", .{msg});
        }

        switch (token.directive) {
            'A', 'a', 'Z' => try packStringDirective(vm, items, &arg_index, token, &out),
            'c' => try packIntegerDirective(vm, items, &arg_index, token, &out, 1, true, .native),
            'C' => try packIntegerDirective(vm, items, &arg_index, token, &out, 1, false, .native),
            's' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_short) else 2, true, token.endianness),
            'S' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_ushort) else 2, false, token.endianness),
            'l' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_long) else 4, true, token.endianness),
            'L' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_ulong) else 4, false, token.endianness),
            'i' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_int) else 4, true, token.endianness),
            'I' => try packIntegerDirective(vm, items, &arg_index, token, &out, if (token.native_size) @sizeOf(c_uint) else 4, false, token.endianness),
            'j' => try packIntegerDirective(vm, items, &arg_index, token, &out, @sizeOf(isize), true, token.endianness),
            'J' => try packIntegerDirective(vm, items, &arg_index, token, &out, @sizeOf(usize), false, token.endianness),
            'q' => try packIntegerDirective(vm, items, &arg_index, token, &out, 8, true, token.endianness),
            'Q' => try packIntegerDirective(vm, items, &arg_index, token, &out, 8, false, token.endianness),
            'n' => try packIntegerDirective(vm, items, &arg_index, token, &out, 2, false, .big),
            'N' => try packIntegerDirective(vm, items, &arg_index, token, &out, 4, false, .big),
            'v' => try packIntegerDirective(vm, items, &arg_index, token, &out, 2, false, .little),
            'V' => try packIntegerDirective(vm, items, &arg_index, token, &out, 4, false, .little),
            'f', 'F' => try packFloatDirective(vm, items, &arg_index, token, &out, 4, token.endianness),
            'd', 'D' => try packFloatDirective(vm, items, &arg_index, token, &out, 8, token.endianness),
            'e' => try packFloatDirective(vm, items, &arg_index, token, &out, 4, .little),
            'E' => try packFloatDirective(vm, items, &arg_index, token, &out, 8, .little),
            'g' => try packFloatDirective(vm, items, &arg_index, token, &out, 4, .big),
            'G' => try packFloatDirective(vm, items, &arg_index, token, &out, 8, .big),
            'x' => {
                if (!token.star) {
                    const count = token.count orelse 1;
                    try appendZeros(vm, &out, count);
                }
            },
            'X' => {
                if (!token.star) {
                    const count = token.count orelse 1;
                    if (count > out.items.len) {
                        return vm.raiseExceptionFmt(vm.argument_error_class, "X outside of the string", .{});
                    }
                    out.shrinkRetainingCapacity(out.items.len - count);
                }
            },
            '@' => {
                const count = token.count orelse 1;
                if (count > out.items.len) {
                    try appendZeros(vm, &out, count - out.items.len);
                } else {
                    out.shrinkRetainingCapacity(count);
                }
            },
            else => {
                return vm.raiseExceptionFmt(vm.argument_error_class, "{c} is not supported", .{token.directive});
            },
        }
    }

    return try vm.newStringWithEncoding(out.items, false, .{ .ascii_8bit = .{} });
}

pub fn stringUnpack(vm: *VM, bytes: []const u8, format: []const u8) VMError!Value {
    var tokens = try tokenize(vm, format);
    defer tokens.deinit(vm.allocator);

    const out = try vm.createArray();
    var index: usize = 0;

    for (tokens.items) |token| {
        if (token.err_msg) |msg| {
            return vm.raiseExceptionFmt(vm.argument_error_class, "{s}", .{msg});
        }

        switch (token.directive) {
            'A' => try unpackA(vm, out, bytes, &index, token),
            'a' => try unpacka(vm, out, bytes, &index, token),
            'Z' => try unpackZ(vm, out, bytes, &index, token),
            'c' => try unpackInteger(vm, out, bytes, &index, token, 1, true, .native),
            'C' => try unpackInteger(vm, out, bytes, &index, token, 1, false, .native),
            's' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_short) else 2, true, token.endianness),
            'S' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_ushort) else 2, false, token.endianness),
            'l' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_long) else 4, true, token.endianness),
            'L' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_ulong) else 4, false, token.endianness),
            'i' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_int) else 4, true, token.endianness),
            'I' => try unpackInteger(vm, out, bytes, &index, token, if (token.native_size) @sizeOf(c_uint) else 4, false, token.endianness),
            'j' => try unpackInteger(vm, out, bytes, &index, token, @sizeOf(isize), true, token.endianness),
            'J' => try unpackInteger(vm, out, bytes, &index, token, @sizeOf(usize), false, token.endianness),
            'q' => try unpackInteger(vm, out, bytes, &index, token, 8, true, token.endianness),
            'Q' => try unpackInteger(vm, out, bytes, &index, token, 8, false, token.endianness),
            'n' => try unpackInteger(vm, out, bytes, &index, token, 2, false, .big),
            'N' => try unpackInteger(vm, out, bytes, &index, token, 4, false, .big),
            'v' => try unpackInteger(vm, out, bytes, &index, token, 2, false, .little),
            'V' => try unpackInteger(vm, out, bytes, &index, token, 4, false, .little),
            'f', 'F' => try unpackFloat(vm, out, bytes, &index, token, 4, token.endianness),
            'd', 'D' => try unpackFloat(vm, out, bytes, &index, token, 8, token.endianness),
            'e' => try unpackFloat(vm, out, bytes, &index, token, 4, .little),
            'E' => try unpackFloat(vm, out, bytes, &index, token, 8, .little),
            'g' => try unpackFloat(vm, out, bytes, &index, token, 4, .big),
            'G' => try unpackFloat(vm, out, bytes, &index, token, 8, .big),
            'x' => {
                const count = token.count orelse 1;
                if (count > bytes.len -| index) {
                    return vm.raiseExceptionFmt(vm.argument_error_class, "x outside of string", .{});
                }
                index += count;
            },
            'X' => {
                const count = token.count orelse 1;
                if (count > index) {
                    return vm.raiseExceptionFmt(vm.argument_error_class, "X outside of string", .{});
                }
                index -= count;
            },
            '@' => {
                const count = token.count orelse 1;
                index = count;
            },
            else => {
                return vm.raiseExceptionFmt(vm.argument_error_class, "{c} is not supported", .{token.directive});
            },
        }
    }

    return Value.fromObject(out);
}

fn tokenize(vm: *VM, format: []const u8) VMError!std.ArrayList(DirectiveToken) {
    var list: std.ArrayList(DirectiveToken) = .empty;
    errdefer list.deinit(vm.allocator);

    var i: usize = 0;
    while (true) {
        skipSeparators(format, &i);
        if (i >= format.len) break;

        var token = DirectiveToken{ .directive = format[i] };
        i += 1;

        if (i < format.len and (format[i] == '>' or format[i] == '<')) {
            applyEndiannessModifier(&token, format[i]);
            i += 1;
        }

        if (i < format.len and (format[i] == '_' or format[i] == '!')) {
            applyNativeSizeModifier(&token, format[i]);
            i += 1;
        }

        if (i < format.len and (format[i] == '>' or format[i] == '<')) {
            applyEndiannessModifier(&token, format[i]);
            i += 1;
        }

        if (i < format.len and std.ascii.isDigit(format[i])) {
            var count: usize = 0;
            while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {
                count = count * 10 + (format[i] - '0');
            }
            token.count = count;
        }

        if (i < format.len and format[i] == '*') {
            token.star = true;
            i += 1;
        }

        list.append(vm.allocator, token) catch return error.Fatal;
        if (token.err_msg != null) break;
    }

    return list;
}

fn skipSeparators(format: []const u8, i: *usize) void {
    while (i.* < format.len) {
        const c = format[i.*];
        if (std.ascii.isWhitespace(c) or c == 0) {
            i.* += 1;
            continue;
        }
        if (c == '#') {
            while (i.* < format.len and format[i.*] != '\n') {
                i.* += 1;
            }
            if (i.* < format.len and format[i.*] == '\n') i.* += 1;
            continue;
        }
        break;
    }
}

fn applyEndiannessModifier(token: *DirectiveToken, modifier: u8) void {
    if (!allowsIntModifiers(token.directive)) {
        token.err_msg = if (modifier == '>')
            "'>' allowed only after types sSiIlLqQjJ"
        else
            "'<' allowed only after types sSiIlLqQjJ";
        return;
    }
    token.endianness = if (modifier == '>') .big else .little;
}

fn applyNativeSizeModifier(token: *DirectiveToken, modifier: u8) void {
    _ = modifier;
    if (!allowsIntModifiers(token.directive)) {
        token.err_msg = "'_' and '!' allowed only after types sSiIlLqQjJ";
        return;
    }
    token.native_size = true;
}

fn allowsIntModifiers(directive: u8) bool {
    return switch (directive) {
        's', 'S', 'i', 'I', 'l', 'L', 'q', 'Q', 'j', 'J' => true,
        else => false,
    };
}

fn packIntegerDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
    byte_size: usize,
    signed: bool,
    fixed_endianness: Endianness,
) VMError!void {
    _ = signed;
    const count = if (token.star) items.len - arg_index.* else token.count orelse 1;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (arg_index.* >= items.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        }
        const int_val = try coerceToInt(vm, items[arg_index.*]);
        arg_index.* += 1;

        var raw: [8]u8 = [_]u8{0} ** 8;
        const bits: u64 = @bitCast(int_val);
        std.mem.writeInt(u64, &raw, bits, .little);

        const endian = if (fixed_endianness == .native) nativeOr(token.endianness) else fixed_endianness;
        if (byte_size > raw.len) return error.Fatal;

        const start = if (endian == .big) byte_size else 0;
        if (endian == .big) {
            var j: usize = 0;
            while (j < byte_size) : (j += 1) {
                out.append(vm.allocator, raw[byte_size - 1 - j]) catch return error.Fatal;
            }
        } else {
            _ = start;
            out.appendSlice(vm.allocator, raw[0..byte_size]) catch return error.Fatal;
        }
    }
}

fn packFloatDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
    byte_size: usize,
    fixed_endianness: Endianness,
) VMError!void {
    const count = if (token.star) items.len - arg_index.* else token.count orelse 1;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (arg_index.* >= items.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        }
        const f = try coerceToFloat(vm, items[arg_index.*]);
        arg_index.* += 1;

        var tmp: [8]u8 = [_]u8{0} ** 8;
        if (byte_size == 4) {
            const f32_val: f32 = @floatCast(f);
            const bits: u32 = @bitCast(f32_val);
            std.mem.writeInt(u32, tmp[0..4], bits, .little);
        } else {
            const bits: u64 = @bitCast(f);
            std.mem.writeInt(u64, &tmp, bits, .little);
        }

        const endian = if (fixed_endianness == .native) nativeOr(token.endianness) else fixed_endianness;
        if (endian == .big) {
            var j: usize = 0;
            while (j < byte_size) : (j += 1) {
                out.append(vm.allocator, tmp[byte_size - 1 - j]) catch return error.Fatal;
            }
        } else {
            out.appendSlice(vm.allocator, tmp[0..byte_size]) catch return error.Fatal;
        }
    }
}

fn packStringDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
) VMError!void {
    if (arg_index.* >= items.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
    }

    const arg = items[arg_index.*];
    arg_index.* += 1;

    const str: []const u8 = if (arg.isNil())
        ""
    else
        try arg.coerceToStr(vm, "no implicit conversion into String");

    switch (token.directive) {
        'a' => {
            if (token.star) {
                out.appendSlice(vm.allocator, str) catch return error.Fatal;
                return;
            }
            const width = token.count orelse 1;
            const used = @min(width, str.len);
            out.appendSlice(vm.allocator, str[0..used]) catch return error.Fatal;
            try appendZeros(vm, out, width - used);
        },
        'A' => {
            if (token.star) {
                out.appendSlice(vm.allocator, str) catch return error.Fatal;
                return;
            }
            const width = token.count orelse 1;
            const used = @min(width, str.len);
            out.appendSlice(vm.allocator, str[0..used]) catch return error.Fatal;
            var i: usize = used;
            while (i < width) : (i += 1) {
                out.append(vm.allocator, ' ') catch return error.Fatal;
            }
        },
        'Z' => {
            if (token.star) {
                out.appendSlice(vm.allocator, str) catch return error.Fatal;
                out.append(vm.allocator, 0) catch return error.Fatal;
                return;
            }
            const width = token.count orelse 1;
            if (width == 0) return;
            const used = @min(width - 1, str.len);
            out.appendSlice(vm.allocator, str[0..used]) catch return error.Fatal;
            out.append(vm.allocator, 0) catch return error.Fatal;
            try appendZeros(vm, out, width - used - 1);
        },
        else => unreachable,
    }
}

fn unpackInteger(
    vm: *VM,
    out: *value.ArrayObject,
    bytes: []const u8,
    index: *usize,
    token: DirectiveToken,
    byte_size: usize,
    signed: bool,
    fixed_endianness: Endianness,
) VMError!void {
    const count = if (token.star)
        (bytes.len -| index.*) / byte_size
    else
        token.count orelse 1;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (index.* + byte_size > bytes.len) {
            out.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            continue;
        }

        const endian = if (fixed_endianness == .native) nativeOr(token.endianness) else fixed_endianness;
        const slice = bytes[index.* .. index.* + byte_size];
        index.* += byte_size;
        const val = decodeInteger(slice, signed, endian);
        out.elements.append(vm.gc_allocator, Value.integer(val)) catch return error.Fatal;
    }
}

fn unpackFloat(
    vm: *VM,
    out: *value.ArrayObject,
    bytes: []const u8,
    index: *usize,
    token: DirectiveToken,
    byte_size: usize,
    fixed_endianness: Endianness,
) VMError!void {
    const count = if (token.star)
        (bytes.len -| index.*) / byte_size
    else
        token.count orelse 1;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (index.* + byte_size > bytes.len) {
            out.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            continue;
        }

        const endian = if (fixed_endianness == .native) nativeOr(token.endianness) else fixed_endianness;
        const slice = bytes[index.* .. index.* + byte_size];
        index.* += byte_size;

        var tmp: [8]u8 = [_]u8{0} ** 8;
        if (endian == .big) {
            var j: usize = 0;
            while (j < byte_size) : (j += 1) {
                tmp[j] = slice[byte_size - 1 - j];
            }
        } else {
            @memcpy(tmp[0..byte_size], slice);
        }

        if (byte_size == 4) {
            const bits = std.mem.readInt(u32, tmp[0..4], .little);
            const f: f32 = @bitCast(bits);
            out.elements.append(vm.gc_allocator, try vm.newFloat(@floatCast(f))) catch return error.Fatal;
        } else {
            const bits = std.mem.readInt(u64, &tmp, .little);
            const f: f64 = @bitCast(bits);
            out.elements.append(vm.gc_allocator, try vm.newFloat(f)) catch return error.Fatal;
        }
    }
}

fn unpackA(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const width = if (token.star) bytes.len -| index.* else token.count orelse 1;
    const start = @min(index.*, bytes.len);
    const end = @min(start + width, bytes.len);
    index.* = start + width;

    var trimmed_end = end;
    while (trimmed_end > start and (bytes[trimmed_end - 1] == ' ' or bytes[trimmed_end - 1] == 0)) {
        trimmed_end -= 1;
    }

    const str = try vm.newStringWithEncoding(bytes[start..trimmed_end], false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn unpacka(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const width = if (token.star) bytes.len -| index.* else token.count orelse 1;
    const start = @min(index.*, bytes.len);
    const end = @min(start + width, bytes.len);
    index.* = start + width;

    const str = try vm.newStringWithEncoding(bytes[start..end], false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn unpackZ(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const start = @min(index.*, bytes.len);
    const width = if (token.star)
        bytes.len - start
    else if (token.count) |count|
        count
    else
        bytes.len - start;

    const end = @min(start + width, bytes.len);
    var nul_pos = end;
    var i = start;
    while (i < end) : (i += 1) {
        if (bytes[i] == 0) {
            nul_pos = i;
            break;
        }
    }

    index.* = start + width;
    const str = try vm.newStringWithEncoding(bytes[start..nul_pos], false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn decodeInteger(slice: []const u8, signed: bool, endian: Endianness) i64 {
    var buf: [8]u8 = [_]u8{0} ** 8;

    if (endian == .big) {
        var j: usize = 0;
        while (j < slice.len) : (j += 1) {
            buf[j] = slice[slice.len - 1 - j];
        }
    } else {
        @memcpy(buf[0..slice.len], slice);
    }

    const raw = std.mem.readInt(u64, &buf, .little);
    if (!signed) {
        if (raw > std.math.maxInt(i64)) {
            return @bitCast(raw);
        }
        return @intCast(raw);
    }

    const bits = slice.len * 8;
    if (bits == 0) return 0;
    if (bits >= 64) return @bitCast(raw);

    const sign_bit: u64 = @as(u64, 1) << @intCast(bits - 1);
    if ((raw & sign_bit) == 0) return @intCast(raw);

    const mask: u64 = ~(@as(u64, 0)) << @intCast(bits);
    return @bitCast(raw | mask);
}

fn appendZeros(vm: *VM, out: *std.ArrayList(u8), count: usize) VMError!void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        out.append(vm.allocator, 0) catch return error.Fatal;
    }
}

fn coerceToInt(vm: *VM, arg: Value) VMError!i64 {
    if (arg.isInteger()) return arg.toInteger();

    const to_int_sym = try vm.intern("to_int");
    const has_to_int = (try vm.findMethod(arg, to_int_sym)) != null;
    if (!has_to_int) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const coerced = try vm.callMethodByName(arg, "to_int", &[_]Value{}, null);
    if (!coerced.isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert to Integer (to_int gives non-Integer)", .{});
    }

    return coerced.toInteger();
}

fn coerceToFloat(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isFloat()) return arg.toFloatObject().val;
    if (arg.isInteger()) return @floatFromInt(arg.toInteger());

    const to_f_sym = try vm.intern("to_f");
    const has_to_f = (try vm.findMethod(arg, to_f_sym)) != null;
    if (!has_to_f) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Float", .{});
    }
    const coerced = try vm.callMethodByName(arg, "to_f", &[_]Value{}, null);
    if (coerced.isFloat()) return coerced.toFloatObject().val;
    if (coerced.isInteger()) return @floatFromInt(coerced.toInteger());
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert to Float (to_f gives non-Float)", .{});
}

fn nativeOr(endianness: Endianness) Endianness {
    if (endianness != .native) return endianness;
    return if (nativeEndian() == .little) .little else .big;
}

fn nativeEndian() std.builtin.Endian {
    return @import("builtin").target.cpu.arch.endian();
}
