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
    alignment: ?usize = null,
    endianness: Endianness = .native,
    err_msg: ?[]const u8 = null,
};

const PackedPointerEntry = struct {
    offset: usize,
    target: *value.StringObject,
};

pub fn arrayPack(vm: *VM, items: []Value, format: []const u8, buffer: ?Value) VMError!Value {
    var tokens = try tokenize(vm, format);
    defer tokens.deinit(vm.allocator);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    const output_buffer = if (buffer) |provided| (if (provided.isNil()) null else provided) else null;
    if (output_buffer) |provided| {
        out.appendSlice(vm.allocator, provided.toStringObject().str) catch return error.Fatal;
    }
    // Coercion callbacks may collect before the output string owns its targets.
    // Keep this temporary pointer storage visible to the GC.
    var packed_pointer_entries: std.ArrayList(PackedPointerEntry) = .empty;

    var arg_index: usize = 0;
    for (tokens.items) |token| {
        if (token.err_msg) |msg| {
            return vm.raiseExceptionFmt(vm.argument_error_class, "{s}", .{msg});
        }

        if (token.alignment) |alignment| {
            const remainder = out.items.len % alignment;
            if (remainder != 0) try appendZeros(vm, &out, alignment - remainder);
            continue;
        }

        switch (token.directive) {
            'A', 'a', 'Z' => try packStringDirective(vm, items, &arg_index, token, &out),
            'B', 'b' => try packBitDirective(vm, items, &arg_index, token, &out),
            'H' => try packHexDirective(vm, items, &arg_index, token, &out, true),
            'h' => try packHexDirective(vm, items, &arg_index, token, &out, false),
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
            'm', 'u' => try packEncodedTextDirective(vm, items, &arg_index, token, &out),
            'M' => try packQuotedPrintableDirective(vm, items, &arg_index, token, &out),
            'U' => try packUnicodeDirective(vm, items, &arg_index, token, &out),
            'w', 'R', 'r' => try packVariableIntegerDirective(vm, items, &arg_index, token, &out),
            'p', 'P' => try packPointerDirective(vm, items, &arg_index, token, &out, &packed_pointer_entries),
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
                return vm.raiseExceptionFmt(
                    vm.argument_error_class,
                    "unknown pack directive '{c}' in '{s}'",
                    .{ token.directive, format },
                );
            },
        }
    }

    var output_encoding: enc.Encoding = .{ .us_ascii = .{} };
    for (tokens.items) |token| {
        switch (token.directive) {
            'U' => if (output_encoding == .us_ascii) {
                output_encoding = .{ .utf8 = .{} };
            },
            'm', 'M', 'u' => {},
            else => output_encoding = .{ .ascii_8bit = .{} },
        }
    }
    const packed_value = if (output_buffer) |provided| blk: {
        const bytes = vm.gc_allocator_atomic.dupeSentinel(u8, out.items, 0) catch return error.Fatal;
        const string = provided.toStringObject();
        string.replaceBytes(bytes);
        string.capacity = out.items.len;
        string.validity = .unknown;
        break :blk provided;
    } else try vm.newStringWithEncoding(out.items, false, output_encoding);
    const packed_obj = packed_value.toStringObject();
    for (packed_pointer_entries.items) |entry| {
        try vm.registerPackedPointerTarget(packed_obj, entry.offset, entry.target);
    }
    return packed_value;
}

fn packVariableIntegerDirective(vm: *VM, items: []Value, arg_index: *usize, token: DirectiveToken, out: *std.ArrayList(u8)) VMError!void {
    const count = if (token.star) items.len - arg_index.* else token.count orelse 1;
    for (0..count) |_| {
        if (arg_index.* >= items.len) return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        const integer = try items[arg_index.*].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer (to_int gives non-Integer)");
        arg_index.* += 1;
        var number = try integer.integerToManaged(vm);
        defer number.deinit();
        if (token.directive != 'r' and !number.isPositive()) return vm.raiseExceptionFmt(vm.argument_error_class, "can't compress negative numbers", .{});
        const bit_count = number.toConst().bitCountTwosCompForSignedness(if (token.directive == 'r') .signed else .unsigned);
        const groups = @max(1, (bit_count + 6) / 7);
        const raw = vm.allocator.alloc(u8, (groups * 7 + 7) / 8) catch return error.Fatal;
        defer vm.allocator.free(raw);
        number.toConst().writeTwosComplement(raw, .little);
        for (0..groups) |i| {
            const offset = (if (token.directive == 'w') groups - 1 - i else i) * 7;
            const byte_index = offset / 8;
            const word = @as(u16, raw[byte_index]) | (if (byte_index + 1 < raw.len) @as(u16, raw[byte_index + 1]) << 8 else 0);
            var payload: u8 = @intCast((word >> @as(u4, @intCast(offset % 8))) & 0x7f);
            if (i + 1 < groups) payload |= 0x80;
            out.append(vm.allocator, payload) catch return error.Fatal;
        }
    }
}

fn packUnicodeDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
) VMError!void {
    const count = if (token.star) items.len - arg_index.* else token.count orelse 1;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (arg_index.* >= items.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        }
        const number = try coerceToInt(vm, items[arg_index.*]);
        arg_index.* += 1;
        if (number < 0 or number > 0x7fff_ffff) {
            return vm.raiseExceptionFmt(vm.range_error_class, "pack(U): value out of range", .{});
        }

        var codepoint: u32 = @intCast(number);
        const length: usize = if (codepoint <= 0x7f) 1 else if (codepoint <= 0x7ff) 2 else if (codepoint <= 0xffff) 3 else if (codepoint <= 0x1f_ffff) 4 else if (codepoint <= 0x3ff_ffff) 5 else 6;
        var encoded: [6]u8 = undefined;
        var position = length;
        while (position > 1) {
            position -= 1;
            encoded[position] = @as(u8, @truncate(codepoint & 0x3f)) | 0x80;
            codepoint >>= 6;
        }
        const prefixes = [_]u8{ 0, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc };
        encoded[0] = prefixes[length - 1] | @as(u8, @truncate(codepoint));
        out.appendSlice(vm.allocator, encoded[0..length]) catch return error.Fatal;
    }
}

fn packEncodedTextDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
) VMError!void {
    if (arg_index.* >= items.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
    }

    const bytes = try items[arg_index.*].coerceToStr(vm, "no implicit conversion into String");
    arg_index.* += 1;
    if (bytes.len == 0) return;

    const count = token.count orelse 1;
    if (token.directive == 'm' and !token.star and count == 0) {
        const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
        const encoded = vm.allocator.alloc(u8, encoded_len) catch return error.Fatal;
        defer vm.allocator.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, bytes);
        out.appendSlice(vm.allocator, encoded) catch return error.Fatal;
        return;
    }

    const requested_width = if (token.star or count < 3) 45 else (count / 3) * 3;
    const bytes_per_line = if (token.directive == 'u') @min(63, requested_width) else requested_width;
    var offset: usize = 0;
    while (offset < bytes.len) {
        const end = @min(offset + bytes_per_line, bytes.len);
        const chunk = bytes[offset..end];
        if (token.directive == 'u') {
            out.append(vm.allocator, @as(u8, @intCast(chunk.len)) + 32) catch return error.Fatal;
            var i: usize = 0;
            while (i < chunk.len) : (i += 3) {
                const a = chunk[i];
                const b = if (i + 1 < chunk.len) chunk[i + 1] else 0;
                const c = if (i + 2 < chunk.len) chunk[i + 2] else 0;
                const encoded = [_]u8{
                    uuCharacter(a >> 2),
                    uuCharacter(((a & 3) << 4) | (b >> 4)),
                    uuCharacter(((b & 15) << 2) | (c >> 6)),
                    uuCharacter(c & 63),
                };
                out.appendSlice(vm.allocator, &encoded) catch return error.Fatal;
            }
        } else {
            const encoded_len = std.base64.standard.Encoder.calcSize(chunk.len);
            const encoded = vm.allocator.alloc(u8, encoded_len) catch return error.Fatal;
            defer vm.allocator.free(encoded);
            _ = std.base64.standard.Encoder.encode(encoded, chunk);
            out.appendSlice(vm.allocator, encoded) catch return error.Fatal;
        }
        out.append(vm.allocator, '\n') catch return error.Fatal;
        offset = end;
    }
}

fn packQuotedPrintableDirective(vm: *VM, items: []Value, arg_index: *usize, token: DirectiveToken, out: *std.ArrayList(u8)) VMError!void {
    if (arg_index.* >= items.len) return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
    const str = try vm.objectAsString(items[arg_index.*]);
    arg_index.* += 1;
    const bytes = str.toStringObject().str;
    const requested = if (token.star) 72 else token.count orelse 72;
    const width = if (requested < 2) 72 else requested;
    var column: usize = 0;
    for (bytes, 0..) |byte, i| {
        if (byte == '\n') {
            if (column != 0 and i > 0 and (bytes[i - 1] == ' ' or bytes[i - 1] == '\t')) {
                out.appendSlice(vm.allocator, "=\n") catch return error.Fatal;
            }
            out.append(vm.allocator, '\n') catch return error.Fatal;
            column = 0;
            continue;
        }
        if (byte == '\t' or byte == ' ' or (byte >= 33 and byte <= 126 and byte != '=')) {
            out.append(vm.allocator, byte) catch return error.Fatal;
            column += 1;
        } else {
            const hex = "0123456789ABCDEF";
            const escaped = [_]u8{ '=', hex[byte >> 4], hex[byte & 15] };
            out.appendSlice(vm.allocator, &escaped) catch return error.Fatal;
            column += 3;
        }
        if (column > width) {
            out.appendSlice(vm.allocator, "=\n") catch return error.Fatal;
            column = 0;
        }
    }
    if (column != 0) out.appendSlice(vm.allocator, "=\n") catch return error.Fatal;
}

fn uuCharacter(bits: u8) u8 {
    return if (bits == 0) '`' else bits + 32;
}

pub fn stringUnpack(vm: *VM, source: *value.StringObject, base_offset: usize, format: []const u8) VMError!Value {
    var tokens = try tokenize(vm, format);
    defer tokens.deinit(vm.allocator);

    const out = try vm.createArray();
    const bytes = source.str[base_offset..];
    var index: usize = 0;

    for (tokens.items) |token| {
        if (token.err_msg) |msg| {
            return vm.raiseExceptionFmt(vm.argument_error_class, "{s}", .{msg});
        }

        if (token.alignment) |alignment| {
            const position = if (token.directive == '@') base_offset + index else index;
            const remainder = position % alignment;
            const padding = if (remainder == 0) 0 else alignment - remainder;
            if (padding > bytes.len -| index) {
                return vm.raiseExceptionFmt(vm.argument_error_class, "{c} outside of string", .{token.directive});
            }
            index += padding;
            continue;
        }

        switch (token.directive) {
            'A' => try unpackA(vm, out, bytes, &index, token),
            'a' => try unpacka(vm, out, bytes, &index, token),
            'Z' => try unpackZ(vm, out, bytes, &index, token),
            'B' => try unpackBitString(vm, out, bytes, &index, token, true),
            'b' => try unpackBitString(vm, out, bytes, &index, token, false),
            'H' => try unpackHexString(vm, out, bytes, &index, token, true),
            'h' => try unpackHexString(vm, out, bytes, &index, token, false),
            'M' => try unpackQuotedPrintable(vm, out, bytes, &index),
            'm' => try unpackBase64(vm, out, bytes, &index, token),
            'w', 'R', 'r' => try unpackVariableInteger(vm, out, bytes, &index, token),
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
            'P' => try unpackPointer(vm, out, source, base_offset, bytes, &index, token, true),
            'p' => try unpackPointer(vm, out, source, base_offset, bytes, &index, token, false),
            'x' => {
                if (token.star) {
                    index = bytes.len;
                } else {
                    const count = token.count orelse 1;
                    if (count > bytes.len -| index) {
                        return vm.raiseExceptionFmt(vm.argument_error_class, "x outside of string", .{});
                    }
                    index += count;
                }
            },
            'X' => {
                const count = if (token.star) bytes.len -| index else token.count orelse 1;
                if (count > index) {
                    return vm.raiseExceptionFmt(vm.argument_error_class, "X outside of string", .{});
                }
                index -= count;
            },
            '@' => {
                if (!token.star) {
                    const count = token.count orelse 0;
                    if (count > bytes.len) {
                        return vm.raiseExceptionFmt(vm.argument_error_class, "@ outside of string", .{});
                    }
                    index = count;
                }
            },
            else => {
                return raiseUnknownUnpackDirective(vm, token.directive, format);
            },
        }
    }

    return Value.fromObject(&out.object);
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

        if ((token.directive == 'x' or token.directive == '@') and i < format.len and format[i] == '!') {
            i += 1;
            if (i == format.len) return vm.raiseExceptionFmt(vm.argument_error_class, "missing alignment", .{});
            var alignment: usize = 0;
            if (std.ascii.isDigit(format[i])) {
                while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {
                    alignment = std.math.mul(usize, alignment, 10) catch return vm.raiseExceptionFmt(vm.range_error_class, "invalid alignment", .{});
                    alignment = std.math.add(usize, alignment, format[i] - '0') catch return vm.raiseExceptionFmt(vm.range_error_class, "invalid alignment", .{});
                }
                if (alignment == 0 or alignment > std.math.maxInt(isize)) return vm.raiseExceptionFmt(vm.range_error_class, "invalid alignment", .{});
            } else {
                const directive = format[i];
                i += 1;
                const native = i < format.len and (format[i] == '!' or format[i] == '_');
                if (native) {
                    if (!allowsIntModifiers(directive)) return vm.raiseExceptionFmt(vm.argument_error_class, "'_' and '!' allowed only after types sSiIlLqQjJ", .{});
                    i += 1;
                }
                if (i < format.len and (format[i] == '<' or format[i] == '>')) return vm.raiseExceptionFmt(vm.argument_error_class, "endian modifier is not allowed for alignment", .{});
                alignment = switch (directive) {
                    'c', 'C' => 1,
                    's', 'S' => if (native) @alignOf(c_short) else 2,
                    'i', 'I' => @alignOf(c_int),
                    'l', 'L' => if (native) @alignOf(c_long) else 4,
                    'q', 'Q' => @alignOf(i64),
                    'j', 'J' => @alignOf(usize),
                    'n', 'v' => @alignOf(u16),
                    'N', 'V' => @alignOf(u32),
                    'f', 'F', 'e', 'g' => @alignOf(f32),
                    'd', 'D', 'E', 'G' => @alignOf(f64),
                    'p', 'P' => @alignOf(usize),
                    else => return vm.raiseExceptionFmt(vm.argument_error_class, "unknown alignment directive '{c}'", .{directive}),
                };
            }
            token.alignment = alignment;
            list.append(vm.allocator, token) catch return error.Fatal;
            continue;
        }

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
        const int_val = try items[arg_index.*].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer (to_int gives non-Integer)");
        arg_index.* += 1;

        var raw: [8]u8 = @splat(0);
        const bits: u64 = if (int_val.isInteger()) @bitCast(int_val.toInteger()) else blk: {
            var truncated = std.math.big.int.Managed.init(vm.allocator) catch return error.Fatal;
            defer truncated.deinit();
            truncated.truncate(&int_val.toBigIntegerObject().value, .unsigned, 64) catch return error.Fatal;
            break :blk truncated.toInt(u64) catch return error.Fatal;
        };
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

        var tmp: [8]u8 = @splat(0);
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
            const used = @min(width, str.len);
            out.appendSlice(vm.allocator, str[0..used]) catch return error.Fatal;
            try appendZeros(vm, out, width - used);
        },
        else => unreachable,
    }
}

fn packBitDirective(vm: *VM, items: []Value, arg_index: *usize, token: DirectiveToken, out: *std.ArrayList(u8)) VMError!void {
    if (arg_index.* >= items.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
    }
    const arg = items[arg_index.*];
    arg_index.* += 1;
    const bytes = if (arg.isNil()) "" else try arg.coerceToStr(vm, "no implicit conversion into String");
    const count = if (token.star) bytes.len else token.count orelse 1;
    const used = @min(count, bytes.len);
    var i: usize = 0;
    while (i < used) : (i += 8) {
        var byte: u8 = 0;
        for (0..@min(8, used - i)) |bit| {
            const shift: u3 = @intCast(if (token.directive == 'B') 7 - bit else bit);
            byte |= (bytes[i + bit] & 1) << shift;
        }
        out.append(vm.allocator, byte) catch return error.Fatal;
    }
    // Ruby pads by one byte for each pair of missing input characters.
    const missing = count - used;
    try appendZeros(vm, out, missing / 2 + missing % 2);
}

fn packHexDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
    high_nibble_first: bool,
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
    const nibble_count = if (token.star) str.len else token.count orelse 1;

    var nibble_index: usize = 0;
    while (nibble_index < nibble_count) : (nibble_index += 2) {
        const first = if (nibble_index < str.len) packHexNibble(str[nibble_index]) else 0;
        const second_index = nibble_index + 1;
        const second = if (second_index < nibble_count and second_index < str.len)
            packHexNibble(str[second_index])
        else
            0;
        const byte_value = if (high_nibble_first)
            (first << 4) | second
        else
            first | (second << 4);
        out.append(vm.allocator, byte_value) catch return error.Fatal;
    }
}

fn packHexNibble(byte: u8) u8 {
    // Unlike unpacking, packing accepts every byte, using its low nibble.
    return if (std.ascii.isAlphabetic(byte)) ((byte & 0x0f) + 9) & 0x0f else byte & 0x0f;
}

fn packPointerDirective(
    vm: *VM,
    items: []Value,
    arg_index: *usize,
    token: DirectiveToken,
    out: *std.ArrayList(u8),
    packed_pointer_entries: *std.ArrayList(PackedPointerEntry),
) VMError!void {
    const pointer_size = @sizeOf(usize);
    const pointer_count = if (token.directive == 'P')
        1
    else if (token.star)
        items.len - arg_index.*
    else
        token.count orelse 1;

    var i: usize = 0;
    while (i < pointer_count) : (i += 1) {
        if (arg_index.* >= items.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "too few arguments", .{});
        }
        const arg = items[arg_index.*];
        arg_index.* += 1;

        var ptr_value: usize = 0;
        if (!arg.isNil()) {
            const str_value = try arg.coerceToStringValue(vm, "no implicit conversion into String");
            const str_obj = str_value.toStringObject();
            const str_bytes = str_obj.str;
            if (token.directive == 'P') {
                const min_len = token.count orelse 1;
                if (str_bytes.len < min_len) {
                    return vm.raiseExceptionFmt(
                        vm.argument_error_class,
                        "too short buffer for P({d} for {d})",
                        .{ str_bytes.len, min_len },
                    );
                }
            }

            ptr_value = @intFromPtr(str_obj.str.ptr);
            packed_pointer_entries.append(vm.gc_allocator, .{
                .offset = out.items.len,
                .target = str_obj,
            }) catch return error.Fatal;
        }

        var ptr_buf: [@sizeOf(usize)]u8 = undefined;
        std.mem.writeInt(usize, &ptr_buf, ptr_value, nativeEndian());
        out.appendSlice(vm.allocator, ptr_buf[0..pointer_size]) catch return error.Fatal;
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
        const val = if (signed)
            try integerValueFromSignedDecoded(vm, decodeSignedInteger(slice, endian))
        else
            try integerValueFromUnsignedDecoded(vm, decodeUnsignedInteger(slice, endian));
        out.elements.append(vm.gc_allocator, val) catch return error.Fatal;
    }
}

fn unpackPointer(
    vm: *VM,
    out: *value.ArrayObject,
    source: *value.StringObject,
    base_offset: usize,
    bytes: []const u8,
    index: *usize,
    token: DirectiveToken,
    packed_mode: bool,
) VMError!void {
    const pointer_size = @sizeOf(usize);

    if (packed_mode) {
        if (index.* + pointer_size > bytes.len) return;

        const assoc_offset = base_offset + index.*;
        const ptr_slice = bytes[index.* .. index.* + pointer_size];
        index.* += pointer_size;
        const ptr_raw: usize = @intCast(decodeUnsignedInteger(ptr_slice, nativeOr(.native)));

        if (ptr_raw == 0) {
            out.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            return;
        }

        const associated = vm.packedPointerTargetAt(source, assoc_offset) orelse {
            return vm.raiseExceptionFmt(vm.argument_error_class, "no associated pointer", .{});
        };
        if (ptr_raw != @intFromPtr(associated.str.ptr)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "non associated pointer", .{});
        }

        const width = if (token.star) associated.str.len else token.count orelse 1;
        const read_len = @min(width, associated.str.len);
        const str = try vm.newStringWithEncoding(associated.str[0..read_len], false, .{ .ascii_8bit = .{} });
        out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
        return;
    }

    const count = if (token.star) (bytes.len -| index.*) / pointer_size else token.count orelse 1;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (index.* + pointer_size > bytes.len) break;

        const assoc_offset = base_offset + index.*;
        const ptr_slice = bytes[index.* .. index.* + pointer_size];
        index.* += pointer_size;
        const ptr_raw: usize = @intCast(decodeUnsignedInteger(ptr_slice, nativeOr(.native)));

        if (ptr_raw == 0) {
            out.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
            continue;
        }

        const associated = vm.packedPointerTargetAt(source, assoc_offset) orelse {
            return vm.raiseExceptionFmt(vm.argument_error_class, "no associated pointer", .{});
        };
        if (ptr_raw != @intFromPtr(associated.str.ptr)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "non associated pointer", .{});
        }

        const str = try vm.newStringWithEncoding(associated.str, false, .{ .ascii_8bit = .{} });
        out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
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

        var tmp: [8]u8 = @splat(0);
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
    if (token.star) {
        var i = start;
        while (i < bytes.len and bytes[i] != 0) : (i += 1) {}
        const nul_found = i < bytes.len and bytes[i] == 0;
        index.* = if (nul_found) i + 1 else bytes.len;
        const str = try vm.newStringWithEncoding(bytes[start..i], false, .{ .ascii_8bit = .{} });
        out.elements.append(vm.gc_allocator, str) catch return error.Fatal;
        return;
    }

    const width = token.count orelse 1;
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

fn unpackHexString(
    vm: *VM,
    out: *value.ArrayObject,
    bytes: []const u8,
    index: *usize,
    token: DirectiveToken,
    high_nibble_first: bool,
) VMError!void {
    const start = @min(index.*, bytes.len);
    const nibbles_requested: usize = if (token.star)
        (bytes.len - start) * 2
    else
        token.count orelse 1;
    const bytes_to_consume = if (token.star)
        bytes.len - start
    else
        (nibbles_requested + 1) / 2;
    const available_bytes = @min(bytes_to_consume, bytes.len - start);
    const available_nibbles = @min(nibbles_requested, available_bytes * 2);

    var out_hex: std.ArrayList(u8) = .empty;
    defer out_hex.deinit(vm.allocator);
    out_hex.ensureTotalCapacity(vm.allocator, available_nibbles) catch return error.Fatal;

    var nibble_i: usize = 0;
    while (nibble_i < available_nibbles) : (nibble_i += 1) {
        const byte_off = nibble_i / 2;
        const nibble_off = nibble_i % 2;
        const b = bytes[start + byte_off];
        const nibble: u8 = if (high_nibble_first)
            if (nibble_off == 0) (b >> 4) & 0x0F else b & 0x0F
        else if (nibble_off == 0)
            b & 0x0F
        else
            (b >> 4) & 0x0F;
        out_hex.appendAssumeCapacity("0123456789abcdef"[nibble]);
    }

    index.* = start + bytes_to_consume;
    const str = try vm.newStringWithEncoding(out_hex.items, false, .{ .us_ascii = .{} });
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

fn unpackVariableInteger(vm: *VM, out: *value.ArrayObject, bytes: []const u8, index: *usize, token: DirectiveToken) VMError!void {
    const count = if (token.star) std.math.maxInt(usize) else token.count orelse 1;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const maybe = if (token.directive == 'w') try unpackOneBerInteger(vm, bytes, index) else try unpackOneLebInteger(vm, bytes, index, token.directive == 'r');
        if (maybe) |val| {
            out.elements.append(vm.gc_allocator, val) catch return error.Fatal;
            continue;
        }

        if (token.star) break;
        out.elements.append(vm.gc_allocator, Value.nil()) catch return error.Fatal;
    }
}

fn unpackOneLebInteger(vm: *VM, bytes: []const u8, index: *usize, signed: bool) VMError!?Value {
    if (index.* >= bytes.len) return null;
    var result = std.math.big.int.Managed.initSet(vm.allocator, @as(u8, 0)) catch return error.Fatal;
    defer result.deinit();
    var digit = std.math.big.int.Managed.init(vm.allocator) catch return error.Fatal;
    defer digit.deinit();
    var shift: usize = 0;
    while (index.* < bytes.len) {
        const byte = bytes[index.*];
        index.* += 1;
        digit.set(byte & 0x7f) catch return error.Fatal;
        digit.shiftLeft(&digit, shift) catch return error.Fatal;
        result.add(&result, &digit) catch return error.Fatal;
        shift = std.math.add(usize, shift, 7) catch return error.Fatal;
        if (byte & 0x80 == 0) {
            if (signed and byte & 0x40 != 0) {
                digit.set(@as(u8, 1)) catch return error.Fatal;
                digit.shiftLeft(&digit, shift) catch return error.Fatal;
                result.sub(&result, &digit) catch return error.Fatal;
            }
            return try vm.valueFromManagedInteger(&result);
        }
    }
    // Incomplete LEB128 values are omitted for '*', and nil for fixed counts.
    return null;
}

fn unpackOneBerInteger(vm: *VM, bytes: []const u8, index: *usize) VMError!?Value {
    if (index.* >= bytes.len) return null;

    var acc_u64: u64 = 0;
    var acc_big: ?std.math.big.int.Managed = null;
    defer if (acc_big) |*b| b.deinit();
    var base_big = std.math.big.int.Managed.initSet(vm.allocator, @as(i64, 128)) catch return error.Fatal;
    defer base_big.deinit();

    while (true) {
        if (index.* >= bytes.len) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "malformed BER compressed integer", .{});
        }

        const b = bytes[index.*];
        index.* += 1;
        const payload: u8 = b & 0x7F;

        if (acc_big) |*big| {
            big.mul(big, &base_big) catch return error.Fatal;
            big.addScalar(big, payload) catch return error.Fatal;
        } else {
            const mul, const mul_overflow = @mulWithOverflow(acc_u64, 128);
            const sum, const sum_overflow = @addWithOverflow(mul, @as(u64, payload));
            if (mul_overflow != 0 or sum_overflow != 0) {
                acc_big = std.math.big.int.Managed.initSet(vm.allocator, acc_u64) catch return error.Fatal;
                acc_big.?.mul(&acc_big.?, &base_big) catch return error.Fatal;
                acc_big.?.addScalar(&acc_big.?, payload) catch return error.Fatal;
            } else {
                acc_u64 = sum;
            }
        }

        if ((b & 0x80) == 0) break;
    }

    if (acc_big) |*big| {
        return try vm.valueFromManagedInteger(big);
    }
    return try integerValueFromUnsignedDecoded(vm, acc_u64);
}

fn decodeBase64(vm: *VM, bytes: []const u8, strict: bool) VMError![]u8 {
    if (!strict) return decodeBase64Permissive(vm, bytes);

    var filtered: std.ArrayList(u8) = .empty;
    defer filtered.deinit(vm.allocator);

    for (bytes) |b| {
        if (isBase64Byte(b) or b == '=') {
            filtered.append(vm.allocator, b) catch return error.Fatal;
            continue;
        }
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    }

    if (filtered.items.len == 0) {
        return vm.allocator.alloc(u8, 0) catch return error.Fatal;
    }

    if (filtered.items.len % 4 != 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    }

    const decoder = std.base64.standard.Decoder;
    const decoded_len = decoder.calcSizeForSlice(filtered.items) catch {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    };
    const out = vm.allocator.alloc(u8, decoded_len) catch return error.Fatal;
    _ = decoder.decode(out, filtered.items) catch {
        vm.allocator.free(out);
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid base64", .{});
    };
    return out;
}

fn decodeBase64Permissive(vm: *VM, bytes: []const u8) VMError![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(vm.allocator);

    var bits: u32 = 0;
    var bit_count: u5 = 0;
    for (bytes) |b| {
        if (b == '=') break;
        const sextet = base64SixBit(b) orelse continue;
        bits = (bits << 6) | sextet;
        bit_count += 6;
        if (bit_count >= 8) {
            bit_count -= 8;
            decoded.append(vm.allocator, @intCast((bits >> bit_count) & 0xff)) catch return error.Fatal;
            bits &= if (bit_count == 0) 0 else (@as(u32, 1) << bit_count) - 1;
        }
    }

    return decoded.toOwnedSlice(vm.allocator) catch return error.Fatal;
}

fn base64SixBit(b: u8) ?u6 {
    return if (b >= 'A' and b <= 'Z') @intCast(b - 'A') else if (b >= 'a' and b <= 'z') @intCast(b - 'a' + 26) else if (b >= '0' and b <= '9') @intCast(b - '0' + 52) else if (b == '+') 62 else if (b == '/') 63 else null;
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

fn decodeUnsignedInteger(slice: []const u8, endian: Endianness) u64 {
    var buf: [8]u8 = @splat(0);

    if (endian == .big) {
        var j: usize = 0;
        while (j < slice.len) : (j += 1) {
            buf[j] = slice[slice.len - 1 - j];
        }
    } else {
        @memcpy(buf[0..slice.len], slice);
    }

    return std.mem.readInt(u64, &buf, .little);
}

fn decodeSignedInteger(slice: []const u8, endian: Endianness) i64 {
    const raw = decodeUnsignedInteger(slice, endian);

    const bits = slice.len * 8;
    if (bits == 0) return 0;
    if (bits >= 64) return @bitCast(raw);

    const sign_bit: u64 = @as(u64, 1) << @intCast(bits - 1);
    if ((raw & sign_bit) == 0) return @intCast(raw);

    const mask: u64 = ~(@as(u64, 0)) << @intCast(bits);
    return @bitCast(raw | mask);
}

fn integerValueFromSignedDecoded(vm: *VM, n: i64) VMError!Value {
    if (std.math.cast(i63, n)) |small| {
        return Value.integer(@as(i64, small));
    }
    return vm.newBigIntegerFromI64(n);
}

fn integerValueFromUnsignedDecoded(vm: *VM, n: u64) VMError!Value {
    if (std.math.cast(i63, n)) |small| {
        return Value.integer(@as(i64, small));
    }

    var managed = std.math.big.int.Managed.initSet(vm.allocator, n) catch return error.Fatal;
    defer managed.deinit();
    return vm.valueFromManagedInteger(&managed);
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
    if (arg.isInteger() or arg.isBigInteger()) return arg.integerToF64();
    if (arg.isNil() or arg.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    }

    const maybe_coerced = try vm.checkCallMethodByName(arg, "to_f", true, &[_]Value{}, null);
    const coerced = maybe_coerced orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float", .{vm.className(arg)});
    };
    if (coerced.isFloat()) return coerced.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Float ({s}#to_f gives {s})", .{ vm.className(arg), vm.className(arg), vm.className(coerced) });
}

fn nativeOr(endianness: Endianness) Endianness {
    if (endianness != .native) return endianness;
    return if (nativeEndian() == .little) .little else .big;
}

fn nativeEndian() std.builtin.Endian {
    return @import("builtin").target.cpu.arch.endian();
}
