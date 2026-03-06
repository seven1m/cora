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
            'B' => try unpackBitString(vm, out, bytes, &index, token, true),
            'b' => try unpackBitString(vm, out, bytes, &index, token, false),
            'M' => try unpackQuotedPrintable(vm, out, bytes, &index),
            'm' => try unpackBase64(vm, out, bytes, &index, token),
            'U' => try unpackUnicodeCodepoints(vm, out, bytes, &index, token),
            'u' => try unpackUu(vm, out, bytes, &index),
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
                return raiseUnknownUnpackDirective(vm, token.directive, format);
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
        if (std.ascii.isWhitespace(c)) {
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

fn unpackBitString(
    vm: *VM,
    out: *value.ArrayObject,
    bytes: []const u8,
    index: *usize,
    token: DirectiveToken,
    msb_first: bool,
) VMError!void {
    const start = @min(index.*, bytes.len);
    const bits_requested: usize = if (token.star)
        (bytes.len - start) * 8
    else
        token.count orelse 1;
    const bytes_to_consume = if (token.star)
        bytes.len - start
    else
        (bits_requested + 7) / 8;
    const available_bytes = @min(bytes_to_consume, bytes.len - start);
    const available_bits = @min(bits_requested, available_bytes * 8);

    var out_bits: std.ArrayList(u8) = .empty;
    defer out_bits.deinit(vm.allocator);
    out_bits.ensureTotalCapacity(vm.allocator, available_bits) catch return error.Fatal;

    var bit_i: usize = 0;
    while (bit_i < available_bits) : (bit_i += 1) {
        const byte_off = bit_i / 8;
        const bit_off = bit_i % 8;
        const b = bytes[start + byte_off];
        const bit = if (msb_first)
            (b >> @intCast(7 - bit_off)) & 1
        else
            (b >> @intCast(bit_off)) & 1;
        out_bits.appendAssumeCapacity(if (bit == 0) '0' else '1');
    }

    index.* = start + bytes_to_consume;
    const str = try vm.newStringWithEncoding(out_bits.items, false, .{ .us_ascii = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn unpackQuotedPrintable(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize) VMError!void {
    const start = @min(index.*, bytes.len);
    index.* = bytes.len;

    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(vm.allocator);

    var i: usize = start;
    while (i < bytes.len) {
        const b = bytes[i];
        if (b != '=') {
            decoded.append(vm.allocator, b) catch return error.Fatal;
            i += 1;
            continue;
        }

        if (i + 1 >= bytes.len) {
            decoded.append(vm.allocator, '=') catch return error.Fatal;
            i += 1;
            continue;
        }

        if (bytes[i + 1] == '\n') {
            i += 2;
            continue;
        }
        if (i + 2 < bytes.len and bytes[i + 1] == '\r' and bytes[i + 2] == '\n') {
            i += 3;
            continue;
        }

        if (i + 2 < bytes.len and isHexDigit(bytes[i + 1]) and isHexDigit(bytes[i + 2])) {
            const hi = hexNibble(bytes[i + 1]).?;
            const lo = hexNibble(bytes[i + 2]).?;
            decoded.append(vm.allocator, (hi << 4) | lo) catch return error.Fatal;
            i += 3;
            continue;
        }

        decoded.append(vm.allocator, '=') catch return error.Fatal;
        i += 1;
    }

    const str = try vm.newStringWithEncoding(decoded.items, false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn unpackUnicodeCodepoints(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const count = if (token.star) std.math.maxInt(usize) else token.count orelse 1;
    var i: usize = 0;
    while (i < count and index.* < bytes.len) : (i += 1) {
        const parsed = (@as(enc.Encoding, .{ .utf8 = .{} })).nextCodepoint(bytes, index);
        if (parsed.len == 0) break;
        if (!parsed.valid) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "malformed UTF-8 character", .{});
        }
        out.elements.append(vm.gc_allocator, Value.integer(@intCast(parsed.codepoint))) catch return error.Fatal;
    }
}

fn unpackUu(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize) VMError!void {
    const start = @min(index.*, bytes.len);
    index.* = bytes.len;

    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(vm.allocator);

    var line_start = start;
    while (line_start < bytes.len) {
        var line_end = line_start;
        while (line_end < bytes.len and bytes[line_end] != '\n') : (line_end += 1) {}

        var logical_end = line_end;
        if (logical_end > line_start and bytes[logical_end - 1] == '\r') {
            logical_end -= 1;
        }
        if (logical_end == line_start) {
            line_start = if (line_end < bytes.len) line_end + 1 else bytes.len;
            continue;
        }

        const len_char = bytes[line_start];
        var expected_bytes: usize = (len_char -% 32) & 0x3F;
        if (expected_bytes > 0) {
            var pos = line_start + 1;
            while (expected_bytes > 0 and pos < logical_end) {
                const a = uuSixBit(bytes[pos]);
                const b = if (pos + 1 < logical_end) uuSixBit(bytes[pos + 1]) else 0;
                const c = if (pos + 2 < logical_end) uuSixBit(bytes[pos + 2]) else 0;
                const d = if (pos + 3 < logical_end) uuSixBit(bytes[pos + 3]) else 0;
                pos += 4;

                const o1: u8 = (a << 2) | (b >> 4);
                decoded.append(vm.allocator, o1) catch return error.Fatal;
                expected_bytes -= 1;
                if (expected_bytes == 0) break;

                const o2: u8 = ((b & 0x0F) << 4) | (c >> 2);
                decoded.append(vm.allocator, o2) catch return error.Fatal;
                expected_bytes -= 1;
                if (expected_bytes == 0) break;

                const o3: u8 = ((c & 0x03) << 6) | d;
                decoded.append(vm.allocator, o3) catch return error.Fatal;
                expected_bytes -= 1;
            }
        }

        line_start = if (line_end < bytes.len) line_end + 1 else bytes.len;
    }

    const str = try vm.newStringWithEncoding(decoded.items, false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn uuSixBit(c: u8) u8 {
    return (c -% 32) & 0x3F;
}

fn unpackBase64(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const start = @min(index.*, bytes.len);
    index.* = bytes.len;
    const strict = token.count != null and token.count.? == 0 and !token.star;
    const decoded = try decodeBase64(vm, bytes[start..], strict);
    defer vm.allocator.free(decoded);

    const str = try vm.newStringWithEncoding(decoded, false, .{ .ascii_8bit = .{} });
    out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
}

fn decodeBase64(vm: *VM, bytes: []const u8, strict: bool) VMError![]u8 {
    var filtered: std.ArrayList(u8) = .empty;
    defer filtered.deinit(vm.allocator);

    for (bytes) |b| {
        if (isBase64Byte(b) or b == '=') {
            filtered.append(vm.allocator, b) catch return error.Fatal;
            continue;
        }
        if (std.ascii.isWhitespace(b)) continue;
        if (strict) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
        }
    }

    if (filtered.items.len == 0) {
        return vm.allocator.alloc(u8, 0) catch return error.Fatal;
    }

    if (!strict) {
        const rem = filtered.items.len % 4;
        if (rem == 1) {
            filtered.items.len -= 1;
        } else if (rem > 1) {
            var pad: usize = 0;
            while (pad < 4 - rem) : (pad += 1) {
                filtered.append(vm.allocator, '=') catch return error.Fatal;
            }
        }
    } else if (filtered.items.len % 4 != 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    }

    const decoder = std.base64.standard.Decoder;
    const decoded_len = decoder.calcSizeForSlice(filtered.items) catch {
        if (!strict) {
            return vm.allocator.alloc(u8, 0) catch return error.Fatal;
        }
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    };
    const out = vm.allocator.alloc(u8, decoded_len) catch return error.Fatal;
    _ = decoder.decode(out, filtered.items) catch {
        vm.allocator.free(out);
        if (!strict) {
            return vm.allocator.alloc(u8, 0) catch return error.Fatal;
        }
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    };
    return out;
}

fn isBase64Byte(b: u8) bool {
    return (b >= 'A' and b <= 'Z') or
        (b >= 'a' and b <= 'z') or
        (b >= '0' and b <= '9') or
        b == '+' or b == '/';
}

fn isHexDigit(b: u8) bool {
    return (b >= '0' and b <= '9') or
        (b >= 'a' and b <= 'f') or
        (b >= 'A' and b <= 'F');
}

fn hexNibble(b: u8) ?u8 {
    return if (b >= '0' and b <= '9')
        b - '0'
    else if (b >= 'a' and b <= 'f')
        b - 'a' + 10
    else if (b >= 'A' and b <= 'F')
        b - 'A' + 10
    else
        null;
}

fn raiseUnknownUnpackDirective(vm: *VM, directive: u8, format: []const u8) VMError!Value {
    return vm.raiseExceptionFmt(
        vm.argument_error_class,
        "unknown unpack directive '{c}' in '{s}'",
        .{ directive, format },
    );
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
    return arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "integer too large",
    );
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
