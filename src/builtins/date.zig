const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const Block = vm_mod.Block;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const date_name = try vm.intern("Date");
    if (vm.object_class.module.constants.contains(date_name)) return;

    const date_value = try vm.newClass(date_name, vm.object_class);
    const date_class = date_value.toClassObject();
    date_class.builtin_alloc_func = &builtinDateAllocate;
    try vm.setConstant(&vm.object_class.module, date_name, date_value);

    const datetime_name = try vm.intern("DateTime");
    const datetime_value = try vm.newClass(datetime_name, date_class);
    const datetime_class = datetime_value.toClassObject();
    datetime_class.builtin_alloc_func = &builtinDateTimeAllocate;
    try vm.setConstant(&vm.object_class.module, datetime_name, datetime_value);

    for ([_]*value.ClassObject{ date_class, datetime_class }) |class| {
        try class.module.methods.put(try vm.intern("inspect"), value.MethodEntry.builtin(&builtinDateInspect, .{ .exact = 0 }));
        try class.module.methods.put(try vm.intern("eql?"), value.MethodEntry.builtin(&builtinDateEql, .{ .exact = 1 }));
        try class.module.methods.put(try vm.intern("hash"), value.MethodEntry.builtin(&builtinDateHash, .{ .exact = 0 }));
    }
}

pub fn builtinDateAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return allocateDate(vm, receiver.toClassObject(), .date);
}

fn builtinDateTimeAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return allocateDate(vm, receiver.toClassObject(), .datetime);
}

fn allocateDate(vm: *VM, class: *value.ClassObject, kind: value.DateKind) VMError!Value {
    const zero = try vm.newRational(0, 1);
    return vm.newDate(class, Value.integer(0), zero, zero, Value.integer(2_299_161), kind);
}

fn builtinDateInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const date = receiver.toDateObject();
    const class_name = if (date.kind == .datetime) "DateTime" else "Date";
    const text = std.fmt.allocPrint(vm.gc_allocator, "#<{s}: day={d}>", .{ class_name, date.chronological_day.toInteger() }) catch return error.Fatal;
    return vm.newString(text, false);
}

fn builtinDateEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(receiver.eql(args[0]));
}

fn builtinDateHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@bitCast(receiver.hash()));
}
