const std = @import("std");
const enc = @import("../encoding.zig");
const value = @import("../value.zig");
const vm_mod = @import("../vm.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

const marshal_major: u8 = 4;
const marshal_minor: u8 = 8;

const Tag = struct {
    const nil_value: u8 = '0';
    const true_value: u8 = 'T';
    const false_value: u8 = 'F';
    const fixnum: u8 = 'i';
    const symbol: u8 = ':';
    const symbol_link: u8 = ';';
    const object_link: u8 = '@';
    const string: u8 = '"';
    const array: u8 = '[';
    const hash: u8 = '{';
    const hash_default: u8 = '}';
    const float: u8 = 'f';
    const bignum: u8 = 'l';
    const ivar: u8 = 'I';
    const user_defined_object: u8 = 'u';
    const user_marshaled_object: u8 = 'U';
};

const MarshalObjectRefs = std.AutoHashMap(usize, usize);
const MarshalSymbolRefs = std.AutoHashMap(*value.SymbolObject, usize);

const DumpState = struct {
    vm: *VM,
    out: std.ArrayList(u8),
    object_refs: MarshalObjectRefs,
    symbol_refs: MarshalSymbolRefs,
    object_count: usize,
    symbol_count: usize,

    fn init(vm: *VM) DumpState {
        return .{
            .vm = vm,
            .out = .empty,
            .object_refs = MarshalObjectRefs.init(vm.allocator),
            .symbol_refs = MarshalSymbolRefs.init(vm.allocator),
            .object_count = 0,
            .symbol_count = 0,
        };
    }

    fn deinit(self: *DumpState) void {
        self.out.deinit(self.vm.allocator);
        self.object_refs.deinit();
        self.symbol_refs.deinit();
    }
};

const LoadState = struct {
    vm: *VM,
    bytes: []const u8,
    offset: usize,
    object_refs: std.ArrayList(Value),
    symbol_refs: std.ArrayList(*value.SymbolObject),

    fn init(vm: *VM, bytes: []const u8) LoadState {
        return .{
            .vm = vm,
            .bytes = bytes,
            .offset = 0,
            .object_refs = .empty,
            .symbol_refs = .empty,
        };
    }

    fn deinit(self: *LoadState) void {
        self.object_refs.deinit(self.vm.allocator);
        self.symbol_refs.deinit(self.vm.allocator);
    }

    fn readByte(self: *LoadState) !u8 {
        if (self.offset >= self.bytes.len) {
            return self.vm.raiseExceptionFmt(self.vm.argument_error_class, "marshal data too short", .{});
        }
        const byte = self.bytes[self.offset];
        self.offset += 1;
        return byte;
    }

    fn readBytes(self: *LoadState, len: usize) ![]const u8 {
        if (self.offset + len > self.bytes.len) {
            return self.vm.raiseExceptionFmt(self.vm.argument_error_class, "marshal data too short", .{});
        }
        const slice = self.bytes[self.offset .. self.offset + len];
        self.offset += len;
        return slice;
    }
};

pub fn register(vm: *VM) !void {
    const marshal_obj = Value.fromObject(&vm.marshal_module.object);
    const marshal_singleton = try vm.getOrCreateSingletonClass(marshal_obj);

    const dump_sym = try vm.intern("dump");
    try marshal_singleton.module.methods.put(dump_sym, value.MethodEntry.builtin(&builtinMarshalDump, .{ .variadic = 1 }));

    const load_sym = try vm.intern("load");
    try marshal_singleton.module.methods.put(load_sym, value.MethodEntry.builtin(&builtinMarshalLoad, .{ .variadic = 1 }));
}

pub fn builtinMarshalDump(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);

    var io_arg: ?Value = null;
    if (args.len >= 2 and !args[1].isNil() and !args[1].isInteger()) {
        io_arg = args[1];
    }

    var state = DumpState.init(vm);
    defer state.deinit();

    state.out.append(vm.allocator, marshal_major) catch return error.Fatal;
    state.out.append(vm.allocator, marshal_minor) catch return error.Fatal;
    try dumpValue(&state, args[0]);

    const dumped = try vm.newStringWithEncoding(state.out.items, false, .{ .ascii_8bit = .{} });
    if (io_arg) |io| {
        var write_args = [_]Value{dumped};
        _ = try vm.callMethodByName(io, "write", write_args[0..], null);
        return io;
    }
    return dumped;
}

pub fn builtinMarshalLoad(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    var freeze: ?Value = null;
    try vm.consumeKeywordArgs(.{"freeze"}, .{&freeze});
    try vm.validateKeywordArgsConsumed();

    const source = if (args[0].isString())
        args[0]
    else blk: {
        const read_result = try vm.callMethodByName(args[0], "read", &.{}, null);
        break :blk read_result;
    };
    if (!source.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "instance of IO needed", .{});
    }

    var state = LoadState.init(vm, source.toStringObject().str);
    defer state.deinit();

    const major = try state.readByte();
    const minor = try state.readByte();
    if (major != marshal_major or minor != marshal_minor) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "incompatible marshal file format (can't be read)\n\tformat version {d}.{d} required; {d}.{d} given", .{
            marshal_major,
            marshal_minor,
            major,
            minor,
        });
    }

    const loaded = try loadValue(&state);
    if (state.offset != state.bytes.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "marshal data too long", .{});
    }

    if (args.len >= 2 and !args[1].isNil()) {
        var proc_args = [_]Value{loaded};
        _ = try vm.callMethodByName(args[1], "call", proc_args[0..], null);
    }

    return loaded;
}

fn dumpValue(state: *DumpState, val: Value) VMError!void {
    if (val.isNil()) {
        try appendByte(state, Tag.nil_value);
        return;
    }
    if (val.isBool()) {
        try appendByte(state, if (val.toBool()) Tag.true_value else Tag.false_value);
        return;
    }
    if (val.isInteger()) {
        const int = val.toInteger();
        if (int >= -1073741824 and int <= 1073741823) {
            try appendByte(state, Tag.fixnum);
            try dumpPackedInt(state, int);
        } else {
            try appendByte(state, Tag.bignum);
            try dumpBignumI64(state, int);
        }
        return;
    }
    if (val.isFloat()) {
        try dumpLinkedObject(state, val, dumpFloatBody);
        return;
    }
    if (val.isString()) {
        try dumpStringValue(state, val);
        return;
    }
    if (val.isSymbol()) {
        try dumpSymbolValue(state, val.toSymbolObject());
        return;
    }
    if (val.isArray()) {
        try dumpLinkedObject(state, val, dumpArrayBody);
        return;
    }
    if (val.isHash()) {
        try dumpLinkedObject(state, val, dumpHashBody);
        return;
    }
    if (val.isBigInteger()) {
        try appendByte(state, Tag.bignum);
        try dumpBignumValue(state, val.toBigIntegerObject().value);
        return;
    }
    if (val.getObjectPointer() != null) {
        if (try state.vm.checkCallMethodByName(val, "marshal_dump", false, &.{}, null)) |dumped| {
            try dumpUserMarshaledObject(state, val, dumped);
            return;
        }
    }

    return state.vm.raiseExceptionFmt(state.vm.type_error_class, "can't dump {s}", .{state.vm.className(val)});
}

fn dumpUserMarshaledObject(state: *DumpState, val: Value, dumped: Value) VMError!void {
    const key: usize = @intCast(val.raw);
    if (state.object_refs.get(key)) |idx| {
        try appendByte(state, Tag.object_link);
        try dumpPackedInt(state, @intCast(idx));
        return;
    }

    const class_obj = state.vm.getClass(val);
    const class_path = (try marshalClassPath(state.vm, class_obj)) orelse {
        return state.vm.raiseExceptionFmt(state.vm.type_error_class, "can't dump anonymous class", .{});
    };

    state.object_refs.put(key, state.object_count) catch return error.Fatal;
    state.object_count += 1;

    try appendByte(state, Tag.user_marshaled_object);
    try dumpSymbolValue(state, try state.vm.intern(class_path));
    try dumpValue(state, dumped);
}

fn dumpLinkedObject(state: *DumpState, val: Value, comptime body: fn (*DumpState, Value) VMError!void) VMError!void {
    const key: usize = @intCast(val.raw);
    if (state.object_refs.get(key)) |idx| {
        try appendByte(state, Tag.object_link);
        try dumpPackedInt(state, @intCast(idx));
        return;
    }
    state.object_refs.put(key, state.object_count) catch return error.Fatal;
    state.object_count += 1;
    try body(state, val);
}

fn dumpStringValue(state: *DumpState, val: Value) VMError!void {
    const string_obj = val.toStringObject();
    try dumpLinkedObject(state, val, struct {
        fn f(inner_state: *DumpState, inner_val: Value) VMError!void {
            const obj = inner_val.toStringObject();
            switch (obj.encoding) {
                .ascii_8bit => try dumpStringBody(inner_state, obj.str),
                .utf8, .us_ascii => {
                    try appendByte(inner_state, Tag.ivar);
                    try dumpStringBody(inner_state, obj.str);
                    try dumpPackedInt(inner_state, 1);
                    try dumpSymbolValue(inner_state, try inner_state.vm.intern("E"));
                    try dumpValue(inner_state, Value.boolean(obj.encoding == .utf8));
                },
                else => {
                    try appendByte(inner_state, Tag.ivar);
                    try dumpStringBody(inner_state, obj.str);
                    try dumpPackedInt(inner_state, 1);
                    try dumpSymbolValue(inner_state, try inner_state.vm.intern("encoding"));
                    const name_value = try inner_state.vm.newStringWithEncoding(marshalEncodingName(obj.encoding), false, .{ .ascii_8bit = .{} });
                    try dumpValue(inner_state, name_value);
                },
            }
        }
    }.f);
    _ = string_obj;
}

fn dumpStringBody(state: *DumpState, bytes: []const u8) VMError!void {
    try appendByte(state, Tag.string);
    try dumpPackedInt(state, @intCast(bytes.len));
    state.out.appendSlice(state.vm.allocator, bytes) catch return error.Fatal;
}

fn dumpSymbolValue(state: *DumpState, symbol: *value.SymbolObject) VMError!void {
    if (state.symbol_refs.get(symbol)) |idx| {
        try appendByte(state, Tag.symbol_link);
        try dumpPackedInt(state, @intCast(idx));
        return;
    }
    state.symbol_refs.put(symbol, state.symbol_count) catch return error.Fatal;
    state.symbol_count += 1;

    switch (symbol.encoding) {
        .us_ascii => try dumpSymbolBody(state, symbol.name),
        .utf8 => {
            try appendByte(state, Tag.ivar);
            try dumpSymbolBody(state, symbol.name);
            try dumpPackedInt(state, 1);
            try dumpSymbolValue(state, try state.vm.intern("E"));
            try dumpValue(state, Value.boolean(true));
        },
        else => {
            try appendByte(state, Tag.ivar);
            try dumpSymbolBody(state, symbol.name);
            try dumpPackedInt(state, 1);
            try dumpSymbolValue(state, try state.vm.intern("encoding"));
            const name_value = try state.vm.newStringWithEncoding(marshalEncodingName(symbol.encoding), false, .{ .ascii_8bit = .{} });
            try dumpValue(state, name_value);
        },
    }
}

fn dumpSymbolBody(state: *DumpState, bytes: []const u8) VMError!void {
    try appendByte(state, Tag.symbol);
    try dumpPackedInt(state, @intCast(bytes.len));
    state.out.appendSlice(state.vm.allocator, bytes) catch return error.Fatal;
}

fn dumpArrayBody(state: *DumpState, val: Value) VMError!void {
    try appendByte(state, Tag.array);
    const items = val.toArrayObject().elements.items;
    try dumpPackedInt(state, @intCast(items.len));
    for (items) |item| {
        try dumpValue(state, item);
    }
}

fn dumpHashBody(state: *DumpState, val: Value) VMError!void {
    const hash = val.toHashObject();
    if (hash.default_proc != null or hash.compare_by_identity) {
        return state.vm.raiseExceptionFmt(state.vm.type_error_class, "can't dump hash with custom default or identity semantics", .{});
    }

    try appendByte(state, if (hash.default_value == null) Tag.hash else Tag.hash_default);
    try dumpPackedInt(state, @intCast(hash.entries.items.len));
    for (hash.entries.items) |entry| {
        try dumpValue(state, entry.key);
        try dumpValue(state, entry.value);
    }
    if (hash.default_value) |default_value| {
        try dumpValue(state, default_value);
    }
}

fn dumpFloatBody(state: *DumpState, val: Value) VMError!void {
    try appendByte(state, Tag.float);
    var buf: [64]u8 = undefined;
    const float = val.toFloatObject().val;
    const repr = if (std.math.isNan(float))
        "nan"
    else if (std.math.isPositiveInf(float))
        "inf"
    else if (std.math.isNegativeInf(float))
        "-inf"
    else if (float == 0 and std.math.signbit(float))
        "-0"
    else blk: {
        if (std.math.isFinite(float) and @trunc(float) == float) {
            const int_value: i64 = @intFromFloat(float);
            break :blk std.fmt.bufPrint(&buf, "{d}", .{int_value}) catch return error.Fatal;
        }
        break :blk std.fmt.bufPrint(&buf, "{d}", .{float}) catch return error.Fatal;
    };
    try dumpPackedInt(state, @intCast(repr.len));
    state.out.appendSlice(state.vm.allocator, repr) catch return error.Fatal;
}

fn dumpPackedInt(state: *DumpState, value_i64: i64) VMError!void {
    if (value_i64 == 0) {
        try appendByte(state, 0);
        return;
    }
    if (value_i64 > 0 and value_i64 < 123) {
        try appendByte(state, @intCast(value_i64 + 5));
        return;
    }
    if (value_i64 < 0 and value_i64 > -124) {
        try appendByte(state, @intCast(256 + value_i64 - 5));
        return;
    }

    if (value_i64 > 0) {
        const unsigned: u32 = @intCast(value_i64);
        var len: u8 = 4;
        while (len > 1 and ((unsigned >> (@as(u5, @intCast((len - 1) * 8)))) & 0xff) == 0) : (len -= 1) {}
        try appendByte(state, len);
        var i: u8 = 0;
        while (i < len) : (i += 1) {
            try appendByte(state, @truncate(unsigned >> (@as(u5, @intCast(i * 8)))));
        }
        return;
    }

    const signed: i32 = @intCast(value_i64);
    var len: u8 = 4;
    while (len > 1) : (len -= 1) {
        const top = @as(u8, @truncate(@as(u32, @bitCast(signed)) >> (@as(u5, @intCast((len - 1) * 8)))));
        const next = @as(u8, @truncate(@as(u32, @bitCast(signed)) >> (@as(u5, @intCast((len - 2) * 8)))));
        if (top == 0xff and (next & 0x80) != 0) continue;
        break;
    }
    try appendByte(state, @intCast(@as(u16, 256) - len));
    var i: u8 = 0;
    while (i < len) : (i += 1) {
        try appendByte(state, @truncate(@as(u32, @bitCast(signed)) >> (@as(u5, @intCast(i * 8)))));
    }
}

fn dumpBignumI64(state: *DumpState, int: i64) VMError!void {
    const magnitude: u64 = if (int < 0)
        @intCast(-(@as(i128, int)))
    else
        @intCast(int);
    try dumpBignumMagnitude(state, int < 0, magnitude);
}

fn dumpBignumValue(state: *DumpState, managed: std.math.big.int.Managed) VMError!void {
    const magnitude = managed.toConst();
    const is_negative = magnitude.positive == false and magnitude.limbs.len > 0;

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(state.vm.allocator);

    for (magnitude.limbs) |limb| {
        var word = limb;
        var i: usize = 0;
        while (i < @sizeOf(std.math.big.Limb)) : (i += 1) {
            bytes.append(state.vm.allocator, @truncate(word & 0xff)) catch return error.Fatal;
            word >>= 8;
        }
    }
    while (bytes.items.len > 0 and bytes.items[bytes.items.len - 1] == 0) {
        _ = bytes.pop();
    }
    try dumpBignumBytes(state, is_negative, bytes.items);
}

fn dumpBignumMagnitude(state: *DumpState, negative: bool, magnitude: u64) VMError!void {
    var bytes: [8]u8 = undefined;
    var len: usize = 0;
    var remaining = magnitude;
    while (remaining != 0) : (remaining >>= 8) {
        bytes[len] = @truncate(remaining & 0xff);
        len += 1;
    }
    try dumpBignumBytes(state, negative, bytes[0..len]);
}

fn dumpBignumBytes(state: *DumpState, negative: bool, bytes: []const u8) VMError!void {
    try appendByte(state, if (negative) '-' else '+');
    const words = (bytes.len + 1) / 2;
    try dumpPackedInt(state, @intCast(words));
    state.out.appendSlice(state.vm.allocator, bytes) catch return error.Fatal;
    if ((bytes.len & 1) == 1) {
        try appendByte(state, 0);
    }
}

fn loadValue(state: *LoadState) VMError!Value {
    const tag = try state.readByte();
    return switch (tag) {
        Tag.nil_value => Value.nil(),
        Tag.true_value => Value.boolean(true),
        Tag.false_value => Value.boolean(false),
        Tag.fixnum => Value.integer(try loadPackedInt(state)),
        Tag.symbol => Value.fromObject(&(try loadSymbol(state)).object),
        Tag.symbol_link => Value.fromObject(&(try loadSymbolLink(state)).object),
        Tag.object_link => try loadObjectLink(state),
        Tag.string => try loadString(state),
        Tag.array => try loadArray(state),
        Tag.hash => try loadHash(state, false),
        Tag.hash_default => try loadHash(state, true),
        Tag.float => try loadFloat(state),
        Tag.bignum => try loadBignum(state),
        Tag.ivar => try loadIvarWrapped(state),
        Tag.user_defined_object => try loadUserDefinedObject(state),
        Tag.user_marshaled_object => try loadUserMarshaledObject(state),
        else => state.vm.raiseExceptionFmt(state.vm.argument_error_class, "unsupported marshal type", .{}),
    };
}

fn loadUserDefinedObject(state: *LoadState) VMError!Value {
    const class_name_value = try loadValue(state);
    if (!class_name_value.isSymbol()) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal user class", .{});
    }

    const class_path = class_name_value.toSymbolObject().name;
    const class_value = (try state.vm.resolveConstantPath(class_path)) orelse {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "undefined class/module {s}", .{class_path});
    };
    if (!class_value.isClass()) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "undefined class/module {s}", .{class_path});
    }

    const byte_count = try loadPackedInt(state);
    if (byte_count < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative string size", .{});
    }

    const bytes = try state.readBytes(@intCast(byte_count));
    const payload = try state.vm.newStringWithEncoding(bytes, false, .{ .ascii_8bit = .{} });
    var load_args = [_]Value{payload};
    const object = try state.vm.callMethodByName(class_value, "_load", load_args[0..], null);
    state.object_refs.append(state.vm.allocator, object) catch return error.Fatal;
    return object;
}

fn loadUserMarshaledObject(state: *LoadState) VMError!Value {
    const class_name_value = try loadValue(state);
    if (!class_name_value.isSymbol()) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal user class", .{});
    }

    const class_path = class_name_value.toSymbolObject().name;
    const class_value = (try state.vm.resolveConstantPath(class_path)) orelse {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "undefined class/module {s}", .{class_path});
    };
    if (!class_value.isClass()) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "undefined class/module {s}", .{class_path});
    }

    const object = try state.vm.newObjectForClass(class_value.toClassObject());
    state.object_refs.append(state.vm.allocator, object) catch return error.Fatal;

    const dumped = try loadValue(state);
    var load_args = [_]Value{dumped};
    _ = try state.vm.callMethodByName(object, "marshal_load", load_args[0..], null);
    return object;
}

fn loadPackedInt(state: *LoadState) VMError!i64 {
    const b = try state.readByte();
    return switch (b) {
        0x00 => 0,
        0x01 => @intCast(try state.readByte()),
        0x02 => blk: {
            const bytes = try state.readBytes(2);
            break :blk @intCast(std.mem.readInt(u16, bytes[0..2], .little));
        },
        0x03 => blk: {
            const bytes = try state.readBytes(3);
            break :blk @as(i64, bytes[0]) | (@as(i64, bytes[1]) << 8) | (@as(i64, bytes[2]) << 16);
        },
        0x04 => blk: {
            const bytes = try state.readBytes(4);
            break :blk @as(i64, std.mem.readInt(i32, bytes[0..4], .little));
        },
        0xFC => blk: {
            const bytes = try state.readBytes(4);
            break :blk @as(i64, std.mem.readInt(i32, bytes[0..4], .little));
        },
        0xFD => blk: {
            const bytes = try state.readBytes(3);
            const unsigned = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | 0xFF000000;
            break :blk @as(i64, @as(i32, @bitCast(unsigned)));
        },
        0xFE => blk: {
            const bytes = try state.readBytes(2);
            const unsigned = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | 0xFFFF0000;
            break :blk @as(i64, @as(i32, @bitCast(unsigned)));
        },
        0xFF => blk: {
            const byte = try state.readByte();
            const unsigned = @as(u32, byte) | 0xFFFFFF00;
            break :blk @as(i64, @as(i32, @bitCast(unsigned)));
        },
        else => blk: {
            const signed: i16 = if (b >= 128) @as(i16, b) - 256 else b;
            break :blk if (b >= 128) signed + 5 else signed - 5;
        },
    };
}

fn loadSymbol(state: *LoadState) VMError!*value.SymbolObject {
    const len = try loadPackedInt(state);
    if (len < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative symbol length", .{});
    }
    const bytes = try state.readBytes(@intCast(len));
    const initial_encoding: enc.Encoding = if (enc.isAsciiOnly(bytes)) .{ .us_ascii = .{} } else .{ .ascii_8bit = .{} };
    const symbol = try state.vm.internWithEncoding(bytes, initial_encoding);
    state.symbol_refs.append(state.vm.allocator, symbol) catch return error.Fatal;
    return symbol;
}

fn loadSymbolLink(state: *LoadState) VMError!*value.SymbolObject {
    const idx = try loadPackedInt(state);
    if (idx < 0 or @as(usize, @intCast(idx)) >= state.symbol_refs.items.len) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "bad symbol link", .{});
    }
    return state.symbol_refs.items[@intCast(idx)];
}

fn loadObjectLink(state: *LoadState) VMError!Value {
    const idx = try loadPackedInt(state);
    if (idx < 0 or @as(usize, @intCast(idx)) >= state.object_refs.items.len) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "bad object link", .{});
    }
    return state.object_refs.items[@intCast(idx)];
}

fn loadString(state: *LoadState) VMError!Value {
    const len = try loadPackedInt(state);
    if (len < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative string length", .{});
    }
    const bytes = try state.readBytes(@intCast(len));
    const str = try state.vm.newStringWithEncoding(bytes, false, .{ .ascii_8bit = .{} });
    state.object_refs.append(state.vm.allocator, str) catch return error.Fatal;
    return str;
}

fn loadArray(state: *LoadState) VMError!Value {
    const len = try loadPackedInt(state);
    if (len < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative array length", .{});
    }
    const array = try state.vm.createArray();
    const array_val = Value.fromObject(&array.object);
    state.object_refs.append(state.vm.allocator, array_val) catch return error.Fatal;
    var i: i64 = 0;
    while (i < len) : (i += 1) {
        array.elements.append(state.vm.gc_allocator, try loadValue(state)) catch return error.Fatal;
    }
    return array_val;
}

fn loadHash(state: *LoadState, has_default: bool) VMError!Value {
    const len = try loadPackedInt(state);
    if (len < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative hash length", .{});
    }
    const hash = try state.vm.createHash();
    const hash_val = Value.fromObject(&hash.object);
    state.object_refs.append(state.vm.allocator, hash_val) catch return error.Fatal;
    var i: i64 = 0;
    while (i < len) : (i += 1) {
        const key = try loadValue(state);
        const entry_value = try loadValue(state);
        try state.vm.hashSetEntry(hash, key, entry_value);
    }
    if (has_default) {
        hash.default_value = try loadValue(state);
    }
    return hash_val;
}

fn loadFloat(state: *LoadState) VMError!Value {
    const len = try loadPackedInt(state);
    if (len < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative float length", .{});
    }
    const bytes = try state.readBytes(@intCast(len));
    const parsed = if (std.mem.eql(u8, bytes, "inf"))
        std.math.inf(f64)
    else if (std.mem.eql(u8, bytes, "-inf"))
        -std.math.inf(f64)
    else if (std.mem.eql(u8, bytes, "nan"))
        std.math.nan(f64)
    else blk: {
        break :blk std.fmt.parseFloat(f64, bytes) catch {
            return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal float", .{});
        };
    };
    const float_val = try state.vm.newFloat(parsed);
    state.object_refs.append(state.vm.allocator, float_val) catch return error.Fatal;
    return float_val;
}

fn loadBignum(state: *LoadState) VMError!Value {
    const sign = try state.readByte();
    const word_count = try loadPackedInt(state);
    if (word_count < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative bignum length", .{});
    }
    const byte_count: usize = @intCast(word_count * 2);
    const bytes = try state.readBytes(byte_count);

    var magnitude: i128 = 0;
    var i: usize = byte_count;
    while (i > 0) {
        i -= 1;
        magnitude = (magnitude << 8) | bytes[i];
    }
    const signed_value: i128 = switch (sign) {
        '+' => magnitude,
        '-' => -magnitude,
        else => return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal bignum sign", .{}),
    };

    const result = if (signed_value >= std.math.minInt(i64) and signed_value <= std.math.maxInt(i64))
        Value.integer(@intCast(signed_value))
    else blk: {
        const decimal = std.fmt.allocPrint(state.vm.allocator, "{d}", .{signed_value}) catch return error.Fatal;
        defer state.vm.allocator.free(decimal);
        break :blk try state.vm.newBigIntegerFromDecimalString(decimal);
    };
    state.object_refs.append(state.vm.allocator, result) catch return error.Fatal;
    return result;
}

fn loadIvarWrapped(state: *LoadState) VMError!Value {
    const base = try loadValue(state);
    const ivar_count = try loadPackedInt(state);
    if (ivar_count < 0) {
        return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "negative ivar count", .{});
    }

    var encoding_override: ?enc.Encoding = null;
    var i: i64 = 0;
    while (i < ivar_count) : (i += 1) {
        const key = try loadValue(state);
        const ivar_value = try loadValue(state);
        if (key.isSymbol()) {
            const key_name = key.toSymbolObject().name;
            if (std.mem.eql(u8, key_name, "E")) {
                if (!ivar_value.isBool()) {
                    return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal encoding ivar", .{});
                }
                encoding_override = if (ivar_value.toBool()) .{ .utf8 = .{} } else .{ .us_ascii = .{} };
            } else if (std.mem.eql(u8, key_name, "encoding")) {
                const name_bytes = if (ivar_value.isString())
                    ivar_value.toStringObject().str
                else if (ivar_value.isSymbol())
                    ivar_value.toSymbolObject().name
                else
                    return state.vm.raiseExceptionFmt(state.vm.argument_error_class, "invalid marshal encoding object", .{});
                encoding_override = try marshalEncodingByName(state.vm, name_bytes);
            }
        }
    }

    if (encoding_override) |encoding_value| {
        if (base.isString()) {
            base.toStringObject().encoding = encoding_value;
        } else if (base.isSymbol()) {
            return Value.fromObject(&(try state.vm.internWithEncoding(base.toSymbolObject().name, encoding_value)).object);
        }
    }

    return base;
}

fn appendByte(state: *DumpState, byte: u8) !void {
    state.out.append(state.vm.allocator, byte) catch return error.Fatal;
}

fn marshalEncodingName(encoding: enc.Encoding) []const u8 {
    return switch (encoding) {
        .us_ascii => "US-ASCII",
        .ascii_8bit => "ASCII-8BIT",
        .utf8 => "UTF-8",
        .shift_jis => "Shift_JIS",
        .windows_31j => "Windows-31J",
        .euc_jp => "EUC-JP",
        .iso_8859_1 => "ISO-8859-1",
        .iso_8859_9 => "ISO-8859-9",
        .iso_8859_15 => "ISO-8859-15",
        .utf7 => "UTF-7",
        .utf16 => "UTF-16",
        .utf16le => "UTF-16LE",
        .utf16be => "UTF-16BE",
        .utf32 => "UTF-32",
        .utf32le => "UTF-32LE",
        .utf32be => "UTF-32BE",
        .cesu8 => "CESU-8",
        .cp437 => "CP437",
        .cp866 => "IBM866",
        .iso_2022_jp => "ISO-2022-JP",
    };
}

fn marshalEncodingByName(vm: *VM, name: []const u8) VMError!enc.Encoding {
    if (std.ascii.eqlIgnoreCase(name, "US-ASCII")) return .{ .us_ascii = .{} };
    if (std.ascii.eqlIgnoreCase(name, "ASCII-8BIT")) return .{ .ascii_8bit = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-8")) return .{ .utf8 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "Shift_JIS")) return .{ .shift_jis = .{} };
    if (std.ascii.eqlIgnoreCase(name, "Windows-31J")) return .{ .windows_31j = .{} };
    if (std.ascii.eqlIgnoreCase(name, "EUC-JP")) return .{ .euc_jp = .{} };
    if (std.ascii.eqlIgnoreCase(name, "ISO-8859-1")) return .{ .iso_8859_1 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "ISO-8859-9")) return .{ .iso_8859_9 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "ISO-8859-15")) return .{ .iso_8859_15 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-7")) return .{ .utf7 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-16")) return .{ .utf16 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-16LE")) return .{ .utf16le = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-16BE")) return .{ .utf16be = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-32")) return .{ .utf32 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-32LE")) return .{ .utf32le = .{} };
    if (std.ascii.eqlIgnoreCase(name, "UTF-32BE")) return .{ .utf32be = .{} };
    if (std.ascii.eqlIgnoreCase(name, "CESU-8")) return .{ .cesu8 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "CP437")) return .{ .cp437 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "IBM866")) return .{ .cp866 = .{} };
    if (std.ascii.eqlIgnoreCase(name, "ISO-2022-JP")) return .{ .iso_2022_jp = .{} };
    return vm.raiseExceptionFmt(vm.argument_error_class, "unsupported marshal encoding", .{});
}

fn marshalClassPath(vm: *VM, class_obj: *value.ClassObject) VMError!?[]const u8 {
    if (class_obj.attached_object != null) return null;
    return vm.publicModuleName(Value.fromObject(&class_obj.module.object));
}
