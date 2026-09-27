const bdwgc = @import("bdwgc");
const std = @import("std");

const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;

const Stat = struct {
    name: []const u8,
    value: i64,
};

// Boehm GC performs collection automatically; there is no hook for forcing a
// collection on every allocation, so stress mode is tracked as a flag only.
var stress_mode: bool = false;

pub fn register(vm: *VM) !void {
    const gc_name = try vm.intern("GC");
    const gc_value = try vm.newModule(gc_name);
    const gc_module = gc_value.toModuleObject();
    try vm.setConstant(&vm.object_class.module, gc_name, gc_value);

    const singleton = try vm.getOrCreateSingletonClass(gc_value);
    const start_sym = try vm.intern("start");
    try singleton.module.methods.put(start_sym, value.MethodEntry.keywordBuiltin(&builtinGCStart, .{ .exact = 0 }));
    const stat_sym = try vm.intern("stat");
    try singleton.module.methods.put(stat_sym, value.MethodEntry.builtin(&builtinGCStat, .{ .variadic = 0 }));
    const count_sym = try vm.intern("count");
    try singleton.module.methods.put(count_sym, value.MethodEntry.builtin(&builtinGCCount, .{ .exact = 0 }));
    const total_time_sym = try vm.intern("total_time");
    try singleton.module.methods.put(total_time_sym, value.MethodEntry.builtin(&builtinGCTotalTime, .{ .exact = 0 }));
    const stress_sym = try vm.intern("stress");
    try singleton.module.methods.put(stress_sym, value.MethodEntry.builtin(&builtinGCStress, .{ .exact = 0 }));
    const set_stress_sym = try vm.intern("stress=");
    try singleton.module.methods.put(set_stress_sym, value.MethodEntry.builtin(&builtinGCSetStress, .{ .exact = 1 }));

    const garbage_collect_sym = try vm.intern("garbage_collect");
    try gc_module.methods.put(garbage_collect_sym, value.MethodEntry.keywordBuiltin(&builtinGCStart, .{ .exact = 0 }));
}

fn builtinGCStart(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    bdwgc.c.GC_gcollect();
    try vm.runObjectFinalizers(false);
    return Value.nil();
}

fn stats() [4]Stat {
    const word_size = @sizeOf(usize);
    return .{
        .{ .name = "count", .value = @intCast(bdwgc.c.GC_get_gc_no()) },
        .{ .name = "major_gc_count", .value = @intCast(bdwgc.c.GC_get_gc_no()) },
        .{ .name = "heap_free_slots", .value = @intCast(bdwgc.c.GC_get_free_bytes() / word_size) },
        // Boehm does not expose an allocated-object count. Cumulative allocated
        // bytes expressed as pointer-sized slots is the closest monotonic value.
        .{ .name = "total_allocated_objects", .value = @intCast(bdwgc.c.GC_get_total_bytes() / word_size) },
    };
}

fn builtinGCCount(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(bdwgc.c.GC_get_gc_no()));
}

fn builtinGCTotalTime(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    // Boehm exposes no cumulative GC CPU time, so report monotonic clock
    // nanoseconds: an Integer that never decreases across collections.
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(.MONOTONIC, &timespec) != 0) {
        return Value.integer(0);
    }
    const seconds: i128 = @intCast(timespec.sec);
    const nanoseconds: i128 = @intCast(timespec.nsec);
    const total: i128 = seconds * 1_000_000_000 + nanoseconds;
    return Value.integer(@intCast(total));
}

fn builtinGCStress(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(stress_mode);
}

fn builtinGCSetStress(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    stress_mode = args[0].isTruthy();
    return Value.boolean(stress_mode);
}

fn statByName(name: []const u8) ?i64 {
    for (stats()) |stat| {
        if (std.mem.eql(u8, stat.name, name)) return stat.value;
    }
    return null;
}

fn builtinGCStat(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    if (args.len == 1 and args[0].isSymbol()) {
        const name = args[0].toSymbolObject().name;
        const result = statByName(name) orelse
            return vm.raiseExceptionFmt(vm.argument_error_class, "unknown key: {s}", .{name});
        return Value.integer(result);
    }

    const result = if (args.len == 0)
        try vm.createHash()
    else if (args[0].isHash())
        args[0].toHashObject()
    else
        return vm.raiseExceptionFmt(vm.type_error_class, "non-hash or symbol given", .{});

    for (stats()) |stat| {
        const key = try vm.intern(stat.name);
        try vm.hashSetEntry(result, Value.fromObject(&key.object), Value.integer(stat.value));
    }
    return Value.fromObject(&result.object);
}
