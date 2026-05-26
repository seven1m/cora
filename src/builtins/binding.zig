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

fn evalLineOffset(vm: *VM, lineno_arg: ?Value) VMError!u32 {
    const arg = lineno_arg orelse return 0;
    if (arg.isNil()) return 0;
    const lineno = try arg.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );
    if (lineno <= 1) return 0;
    return @intCast(lineno - 1);
}

/// Binding#eval(source, filename=nil, lineno=nil)
/// Evaluates `source` in the context of the binding, optionally overriding the
/// reported filename and starting line number.
pub fn builtinBindingEval(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 3);
    const source_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const source_obj = source_value.toStringObject();

    const filename = try evalFilename(vm, if (args.len >= 2) args[1] else null);
    const line_offset = try evalLineOffset(vm, if (args.len >= 3) args[2] else null);
    const has_explicit_filename = args.len >= 2 and !args[1].isNil();

    const binding_obj = receiver.toBindingObject();
    const real_names = binding_obj.local_names.items[0..binding_obj.real_local_count];

    return vm.evalSourceWithEncodingAndContext(
        source_obj.str,
        filename,
        source_obj.encoding,
        .{
            .self_value = binding_obj.self_value,
            .parent_ep = binding_obj.ep,
            .lexical_scope = binding_obj.lexical_scope,
            .parent_local_names = if (real_names.len > 0) real_names else null,
            .dir_returns_nil = !has_explicit_filename,
            .line_offset = line_offset,
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
