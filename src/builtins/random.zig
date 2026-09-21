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
    const srand_sym = try vm.intern("srand");
    try random_singleton.module.methods.put(srand_sym, value.MethodEntry.builtin(&builtinRandomSingletonSrand, .{ .variadic = 0 }));
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

fn ensureDefaultRandom(vm: *VM) void {
    if (!vm.default_random_seed.isNil()) return;
    const seed = nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1);
    vm.default_random_seed = Value.integer(@intCast(seed));
    vm.default_random = vm_mod.RubyRandom.init(seed);
}

pub fn srand(vm: *VM, args: []Value) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    ensureDefaultRandom(vm);
    const previous = vm.default_random_seed;
    const seed = if (args.len == 0)
        Value.integer(@intCast(nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1)))
    else
        try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer (to_int gives non-Integer)");
    vm.default_random_seed = seed;
    vm.default_random = vm_mod.RubyRandom.init(seed.hash());
    return previous;
}

fn randomFloatFromState(vm: *VM, state: *vm_mod.RubyRandom) VMError!Value {
    const n: U53 = (@as(U53, @intCast(state.next() >> 5)) << 26) | @as(U53, @intCast(state.next() >> 6));
    return vm.newFloat(@as(f64, @floatFromInt(n)) / 9007199254740992.0);
}

fn randomFloat(vm: *VM) VMError!Value {
    ensureDefaultRandom(vm);
    return randomFloatFromState(vm, &vm.default_random);
}

fn randomFloatBelow(vm: *VM, state: *vm_mod.RubyRandom, limit: f64) VMError!Value {
    if (!(limit > 0.0)) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
    const unit = try randomFloatFromState(vm, state);
    return vm.newFloat(unit.toFloatObject().val * limit);
}

fn randomRange(vm: *VM, state: *vm_mod.RubyRandom, range_value: Value) VMError!Value {
    const range = range_value.toRangeObject();
    if (range.begin.isNil() or range.end.isNil()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
    }

    var subtract_args = [_]Value{range.begin};
    const width = vm.callMethodByName(range.end, "-", &subtract_args, null) catch |err| switch (err) {
        error.Unwind => {
            if (vm.pendingException()) |exc| {
                if (exc.object.class == vm.no_method_error_class) {
                    vm.setPendingException(null);
                    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
                }
            }
            return error.Unwind;
        },
        else => return err,
    };

    const offset = if (width.isFloat())
        try randomFloatBelow(vm, state, width.toFloatObject().val)
    else blk: {
        var integer_width = try width.coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer");
        if (!range.exclude_end) integer_width = try vm.addIntegerValues(integer_width, Value.integer(1));
        break :blk try randomIntegerValueBelow(vm, state, integer_width);
    };

    var add_args = [_]Value{offset};
    return vm.callMethodByName(range.begin, "+", &add_args, null) catch |err| switch (err) {
        error.Unwind => {
            if (vm.pendingException()) |exc| {
                if (exc.object.class == vm.no_method_error_class) {
                    vm.setPendingException(null);
                    return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
                }
            }
            return error.Unwind;
        },
        else => return err,
    };
}

fn randomIntegerBelow(vm: *VM, limit: i64) VMError!Value {
    if (limit <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{limit});
    }

    ensureDefaultRandom(vm);
    const random_value = vm.default_random.below(@intCast(limit));
    return Value.integer(@intCast(random_value));
}

fn randomIntegerValueBelow(vm: *VM, state: *vm_mod.RubyRandom, limit: Value) VMError!Value {
    if (limit.isInteger()) {
        const small_limit = limit.toInteger();
        if (small_limit <= 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{small_limit});
        }
        if (small_limit <= std.math.maxInt(u32)) {
            return Value.integer(state.below(@intCast(small_limit)));
        }
    } else if (!limit.toBigIntegerObject().value.isPositive()) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
    }

    var managed_limit = try limit.integerToManaged(vm);
    defer managed_limit.deinit();
    const bit_count = managed_limit.bitCountAbs();

    while (true) {
        var candidate = std.math.big.int.Managed.initSet(vm.allocator, 0) catch return error.Fatal;
        defer candidate.deinit();

        var remaining = bit_count;
        while (remaining >= 32) : (remaining -= 32) {
            candidate.shiftLeft(&candidate, 32) catch return error.Fatal;
            candidate.addScalar(&candidate, state.next()) catch return error.Fatal;
        }
        if (remaining > 0) {
            candidate.shiftLeft(&candidate, remaining) catch return error.Fatal;
            const mask = (@as(u32, 1) << @intCast(remaining)) - 1;
            candidate.addScalar(&candidate, state.next() & mask) catch return error.Fatal;
        }

        if (std.math.big.int.Managed.order(candidate, managed_limit) == .lt) {
            return vm.valueFromManagedInteger(&candidate);
        }
    }
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
    if (args[0].isRange()) {
        ensureDefaultRandom(vm);
        return randomRange(vm, &vm.default_random, args[0]);
    }
    if (args[0].isFloat()) {
        ensureDefaultRandom(vm);
        return randomFloatBelow(vm, &vm.default_random, args[0].toFloatObject().val);
    }
    const limit = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer");
    ensureDefaultRandom(vm);
    return randomIntegerValueBelow(vm, &vm.default_random, limit);
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
    const seed = if (args.len == 0) Value.integer(@intCast(nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1))) else blk: {
        if (!args[0].isInteger()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
        }
        break :blk args[0];
    };
    try vm.setInstanceVariable(receiver, "@seed", seed);
    vm.random_states.put(receiver.raw, vm_mod.RubyRandom.init(seed.hash())) catch return error.Fatal;
    return receiver;
}

pub fn builtinRandomRand(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const state = vm.random_states.getPtr(receiver.raw) orelse return randomNumberFromArgs(vm, args);
    if (args.len == 0 or args[0].isNil()) {
        return randomFloatFromState(vm, state);
    }
    if (args[0].isRange()) return randomRange(vm, state, args[0]);
    if (args[0].isFloat()) {
        return randomFloatBelow(vm, state, args[0].toFloatObject().val);
    }
    const limit = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer");
    return randomIntegerValueBelow(vm, state, limit);
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

pub fn builtinRandomSingletonSrand(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return srand(vm, args);
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
