const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const equal_sym = try vm.intern("==");
    try vm.symbol_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinSymbolEqual } });

    const to_s_sym = try vm.intern("to_s");
    try vm.symbol_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinSymbolToS } });

    const to_sym_sym = try vm.intern("to_sym");
    try vm.symbol_class.module.methods.put(to_sym_sym, .{ .method = .{ .builtin = &builtinSymbolToSym } });

    const intern_sym = try vm.intern("intern");
    try vm.symbol_class.module.methods.put(intern_sym, .{ .method = .{ .builtin = &builtinSymbolToSym } });

    const inspect_sym = try vm.intern("inspect");
    try vm.symbol_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinSymbolInspect } });

    const to_proc_sym = try vm.intern("to_proc");
    try vm.symbol_class.module.methods.put(to_proc_sym, .{ .method = .{ .builtin = &builtinSymbolToProc } });

    const encoding_sym = try vm.intern("encoding");
    try vm.symbol_class.module.methods.put(encoding_sym, .{ .method = .{ .builtin = &builtinSymbolEncoding } });

    const length_sym = try vm.intern("length");
    try vm.symbol_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinSymbolLength } });

    const size_sym = try vm.intern("size");
    try vm.symbol_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinSymbolLength } });
}

pub fn builtinSymbolEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isSymbol()) return Value.boolean(false);
    return Value.boolean(receiver.toSymbolObject() == other.toSymbolObject());
}

pub fn builtinSymbolToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = receiver.toSymbolObject();
    const out = try vm.newStringWithEncoding(sym.name, false, sym.encoding);
    out.toStringObject().symbol_to_s_source = sym;
    return out;
}

pub fn builtinSymbolInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const str = std.fmt.allocPrint(vm.gc_allocator, ":{s}", .{receiver.toSymbolObject().name}) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinSymbolToSym(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinSymbolToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.newProc(.{
        .kind = .{ .symbol = receiver.toSymbolObject() },
    });
}

pub fn builtinSymbolEncoding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.encodingToValue(receiver.toSymbolObject().encoding);
}

pub fn builtinSymbolLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = receiver.toSymbolObject();
    return Value.integer(@intCast(sym.encoding.charCount(sym.name)));
}
