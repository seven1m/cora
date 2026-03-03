const vm_mod = @import("../../vm.zig");
const value = @import("../../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const converter_const_sym = try vm.intern("Converter");
    if (vm.encoding_class.module.constants.get(converter_const_sym)) |converter_val| {
        const initialize_sym = try vm.intern("initialize");
        try converter_val.toClassObject().module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinEncodingConverterInitialize } });
    }
}

pub fn builtinEncodingConverterInitialize(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);
    return vm.raiseExceptionFmt(vm.encoding_converter_not_found_error_class, "code converter not found", .{});
}
