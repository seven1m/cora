const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const enumerable_sym = try vm.intern("Enumerable");
    const enumerable_val = vm.object_class.module.constants.get(enumerable_sym) orelse return error.Fatal;
    const entries_sym = try vm.intern("entries");
    try enumerable_val.toModuleObject().methods.put(entries_sym, .{ .method = .{ .builtin = &builtinEnumerableEntries } });
    const map_sym = try vm.intern("map");
    try enumerable_val.toModuleObject().methods.put(map_sym, .{ .method = .{ .builtin = &builtinEnumerableMap } });
    const collect_sym = try vm.intern("collect");
    try enumerable_val.toModuleObject().methods.put(collect_sym, .{ .method = .{ .builtin = &builtinEnumerableMap } });
}

fn builtinEnumerableEntries(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.callMethodByName(receiver, "to_a", &.{}, null);
}

fn builtinEnumerableMap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const method_name = try vm.intern("map");
        if (try vm.checkCallMethodByName(receiver, "size", false, &.{}, null)) |size| {
            return vm.createMethodEnumeratorWithSize(receiver, method_name, &.{}, size);
        }
        return vm.createMethodEnumerator(receiver, method_name, &.{});
    };

    const enum_value = try vm.createMethodEnumerator(receiver, try vm.intern("each"), &.{});
    const out = try vm.createArray();

    while (true) {
        const next_values = vm.callMethodByName(enum_value, "next_values", &.{}, null) catch |err| {
            if (err == error.Unwind and vm.pending_exception != null and vm.pending_exception.?.object.class == vm.stop_iteration_class) {
                vm.pending_exception = null;
                break;
            }
            return err;
        };
        const yielded = next_values.toArrayObject().elements.items;
        const result = try vm.yieldToBlock(blk, yielded);
        if (result.controlFlowValue()) |return_value| return return_value;
        out.elements.append(vm.gc_allocator, result.value) catch return error.Fatal;
    }

    return Value.fromObject(out);
}
