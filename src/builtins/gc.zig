const bdwgc = @import("bdwgc");
const std = @import("std");

const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

const Stat = struct {
    name: []const u8,
    value: i64,
};

pub fn register(vm: *VM) !void {
    const gc_name = try vm.intern("GC");
    const gc_value = try vm.newModule(gc_name);
    const gc_module = gc_value.toModuleObject();
    try vm.setConstant(&vm.object_class.module, gc_name, gc_value);

    const singleton = try vm.getOrCreateSingletonClass(gc_value);
    const start_sym = try vm.intern("start");
    try singleton.module.methods.put(start_sym, value.MethodEntry.builtin(&builtinGCStart, .{ .exact = 0 }));
    const stat_sym = try vm.intern("stat");
    try singleton.module.methods.put(stat_sym, value.MethodEntry.builtin(&builtinGCStat, .{ .variadic = 0 }));

    const garbage_collect_sym = try vm.intern("garbage_collect");
    try gc_module.methods.put(garbage_collect_sym, value.MethodEntry.builtin(&builtinGCStart, .{ .exact = 0 }));
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
