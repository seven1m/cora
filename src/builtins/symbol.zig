const std = @import("std");
const inspect_util = @import("../inspect.zig");
const vm_mod = @import("../vm.zig");
const string_builtin = @import("string.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const equal_sym = try vm.intern("==");
    try vm.symbol_class.module.methods.put(equal_sym, .{ .method = .{ .builtin = &builtinSymbolEqual } });

    const compare_sym = try vm.intern("<=>");
    try vm.symbol_class.module.methods.put(compare_sym, .{ .method = .{ .builtin = &builtinSymbolCompare } });

    const to_s_sym = try vm.intern("to_s");
    try vm.symbol_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinSymbolToS } });

    const id2name_sym = try vm.intern("id2name");
    try vm.symbol_class.module.methods.put(id2name_sym, .{ .method = .{ .builtin = &builtinSymbolToS } });

    const to_sym_sym = try vm.intern("to_sym");
    try vm.symbol_class.module.methods.put(to_sym_sym, .{ .method = .{ .builtin = &builtinSymbolIdentity } });

    const intern_sym = try vm.intern("intern");
    try vm.symbol_class.module.methods.put(intern_sym, .{ .method = .{ .builtin = &builtinSymbolIdentity } });

    const name_sym = try vm.intern("name");
    try vm.symbol_class.module.methods.put(name_sym, .{ .method = .{ .builtin = &builtinSymbolName } });

    const inspect_sym = try vm.intern("inspect");
    try vm.symbol_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinSymbolInspect } });

    const match_op_sym = try vm.intern("=~");
    try vm.symbol_class.module.methods.put(match_op_sym, .{ .method = .{ .builtin = &builtinSymbolMatchOp } });

    const match_sym = try vm.intern("match");
    try vm.symbol_class.module.methods.put(match_sym, .{ .method = .{ .builtin = &builtinSymbolMatch } });

    const match_q_sym = try vm.intern("match?");
    try vm.symbol_class.module.methods.put(match_q_sym, .{ .method = .{ .builtin = &builtinSymbolMatchQ } });

    const dup_sym = try vm.intern("dup");
    try vm.symbol_class.module.methods.put(dup_sym, .{ .method = .{ .builtin = &builtinSymbolIdentity } });

    const to_proc_sym = try vm.intern("to_proc");
    try vm.symbol_class.module.methods.put(to_proc_sym, .{ .method = .{ .builtin = &builtinSymbolToProc } });

    const encoding_sym = try vm.intern("encoding");
    try vm.symbol_class.module.methods.put(encoding_sym, .{ .method = .{ .builtin = &builtinSymbolEncoding } });

    const length_sym = try vm.intern("length");
    try vm.symbol_class.module.methods.put(length_sym, .{ .method = .{ .builtin = &builtinSymbolLength } });

    const size_sym = try vm.intern("size");
    try vm.symbol_class.module.methods.put(size_sym, .{ .method = .{ .builtin = &builtinSymbolLength } });

    const element_reference_sym = try vm.intern("[]");
    try vm.symbol_class.module.methods.put(element_reference_sym, .{ .method = .{ .builtin = &builtinSymbolElementReference } });

    const slice_sym = try vm.intern("slice");
    try vm.symbol_class.module.methods.put(slice_sym, .{ .method = .{ .builtin = &builtinSymbolElementReference } });

    const empty_sym = try vm.intern("empty?");
    try vm.symbol_class.module.methods.put(empty_sym, .{ .method = .{ .builtin = &builtinSymbolEmpty } });

    const start_with_sym = try vm.intern("start_with?");
    try vm.symbol_class.module.methods.put(start_with_sym, .{ .method = .{ .builtin = &builtinSymbolStartWith } });

    const end_with_sym = try vm.intern("end_with?");
    try vm.symbol_class.module.methods.put(end_with_sym, .{ .method = .{ .builtin = &builtinSymbolEndWith } });

    const succ_sym = try vm.intern("succ");
    try vm.symbol_class.module.methods.put(succ_sym, .{ .method = .{ .builtin = &builtinSymbolSucc } });

    const next_sym = try vm.intern("next");
    try vm.symbol_class.module.methods.put(next_sym, .{ .method = .{ .builtin = &builtinSymbolSucc } });

    const downcase_sym = try vm.intern("downcase");
    try vm.symbol_class.module.methods.put(downcase_sym, .{ .method = .{ .builtin = &builtinSymbolDowncase } });

    const swapcase_sym = try vm.intern("swapcase");
    try vm.symbol_class.module.methods.put(swapcase_sym, .{ .method = .{ .builtin = &builtinSymbolSwapcase } });

    const upcase_sym = try vm.intern("upcase");
    try vm.symbol_class.module.methods.put(upcase_sym, .{ .method = .{ .builtin = &builtinSymbolUpcase } });

    const capitalize_sym = try vm.intern("capitalize");
    try vm.symbol_class.module.methods.put(capitalize_sym, .{ .method = .{ .builtin = &builtinSymbolCapitalize } });

    const casecmp_sym = try vm.intern("casecmp");
    try vm.symbol_class.module.methods.put(casecmp_sym, .{ .method = .{ .builtin = &builtinSymbolCasecmp } });

    const casecmp_q_sym = try vm.intern("casecmp?");
    try vm.symbol_class.module.methods.put(casecmp_q_sym, .{ .method = .{ .builtin = &builtinSymbolCasecmpQ } });
}

pub fn builtinSymbolEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isSymbol()) return Value.boolean(false);
    return Value.boolean(receiver.toSymbolObject() == other.toSymbolObject());
}

pub fn builtinSymbolCompare(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isSymbol()) return Value.nil();

    const lhs = receiver.toSymbolObject();
    const rhs = other.toSymbolObject();
    const lhs_string = value.StringObject{
        .object = undefined,
        .str = lhs.name,
        .encoding = lhs.encoding,
    };
    const rhs_string = value.StringObject{
        .object = undefined,
        .str = rhs.name,
        .encoding = rhs.encoding,
    };
    return string_builtin.compareStringObjects(&lhs_string, &rhs_string);
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

    const sym = receiver.toSymbolObject();
    const target_encoding = vm.inspectTargetEncoding();
    if (inspect_util.isBareInspectableSymbol(sym, target_encoding)) {
        const str = std.fmt.allocPrint(vm.gc_allocator, ":{s}", .{sym.name}) catch return error.Fatal;
        return try vm.newStringWithEncoding(str, false, sym.encoding);
    }

    const inspected = inspect_util.inspectSymbolBytes(vm.allocator, sym.name, sym.encoding, target_encoding) catch return error.Fatal;
    defer vm.allocator.free(inspected);

    const str = std.fmt.allocPrint(vm.gc_allocator, ":{s}", .{inspected}) catch return error.Fatal;
    return try vm.newStringWithEncoding(str, false, target_encoding);
}

fn symbolStringView(vm: *VM, sym: *value.SymbolObject) value.StringObject {
    return .{
        .object = .{
            .type_tag = .string,
            .flags = 0,
            .class = vm.string_class,
            .singleton_class = null,
            .instance_variables = null,
        },
        .str = sym.name,
        .encoding = sym.encoding,
        .validity = .unknown,
        .chilled_literal = false,
        .symbol_to_s_source = sym,
    };
}

pub fn builtinSymbolIdentity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

pub fn builtinSymbolName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = receiver.toSymbolObject();
    return vm.getOrCreateCanonicalFString(sym.name, sym.encoding);
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

pub fn builtinSymbolElementReference(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const sym = receiver.toSymbolObject();
    var string_view = symbolStringView(vm, sym);
    return string_builtin.builtinStringSlice(vm, Value.fromObject(&string_view), args, null);
}

pub fn builtinSymbolEmpty(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = receiver.toSymbolObject();
    return Value.boolean(sym.encoding.charCount(sym.name) == 0);
}

pub fn builtinSymbolStartWith(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = block;
    const sym = receiver.toSymbolObject();
    return string_builtin.stringLikeStartWith(vm, receiver, sym.name, sym.encoding, args);
}

pub fn builtinSymbolEndWith(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = block;
    const sym = receiver.toSymbolObject();
    return string_builtin.stringLikeEndWith(vm, sym.name, sym.encoding, args);
}

pub fn builtinSymbolMatchOp(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const sym = receiver.toSymbolObject();
    var string_view = symbolStringView(vm, sym);
    return string_builtin.builtinStringMatchOp(vm, Value.fromObject(&string_view), args, block);
}

pub fn builtinSymbolMatch(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const sym = receiver.toSymbolObject();
    var string_view = symbolStringView(vm, sym);
    return string_builtin.builtinStringMatch(vm, Value.fromObject(&string_view), args, block);
}

pub fn builtinSymbolMatchQ(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = block;
    const sym = receiver.toSymbolObject();
    var string_view = symbolStringView(vm, sym);
    return string_builtin.builtinStringMatchQ(vm, Value.fromObject(&string_view), args, null);
}

pub fn builtinSymbolSucc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const sym = receiver.toSymbolObject();
    const next_bytes = try string_builtin.stringNextBytes(vm, sym.name);
    const out = try vm.internWithEncoding(next_bytes, sym.encoding);
    return Value.fromObject(out);
}

pub fn builtinSymbolUpcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return mapSymbolCase(vm, receiver, args, .upcase);
}

pub fn builtinSymbolDowncase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return mapSymbolCase(vm, receiver, args, .downcase);
}

pub fn builtinSymbolSwapcase(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return mapSymbolCase(vm, receiver, args, .swapcase);
}

pub fn builtinSymbolCapitalize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return mapSymbolCase(vm, receiver, args, .capitalize);
}

fn mapSymbolCase(
    vm: *VM,
    receiver: Value,
    args: []Value,
    operation: string_builtin.CaseOperation,
) VMError!Value {
    const sym = receiver.toSymbolObject();
    const mapped = try string_builtin.mapStringCase(vm, sym.name, sym.encoding, args, operation);
    const mapped_sym = try vm.internWithEncoding(mapped.bytes, mapped.encoding);
    return Value.fromObject(mapped_sym);
}

fn symbolCasecmpOrder(vm: *VM, lhs: *const value.SymbolObject, rhs: *const value.SymbolObject, fold: bool) VMError!?i64 {
    const lhs_string = value.StringObject{
        .object = undefined,
        .str = lhs.name,
        .encoding = lhs.encoding,
    };
    const rhs_string = value.StringObject{
        .object = undefined,
        .str = rhs.name,
        .encoding = rhs.encoding,
    };
    return string_builtin.casecmpOrder(vm, &lhs_string, &rhs_string, fold);
}

pub fn builtinSymbolCasecmp(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toSymbolObject();
    const other = args[0];
    if (!other.isSymbol()) return Value.nil();

    const rhs = other.toSymbolObject();
    const order = try symbolCasecmpOrder(vm, lhs, rhs, false) orelse return Value.nil();
    return Value.integer(order);
}

pub fn builtinSymbolCasecmpQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const lhs = receiver.toSymbolObject();
    const other = args[0];
    if (!other.isSymbol()) return Value.nil();

    const rhs = other.toSymbolObject();
    const order = try symbolCasecmpOrder(vm, lhs, rhs, true) orelse return Value.nil();
    return Value.boolean(order == 0);
}
