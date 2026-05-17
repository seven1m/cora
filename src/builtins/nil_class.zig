const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const to_s_sym = try vm.intern("to_s");
    try vm.nil_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinNilClassToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.nil_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinNilClassInspect, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.nil_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinNilClassEqual, .{ .exact = 1 }));

    const and_sym = try vm.intern("&");
    try vm.nil_class.module.methods.put(and_sym, value.MethodEntry.builtin(&builtinNilClassAnd, .{ .exact = 1 }));

    const or_sym = try vm.intern("|");
    try vm.nil_class.module.methods.put(or_sym, value.MethodEntry.builtin(&builtinNilClassOr, .{ .exact = 1 }));

    const xor_sym = try vm.intern("^");
    try vm.nil_class.module.methods.put(xor_sym, value.MethodEntry.builtin(&builtinNilClassXor, .{ .exact = 1 }));

    const nil_sym = try vm.intern("nil?");
    try vm.nil_class.module.methods.put(nil_sym, value.MethodEntry.builtin(&builtinNilClassNil, .{ .exact = 0 }));

    const eql_sym = try vm.intern("eql?");
    try vm.nil_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinNilClassEql, .{ .exact = 1 }));

    const to_i_sym = try vm.intern("to_i");
    try vm.nil_class.module.methods.put(to_i_sym, value.MethodEntry.builtin(&builtinNilClassToI, .{ .exact = 0 }));

    const to_f_sym = try vm.intern("to_f");
    try vm.nil_class.module.methods.put(to_f_sym, value.MethodEntry.builtin(&builtinNilClassToF, .{ .exact = 0 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.nil_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinNilClassToA, .{ .exact = 0 }));

    const to_h_sym = try vm.intern("to_h");
    try vm.nil_class.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinNilClassToH, .{ .exact = 0 }));
}

pub fn builtinNilClassToS(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.getOrCreateCanonicalFString("", .{ .utf8 = .{} });
}

pub fn builtinNilClassInspect(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    return try vm.getOrCreateCanonicalFString("nil", .{ .utf8 = .{} });
}

pub fn builtinNilClassEqual(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isNil());
}

pub fn builtinNilClassAnd(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(false);
}

pub fn builtinNilClassOr(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].is_truthy());
}

pub fn builtinNilClassXor(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].is_truthy());
}

pub fn builtinNilClassNil(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(true);
}

pub fn builtinNilClassEql(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.boolean(args[0].isNil());
}

pub fn builtinNilClassToI(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(0);
}

pub fn builtinNilClassToF(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.newFloat(0.0);
}

pub fn builtinNilClassToA(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = try vm.createArray();
    return Value.fromObject(&array.object);
}

pub fn builtinNilClassToH(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash = try vm.createHash();
    return Value.fromObject(&hash.object);
}
