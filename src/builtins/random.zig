const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const kernel_builtin = @import("kernel.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

const U53 = u53;

const RandomSource = union(enum) {
    generator: *vm_mod.RubyRandom,
    receiver: Value,

    fn next(self: RandomSource, vm: *VM) VMError!u32 {
        return switch (self) {
            .generator => |generator| generator.next(),
            .receiver => |receiver| blk: {
                var args = [_]Value{Value.integer(4)};
                const bytes = try vm.callMethodByName(receiver, "bytes", &args, null);
                if (!bytes.isString()) return vm.raiseExceptionFmt(vm.type_error_class, "bytes must return String", .{});
                if (bytes.toStringObject().str.len != 4) return vm.raiseExceptionFmt(vm.range_error_class, "bytes must return 4 bytes", .{});
                break :blk std.mem.readInt(u32, bytes.toStringObject().str[0..4], .little);
            },
        };
    }

    fn below(self: RandomSource, vm: *VM, limit: u32) VMError!u32 {
        var mask = limit - 1;
        mask |= mask >> 1;
        mask |= mask >> 2;
        mask |= mask >> 4;
        mask |= mask >> 8;
        mask |= mask >> 16;
        while (true) {
            const number = (try self.next(vm)) & mask;
            if (number < limit) return number;
        }
    }
};

const RandomObject = struct {
    object: value.Object,
    seed: Value,
    generator: vm_mod.RubyRandom,
};

fn randomObject(receiver: Value) *RandomObject {
    return @fieldParentPtr("object", receiver.getObjectPointer().?);
}

pub fn register(vm: *VM) !void {
    vm.random_class.builtin_alloc_func = &builtinRandomAllocate;
    try vm.random_class.module.methods.put(try vm.intern("initialize_copy"), value.MethodEntry.builtinWithVisibility(&builtinRandomInitializeCopy, .{ .exact = 1 }, .private));
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

    const state_sym = try vm.intern("state");
    try vm.random_class.module.methods.put(state_sym, value.MethodEntry.builtinWithVisibility(&builtinRandomState, .{ .exact = 0 }, .private));

    const equal_sym = try vm.intern("==");
    try vm.random_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinRandomEqual, .{ .exact = 1 }));

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
    vm.default_random = try generatorFromSeed(vm, seed);
    return previous;
}

fn randomFloatFromSource(vm: *VM, state: RandomSource) VMError!Value {
    const n: U53 = (@as(U53, @intCast((try state.next(vm)) >> 5)) << 26) | @as(U53, @intCast((try state.next(vm)) >> 6));
    return vm.newFloat(@as(f64, @floatFromInt(n)) / 9007199254740992.0);
}

fn randomFloat(vm: *VM) VMError!Value {
    ensureDefaultRandom(vm);
    return randomFloatFromSource(vm, .{ .generator = &vm.default_random });
}

fn randomFloatBelow(vm: *VM, state: RandomSource, limit: f64) VMError!Value {
    if (!(limit > 0.0)) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
    const unit = try randomFloatFromSource(vm, state);
    return vm.newFloat(unit.toFloatObject().val * limit);
}

fn randomRange(vm: *VM, state: RandomSource, range_value: Value) VMError!Value {
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

fn randomIntegerValueBelow(vm: *VM, state: RandomSource, limit: Value) VMError!Value {
    if (limit.isInteger()) {
        const small_limit = limit.toInteger();
        if (small_limit <= 0) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{small_limit});
        }
        if (small_limit <= std.math.maxInt(u32)) {
            return Value.integer(try state.below(vm, @intCast(small_limit)));
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
            candidate.addScalar(&candidate, (try state.next(vm))) catch return error.Fatal;
        }
        if (remaining > 0) {
            candidate.shiftLeft(&candidate, remaining) catch return error.Fatal;
            const mask = (@as(u32, 1) << @intCast(remaining)) - 1;
            candidate.addScalar(&candidate, (try state.next(vm)) & mask) catch return error.Fatal;
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

    std.Io.randomSecure(vm.io, bytes) catch |err|
        return vm.raiseExceptionFmt(vm.runtime_error_class, "failed to obtain random bytes: {s}", .{@errorName(err)});
    return vm.newStringWithEncoding(bytes, false, .{ .ascii_8bit = .{} });
}

fn randomNumberFromArgs(vm: *VM, args: []Value) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    if (args.len == 0 or args[0].isNil()) {
        return randomFloat(vm);
    }
    if (args[0].isRange()) {
        ensureDefaultRandom(vm);
        return randomRange(vm, .{ .generator = &vm.default_random }, args[0]);
    }
    if (args[0].isFloat()) {
        ensureDefaultRandom(vm);
        return randomFloatBelow(vm, .{ .generator = &vm.default_random }, args[0].toFloatObject().val);
    }
    const limit = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer");
    ensureDefaultRandom(vm);
    return randomIntegerValueBelow(vm, .{ .generator = &vm.default_random }, limit);
}

fn randomNumberFromReceiverBytes(vm: *VM, receiver: Value, args: []Value) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const source = RandomSource{ .receiver = receiver };
    if (args.len == 0 or args[0].isNil()) return randomFloatFromSource(vm, source);
    const limit = args[0];
    if (limit.isRange()) return randomRange(vm, source, limit);
    if (limit.isFloat()) {
        const maximum = limit.toFloatObject().val;
        if (maximum <= 0) return randomFloatFromSource(vm, source);
        return randomFloatBelow(vm, source, maximum);
    }
    if (!limit.isInteger() and !limit.isBigInteger()) return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument", .{});
    if ((try vm.compareIntegerValues(limit, Value.integer(0))) != .gt) return randomFloatFromSource(vm, source);
    return randomIntegerValueBelow(vm, source, limit);
}

fn generatorFromSeed(vm: *VM, seed: Value) VMError!vm_mod.RubyRandom {
    var magnitude = try seed.integerToManaged(vm);
    defer magnitude.deinit();
    magnitude.setSign(true);
    const count = @max(1, (magnitude.bitCountAbs() + 31) / 32);
    const words = vm.allocator.alloc(u32, count) catch return error.Fatal;
    defer vm.allocator.free(words);
    for (words) |*word| {
        word.* = @truncate(magnitude.toConst().limbs[0]);
        magnitude.shiftRight(&magnitude, 32) catch return error.Fatal;
    }
    if (count == 1) return vm_mod.RubyRandom.init(words[0]);
    const length = if (words[count - 1] == 1) count - 1 else count;
    return vm_mod.RubyRandom.initWords(words[0..length]);
}

fn builtinRandomAllocate(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const seed = Value.integer(@intCast(nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1)));
    const object = vm.gc_allocator.create(RandomObject) catch return error.Fatal;
    object.* = .{
        .object = .{ .type_tag = .instance, .flags = 0, .class = receiver.toClassObject(), .singleton_class = null, .instance_variables = null },
        .seed = seed,
        .generator = try generatorFromSeed(vm, seed),
    };
    return Value.fromObject(&object.object);
}

fn builtinRandomInitializeCopy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = try kernel_builtin.builtinKernelInitializeCopy(vm, receiver, args, block);
    if (receiver.raw != args[0].raw) {
        randomObject(receiver).seed = randomObject(args[0]).seed;
        randomObject(receiver).generator = randomObject(args[0]).generator;
    }
    return receiver;
}

fn bytesFromState(vm: *VM, state: *vm_mod.RubyRandom, len: usize) VMError!Value {
    const bytes = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(bytes);
    var offset: usize = 0;
    while (offset < len) {
        var word = state.next();
        const end = @min(len, offset + 4);
        while (offset < end) : (offset += 1) {
            bytes[offset] = @truncate(word);
            word >>= 8;
        }
    }
    return vm.newStringWithEncoding(bytes, false, .{ .ascii_8bit = .{} });
}

pub fn builtinRandomInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    try vm.guardNotFrozen(receiver);
    const object = randomObject(receiver);
    const seed = if (args.len == 0)
        Value.integer(@intCast(nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1)))
    else
        try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer (to_int gives non-Integer)");
    object.generator = try generatorFromSeed(vm, seed);
    object.seed = seed;
    return receiver;
}

pub fn builtinRandomRand(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const state = RandomSource{ .generator = &randomObject(receiver).generator };
    if (args.len == 0 or args[0].isNil()) {
        return randomFloatFromSource(vm, state);
    }
    if (args[0].isRange()) return randomRange(vm, state, args[0]);
    if (args[0].isFloat()) {
        return randomFloatBelow(vm, state, args[0].toFloatObject().val);
    }
    const limit = try args[0].coerceToIntegerValue(vm, "no implicit conversion into Integer", "can't convert to Integer");
    return randomIntegerValueBelow(vm, state, limit);
}

pub fn builtinRandomBytes(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return bytesFromState(vm, &randomObject(receiver).generator, try bytesLengthArg(vm, args[0]));
}

pub fn builtinRandomSeed(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return randomObject(receiver).seed;
}

pub fn builtinRandomState(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    var integer = std.math.big.int.Managed.initSet(vm.allocator, 0) catch return error.Fatal;
    defer integer.deinit();
    const state = &randomObject(receiver).generator.state;
    var index: usize = state.len;
    while (index > 0) {
        index -= 1;
        integer.shiftLeft(&integer, 32) catch return error.Fatal;
        integer.addScalar(&integer, state[index]) catch return error.Fatal;
    }
    return vm.valueFromManagedInteger(&integer);
}

pub fn builtinRandomEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (vm.getClass(receiver) != vm.getClass(args[0])) return Value.boolean(false);
    const left = randomObject(receiver);
    const right = randomObject(args[0]);
    return Value.boolean(left.generator.index == right.generator.index and
        std.mem.eql(u32, &left.generator.state, &right.generator.state) and
        try vm.valueEquals(left.seed, right.seed));
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
    const len = try bytesLengthArg(vm, args[0]);
    ensureDefaultRandom(vm);
    return bytesFromState(vm, &vm.default_random, len);
}

pub fn builtinRandomSingletonSeed(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    ensureDefaultRandom(vm);
    return vm.default_random_seed;
}

pub fn builtinRandomSingletonNewSeed(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(nextSeed(vm) & (@as(u64, std.math.maxInt(i64)) >> 1)));
}

pub fn builtinRandomSingletonUrandom(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return randomBytes(vm, try bytesLengthArg(vm, args[0]));
}

pub fn builtinRandomFormatterRandomNumber(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return randomNumberFromReceiverBytes(vm, receiver, args);
}
