const enc = @import("../encoding.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const getc_sym = try vm.intern("getc");
    const stringio_name_sym = try vm.intern("StringIO");

    if (vm.object_class.module.constants.getPtr(stringio_name_sym)) |entry| {
        const stringio_class_val = entry.value;
        if (stringio_class_val.isClass()) {
            const stringio_class = stringio_class_val.toClassObject();
            try stringio_class.module.methods.put(
                getc_sym,
                value.MethodEntry.builtin(&builtinStringIOGetc, .{ .exact = 0 }),
            );
        }
    }
}

pub fn builtinStringIOGetc(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const string_val = try vm.getInstanceVariable(receiver, "@string");
    if (!string_val.isString()) {
        return vm.raiseNoMethod(receiver, "getc");
    }

    const string_obj = string_val.toStringObject();

    const pos_val = try vm.getInstanceVariable(receiver, "@pos");
    if (!pos_val.isInteger()) {
        return vm.raiseNoMethod(receiver, "getc");
    }

    const pos = @as(usize, @intCast(pos_val.toInteger()));

    if (pos >= string_obj.str.len) {
        return Value.nil();
    }

    var byte_index = pos;
    const result = string_obj.encoding.nextChar(string_obj.str, &byte_index);

    if (!result.valid or result.len == 0) {
        return Value.nil();
    }

    const char_bytes = string_obj.str[pos..byte_index];
    const char_val = try vm.newString(char_bytes, false);

    const new_pos = @as(i64, @intCast(byte_index));
    try vm.setInstanceVariable(receiver, "@pos", Value.integer(new_pos));

    return char_val;
}