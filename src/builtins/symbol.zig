const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.symbol_class.module.methods.put(to_s_sym, .{ .builtin = &builtinSymbolToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.symbol_class.module.methods.put(inspect_sym, .{ .builtin = &builtinSymbolInspect });
}

pub fn builtinSymbolToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const str = std.fmt.allocPrint(vm.gc_allocator, "{s}", .{receiver.data.symbol.name}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinSymbolInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const str = std.fmt.allocPrint(vm.gc_allocator, ":{s}", .{receiver.data.symbol.name}) catch return error.Fatal;
    return try vm.newString(str, false);
}
