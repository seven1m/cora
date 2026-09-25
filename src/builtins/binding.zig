const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodEntry = value.MethodEntry;

pub fn register(vm: *VM) !void {
    const eval_sym = try vm.intern("eval");
    try vm.binding_class.module.methods.put(eval_sym, MethodEntry.builtin(&builtinBindingEval, .{ .variadic = 1 }));

    const local_variables_sym = try vm.intern("local_variables");
    try vm.binding_class.module.methods.put(local_variables_sym, MethodEntry.builtin(&builtinBindingLocalVariables, .{ .exact = 0 }));

    const local_variable_defined_sym = try vm.intern("local_variable_defined?");
    try vm.binding_class.module.methods.put(local_variable_defined_sym, MethodEntry.builtin(&builtinBindingLocalVariableDefined, .{ .exact = 1 }));

    const local_variable_set_sym = try vm.intern("local_variable_set");
    try vm.binding_class.module.methods.put(local_variable_set_sym, MethodEntry.builtin(&builtinBindingLocalVariableSet, .{ .exact = 2 }));

    const local_variable_get_sym = try vm.intern("local_variable_get");
    try vm.binding_class.module.methods.put(local_variable_get_sym, MethodEntry.builtin(&builtinBindingLocalVariableGet, .{ .exact = 1 }));

    const receiver_sym = try vm.intern("receiver");
    try vm.binding_class.module.methods.put(receiver_sym, MethodEntry.builtin(&builtinBindingReceiver, .{ .exact = 0 }));

    const source_location_sym = try vm.intern("source_location");
    try vm.binding_class.module.methods.put(source_location_sym, MethodEntry.builtin(&builtinBindingSourceLocation, .{ .exact = 0 }));
}

/// Default filename for Binding#eval when no filename argument is given.
/// Uses the caller's source file and line, producing "(eval at file:line)".
fn evalFilename(vm: *VM, source_file_arg: ?Value) VMError![]const u8 {
    if (source_file_arg) |arg| {
        if (!arg.isNil()) {
            return arg.coerceToStr(vm, "no implicit conversion into String");
        }
    }

    if (vm.currentRubyCallerFrame()) |frame| {
        const caller_source = frame.chunk.source_file orelse "(eval)";
        const caller_line = vm.backtraceLineForFrame(frame);
        return std.fmt.allocPrint(vm.gc_allocator, "(eval at {s}:{d})", .{ caller_source, caller_line }) catch return error.Fatal;
    }

    return "(eval)";
}

fn evalStartLine(vm: *VM, lineno_arg: ?Value) VMError!i32 {
    const arg = lineno_arg orelse return 1;
    if (arg.isNil()) return 1;
    const lineno = try arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );
    return std.math.cast(i32, lineno) orelse vm.raiseExceptionFmt(vm.range_error_class, "bignum too big to convert into `long'", .{});
}

/// Binding#eval(source, filename=nil, lineno=nil)
/// Evaluates `source` in the context of the binding, optionally overriding the
/// reported filename and starting line number.
pub fn builtinBindingEval(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);
    const source_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const source_obj = source_value.toStringObject();

    const filename = try evalFilename(vm, if (args.len >= 2) args[1] else null);
    const start_line = try evalStartLine(vm, if (args.len >= 3) args[2] else null);
    const has_explicit_filename = args.len >= 2 and !args[1].isNil();

    const binding_obj = receiver.toBindingObject();
    const scopes = try vm.bindingLocalNameScopes(binding_obj);
    defer vm.allocator.free(scopes);

    return vm.evalSourceWithEncodingAndContext(
        source_obj.str,
        filename,
        source_obj.encoding,
        .{
            .self_value = binding_obj.self_value,
            .parent_ep = binding_obj.ep,
            .lexical_scope = binding_obj.lexical_scope,
            .parent_local_scopes = if (scopes.len > 0) scopes else null,
            .dir_returns_nil = !has_explicit_filename,
            .start_line = start_line,
            .binding_to_update = binding_obj,
            .method_name = binding_obj.method_name,
        },
    );
}

/// Binding#local_variables -> Array of Symbols
/// Returns the names of all local variables accessible in this binding,
/// including any that have been introduced via eval calls on this binding.
pub fn builtinBindingLocalVariables(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const binding_obj = receiver.toBindingObject();
    const result = try vm.createArray();
    for (binding_obj.local_names.items) |name| {
        const sym = try vm.intern(name);
        result.elements.append(vm.gc_allocator, Value.fromObject(&sym.object)) catch return error.Fatal;
    }
    return Value.fromObject(&result.object);
}

/// Binding#local_variable_defined?(name) -> true or false
pub fn builtinBindingLocalVariableDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const name = if (args[0].isSymbol()) args[0].toSymbolObject().name else try args[0].coerceToStr(vm, "no implicit conversion into String");
    const binding_obj = receiver.toBindingObject();
    for (binding_obj.local_names.items) |local_name| {
        if (std.mem.eql(u8, name, local_name)) return Value.TRUE;
    }
    return Value.FALSE;
}

/// Binding#local_variable_set(name, value) -> value
pub fn builtinBindingLocalVariableSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const name = if (args[0].isSymbol()) args[0].toSymbolObject().name else try args[0].coerceToStr(vm, "no implicit conversion into String");
    try vm.setBindingLocal(receiver.toBindingObject(), name, args[1]);
    return args[1];
}

/// Binding#local_variable_get(name) -> value
pub fn builtinBindingLocalVariableGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const name = if (args[0].isSymbol()) args[0].toSymbolObject().name else try args[0].coerceToStr(vm, "no implicit conversion into String");
    const binding_obj = receiver.toBindingObject();
    if (binding_obj.localSlot(name)) |slot| return slot.*;
    const name_sym = try vm.intern(name);
    return vm.raiseNameErrorFmt(name_sym, "local variable '{s}' is not defined for Binding", .{name});
}

/// Binding#receiver -> Object
/// Returns the object captured as self by this binding.
pub fn builtinBindingReceiver(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver.toBindingObject().self_value;
}

/// Binding#source_location -> [String, Integer] or nil
pub fn builtinBindingSourceLocation(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const binding = receiver.toBindingObject();
    const source_file = binding.source_file orelse return Value.nil();
    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, try vm.newString(source_file, false)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(binding.source_line)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}
