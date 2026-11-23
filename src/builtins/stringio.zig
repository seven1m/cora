const io = @import("io.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const getc_sym = try vm.intern("getc");
    const getbyte_sym = try vm.intern("getbyte");
    const tty_q_sym = try vm.intern("tty?");
    const isatty_sym = try vm.intern("isatty");
    const stringio_name_sym = try vm.intern("StringIO");

    if (vm.object_class.module.constants.getPtr(stringio_name_sym)) |entry| {
        const stringio_class_val = entry.value;
        if (stringio_class_val.isClass()) {
            const stringio_class = stringio_class_val.toClassObject();
            try stringio_class.module.methods.put(
                getc_sym,
                value.MethodEntry.builtin(&builtinStringIOGetc, .{ .exact = 0 }),
            );
            try stringio_class.module.methods.put(
                getbyte_sym,
                value.MethodEntry.builtin(&builtinStringIOGetbyte, .{ .exact = 0 }),
            );

            try stringio_class.module.methods.put(try vm.intern("print"), value.MethodEntry.builtin(&builtinStringIOPrint, .{ .variadic = 0 }));
            try stringio_class.module.methods.put(try vm.intern("puts"), value.MethodEntry.builtin(&builtinStringIOPuts, .{ .variadic = 0 }));
            const tty_q_entry = value.MethodEntry.builtin(&builtinStringIOTtyQ, .{ .exact = 0 });
            try stringio_class.module.methods.put(tty_q_sym, tty_q_entry);
            try stringio_class.module.methods.put(isatty_sym, tty_q_entry);
        }
    }
}

pub fn builtinStringIOTtyQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(false);
}

pub fn builtinStringIOGetc(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    if ((try vm.getInstanceVariable(receiver, "@closed_read")).isTruthy()) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for reading", .{});
    }
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

    const encoding_val = try vm.getInstanceVariable(receiver, "@external_encoding");
    const encoding = if (encoding_val.isNil()) string_obj.encoding else encoding_val.toEncodingObject().encoding;
    var byte_index = pos;
    _ = encoding.nextChar(string_obj.str, &byte_index);
    if (byte_index == pos) byte_index += 1;
    const char_val = try vm.newStringWithEncoding(string_obj.str[pos..byte_index], false, encoding);

    const new_pos = @as(i64, @intCast(byte_index));
    try vm.setInstanceVariable(receiver, "@pos", Value.integer(new_pos));

    return char_val;
}

pub fn builtinStringIOGetbyte(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const closed_read_val = try vm.getInstanceVariable(receiver, "@closed_read");
    if (closed_read_val.isTrue()) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for reading", .{});
    }

    const string_val = try vm.getInstanceVariable(receiver, "@string");
    if (!string_val.isString()) {
        return vm.raiseNoMethod(receiver, "getbyte");
    }

    const string_obj = string_val.toStringObject();

    const pos_val = try vm.getInstanceVariable(receiver, "@pos");
    if (!pos_val.isInteger()) {
        return vm.raiseNoMethod(receiver, "getbyte");
    }

    const pos = @as(usize, @intCast(pos_val.toInteger()));

    if (pos >= string_obj.str.len) {
        return Value.nil();
    }

    const byte = string_obj.str[pos];
    const new_pos = pos + 1;
    try vm.setInstanceVariable(receiver, "@pos", Value.integer(@as(i64, @intCast(new_pos))));

    return Value.integer(@as(i64, @intCast(byte)));
}
fn requireWritable(vm: *VM, receiver: Value) VMError!void {
    if ((try vm.getInstanceVariable(receiver, "@closed_write")).isTruthy()) {
        return vm.raiseExceptionFmt(vm.io_error_class, "not opened for writing", .{});
    }
}

fn builtinStringIOPrint(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try requireWritable(vm, receiver);
    return io.printValues(vm, receiver, args);
}

fn builtinStringIOPuts(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try requireWritable(vm, receiver);
    return io.putsValues(vm, receiver, args);
}
