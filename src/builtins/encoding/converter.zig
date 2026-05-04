const enc = @import("../../encoding.zig");
const vm_mod = @import("../../vm.zig");
const value = @import("../../value.zig");
const encoding_builtin = @import("../encoding.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const converter_const_sym = try vm.intern("Converter");
    if (vm.encoding_class.module.constants.get(converter_const_sym)) |converter_entry| {
        const initialize_sym = try vm.intern("initialize");
        try converter_entry.value.toClassObject().module.methods.put(initialize_sym, .{ .method = .{ .builtin = &builtinEncodingConverterInitialize } });
    }
}

fn resolveEncodingArg(vm: *VM, arg: Value) VMError!enc.Encoding {
    if (arg.isEncoding()) return arg.toEncodingObject().encoding;
    var find_args = [_]Value{arg};
    const result = try encoding_builtin.builtinEncodingFind(vm, Value.nil(), find_args[0..], null);
    return result.toEncodingObject().encoding;
}

pub fn builtinEncodingConverterInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 2, 3);
    const from_encoding = try resolveEncodingArg(vm, args[0]);
    const to_encoding = try resolveEncodingArg(vm, args[1]);

    if (enc.converterAvailability(from_encoding, to_encoding) == .available) {
        return receiver;
    }

    return vm.raiseExceptionFmt(vm.encoding_converter_not_found_error_class, "code converter not found", .{});
}
