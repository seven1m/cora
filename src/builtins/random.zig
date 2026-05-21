const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const U53 = std.meta.Int(.unsigned, 53);

pub fn register(vm: *VM) !void {
    const formatter_name = try vm.intern("Formatter");
    const formatter_val = try vm.newModule(formatter_name);
    const formatter_module = formatter_val.toModuleObject();
    try vm.random_class.module.constants.put(formatter_name, .{ .value = formatter_val });

    const initialize_sym = try vm.intern("initialize");
    try vm.random_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinRandomInitialize, .{ .variadic = 0 }, .private));

    const rand_sym = try vm.intern("rand");
    try vm.random_class.module.methods.put(rand_sym, value.MethodEntry.builtin(&builtinRandomRand, .{ .variadic = 0 }));

    const bytes_sym = try vm.intern("bytes");
    try vm.random_class.module.methods.put(bytes_sym, value.MethodEntry.builtin(&builtinRandomBytes, .{ .exact = 1 }));

    const seed_sym = try vm.intern("seed");
    try vm.random_class.module.methods.put(seed_sym, value.MethodEntry.builtin(&builtinRandomSeed, .{ .exact = 0 }));

    const random_number_sym = try vm.intern("random_number");
    try formatter_module.methods.put(rand_sym, value.MethodEntry.builtin(&builtinRandomFormatterRandomNumber, .{ .variadic = 0 }));
    try formatter_module.methods.put(random_number_sym, value.MethodEntry.builtin(&builtinRandomFormatterRandomNumber, .{ .variadic = 0 }));

    const random_val = Value.fromObject(&vm.random_class.module.object);
    const random_singleton = try vm.getOrCreateSingletonClass(random_val);

    try random_singleton.module.methods.put(rand_sym, value.MethodEntry.builtin(&builtinRandomSingletonRand, .{ .variadic = 0 }));
    try random_singleton.module.methods.put(bytes_sym, value.MethodEntry.builtin(&builtinRandomSingletonBytes, .{ .exact = 1 }));
    try random_singleton.module.methods.put(seed_sym, value.MethodEntry.builtin(&builtinRandomSingletonSeed, .{ .exact = 0 }));
    try random_singleton.module.methods.put(random_number_sym, value.MethodEntry.builtin(&builtinRandomSingletonRandomNumber, .{ .variadic = 0 }));

    const new_seed_sym = try vm.intern("new_seed");
    try random_singleton.module.methods.put(new_seed_sym, value.MethodEntry.builtin(&builtinRandomSingletonNewSeed, .{ .exact = 0 }));

    const urandom_sym = try vm.intern("urandom");
    try random_singleton.module.methods.put(urandom_sym, value.MethodEntry.builtin(&builtinRandomSingletonUrandom, .{ .exact = 1 }));
}

fn nextSeed(vm: *VM) u64 {
    vm.random_counter +%= 0x9E3779B97F4A7C15;
    const now: u64 = @intCast(std.Io.Clock.boot.now(vm.io).nanoseconds);
    return now ^ (vm.random_counter *% 0xBF58476D1CE4E5B9);
}

fn nextPrng(vm: *VM) std.Random.DefaultPrng {
    return std.Random.DefaultPrng.init(nextSeed(vm));
}

fn randomFloat(vm: *VM) VMError!Value {
    var prng = nextPrng(vm);
    const n = prng.random().int(U53);
    return try vm.newFloat(@as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(std.math.maxInt(U53))));
}

fn randomIntegerBelow(vm: *VM, limit: i64) VMError!Value {
    if (limit <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{limit});
    }

    var prng = nextPrng(vm);
    const random_value = prng.random().intRangeLessThan(u64, 0, @intCast(limit));
    return Value.integer(@intCast(random_value));
}

fn bytesLengthArg(vm: *VM, arg: Value) VMError!usize {
    const len = try arg.integerArgToI64(vm, "no implicit conversion into Integer", "size too big");
    if (len < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});
    }
    return std.math.cast(usize, len) orelse return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});
}

fn randomBytes(vm: *VM, len: usize) VMError!Value {
    const bytes = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(bytes);

    var prng = nextPrng(vm);
    prng.random().bytes(bytes);
    return vm.newStringWithEncoding(bytes, false, .{ .ascii_8bit = .{} });
}

fn randomNumberFromArgs(vm: *VM, args: []Value) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 0 or args[0].isNil()) {
        return randomFloat(vm);
    }
    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }
    return randomIntegerBelow(vm, args[0].toInteger());
}

fn randomNumberFromReceiverBytes(vm: *VM, receiver: Value, args: []Value) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    if (args.len == 0 or args[0].isNil()) {
        var byte_args = [_]Value{Value.integer(8)};
        const byte_string = try vm.callMethodByName(receiver, "bytes", byte_args[0..], null);
        if (!byte_string.isString()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "bytes must return String", .{});
        }
        const str = byte_string.toStringObject().str;
        var buf: [8]u8 = [_]u8{0} ** 8;
        const copy_len = @min(str.len, buf.len);
        @memcpy(buf[0..copy_len], str[0..copy_len]);
        const raw = std.mem.readInt(u64, &buf, .little);
        const n: U53 = @intCast(raw & std.math.maxInt(U53));
        return try vm.newFloat(@as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(std.math.maxInt(U53))));
    }

    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const limit = args[0].toInteger();
    if (limit <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{limit});
    }

    var byte_args = [_]Value{Value.integer(8)};
    const byte_string = try vm.callMethodByName(receiver, "bytes", byte_args[0..], null);
    if (!byte_string.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "bytes must return String", .{});
    }
    const str = byte_string.toStringObject().str;
    var buf: [8]u8 = [_]u8{0} ** 8;
    const copy_len = @min(str.len, buf.len);
    @memcpy(buf[0..copy_len], str[0..copy_len]);
    const raw = std.mem.readInt(u64, &buf, .little);
    return Value.integer(@intCast(raw % @as(u64, @intCast(limit))));
}

pub fn builtinRandomInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const seed = if (args.len == 0) Value.integer(@intCast(nextSeed(vm))) else blk: {
        if (!args[0].isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        break :blk args[0];
    };
    try vm.setInstanceVariable(receiver, "@seed", seed);
    return receiver;
}

pub fn builtinRandomRand(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return randomNumberFromArgs(vm, args);
}

pub fn builtinRandomBytes(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return randomBytes(vm, try bytesLengthArg(vm, args[0]));
}

pub fn builtinRandomSeed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const seed = try vm.getInstanceVariable(receiver, "@seed");
    if (!seed.isNil()) return seed;
    return Value.integer(@intCast(nextSeed(vm)));
}

pub fn builtinRandomSingletonRand(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return randomNumberFromArgs(vm, args);
}

pub fn builtinRandomSingletonRandomNumber(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return randomNumberFromArgs(vm, args);
}

pub fn builtinRandomSingletonBytes(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return randomBytes(vm, try bytesLengthArg(vm, args[0]));
}

pub fn builtinRandomSingletonSeed(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(nextSeed(vm)));
}

pub fn builtinRandomSingletonNewSeed(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(nextSeed(vm)));
}

pub fn builtinRandomSingletonUrandom(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return randomBytes(vm, try bytesLengthArg(vm, args[0]));
}

pub fn builtinRandomFormatterRandomNumber(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return randomNumberFromReceiverBytes(vm, receiver, args);
}
