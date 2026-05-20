const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const method_reflection = @import("method_reflection.zig");
const module_builtin = @import("module.zig");
const method_builtin = @import("method.zig");
const method_common = @import("method_common.zig");
const openssl_builtin = @import("openssl.zig");
const rational_builtin = @import("rational.zig");
const stringio_builtin = @import("stringio.zig");
const warning_builtin = @import("warning.zig");
const zlib_builtin = @import("zlib.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;
const ModuleObject = value.ModuleObject;
const MethodEntry = value.MethodEntry;
const SymbolObject = value.SymbolObject;
const MethodListFilter = method_reflection.MethodListFilter;

fn implicitAutoloadReceiver(vm: *VM) Value {
    if (vm.current_lexical_scope) |scope| {
        return switch (scope.scope_module) {
            .class => |klass| Value.fromObject(&klass.module.object),
            .module => |mod| Value.fromObject(&mod.object),
        };
    }
    return Value.fromObject(&vm.object_class.module.object);
}

const BoundMethodLookup = struct {
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
};

fn collectKernelMethods(vm: *VM, receiver: Value, filter: MethodListFilter, include_super: bool) VMError!Value {
    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);

    var seen: std.AutoHashMap(*SymbolObject, usize) = std.AutoHashMap(*SymbolObject, usize).init(vm.gc_allocator);
    defer seen.deinit();

    var blocked: std.AutoHashMap(*SymbolObject, void) = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer blocked.deinit();

    const receiver_class = vm.getClass(receiver);
    const singleton = receiver.getSingletonClass();

    if (include_super) {
        if (singleton) |singleton_class| {
            try method_reflection.collectClassChainMethods(vm, singleton_class, true, filter, true, &names, &seen, &blocked);
        } else {
            try method_reflection.collectClassChainMethods(vm, receiver_class, true, filter, true, &names, &seen, &blocked);
        }
    } else {
        if (singleton) |singleton_class| {
            try method_reflection.collectClassChainMethods(vm, singleton_class, false, filter, false, &names, &seen, &blocked);
        }
        if (filter == .private_only) {
            try method_reflection.collectClassChainMethods(vm, receiver_class, false, filter, false, &names, &seen, &blocked);
        }
    }

    return method_reflection.sortedSymbolArray(vm, names.items);
}

fn collectSingletonMethods(vm: *VM, receiver: Value, include_super: bool) VMError!Value {
    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);

    var seen: std.AutoHashMap(*SymbolObject, usize) = std.AutoHashMap(*SymbolObject, usize).init(vm.gc_allocator);
    defer seen.deinit();

    var blocked: std.AutoHashMap(*SymbolObject, void) = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer blocked.deinit();

    const singleton_class = receiver.getSingletonClass() orelse return method_reflection.sortedSymbolArray(vm, names.items);

    if (include_super) {
        var current: ?*ClassObject = singleton_class;
        while (current) |klass| {
            if (klass.attached_object == null) break;
            try method_reflection.collectModuleAncestryMethods(
                vm,
                &klass.module,
                .public_and_protected,
                true,
                &names,
                &seen,
                &blocked,
            );
            current = klass.superclass;
        }
    } else {
        try method_reflection.collectMethodsFromTable(
            vm,
            &singleton_class.module.methods,
            .public_and_protected,
            &names,
            &seen,
            &blocked,
        );
    }

    return method_reflection.sortedSymbolArray(vm, names.items);
}

fn resolveMethodEntry(
    method_name: *SymbolObject,
    owner_class: *ClassObject,
    owner: Value,
    entry: MethodEntry,
) ?BoundMethodLookup {
    return switch (entry.method) {
        .undefined => null,
        else => .{
            .resolved = .{
                .name = method_name,
                .owner_class = owner_class,
                .entry = entry,
            },
            .owner = owner,
        },
    };
}

fn lookupSingletonMethodOnly(singleton_class: *ClassObject, method_name: *SymbolObject) ?BoundMethodLookup {
    var i = singleton_class.module.prepended_modules.items.len;
    while (i > 0) {
        i -= 1;
        const prepended = singleton_class.module.prepended_modules.items[i];
        if (prepended.methods.get(method_name)) |entry| {
            return resolveMethodEntry(method_name, singleton_class, Value.fromObject(&prepended.object), entry);
        }
    }

    if (singleton_class.module.methods.get(method_name)) |entry| {
        return resolveMethodEntry(method_name, singleton_class, Value.fromObject(&singleton_class.module.object), entry);
    }

    i = singleton_class.module.included_modules.items.len;
    while (i > 0) {
        i -= 1;
        const included = singleton_class.module.included_modules.items[i];
        if (included.methods.get(method_name)) |entry| {
            return resolveMethodEntry(method_name, singleton_class, Value.fromObject(&included.object), entry);
        }
    }

    return null;
}

fn isClassOrSubclassOf(class: *ClassObject, candidate_ancestor: *ClassObject) bool {
    var current: ?*ClassObject = class;
    while (current) |klass| {
        if (klass == candidate_ancestor) return true;
        current = klass.superclass;
    }
    return false;
}

pub fn register(vm: *VM) !void {
    const kernel_array_convert_sym = try vm.intern("Array");
    try vm.kernel_module.methods.put(kernel_array_convert_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelArrayConvert, .{ .exact = 1 }, .private));

    const kernel_string_convert_sym = try vm.intern("String");
    try vm.kernel_module.methods.put(kernel_string_convert_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelStringConvert, .{ .exact = 1 }, .private));

    const kernel_integer_convert_sym = try vm.intern("Integer");
    try vm.kernel_module.methods.put(kernel_integer_convert_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelIntegerConvert, .{ .exact = 1 }, .private));

    const puts_sym = try vm.intern("puts");
    try vm.kernel_module.methods.put(puts_sym, MethodEntry.builtin(&builtinKernelPuts, .{ .variadic = 0 }));

    const print_sym = try vm.intern("print");
    try vm.kernel_module.methods.put(print_sym, MethodEntry.builtin(&builtinKernelPrint, .{ .variadic = 0 }));

    const warn_sym = try vm.intern("warn");
    try vm.kernel_module.methods.put(warn_sym, MethodEntry.builtinWithVisibility(&builtinKernelWarn, .{ .variadic = 0 }, .private));

    const catch_sym = try vm.intern("catch");
    try vm.kernel_module.methods.put(catch_sym, MethodEntry.builtinWithVisibility(&builtinKernelCatch, .{ .variadic = 0 }, .private));

    const throw_sym = try vm.intern("throw");
    try vm.kernel_module.methods.put(throw_sym, MethodEntry.builtinWithVisibility(&builtinKernelThrow, .{ .variadic = 1 }, .private));

    const abort_sym = try vm.intern("abort");
    try vm.kernel_module.methods.put(abort_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelAbort, .{ .variadic = 0 }, .private));

    const exit_sym = try vm.intern("exit");
    try vm.kernel_module.methods.put(exit_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelExit, .{ .variadic = 0 }, .private));

    const exit_bang_sym = try vm.intern("exit!");
    try vm.kernel_module.methods.put(exit_bang_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelExitBang, .{ .variadic = 0 }, .private));

    const system_sym = try vm.intern("system");
    try vm.kernel_module.methods.put(system_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelSystem, .{ .variadic = 0 }, .private));

    const eval_sym = try vm.intern("eval");
    try vm.kernel_module.methods.put(eval_sym, value.MethodEntry.builtin(&builtinKernelEval, .{ .variadic = 0 }));

    const binding_sym = try vm.intern("binding");
    try vm.kernel_module.methods.put(binding_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelBinding, .{ .exact = 0 }, .private));

    const proc_sym = try vm.intern("proc");
    try vm.kernel_module.methods.put(proc_sym, value.MethodEntry.builtin(&builtinKernelProc, .{ .exact = 0 }));

    const lambda_sym = try vm.intern("lambda");
    try vm.kernel_module.methods.put(lambda_sym, value.MethodEntry.builtin(&builtinKernelLambda, .{ .exact = 0 }));

    const require_sym = try vm.intern("require");
    try vm.kernel_module.methods.put(require_sym, value.MethodEntry.builtin(&builtinKernelRequire, .{ .exact = 1 }));

    const autoload_sym = try vm.intern("autoload");
    try vm.kernel_module.methods.put(autoload_sym, MethodEntry.builtinWithVisibility(&builtinKernelAutoload, .{ .exact = 2 }, .private));

    const autoload_q_sym = try vm.intern("autoload?");
    try vm.kernel_module.methods.put(autoload_q_sym, MethodEntry.builtinWithVisibility(&builtinKernelAutoloadQ, .{ .variadic = 0 }, .private));

    const require_relative_sym = try vm.intern("require_relative");
    try vm.kernel_module.methods.put(require_relative_sym, value.MethodEntry.builtin(&builtinKernelRequireRelative, .{ .exact = 1 }));

    const load_sym = try vm.intern("load");
    try vm.kernel_module.methods.put(load_sym, value.MethodEntry.builtin(&builtinKernelLoad, .{ .variadic = 0 }));

    const instance_variable_get_sym = try vm.intern("instance_variable_get");
    try vm.kernel_module.methods.put(instance_variable_get_sym, MethodEntry.builtin(&builtinKernelInstanceVariableGet, .{ .exact = 1 }));

    const instance_variable_defined_sym = try vm.intern("instance_variable_defined?");
    try vm.kernel_module.methods.put(instance_variable_defined_sym, MethodEntry.builtin(&builtinKernelInstanceVariableDefined, .{ .exact = 1 }));

    const instance_variable_set_sym = try vm.intern("instance_variable_set");
    try vm.kernel_module.methods.put(instance_variable_set_sym, MethodEntry.builtin(&builtinKernelInstanceVariableSet, .{ .exact = 2 }));

    const instance_variables_sym = try vm.intern("instance_variables");
    try vm.kernel_module.methods.put(instance_variables_sym, MethodEntry.builtin(&builtinKernelInstanceVariables, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.kernel_module.methods.put(to_s_sym, MethodEntry.builtin(&builtinKernelToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.kernel_module.methods.put(inspect_sym, MethodEntry.builtin(&builtinKernelInspect, .{ .exact = 0 }));

    const itself_sym = try vm.intern("itself");
    try vm.kernel_module.methods.put(itself_sym, MethodEntry.builtin(&builtinKernelItself, .{ .exact = 0 }));

    const kernel_hash_convert_sym = try vm.intern("Hash");
    try vm.kernel_module.methods.put(kernel_hash_convert_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelHashConvert, .{ .exact = 1 }, .private));

    const kernel_module_val = Value.fromObject(&vm.kernel_module.object);
    const kernel_singleton = try vm.getOrCreateSingletonClass(kernel_module_val);
    try kernel_singleton.module.methods.put(kernel_array_convert_sym, value.MethodEntry.builtin(&builtinKernelArrayConvert, .{ .exact = 1 }));
    try kernel_singleton.module.methods.put(kernel_string_convert_sym, value.MethodEntry.builtin(&builtinKernelStringConvert, .{ .exact = 1 }));
    try kernel_singleton.module.methods.put(kernel_integer_convert_sym, value.MethodEntry.builtin(&builtinKernelIntegerConvert, .{ .exact = 1 }));
    try kernel_singleton.module.methods.put(kernel_hash_convert_sym, value.MethodEntry.builtin(&builtinKernelHashConvert, .{ .exact = 1 }));
    try kernel_singleton.module.methods.put(autoload_sym, MethodEntry.builtin(&builtinKernelSingletonAutoload, .{ .exact = 2 }));
    try kernel_singleton.module.methods.put(autoload_q_sym, MethodEntry.builtin(&builtinKernelSingletonAutoloadQ, .{ .variadic = 0 }));
    try kernel_singleton.module.methods.put(warn_sym, MethodEntry.builtin(&builtinKernelWarn, .{ .variadic = 0 }));
    try kernel_singleton.module.methods.put(catch_sym, MethodEntry.builtin(&builtinKernelCatch, .{ .variadic = 0 }));
    try kernel_singleton.module.methods.put(throw_sym, MethodEntry.builtin(&builtinKernelThrow, .{ .variadic = 1 }));

    const hash_sym = try vm.intern("hash");
    try vm.kernel_module.methods.put(hash_sym, MethodEntry.builtin(&builtinKernelHash, .{ .exact = 0 }));

    const p_sym = try vm.intern("p");
    try vm.kernel_module.methods.put(p_sym, MethodEntry.builtin(&builtinKernelP, .{ .variadic = 0 }));

    const rand_sym = try vm.intern("rand");
    try vm.kernel_module.methods.put(rand_sym, value.MethodEntry.builtin(&builtinKernelRand, .{ .variadic = 0 }));

    const raise_sym = try vm.intern("raise");
    try vm.kernel_module.methods.put(raise_sym, MethodEntry.builtin(&builtinKernelRaise, .{ .variadic = 0 }));

    const fail_sym = try vm.intern("fail");
    try vm.kernel_module.methods.put(fail_sym, MethodEntry.builtin(&builtinKernelRaise, .{ .variadic = 0 }));

    const is_a_sym = try vm.intern("is_a?");
    try vm.kernel_module.methods.put(is_a_sym, MethodEntry.builtin(&builtinKernelIsA, .{ .exact = 1 }));

    const kind_of_sym = try vm.intern("kind_of?");
    try vm.kernel_module.methods.put(kind_of_sym, MethodEntry.builtin(&builtinKernelIsA, .{ .exact = 1 }));

    const instance_of_sym = try vm.intern("instance_of?");
    try vm.kernel_module.methods.put(instance_of_sym, MethodEntry.builtin(&builtinKernelInstanceOf, .{ .exact = 1 }));

    const respond_to_sym = try vm.intern("respond_to?");
    try vm.kernel_module.methods.put(respond_to_sym, MethodEntry.builtin(&builtinKernelRespondTo, .{ .variadic = 0 }));

    const respond_to_missing_sym = try vm.intern("respond_to_missing?");
    try vm.kernel_module.methods.put(respond_to_missing_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelRespondToMissing, .{ .exact = 2 }, .private));

    const not_match_sym = try vm.intern("!~");
    try vm.kernel_module.methods.put(not_match_sym, value.MethodEntry.builtin(&builtinKernelNotMatch, .{ .exact = 1 }));

    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.kernel_module.methods.put(initialize_copy_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelInitializeCopy, .{ .exact = 1 }, .private));

    const initialize_dup_sym = try vm.intern("initialize_dup");
    try vm.kernel_module.methods.put(initialize_dup_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelInitializeDup, .{ .exact = 1 }, .private));

    const dup_sym = try vm.intern("dup");
    try vm.kernel_module.methods.put(dup_sym, value.MethodEntry.builtin(&builtinKernelDup, .{ .exact = 0 }));

    const clone_sym = try vm.intern("clone");
    try vm.kernel_module.methods.put(clone_sym, value.MethodEntry.builtin(&builtinKernelClone, .{ .exact = 0 }));

    const initialize_clone_sym = try vm.intern("initialize_clone");
    try vm.kernel_module.methods.put(initialize_clone_sym, value.MethodEntry.builtinWithVisibility(&builtinKernelInitializeClone, .{ .variadic = 0 }, .private));

    const block_given_sym = try vm.intern("block_given?");
    try vm.kernel_module.methods.put(block_given_sym, MethodEntry.builtin(&builtinKernelBlockGiven, .{ .exact = 0 }));

    const at_exit_sym = try vm.intern("at_exit");
    try vm.kernel_module.methods.put(at_exit_sym, value.MethodEntry.builtin(&builtinKernelAtExit, .{ .exact = 0 }));

    const loop_sym = try vm.intern("loop");
    try vm.kernel_module.methods.put(loop_sym, MethodEntry.builtin(&builtinKernelLoop, .{ .exact = 0 }));

    const sleep_sym = try vm.intern("sleep");
    try vm.kernel_module.methods.put(sleep_sym, MethodEntry.builtin(&builtinKernelSleep, .{ .variadic = 0 }));

    const tap_sym = try vm.intern("tap");
    try vm.kernel_module.methods.put(tap_sym, MethodEntry.builtin(&builtinKernelTap, .{ .exact = 0 }));

    const send_sym = try vm.intern("send");
    try vm.kernel_module.methods.put(send_sym, MethodEntry.builtin(&builtinKernelSend, .{ .variadic = 0 }));

    const public_send_sym = try vm.intern("public_send");
    try vm.kernel_module.methods.put(public_send_sym, MethodEntry.builtin(&builtinKernelPublicSend, .{ .variadic = 0 }));

    const method_sym = try vm.intern("method");
    try vm.kernel_module.methods.put(method_sym, MethodEntry.builtin(&builtinKernelMethod, .{ .exact = 1 }));

    const singleton_method_sym = try vm.intern("singleton_method");
    try vm.kernel_module.methods.put(singleton_method_sym, MethodEntry.builtin(&builtinKernelSingletonMethod, .{ .exact = 1 }));

    const to_enum_sym = try vm.intern("to_enum");
    try vm.kernel_module.methods.put(to_enum_sym, MethodEntry.builtin(&builtinKernelToEnum, .{ .variadic = 0 }));

    const enum_for_sym = try vm.intern("enum_for");
    try vm.kernel_module.methods.put(enum_for_sym, MethodEntry.builtin(&builtinKernelEnumFor, .{ .variadic = 0 }));

    const define_singleton_method_sym = try vm.intern("define_singleton_method");
    try vm.kernel_module.methods.put(define_singleton_method_sym, value.MethodEntry.builtin(&builtinKernelDefineSingletonMethod, .{ .variadic = 0 }));

    const extend_sym = try vm.intern("extend");
    try vm.kernel_module.methods.put(extend_sym, value.MethodEntry.builtin(&builtinKernelExtend, .{ .variadic = 0 }));

    const methods_sym = try vm.intern("methods");
    try vm.kernel_module.methods.put(methods_sym, value.MethodEntry.builtin(&builtinKernelMethods, .{ .variadic = 0 }));

    const singleton_methods_sym = try vm.intern("singleton_methods");
    try vm.kernel_module.methods.put(singleton_methods_sym, value.MethodEntry.builtin(&builtinKernelSingletonMethods, .{ .variadic = 0 }));

    const private_methods_sym = try vm.intern("private_methods");
    try vm.kernel_module.methods.put(private_methods_sym, value.MethodEntry.builtin(&builtinKernelPrivateMethods, .{ .variadic = 0 }));

    const nil_sym = try vm.intern("nil?");
    try vm.kernel_module.methods.put(nil_sym, MethodEntry.builtin(&builtinKernelNil, .{ .exact = 0 }));

    const freeze_sym = try vm.intern("freeze");
    try vm.kernel_module.methods.put(freeze_sym, MethodEntry.builtin(&builtinKernelFreeze, .{ .exact = 0 }));

    const frozen_sym = try vm.intern("frozen?");
    try vm.kernel_module.methods.put(frozen_sym, MethodEntry.builtin(&builtinKernelFrozen, .{ .exact = 0 }));

    const singleton_class_sym = try vm.intern("singleton_class");
    try vm.kernel_module.methods.put(singleton_class_sym, MethodEntry.builtin(&builtinKernelSingletonClass, .{ .exact = 0 }));

    const backtick_sym = try vm.intern("`");
    try vm.kernel_module.methods.put(backtick_sym, value.MethodEntry.builtin(&builtinKernelBacktick, .{ .exact = 1 }));

    const dir_sym = try vm.intern("__dir__");
    try vm.kernel_module.methods.put(dir_sym, MethodEntry.builtin(&builtinKernelDir, .{ .exact = 0 }));

    const exitstatus_sym = try vm.intern("exitstatus");
    try vm.process_status_class.module.methods.put(exitstatus_sym, value.MethodEntry.builtin(&builtinProcessStatusExitstatus, .{ .exact = 0 }));

    const success_sym = try vm.intern("success?");
    try vm.process_status_class.module.methods.put(success_sym, value.MethodEntry.builtin(&builtinProcessStatusSuccess, .{ .exact = 0 }));

    const exited_sym = try vm.intern("exited?");
    try vm.process_status_class.module.methods.put(exited_sym, value.MethodEntry.builtin(&builtinProcessStatusExited, .{ .exact = 0 }));

    const signaled_sym = try vm.intern("signaled?");
    try vm.process_status_class.module.methods.put(signaled_sym, value.MethodEntry.builtin(&builtinProcessStatusSignaled, .{ .exact = 0 }));

    const termsig_sym = try vm.intern("termsig");
    try vm.process_status_class.module.methods.put(termsig_sym, value.MethodEntry.builtin(&builtinProcessStatusTermsig, .{ .exact = 0 }));

    const fork_sym = try vm.intern("fork");
    try vm.kernel_module.methods.put(fork_sym, value.MethodEntry.builtin(&builtinKernelFork, .{ .exact = 0 }));

    const rational_sym = try vm.intern("Rational");
    try vm.kernel_module.methods.put(rational_sym, value.MethodEntry.builtin(&builtinKernelRational, .{ .variadic = 0 }));
}

pub fn builtinKernelRational(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const kw_exception = try vm.consumeKeywordArg("exception");
    try vm.validateKeywordArgsConsumed();
    const exception_mode = if (kw_exception) |value_| value_.is_truthy() else true;

    const numerator = args[0];
    const denominator = if (args.len == 2) args[1] else null;

    if (denominator == null) {
        const parts = try builtinKernelRationalCoerce(vm, numerator, exception_mode) orelse return Value.nil();
        if (numerator.isRational()) return numerator;
        return vm.newRationalValues(parts.numerator, parts.denominator);
    }

    const num_parts = try builtinKernelRationalCoerce(vm, numerator, exception_mode) orelse return Value.nil();
    const den_parts = try builtinKernelRationalCoerce(vm, denominator.?, exception_mode) orelse return Value.nil();

    if ((try vm.compareIntegerValues(den_parts.numerator, Value.integer(0))) == .eq) {
        if (exception_mode) {
            return vm.raiseExceptionFmt(vm.zero_division_error_class, "divided by 0", .{});
        }
        return Value.nil();
    }

    const result_num = try vm.mulIntegerValues(num_parts.numerator, den_parts.denominator);
    const result_den = try vm.mulIntegerValues(num_parts.denominator, den_parts.numerator);
    return vm.newRationalValues(result_num, result_den);
}

fn builtinKernelRationalRaiseCantConvert(vm: *VM, arg: Value) VMError!Value {
    if (arg.isNil()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert nil into Rational", .{});
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Rational", .{vm.className(arg)});
}

fn builtinKernelRationalSafeCheckCall(vm: *VM, arg: Value, method_name: []const u8) VMError!?Value {
    return vm.checkCallMethodByName(arg, method_name, false, &[_]Value{}, null) catch |err| {
        if (err == error.Unwind) {
            vm.setPendingException(null);
            return null;
        }
        return err;
    };
}

fn builtinKernelRationalCoerce(vm: *VM, arg: Value, exception_mode: bool) VMError!?rational_builtin.RationalParts {
    if (arg.isRational()) {
        const rational = arg.toRationalObject();
        return .{ .numerator = rational.numerator, .denominator = rational.denominator };
    }
    if (arg.isInteger() or arg.isBigInteger()) {
        return .{ .numerator = arg, .denominator = Value.integer(1) };
    }
    if (arg.isString()) {
        const parsed = try rational_builtin.parseStringToRational(vm, arg.toStringObject().str) orelse {
            if (exception_mode) {
                return vm.raiseExceptionFmt(vm.type_error_class, "can't convert String into Rational", .{});
            }
            return null;
        };
        return parsed;
    }
    if (arg.isFloat()) {
        return try rational_builtin.floatToRationalParts(vm, arg.toFloatObject().val);
    }
    if (try builtinKernelRationalSafeCheckCall(vm, arg, "to_r")) |r| {
        if (r.isRational()) {
            const rational = r.toRationalObject();
            return .{ .numerator = rational.numerator, .denominator = rational.denominator };
        }
        if (exception_mode) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} to Rational ({s}#to_r gives {s})", .{ vm.className(arg), vm.className(arg), vm.className(r) });
        }
        return null;
    }
    if (try builtinKernelRationalSafeCheckCall(vm, arg, "to_int")) |int_val| {
        if (int_val.isInteger() or int_val.isBigInteger()) {
            return .{ .numerator = int_val, .denominator = Value.integer(1) };
        }
        if (exception_mode) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} to Integer ({s}#to_int gives non-Integer)", .{ vm.className(arg), vm.className(arg) });
        }
        return null;
    }
    if (exception_mode) {
        _ = try builtinKernelRationalRaiseCantConvert(vm, arg);
        unreachable;
    }
    return null;
}
pub fn builtinKernelRequire(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try vm.resetLoadedFilesFromGlobal();
    const feature = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const owner_thread = vm.current_thread orelse try vm.ensureMainThread();

    // Builtin libraries whose classes are registered at VM startup:
    // `require 'name'` is a no-op after the first call, matching Ruby's "already loaded" semantics.
    const builtin_libs = [_][]const u8{ "socket", "rbconfig" };
    for (builtin_libs) |lib| {
        if (std.mem.eql(u8, feature, lib)) {
            if (vm.loaded_files.contains(lib)) {
                return Value.boolean(false);
            }
            try vm.insertLoadedFile(lib);
            try vm.syncLoadedFeaturesGlobals();
            return Value.boolean(true);
        }
    }

    const resolved_feature = vm.resolveRequireFeature(feature) catch {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        exc.path = (try vm.newString(feature, false)).toStringObject();
        vm.setPendingException(exc);
        return error.Unwind;
    } orelse {
        if (try vm.loadedFeatureMatches(feature, null)) {
            return Value.boolean(false);
        }
        if (VM.isBareFeatureWithoutExt(feature) and try vm.loadedFeatureMatchesCurrentLoadPath(feature)) {
            return Value.boolean(false);
        }
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        exc.path = (try vm.newString(feature, false)).toStringObject();
        vm.setPendingException(exc);
        return error.Unwind;
    };
    const absolute_path = resolved_feature.load_path;
    const identity_path = resolved_feature.identity_path;

    var waiting_on_require = false;
    defer {
        if (waiting_on_require) owner_thread.waiting_on_require = false;
    }
    while (vm.requireInProgressOwner(identity_path)) |in_progress_owner| {
        if (in_progress_owner == owner_thread) {
            try warning_builtin.writeWarning(vm, "warning: loading in progress, circular require considered harmful\n");
            vm.allocator.free(absolute_path);
            vm.allocator.free(identity_path);
            return Value.boolean(false);
        }

        if (!waiting_on_require) {
            owner_thread.waiting_on_require = true;
            waiting_on_require = true;
        }
        try vm.threadYield();
        try vm.resetLoadedFilesFromGlobal();
    }

    if (try vm.loadedFeatureMatches(feature, identity_path)) {
        vm.allocator.free(absolute_path);
        vm.allocator.free(identity_path);
        return Value.boolean(false);
    }
    if (VM.isBareFeatureWithoutExt(feature) and try vm.loadedFeatureMatchesCurrentLoadPath(feature)) {
        vm.allocator.free(absolute_path);
        vm.allocator.free(identity_path);
        return Value.boolean(false);
    }

    if (std.mem.eql(u8, feature, "openssl") or std.mem.eql(u8, feature, "openssl.rb")) {
        openssl_builtin.register(vm) catch return error.Fatal;
    } else if (std.mem.eql(u8, feature, "zlib") or std.mem.eql(u8, feature, "zlib.rb")) {
        zlib_builtin.register(vm) catch return error.Fatal;
    }

    try vm.beginRequireInProgress(identity_path, owner_thread);
    defer vm.allocator.free(identity_path);
    defer vm.endRequireInProgress(identity_path);

    try vm.insertLoadedFile(absolute_path);
    try vm.syncLoadedFeaturesGlobals();

    vm.loadFile(absolute_path) catch |err| {
        vm.removeLoadedFile(absolute_path);
        vm.allocator.free(absolute_path);
        try vm.syncLoadedFeaturesGlobals();
        return err;
    };

    if (std.mem.eql(u8, feature, "stringio") or std.mem.eql(u8, feature, "stringio.rb")) {
        stringio_builtin.register(vm) catch return error.Fatal;
    }

    try vm.syncLoadedFeaturesGlobals();
    vm.allocator.free(absolute_path);
    return Value.boolean(true);
}

pub fn builtinKernelAutoload(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return module_builtin.builtinModuleAutoload(vm, implicitAutoloadReceiver(vm), args, null);
}

pub fn builtinKernelAutoloadQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return module_builtin.builtinModuleAutoloadQ(vm, implicitAutoloadReceiver(vm), args, null);
}

pub fn builtinKernelSingletonAutoload(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return module_builtin.builtinModuleAutoload(vm, implicitAutoloadReceiver(vm), args, null);
}

pub fn builtinKernelSingletonAutoloadQ(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    return module_builtin.builtinModuleAutoloadQ(vm, implicitAutoloadReceiver(vm), args, null);
}

pub fn builtinKernelEval(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 4);
    const source_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const source_obj = source_value.toStringObject();

    const binding_arg = if (args.len >= 2)
        args[1]
    else if (receiver.isBinding())
        receiver
    else
        Value.nil();
    const filename: ?[]const u8 = if (args.len >= 3 and !args[2].isNil())
        try args[2].coerceToStr(vm, "no implicit conversion into String")
    else
        null;

    if (binding_arg.isNil()) {
        return vm.evalSourceWithEncoding(source_obj.str, filename orelse "(eval)", source_obj.encoding);
    }

    if (!binding_arg.isBinding()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Binding)", .{vm.className(binding_arg)});
    }

    const binding_obj = binding_arg.toBindingObject();
    return vm.evalSourceWithEncodingAndContext(
        source_obj.str,
        filename,
        source_obj.encoding,
        .{
            .self_value = binding_obj.self_value,
            .parent_ep = binding_obj.ep,
            .lexical_scope = binding_obj.lexical_scope,
            .dir_returns_nil = filename == null,
        },
    );
}

pub fn builtinKernelBinding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (vm.currentRubyCallerFrame()) |frame| {
        const binding = try vm.createBinding(frame.self_value, frame.ep, vm.current_lexical_scope);
        return Value.fromObject(&binding.object);
    }

    const binding = try vm.createBinding(receiver, null, vm.current_lexical_scope);
    return Value.fromObject(&binding.object);
}

pub fn builtinKernelRequireRelative(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    try vm.resetLoadedFilesFromGlobal();
    const relative_path = try vm.coerceToPath(args[0], "no implicit conversion into String");
    const owner_thread = vm.current_thread orelse try vm.ensureMainThread();

    const current_file = blk: {
        if (vm.frames.items.len > 0) {
            if (vm.currentFrame().chunk.source_file) |source_file| break :blk source_file;
        }
        break :blk vm.current_loading_file orelse {
            const exc = vm.createException(vm.load_error_class, "cannot infer basepath") catch return error.Fatal;
            vm.setPendingException(exc);
            return error.Unwind;
        };
    };

    const current_dir = std.fs.path.dirname(current_file) orelse ".";
    const full_path = std.fs.path.join(vm.allocator, &[_][]const u8{ current_dir, relative_path }) catch return error.Fatal;
    defer vm.allocator.free(full_path);

    const storage_path = vm.expandPathLexical(full_path) catch return error.Fatal;
    defer vm.allocator.free(storage_path);
    var resolved_path: ?[]const u8 = null;
    var identity_path: ?[]const u8 = null;
    if (vm.fileExists(storage_path)) {
        resolved_path = vm.allocator.dupe(u8, storage_path) catch return error.Fatal;
        identity_path = vm.resolveAbsolutePath(storage_path) catch return error.Fatal;
    } else {
        const with_rb = std.fmt.allocPrint(vm.allocator, "{s}.rb", .{storage_path}) catch return error.Fatal;
        defer vm.allocator.free(with_rb);
        if (vm.fileExists(with_rb)) {
            resolved_path = vm.allocator.dupe(u8, with_rb) catch return error.Fatal;
            identity_path = vm.resolveAbsolutePath(with_rb) catch return error.Fatal;
        }
    }

    if (resolved_path == null) {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{relative_path}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.setPendingException(exc);
        return error.Unwind;
    }

    const resolved_path_value = resolved_path.?;
    const identity_path_value = identity_path.?;

    var waiting_on_require = false;
    defer {
        if (waiting_on_require) owner_thread.waiting_on_require = false;
    }
    while (vm.requireInProgressOwner(identity_path_value)) |in_progress_owner| {
        if (in_progress_owner == owner_thread) {
            try warning_builtin.writeWarning(vm, "warning: loading in progress, circular require considered harmful\n");
            vm.allocator.free(resolved_path_value);
            vm.allocator.free(identity_path_value);
            return Value.boolean(false);
        }

        if (!waiting_on_require) {
            owner_thread.waiting_on_require = true;
            waiting_on_require = true;
        }
        try vm.threadYield();
        try vm.resetLoadedFilesFromGlobal();
    }

    if (try vm.loadedFeatureMatches(relative_path, identity_path_value)) {
        vm.allocator.free(resolved_path_value);
        vm.allocator.free(identity_path_value);
        return Value.boolean(false);
    }

    try vm.beginRequireInProgress(identity_path_value, owner_thread);
    defer vm.allocator.free(identity_path_value);
    defer vm.endRequireInProgress(identity_path_value);

    try vm.insertLoadedFile(resolved_path_value);
    try vm.syncLoadedFeaturesGlobals();
    vm.loadFile(resolved_path_value) catch |err| {
        vm.removeLoadedFile(resolved_path_value);
        vm.allocator.free(resolved_path_value);
        try vm.syncLoadedFeaturesGlobals();
        return err;
    };

    try vm.syncLoadedFeaturesGlobals();
    vm.allocator.free(resolved_path_value);
    return Value.boolean(true);
}

pub fn builtinKernelLoad(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const filename = try vm.coerceToPath(args[0], "no implicit conversion into String");

    var absolute_path: ?[]const u8 = null;

    if (std.fs.path.isAbsolute(filename)) {
        if (vm.fileExists(filename)) {
            absolute_path = vm.resolveAbsolutePath(filename) catch return error.Fatal;
        }
    } else {
        if (vm.current_loading_file) |current_file| {
            const current_dir = std.fs.path.dirname(current_file) orelse ".";
            const full_path = std.fs.path.join(vm.allocator, &[_][]const u8{ current_dir, filename }) catch return error.Fatal;
            defer vm.allocator.free(full_path);

            if (vm.fileExists(full_path)) {
                absolute_path = vm.resolveAbsolutePath(full_path) catch return error.Fatal;
            }
        }

        if (absolute_path == null and vm.fileExists(filename)) {
            absolute_path = vm.resolveAbsolutePath(filename) catch return error.Fatal;
        }
    }

    if (absolute_path == null) {
        const with_rb = std.fmt.allocPrint(vm.allocator, "{s}.rb", .{filename}) catch return error.Fatal;
        defer vm.allocator.free(with_rb);

        if (vm.fileExists(with_rb)) {
            absolute_path = vm.resolveAbsolutePath(with_rb) catch return error.Fatal;
        }
    }

    if (absolute_path == null) {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{filename}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.setPendingException(exc);
        return error.Unwind;
    }

    defer vm.allocator.free(absolute_path.?);
    try vm.loadFile(absolute_path.?);

    return Value.boolean(true);
}

pub fn builtinKernelPuts(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const stdout_target = vm.globals.get("$stdout") orelse return error.Fatal;
    _ = try vm.callMethodByName(stdout_target, "puts", args, null);
    return Value.nil();
}

pub fn builtinKernelAbort(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    return Value.nil();
}

pub fn builtinKernelExit(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const exc_value = try vm.newExceptionInstance(vm.system_exit_class, args, null);
    vm.setPendingException(exc_value.toExceptionObject());
    return error.Unwind;
}

pub fn builtinKernelExitBang(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const exc_value = try vm.newExceptionInstance(vm.system_exit_class, args, null);
    vm.setPendingException(exc_value.toExceptionObject());
    return error.Unwind;
}

pub fn builtinKernelSystem(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountAtLeast(args, 1);

    var chdir_value: ?Value = null;
    try vm.consumeKeywordArgs(.{"chdir"}, .{&chdir_value});
    try vm.validateKeywordArgsConsumed();

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();

    var arg_storage: std.ArrayList([]const u8) = .empty;
    defer arg_storage.deinit(vm.allocator);

    var arg_index: usize = 0;
    if (args[0].isHash()) {
        for (args[0].toHashObject().entries.items) |entry| {
            const key = try entry.key.coerceToStr(vm, "no implicit conversion into String");
            const value_bytes = try entry.value.coerceToStr(vm, "no implicit conversion into String");
            env_map.put(key, value_bytes) catch return error.Fatal;
        }
        arg_index = 1;
    }
    if (arg_index >= args.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "wrong number of arguments (given 0, expected 1+)", .{});
    }

    const use_shell = arg_index + 1 == args.len;
    if (use_shell) {
        const command = try args[arg_index].coerceToStr(vm, "no implicit conversion into String");
        if (builtin.os.tag == .windows) {
            arg_storage.append(vm.allocator, "cmd.exe") catch return error.Fatal;
            arg_storage.append(vm.allocator, "/C") catch return error.Fatal;
        } else {
            arg_storage.append(vm.allocator, "/bin/sh") catch return error.Fatal;
            arg_storage.append(vm.allocator, "-c") catch return error.Fatal;
        }
        arg_storage.append(vm.allocator, command) catch return error.Fatal;
    } else {
        var i = arg_index;
        while (i < args.len) : (i += 1) {
            arg_storage.append(vm.allocator, try args[i].coerceToStr(vm, "no implicit conversion into String")) catch return error.Fatal;
        }
    }

    const run_result = std.process.run(vm.allocator, vm.io, .{
        .argv = arg_storage.items,
        .cwd = if (chdir_value) |value_arg|
            .{ .path = try vm.coerceToPath(value_arg, "no implicit conversion into String") }
        else
            .inherit,
        .environ_map = &env_map,
        .stderr_limit = .limited(16 * 1024 * 1024),
        .stdout_limit = .limited(16 * 1024 * 1024),
    }) catch {
        try vm.setGlobal("$?", Value.nil());
        return Value.nil();
    };
    defer vm.allocator.free(run_result.stdout);
    defer vm.allocator.free(run_result.stderr);

    const result = switch (run_result.term) {
        .exited => |code| blk: {
            try vm.setLastProcessStatus(@intCast(code));
            break :blk Value.boolean(code == 0);
        },
        .signal => |sig| blk: {
            try vm.setLastProcessStatus(128 + @as(i64, @intCast(@intFromEnum(sig))));
            break :blk Value.boolean(false);
        },
        .stopped => |sig| blk: {
            try vm.setLastProcessStatus(128 + @as(i64, @intCast(@intFromEnum(sig))));
            break :blk Value.boolean(false);
        },
        else => blk: {
            try vm.setLastProcessStatus(1);
            break :blk Value.boolean(false);
        },
    };

    return result;
}

pub fn builtinKernelPrint(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const stdout_target = vm.globals.get("$stdout") orelse return error.Fatal;
    _ = try vm.callMethodByName(stdout_target, "print", args, null);
    _ = try vm.callMethodByName(stdout_target, "flush", &[_]Value{}, null);
    return Value.nil();
}

const WarningLocation = struct {
    source: []const u8,
    line: u32,
};

fn warningCategorySymbol(vm: *VM, category_value: ?Value) VMError!?Value {
    const raw = category_value orelse return null;
    if (raw.isNil()) return Value.nil();
    if (raw.isSymbol()) return raw;

    const converted = try vm.checkCallMethodByName(raw, "to_sym", false, &.{}, null) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "category must be a Symbol or nil", .{});
    };
    if (!converted.isSymbol()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "category must be a Symbol or nil", .{});
    }
    return converted;
}

fn warningUplevel(vm: *VM, uplevel_value: ?Value) VMError!?usize {
    const raw = uplevel_value orelse return null;
    if (raw.isNil()) return null;

    const depth = try raw.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "integer too big to convert",
    );
    if (depth < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "uplevel must be non-negative", .{});
    }
    return @intCast(depth);
}

fn warningLocationForUplevel(vm: *VM, depth: usize) ?WarningLocation {
    var remaining = depth;
    var i = vm.frames.items.len;
    while (i > 0) {
        i -= 1;
        const frame = &vm.frames.items[i];
        if (frame.frame_type == .builtin) continue;
        const source = frame.chunk.source_file orelse frame.chunk.name;

        if (std.mem.startsWith(u8, source, "<internal:")) continue;
        if (frame.method_name) |method_name| {
            if (std.mem.eql(u8, method_name, "require") or std.mem.eql(u8, method_name, "require_relative")) continue;
        }

        if (remaining == 0) {
            return .{
                .source = source,
                .line = vm.backtraceLineForFrame(frame),
            };
        }
        remaining -= 1;
    }
    return null;
}

fn warningSupportsKeywordCategory(method: vm_mod.ResolvedMethod) bool {
    return switch (method.entry.method) {
        .builtin => true,
        .proc => false,
        .chunk => |method_chunk| blk: {
            for (method_chunk.required_keywords.items) |req_kw| {
                const name = method_chunk.constants.items[req_kw.name_idx].string;
                if (std.mem.eql(u8, name, "category")) break :blk true;
            }
            for (method_chunk.optional_keywords.items) |opt_kw| {
                const name = method_chunk.constants.items[opt_kw.name_idx].string;
                if (std.mem.eql(u8, name, "category")) break :blk true;
            }
            break :blk false;
        },
        .undefined => false,
    };
}

const WarningDispatchMode = enum {
    keyword,
    positional_hash,
    plain,
};

fn warningDispatchMode(method: vm_mod.ResolvedMethod) WarningDispatchMode {
    return switch (method.entry.method) {
        .builtin => .keyword,
        .proc => .positional_hash,
        .chunk => |method_chunk| blk: {
            if (warningSupportsKeywordCategory(method)) break :blk .keyword;
            if (method_chunk.rest_param_index != null or method_chunk.keyword_rest_index != null) break :blk .positional_hash;
            break :blk .plain;
        },
        .undefined => .plain,
    };
}

fn formatWarnMessage(vm: *VM, arg: Value, uplevel: ?usize) VMError!Value {
    const message_val = try vm.callMethodByName(arg, "to_s", &.{}, null);
    if (!message_val.isString()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "to_s did not return String", .{});
    }

    const message = message_val.toStringObject().str;
    const full_message = if (uplevel) |depth|
        if (warningLocationForUplevel(vm, depth)) |location|
            std.fmt.allocPrint(vm.allocator, "{s}:{d}: warning: {s}", .{ location.source, location.line, message }) catch return error.Fatal
        else
            std.fmt.allocPrint(vm.allocator, "warning: {s}", .{message}) catch return error.Fatal
    else
        std.fmt.allocPrint(vm.allocator, "{s}", .{message}) catch return error.Fatal;
    defer vm.allocator.free(full_message);

    if (std.mem.endsWith(u8, full_message, "\n")) {
        return vm.newString(full_message, false);
    }

    const terminated = std.fmt.allocPrint(vm.allocator, "{s}\n", .{full_message}) catch return error.Fatal;
    defer vm.allocator.free(terminated);
    return vm.newString(terminated, false);
}

fn dispatchWarning(vm: *VM, receiver: Value, warning_message: Value, category: ?Value) VMError!void {
    const warning_receiver = Value.fromObject(&vm.warning_module.object);
    if (receiver.raw == warning_receiver.raw) {
        try warning_builtin.writeWarning(vm, warning_message.toStringObject().str);
        return;
    }

    const warn_sym = try vm.intern("warn");
    const resolved = try vm.findMethod(warning_receiver, warn_sym) orelse return error.Fatal;
    const category_sym = try vm.intern("category");
    const category_value = category orelse Value.nil();

    switch (warningDispatchMode(resolved)) {
        .keyword => {
            var warn_args = [_]Value{warning_message};
            var kw_keys = [_]Value{Value.fromObject(&category_sym.object)};
            var kw_values = [_]Value{category_value};
            _ = vm.callMethodByNameWithKeywords(
                warning_receiver,
                "warn",
                warn_args[0..],
                kw_keys[0..],
                kw_values[0..],
                null,
            ) catch |err| {
                if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.argument_error_class) {
                    vm.setPendingException(null);
                } else {
                    return err;
                }

                const kw_hash = try vm.createHash();
                try vm.hashSetEntry(kw_hash, Value.fromObject(&category_sym.object), category_value);
                var fallback_args = [_]Value{ warning_message, Value.fromObject(&kw_hash.object) };
                _ = vm.callMethodByName(warning_receiver, "warn", fallback_args[0..], null) catch |fallback_err| {
                    if (fallback_err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.argument_error_class) {
                        vm.setPendingException(null);
                    } else {
                        return fallback_err;
                    }

                    var plain_args = [_]Value{warning_message};
                    _ = try vm.callMethodByName(warning_receiver, "warn", plain_args[0..], null);
                    return;
                };
                return;
            };
        },
        .positional_hash => {
            const kw_hash = try vm.createHash();
            try vm.hashSetEntry(kw_hash, Value.fromObject(&category_sym.object), category_value);
            var warn_args = [_]Value{ warning_message, Value.fromObject(&kw_hash.object) };
            _ = vm.callMethodByName(warning_receiver, "warn", warn_args[0..], null) catch |err| {
                if (err == error.Unwind and vm.pendingException() != null and vm.pendingException().?.object.class == vm.argument_error_class) {
                    vm.setPendingException(null);
                    var plain_args = [_]Value{warning_message};
                    _ = try vm.callMethodByName(warning_receiver, "warn", plain_args[0..], null);
                    return;
                }
                return err;
            };
        },
        .plain => {
            var warn_args = [_]Value{warning_message};
            _ = try vm.callMethodByName(warning_receiver, "warn", warn_args[0..], null);
        },
    }
}

fn kernelWarnEmit(vm: *VM, receiver: Value, arg: Value, uplevel: ?usize, category: ?Value) VMError!void {
    if (arg.isArray()) {
        for (arg.toArrayObject().elements.items) |elem| {
            try kernelWarnEmit(vm, receiver, elem, uplevel, category);
        }
        return;
    }

    const warning_message = try formatWarnMessage(vm, arg, uplevel);
    try dispatchWarning(vm, receiver, warning_message, category);
}

pub fn builtinKernelWarn(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    var uplevel_value: ?Value = null;
    var category_value: ?Value = null;
    try vm.consumeKeywordArgs(.{ "uplevel", "category" }, .{ &uplevel_value, &category_value });
    try vm.validateKeywordArgsConsumed();

    const verbose = vm.globals.get("$VERBOSE") orelse Value.nil();
    if (verbose.isNil()) return Value.nil();
    if (args.len == 0) return Value.nil();

    const uplevel = try warningUplevel(vm, uplevel_value);
    const category = try warningCategorySymbol(vm, category_value);

    for (args) |arg| {
        try kernelWarnEmit(vm, receiver, arg, uplevel, category);
    }
    return Value.nil();
}

pub fn builtinKernelProc(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Proc object without a block",
        );
        vm.setPendingException(exc);
        return error.Unwind;
    };

    return try vm.newProc(blk);
}

pub fn builtinKernelLambda(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Lambda without a block",
        );
        vm.setPendingException(exc);
        return error.Unwind;
    };

    // Mark bytecode-backed blocks as lambda; symbol procs are already lambda-like.
    switch (blk.kind) {
        .chunk => |chunk_blk| chunk_blk.chunk.is_lambda = true,
        .symbol, .builtin, .callable => {},
    }

    return try vm.newProc(blk);
}

pub fn builtinKernelRaise(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (vm.frames.items.len > 0 and vm.currentFrame().frame_type == .builtin) {
        vm.popCurrentBuiltinFrame();
    }
    return vm.raiseFromArgs(args, "No exception to re-raise");
}

fn moduleIncludedInChain(vm: *VM, receiver: Value, mod: *const ModuleObject) bool {
    if (receiver.getSingletonClass()) |sc| {
        var current: ?*ClassObject = sc;
        while (current) |c| {
            const m = &c.module;
            if (m == mod) return true;
            for (m.prepended_modules.items) |prepended| {
                if (prepended == mod) return true;
            }
            for (m.included_modules.items) |included| {
                if (included == mod) return true;
            }
            if (c.attached_object != null) break;
            current = c.superclass;
        }
    }
    var current: ?*ClassObject = vm.getClass(receiver);
    while (current) |c| {
        const m = &c.module;
        if (m == mod) return true;
        for (m.prepended_modules.items) |prepended| {
            if (prepended == mod) return true;
        }
        for (m.included_modules.items) |included| {
            if (included == mod) return true;
        }
        current = c.superclass;
    }
    return false;
}

pub fn builtinKernelIsA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isClass()) {
        const cls = arg.toClassObject();
        if (receiver.getSingletonClass()) |sc| {
            var current: ?*ClassObject = sc;
            while (current) |c| {
                if (c == cls) return Value.boolean(true);
                if (c.attached_object != null) break;
                current = c.superclass;
            }
        }
        var current: ?*ClassObject = vm.getClass(receiver);
        while (current) |c| {
            if (c == cls) return Value.boolean(true);
            current = c.superclass;
        }
        return Value.boolean(false);
    } else if (arg.isModule()) {
        return Value.boolean(moduleIncludedInChain(vm, receiver, arg.toModuleObject()));
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "class or module required", .{});
    }
}

pub fn builtinKernelInstanceOf(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isClass()) {
        return Value.boolean(vm.getClass(receiver) == arg.toClassObject());
    } else if (arg.isModule()) {
        return Value.boolean(false);
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "class or module required", .{});
    }
}

pub fn builtinKernelRespondTo(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const method_name_sym = try vm.coerceToMethodNameSymbol(args[0]);
    const include_private = if (args.len == 2) args[1].is_truthy() else false;
    if (try vm.findMethod(receiver, method_name_sym)) |resolved| {
        if (include_private or resolved.entry.visibility == .public) {
            return Value.boolean(true);
        }
    }

    var respond_args: [2]Value = .{
        Value.fromObject(&method_name_sym.object),
        Value.boolean(include_private),
    };
    const hook_result = try vm.callMethodByName(receiver, "respond_to_missing?", &respond_args, null);
    return Value.boolean(hook_result.is_truthy());
}

pub fn builtinKernelRespondToMissing(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    _ = try vm.coerceToMethodNameSymbol(args[0]);
    return Value.boolean(false);
}

pub fn builtinKernelNotMatch(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const match_result = try vm.callMethodByName(receiver, "=~", args, null);
    return Value.boolean(!match_result.is_truthy());
}

pub fn builtinKernelInitializeCopy(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    if (receiver.objectId() == args[0].objectId()) {
        return receiver;
    }

    if (receiver.isFrozen()) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen {s}", .{vm.className(receiver)});
    }

    if (vm.getClass(receiver) != vm.getClass(args[0])) {
        return vm.raiseExceptionFmt(vm.type_error_class, "initialize_copy should take same class object", .{});
    }

    return receiver;
}

pub fn builtinKernelInitializeDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    _ = try vm.callMethodByName(receiver, "initialize_copy", args[0..1], null);
    return receiver;
}

pub fn builtinKernelDup(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (receiver.isRegexp()) {
        const regexp = receiver.toRegexpObject();
        const duplicate = try vm.newRegexpWithEncoding(regexp.pattern, regexp.options, regexp.encoding);
        duplicate.toRegexpObject().object.class = vm.getClass(receiver);
        duplicate.toRegexpObject().object.flags &= ~@as(u32, value.Object.FROZEN_FLAG);

        const src_obj = receiver.getObjectPointer() orelse return error.Fatal;
        const dst_obj = duplicate.getObjectPointer() orelse return error.Fatal;
        try vm.copyObjectInstanceVariables(src_obj, dst_obj);
        duplicate.toRegexpObject().object.flags = 0;
        return duplicate;
    }

    const duplicate = try vm.newObjectForClass(vm.getClass(receiver));
    const src_obj = receiver.getObjectPointer() orelse return receiver;
    const dst_obj = duplicate.getObjectPointer() orelse return error.Fatal;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    var initialize_dup_args = [_]Value{receiver};
    _ = try vm.callMethodByName(duplicate, "initialize_dup", initialize_dup_args[0..], null);
    return duplicate;
}

pub fn builtinKernelInitializeClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    _ = try vm.consumeCloneFreezeOpt();

    _ = try vm.callMethodByName(receiver, "initialize_copy", args[0..1], null);
    return receiver;
}

pub fn builtinKernelClone(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const kwfreeze = try vm.consumeCloneFreezeOpt();
    if (receiver.isSymbol() or receiver.isFloat() or receiver.isBigInteger() or receiver.isRational()) {
        if (kwfreeze.isFalse()) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "can't unfreeze {s}", .{vm.className(receiver)});
        }
        return receiver;
    }
    const src_obj = receiver.getObjectPointer() orelse {
        if (kwfreeze.isFalse()) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "can't unfreeze {s}", .{vm.className(receiver)});
        }
        return receiver;
    };
    const duplicate = try vm.newObjectForClass(vm.getClass(receiver));
    const dst_obj = duplicate.getObjectPointer() orelse return error.Fatal;
    try vm.copyObjectInstanceVariables(src_obj, dst_obj);

    try vm.callInitializeClone(duplicate, receiver, kwfreeze);
    vm.applyCloneFreeze(receiver, duplicate, kwfreeze);
    try vm.copySingletonClassMetadata(receiver, duplicate);
    return duplicate;
}

pub fn builtinKernelBlockGiven(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const frame = vm.currentRubyCallerFrame() orelse return Value.boolean(false);
    return Value.boolean(frame.block != null);
}

pub fn builtinKernelAtExit(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = try vm.requireBlock(block);
    const proc_val = try vm.newProc(blk);
    vm.at_exit_handlers.append(vm.gc_allocator, proc_val) catch return error.Fatal;
    return proc_val;
}

pub fn builtinKernelCatch(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const blk = block orelse {
        const exc = try vm.createException(vm.local_jump_error_class, "no block given");
        vm.setPendingException(exc);
        return error.Unwind;
    };
    const tag = if (args.len == 1) args[0] else try vm.newInstance(vm.object_class);

    try vm.pushActiveCatch(tag);
    defer vm.popActiveCatch();

    const yielded = vm.yieldToBlock(blk, &[_]Value{tag}) catch |err| {
        if (err == error.Unwind and vm.pendingThrow() != null and vm.throwTagsMatch(vm.pendingThrow().?.tag, tag)) {
            const thrown_value = vm.pendingThrow().?.value;
            vm.clearPendingThrow();
            return thrown_value;
        }
        return err;
    };

    if (yielded.controlFlowValue()) |return_value| return return_value;
    return yielded.value;
}

pub fn builtinKernelThrow(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const tag = args[0];
    const thrown_value = if (args.len == 2) args[1] else Value.nil();

    if (!vm.hasActiveCatch(tag)) {
        vm.setPendingException(try vm.createUncaughtThrowError(tag, thrown_value));
        return error.Unwind;
    }

    try vm.startThrow(tag, thrown_value);
    return Value.nil();
}

pub fn builtinKernelLoop(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);

    while (true) {
        const result = try vm.yieldToBlock(blk, &[_]Value{});
        if (result.controlFlowValue()) |return_value| return return_value;
        try vm.maybePreemptCurrentThread(true);
    }
}

pub fn builtinKernelSleep(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    if (args.len == 0 or args[0].isNil()) {
        const thread = vm.current_thread orelse {
            try vm.schedulerYield();
            return Value.integer(0);
        };

        if (vm.main_thread != null and thread == vm.main_thread.?) {
            // Avoid deadlocking the cooperative scheduler on indefinite main-thread sleep.
            try vm.schedulerYield();
            return Value.integer(0);
        }

        thread.state = .sleeping;
        try vm.threadYield();
        return Value.integer(0);
    }

    const seconds = try sleepSecondsArg(vm, args[0]);
    if (seconds < 0.0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "time interval must be non-negative", .{});
    }

    if (seconds == 0.0) {
        try vm.threadYield();
        return Value.integer(0);
    }

    // Cooperative approximation: yield a bounded number of scheduler slices.
    var spin_budget: u32 = @intFromFloat(@min(seconds * 1000.0, 1000.0));
    if (spin_budget == 0) spin_budget = 1;
    while (spin_budget > 0) : (spin_budget -= 1) {
        try vm.threadYield();
    }
    return Value.integer(0);
}

pub fn builtinKernelTap(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = block orelse {
        const exc = try vm.createException(vm.local_jump_error_class, "no block given");
        vm.setPendingException(exc);
        return error.Unwind;
    };
    const result = try vm.yieldToBlock(blk, &[_]Value{receiver});
    if (result.controlFlowValue()) |return_value| return return_value;
    return receiver;
}

pub fn builtinKernelSend(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const name_str = try vm.coerceToMethodNameString(args[0]);
    const call_args = args[1..];
    return vm.callMethodByNameForwardingKeywords(receiver, name_str, call_args, block);
}

pub fn builtinKernelPublicSend(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const name_str = try vm.coerceToMethodNameString(args[0]);
    const call_args = args[1..];
    return vm.callPublicMethodByNameForwardingKeywords(receiver, name_str, call_args, block);
}

fn createBoundMethodObject(vm: *VM, receiver: Value, method_name: *SymbolObject, resolved: vm_mod.ResolvedMethod, owner: Value) VMError!Value {
    return method_builtin.createBoundMethodObject(vm, receiver, method_name, resolved, owner);
}

pub fn builtinKernelMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const method_name = try vm.coerceToMethodNameSymbol(args[0]);

    const resolved = (try vm.findMethod(receiver, method_name)) orelse {
        return vm.raiseExceptionFmt(
            vm.name_error_class,
            "undefined method '{s}'",
            .{method_name.name},
        );
    };

    const owner = (try method_common.resolveMethodOwnerValue(vm, receiver, method_name)) orelse Value.fromObject(&resolved.owner_class.module.object);
    return createBoundMethodObject(vm, receiver, method_name, resolved, owner);
}

pub fn builtinKernelSingletonMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const method_name = try vm.coerceToMethodNameSymbol(args[0]);
    if (receiver.isNil() or receiver.isTrue() or receiver.isFalse()) {
        return vm.raiseExceptionFmt(
            vm.name_error_class,
            "undefined method '{s}'",
            .{method_name.name},
        );
    }
    const singleton_class = receiver.getSingletonClass() orelse {
        return vm.raiseExceptionFmt(
            vm.name_error_class,
            "undefined method '{s}'",
            .{method_name.name},
        );
    };

    const lookup = lookupSingletonMethodOnly(singleton_class, method_name) orelse {
        return vm.raiseExceptionFmt(
            vm.name_error_class,
            "undefined method '{s}'",
            .{method_name.name},
        );
    };

    return createBoundMethodObject(vm, receiver, method_name, lookup.resolved, lookup.owner);
}

fn kernelEnumForCommon(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const method_name = if (args.len == 0)
        try vm.intern("each")
    else
        try vm.coerceToMethodNameSymbol(args[0]);
    const method_args = if (args.len == 0) &[_]Value{} else args[1..];

    const size = if (block) |blk|
        try vm.newProc(blk)
    else
        null;

    return vm.createMethodEnumeratorWithSize(receiver, method_name, method_args, size);
}

pub fn builtinKernelToEnum(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return kernelEnumForCommon(vm, receiver, args, block);
}

pub fn builtinKernelEnumFor(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return kernelEnumForCommon(vm, receiver, args, block);
}

pub fn builtinKernelDefineSingletonMethod(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const name_str = try vm.coerceToMethodNameString(args[0]);
    const name_sym = try vm.intern(name_str);
    const method_entry: MethodEntry = if (args.len == 2) blk: {
        const body = args[1];
        if (body.isProc()) {
            break :blk .{ .method = .{ .proc = body.toProcObject() }, .visibility = .public };
        }

        if (body.isObject() and (vm.getClass(body) == vm.method_class or vm.getClass(body) == vm.unbound_method_class)) {
            const method_name = if (body.isMethodObject())
                body.toMethodObject().name
            else if (body.isUnboundMethodObject())
                body.toUnboundMethodObject().name
            else
                return error.Fatal;
            const method_owner = if (body.isMethodObject())
                body.toMethodObject().owner
            else if (body.isUnboundMethodObject())
                body.toUnboundMethodObject().owner
            else
                return error.Fatal;

            const attached_owner = if (method_owner.isClass())
                method_owner.toClassObject().attached_object
            else
                null;
            if (attached_owner) |attached| {
                if (attached.isClass() and receiver.isClass()) {
                    if (!isClassOrSubclassOf(receiver.toClassObject(), attached.toClassObject())) {
                        return vm.raiseExceptionFmt(vm.type_error_class, "can't bind singleton method to a different class", .{});
                    }
                } else if (attached.objectId() != receiver.objectId()) {
                    return vm.raiseExceptionFmt(vm.type_error_class, "can't bind singleton method to a different class", .{});
                }
            }

            const method_entry = method_common.methodEntryForOwner(method_owner, method_name) orelse {
                return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{method_name.name});
            };
            var copied = method_entry;
            copied.visibility = .public;
            break :blk copied;
        }

        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Proc/Method/UnboundMethod)", .{vm.className(body)});
    } else blk: {
        const proc_val = try vm.newProc(try vm.requireBlock(block));
        break :blk .{ .method = .{ .proc = proc_val.toProcObject() }, .visibility = .public };
    };

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    if ((singleton_class.module.object.flags & value.Object.FROZEN_FLAG) != 0) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen {s}", .{vm.className(receiver)});
    }

    singleton_class.module.methods.put(name_sym, method_entry) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(&name_sym.object);
}

pub fn builtinKernelExtend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    if ((singleton_class.module.object.flags & value.Object.FROZEN_FLAG) != 0) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen {s}", .{vm.className(receiver)});
    }

    for (args) |arg| {
        if (!arg.isModule()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Module)", .{vm.className(arg)});
        }
        try vm.includeModule(&singleton_class.module, arg.toModuleObject());
    }

    vm.markIntegerChangedForReceiver(receiver);
    return receiver;
}

pub fn builtinKernelMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectKernelMethods(vm, receiver, .public_and_protected, include_super);
}

pub fn builtinKernelSingletonMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectSingletonMethods(vm, receiver, include_super);
}

pub fn builtinKernelPrivateMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectKernelMethods(vm, receiver, .private_only, include_super);
}

pub fn builtinKernelInstanceVariableGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const name_str = try vm.coerceToIvarName(args[0]);
    return vm.getInstanceVariable(receiver, name_str) catch return error.Fatal;
}

pub fn builtinKernelInstanceVariableDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const name_str = try vm.coerceToIvarName(args[0]);
    return Value.boolean(try vm.hasInstanceVariable(receiver, name_str));
}

pub fn builtinKernelInstanceVariableSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const name_str = try vm.coerceToIvarName(args[0]);
    try vm.setInstanceVariable(receiver, name_str, args[1]);
    return args[1];
}

pub fn builtinKernelInstanceVariables(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const array = try vm.getInstanceVariableNames(receiver);
    return Value.fromObject(&array.object);
}

pub fn builtinKernelToS(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const class_name = vm.getClass(receiver);
    const class_name_val = try module_builtin.builtinModuleToS(vm, Value.fromObject(&class_name.module.object), &[_]Value{}, null);
    if (!class_name_val.isString()) return error.Fatal;

    const object_id = receiver.objectId();

    const str = std.fmt.allocPrint(vm.gc_allocator, "#<{s}:0x{x}>", .{ class_name_val.toStringObject().str, object_id }) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinKernelInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinKernelToS(vm, receiver, args, null);
}

fn builtinKernelItself(_: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    return receiver;
}

pub fn builtinKernelHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_value: i64 = @bitCast(receiver.hash());
    return Value.integer(hash_value);
}

fn builtinKernelArrayConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isNil()) {
        const array = try vm.createArray();
        return Value.fromObject(&array.object);
    }

    switch (try vm.probeToAryWithVisibility(arg, true)) {
        .array => |array| return array,
        .missing, .nil_result => {},
    }

    if (try vm.checkCallMethodByName(arg, "to_a", true, &[_]Value{}, null)) |coerced| {
        if (coerced.isNil()) {
            const wrapped = try vm.createArray();
            wrapped.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
            return Value.fromObject(&wrapped.object);
        }
        if (coerced.isArray()) return coerced;

        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Array ({s}#to_a gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(coerced) },
        );
    }

    const wrapped = try vm.createArray();
    wrapped.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    return Value.fromObject(&wrapped.object);
}

fn builtinKernelStringConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isString()) return arg;

    const to_str_sym = try vm.intern("to_str");
    const to_s_sym = try vm.intern("to_s");

    if (try vm.respondsToMethodByName(arg, to_str_sym.name, false)) {
        const converted = vm.callMethodByName(arg, "to_str", &[_]Value{}, null) catch |err| switch (err) {
            error.Unwind => {
                if (vm.pendingException()) |exc| {
                    if (exc.object.class == vm.no_method_error_class) {
                        vm.setPendingException(null);
                        return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into String", .{vm.className(arg)});
                    }
                }
                return error.Unwind;
            },
            else => return err,
        };
        if (!converted.isString()) {
            return vm.raiseExceptionFmt(
                vm.type_error_class,
                "can't convert {s} to String ({s}#to_str gives {s})",
                .{ vm.className(arg), vm.className(arg), vm.className(converted) },
            );
        }
        return converted;
    }

    if (!try vm.respondsToMethodByName(arg, to_s_sym.name, false)) {
        if (try vm.findMethod(arg, to_s_sym) != null) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into String", .{vm.className(arg)});
        }
    }

    const converted = vm.callMethodByName(arg, "to_s", &[_]Value{}, null) catch |err| switch (err) {
        error.Unwind => {
            if (vm.pendingException()) |exc| {
                if (exc.object.class == vm.no_method_error_class) {
                    vm.setPendingException(null);
                    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into String", .{vm.className(arg)});
                }
            }
            return error.Unwind;
        },
        else => return err,
    };

    if (!converted.isString()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to String ({s}#to_s gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(converted) },
        );
    }

    return converted;
}

fn builtinKernelIntegerConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isInteger() or arg.isBigInteger()) return arg;

    if (try vm.checkCallMethodByName(arg, "to_int", true, &[_]Value{}, null)) |coerced| {
        if (coerced.isInteger() or coerced.isBigInteger()) return coerced;
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Integer ({s}#to_int gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(coerced) },
        );
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert {s} into Integer", .{vm.className(arg)});
}

fn builtinKernelHashConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isNil()) {
        const hash = try vm.createHash();
        return Value.fromObject(&hash.object);
    }

    if (arg.isArray() and arg.toArrayObject().elements.items.len == 0) {
        const hash = try vm.createHash();
        return Value.fromObject(&hash.object);
    }

    return switch (try vm.probeToHash(arg)) {
        .hash => |hash| hash,
        .missing, .nil_result => vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} into Hash",
            .{vm.className(arg)},
        ),
        .non_hash => |coerced| vm.raiseExceptionFmt(
            vm.type_error_class,
            "can't convert {s} to Hash ({s}#to_hash gives {s})",
            .{ vm.className(arg), vm.className(arg), vm.className(coerced) },
        ),
    };
}

pub fn builtinKernelNil(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(false);
}

pub fn builtinKernelFreeze(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isString()) {
        const string_obj = receiver.toStringObject();
        const object = receiver.getObjectPointer().?;
        const bare_string = vm.getClass(receiver) == vm.string_class and object.instance_variables == null;
        if (string_obj.chilled_literal and bare_string) {
            _ = try vm.getOrCreateCanonicalFStringValue(receiver);
        }
    }
    var mutable_receiver = receiver;
    mutable_receiver.freeze();
    return receiver;
}

pub fn builtinKernelFrozen(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.boolean(receiver.isFrozen());
}

pub fn builtinKernelSingletonClass(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (receiver.isNil()) return Value.fromObject(&vm.nil_class.module.object);
    if (receiver.isBool()) return Value.fromObject(&(if (receiver.toBool()) vm.true_class else vm.false_class).module.object);
    if (receiver.isInteger() or receiver.isFloat() or receiver.isSymbol()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't define singleton", .{});
    }
    if (vm.isCanonicalFStringValue(receiver)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't define singleton", .{});
    }

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    return Value.fromObject(&singleton_class.module.object);
}

pub fn builtinKernelDir(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (vm.frames.items.len > 0 and vm.currentFrame().dir_returns_nil) {
        return Value.nil();
    }

    const current_file = if (vm.frames.items.len > 0)
        vm.currentFrame().chunk.source_file
    else
        vm.current_loading_file;

    if (current_file) |path| {
        if (std.fs.path.isAbsolute(path) or vm.fileExists(path)) {
            const abs_path = vm.resolveAbsolutePath(path) catch return error.Fatal;
            defer vm.allocator.free(abs_path);

            const abs_dir = std.fs.path.dirname(abs_path) orelse ".";
            return try vm.newString(abs_dir, false);
        }

        const dir = std.fs.path.dirname(path) orelse ".";
        return try vm.newString(dir, false);
    }

    return try vm.newString(".", false);
}

pub fn builtinKernelP(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const stdout_target = vm.globals.get("$stdout") orelse return error.Fatal;
    if (args.len == 0) {
        _ = try vm.callMethodByName(stdout_target, "puts", &[_]Value{}, null);
        return Value.nil();
    }

    for (args) |arg| {
        const inspected = try arg.inspect(vm);
        var put_args: [1]Value = .{inspected};
        _ = try vm.callMethodByName(stdout_target, "puts", &put_args, null);
    }

    if (args.len == 1) {
        return args[0];
    } else {
        const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_obj.* = .{
            .object = .{ .type_tag = .array, .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
            .elements = .empty,
        };

        for (args) |arg| {
            array_obj.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
        }

        return Value.fromObject(&array_obj.object);
    }
}

pub fn builtinKernelBacktick(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const command = try args[0].coerceToStr(vm, "no implicit conversion into String");

    const argv = if (builtin.os.tag == .windows)
        [_][]const u8{ "cmd.exe", "/C", command }
    else
        [_][]const u8{ "/bin/sh", "-c", command };

    var env_map = try vm.currentEnvMap();
    defer env_map.deinit();
    const run_result = std.process.run(vm.allocator, vm.io, .{
        .argv = &argv,
        .environ_map = &env_map,
        .stderr_limit = .limited(16 * 1024 * 1024),
        .stdout_limit = .limited(16 * 1024 * 1024),
    }) catch |err| {
        const msg = std.fmt.allocPrint(vm.gc_allocator, "failed to execute command: {s}", .{@errorName(err)}) catch return error.Fatal;
        const exc = try vm.createException(vm.runtime_error_class, msg);
        vm.setPendingException(exc);
        return error.Unwind;
    };
    defer vm.allocator.free(run_result.stdout);
    defer vm.allocator.free(run_result.stderr);
    const stdout_bytes = run_result.stdout;

    const exitstatus: i64 = switch (run_result.term) {
        .exited => |code| @intCast(code),
        .signal => |sig| 128 + @as(i64, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i64, @intCast(@intFromEnum(sig))),
        else => 1,
    };
    try vm.setLastProcessStatus(exitstatus);

    return try vm.newString(stdout_bytes, false);
}

pub fn builtinProcessStatusExitstatus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.getInstanceVariable(receiver, "@exitstatus");
}

pub fn builtinProcessStatusSuccess(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const exitstatus = try vm.getInstanceVariable(receiver, "@exitstatus");
    return Value.boolean(exitstatus.isInteger() and exitstatus.toInteger() == 0);
}

pub fn builtinProcessStatusExited(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const raw_status = try vm.getInstanceVariable(receiver, "@raw_status");
    if (!raw_status.isInteger()) return Value.boolean(false);
    return Value.boolean((raw_status.toInteger() & 0x7f) == 0);
}

pub fn builtinProcessStatusSignaled(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const raw_status = try vm.getInstanceVariable(receiver, "@raw_status");
    if (!raw_status.isInteger()) return Value.boolean(false);
    const signal_bits = raw_status.toInteger() & 0x7f;
    return Value.boolean(signal_bits != 0 and signal_bits != 0x7f);
}

pub fn builtinProcessStatusTermsig(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.getInstanceVariable(receiver, "@termsig");
}

pub fn builtinKernelRand(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    if (args.len == 0) {
        var prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.boot.now(vm.io).nanoseconds));
        const n = prng.random().int(u53);
        return try vm.newFloat(@as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(std.math.maxInt(u53))));
    }

    if (!args[0].isInteger()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion into Integer", .{});
    }

    const limit = args[0].toInteger();
    if (limit <= 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid argument - {d}", .{limit});
    }

    var prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.boot.now(vm.io).nanoseconds));
    const random_value = prng.random().intRangeLessThan(u64, 0, @intCast(limit));
    return Value.integer(@intCast(random_value));
}

fn sleepSecondsArg(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isInteger()) return arg.integerToF64();
    if (arg.isFloat()) return arg.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Float", .{});
}

fn flushForkChildOutputs(vm: *VM) void {
    if (vm.stdout) |out| _ = out.flush() catch {};
    if (vm.stderr) |err_out| _ = err_out.flush() catch {};
}

fn exitForkChild(vm: *VM, status: u8) noreturn {
    flushForkChildOutputs(vm);
    std.c._exit(status);
}

fn finishForkChild(vm: *VM, block_err: ?anyerror) noreturn {
    const at_exit_result = vm.runAtExitHandlers();
    if (at_exit_result) |_| {
        // at_exit handlers completed
    } else |err| switch (err) {
        error.UnhandledException => {
            if (vm.unhandledExceptionExitStatus()) |status| {
                exitForkChild(vm, status);
            }
            vm.printUnhandledException();
            exitForkChild(vm, 1);
        },
        else => exitForkChild(vm, 1),
    }

    if (block_err) |err| {
        switch (err) {
            error.Unwind, error.UnhandledException => {
                if (vm.pendingException() != null) {
                    if (vm.unhandledExceptionExitStatus()) |status| {
                        exitForkChild(vm, status);
                    }
                    vm.printUnhandledException();
                }
            },
            else => {},
        }
        exitForkChild(vm, 1);
    }

    exitForkChild(vm, 0);
}

pub fn builtinKernelFork(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (builtin.os.tag == .windows) {
        return vm.raiseExceptionFmt(vm.not_implemented_error_class, "fork is not implemented on Windows", .{});
    }

    // Flush buffered stdout/stderr before forking so both processes start with empty buffers.
    vm.setupOutput();
    if (vm.stdout) |out| _ = out.flush() catch {};
    if (vm.stderr) |err_out| _ = err_out.flush() catch {};

    const rc = std.c.fork();
    if (rc < 0) {
        return vm.raiseExceptionFmt(vm.runtime_error_class, "fork failed", .{});
    }

    if (rc > 0) {
        // parent
        return Value.integer(@intCast(rc));
    }

    // child
    if (block) |blk| {
        const result = vm.yieldToBlock(blk, &[_]Value{}) catch |err| {
            finishForkChild(vm, err);
        };
        _ = result;
        finishForkChild(vm, null);
    }

    return Value.nil();
}
