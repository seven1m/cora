const std = @import("std");
const builtin = @import("builtin");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const method_reflection = @import("method_reflection.zig");
const module_builtin = @import("module.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;
const MethodEntry = value.MethodEntry;
const SymbolObject = value.SymbolObject;
const MethodListFilter = method_reflection.MethodListFilter;

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

fn resolveMethodOwnerValue(vm: *VM, receiver: Value, method_name_sym: *SymbolObject) VMError!?Value {
    const scanClass = struct {
        fn run(vm_inner: *VM, class_obj: *ClassObject, name_sym: *SymbolObject) ?Value {
            var current: ?*ClassObject = class_obj;
            while (current) |klass| {
                var i = klass.module.prepended_modules.items.len;
                while (i > 0) {
                    i -= 1;
                    const prepended = klass.module.prepended_modules.items[i];
                    if (prepended.methods.get(name_sym)) |entry| {
                        if (entry.method == .undefined) return null;
                        return Value.fromObject(prepended);
                    }
                }

                if (klass.module.methods.get(name_sym)) |entry| {
                    if (entry.method == .undefined) return null;
                    return Value.fromObject(klass);
                }

                i = klass.module.included_modules.items.len;
                while (i > 0) {
                    i -= 1;
                    const included = klass.module.included_modules.items[i];
                    if (included.methods.get(name_sym)) |entry| {
                        if (entry.method == .undefined) return null;
                        return Value.fromObject(included);
                    }
                }

                current = klass.superclass;
            }

            _ = vm_inner;
            return null;
        }
    }.run;

    if (receiver.getObjectPointer() != null) {
        const singleton_class = try vm.getOrCreateSingletonClass(receiver);
        if (scanClass(vm, singleton_class, method_name_sym)) |owner| return owner;
    }

    return scanClass(vm, vm.getClass(receiver), method_name_sym);
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
            return resolveMethodEntry(method_name, singleton_class, Value.fromObject(prepended), entry);
        }
    }

    if (singleton_class.module.methods.get(method_name)) |entry| {
        return resolveMethodEntry(method_name, singleton_class, Value.fromObject(singleton_class), entry);
    }

    i = singleton_class.module.included_modules.items.len;
    while (i > 0) {
        i -= 1;
        const included = singleton_class.module.included_modules.items[i];
        if (included.methods.get(method_name)) |entry| {
            return resolveMethodEntry(method_name, singleton_class, Value.fromObject(included), entry);
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
    const puts_sym = try vm.intern("puts");
    try vm.kernel_module.methods.put(puts_sym, .{ .method = .{ .builtin = &builtinKernelPuts } });

    const print_sym = try vm.intern("print");
    try vm.kernel_module.methods.put(print_sym, .{ .method = .{ .builtin = &builtinKernelPrint } });

    const eval_sym = try vm.intern("eval");
    try vm.kernel_module.methods.put(eval_sym, .{ .method = .{ .builtin = &builtinKernelEval } });

    const binding_sym = try vm.intern("binding");
    try vm.kernel_module.methods.put(binding_sym, .{
        .method = .{ .builtin = &builtinKernelBinding },
        .visibility = .private,
    });

    const proc_sym = try vm.intern("proc");
    try vm.kernel_module.methods.put(proc_sym, .{ .method = .{ .builtin = &builtinKernelProc } });

    const lambda_sym = try vm.intern("lambda");
    try vm.kernel_module.methods.put(lambda_sym, .{ .method = .{ .builtin = &builtinKernelLambda } });

    const require_sym = try vm.intern("require");
    try vm.kernel_module.methods.put(require_sym, .{ .method = .{ .builtin = &builtinKernelRequire } });

    const require_relative_sym = try vm.intern("require_relative");
    try vm.kernel_module.methods.put(require_relative_sym, .{ .method = .{ .builtin = &builtinKernelRequireRelative } });

    const load_sym = try vm.intern("load");
    try vm.kernel_module.methods.put(load_sym, .{ .method = .{ .builtin = &builtinKernelLoad } });

    const instance_variable_get_sym = try vm.intern("instance_variable_get");
    try vm.kernel_module.methods.put(instance_variable_get_sym, .{ .method = .{ .builtin = &builtinKernelInstanceVariableGet } });

    const instance_variable_set_sym = try vm.intern("instance_variable_set");
    try vm.kernel_module.methods.put(instance_variable_set_sym, .{ .method = .{ .builtin = &builtinKernelInstanceVariableSet } });

    const to_s_sym = try vm.intern("to_s");
    try vm.kernel_module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinKernelToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.kernel_module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinKernelInspect } });

    const kernel_hash_convert_sym = try vm.intern("Hash");
    try vm.kernel_module.methods.put(kernel_hash_convert_sym, .{
        .method = .{ .builtin = &builtinKernelHashConvert },
        .visibility = .private,
    });

    const kernel_module_val = Value.fromObject(vm.kernel_module);
    const kernel_singleton = try vm.getOrCreateSingletonClass(kernel_module_val);
    try kernel_singleton.module.methods.put(kernel_hash_convert_sym, .{ .method = .{ .builtin = &builtinKernelHashConvert } });

    const hash_sym = try vm.intern("hash");
    try vm.kernel_module.methods.put(hash_sym, .{ .method = .{ .builtin = &builtinKernelHash } });

    const p_sym = try vm.intern("p");
    try vm.kernel_module.methods.put(p_sym, .{ .method = .{ .builtin = &builtinKernelP } });

    const rand_sym = try vm.intern("rand");
    try vm.kernel_module.methods.put(rand_sym, .{ .method = .{ .builtin = &builtinKernelRand } });

    const raise_sym = try vm.intern("raise");
    try vm.kernel_module.methods.put(raise_sym, .{ .method = .{ .builtin = &builtinKernelRaise } });

    const fail_sym = try vm.intern("fail");
    try vm.kernel_module.methods.put(fail_sym, .{ .method = .{ .builtin = &builtinKernelRaise } });

    const is_a_sym = try vm.intern("is_a?");
    try vm.kernel_module.methods.put(is_a_sym, .{ .method = .{ .builtin = &builtinKernelIsA } });

    const kind_of_sym = try vm.intern("kind_of?");
    try vm.kernel_module.methods.put(kind_of_sym, .{ .method = .{ .builtin = &builtinKernelIsA } });

    const instance_of_sym = try vm.intern("instance_of?");
    try vm.kernel_module.methods.put(instance_of_sym, .{ .method = .{ .builtin = &builtinKernelInstanceOf } });

    const respond_to_sym = try vm.intern("respond_to?");
    try vm.kernel_module.methods.put(respond_to_sym, .{ .method = .{ .builtin = &builtinKernelRespondTo } });

    const respond_to_missing_sym = try vm.intern("respond_to_missing?");
    try vm.kernel_module.methods.put(respond_to_missing_sym, .{
        .method = .{ .builtin = &builtinKernelRespondToMissing },
        .visibility = .private,
    });

    const not_match_sym = try vm.intern("!~");
    try vm.kernel_module.methods.put(not_match_sym, .{ .method = .{ .builtin = &builtinKernelNotMatch } });

    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.kernel_module.methods.put(initialize_copy_sym, .{
        .method = .{ .builtin = &builtinKernelInitializeCopy },
        .visibility = .private,
    });

    const initialize_dup_sym = try vm.intern("initialize_dup");
    try vm.kernel_module.methods.put(initialize_dup_sym, .{
        .method = .{ .builtin = &builtinKernelInitializeDup },
        .visibility = .private,
    });

    const dup_sym = try vm.intern("dup");
    try vm.kernel_module.methods.put(dup_sym, .{ .method = .{ .builtin = &builtinKernelDup } });

    const initialize_clone_sym = try vm.intern("initialize_clone");
    try vm.kernel_module.methods.put(initialize_clone_sym, .{
        .method = .{ .builtin = &builtinKernelInitializeClone },
        .visibility = .private,
    });

    const block_given_sym = try vm.intern("block_given?");
    try vm.kernel_module.methods.put(block_given_sym, .{ .method = .{ .builtin = &builtinKernelBlockGiven } });

    const at_exit_sym = try vm.intern("at_exit");
    try vm.kernel_module.methods.put(at_exit_sym, .{ .method = .{ .builtin = &builtinKernelAtExit } });

    const loop_sym = try vm.intern("loop");
    try vm.kernel_module.methods.put(loop_sym, .{ .method = .{ .builtin = &builtinKernelLoop } });

    const sleep_sym = try vm.intern("sleep");
    try vm.kernel_module.methods.put(sleep_sym, .{ .method = .{ .builtin = &builtinKernelSleep } });

    const tap_sym = try vm.intern("tap");
    try vm.kernel_module.methods.put(tap_sym, .{ .method = .{ .builtin = &builtinKernelTap } });

    const send_sym = try vm.intern("send");
    try vm.kernel_module.methods.put(send_sym, .{ .method = .{ .builtin = &builtinKernelSend } });

    const method_sym = try vm.intern("method");
    try vm.kernel_module.methods.put(method_sym, .{ .method = .{ .builtin = &builtinKernelMethod } });

    const singleton_method_sym = try vm.intern("singleton_method");
    try vm.kernel_module.methods.put(singleton_method_sym, .{ .method = .{ .builtin = &builtinKernelSingletonMethod } });

    const to_enum_sym = try vm.intern("to_enum");
    try vm.kernel_module.methods.put(to_enum_sym, .{ .method = .{ .builtin = &builtinKernelToEnum } });

    const enum_for_sym = try vm.intern("enum_for");
    try vm.kernel_module.methods.put(enum_for_sym, .{ .method = .{ .builtin = &builtinKernelEnumFor } });

    const define_singleton_method_sym = try vm.intern("define_singleton_method");
    try vm.kernel_module.methods.put(define_singleton_method_sym, .{ .method = .{ .builtin = &builtinKernelDefineSingletonMethod } });

    const extend_sym = try vm.intern("extend");
    try vm.kernel_module.methods.put(extend_sym, .{ .method = .{ .builtin = &builtinKernelExtend } });

    const methods_sym = try vm.intern("methods");
    try vm.kernel_module.methods.put(methods_sym, .{ .method = .{ .builtin = &builtinKernelMethods } });

    const singleton_methods_sym = try vm.intern("singleton_methods");
    try vm.kernel_module.methods.put(singleton_methods_sym, .{ .method = .{ .builtin = &builtinKernelSingletonMethods } });

    const private_methods_sym = try vm.intern("private_methods");
    try vm.kernel_module.methods.put(private_methods_sym, .{ .method = .{ .builtin = &builtinKernelPrivateMethods } });

    const nil_sym = try vm.intern("nil?");
    try vm.kernel_module.methods.put(nil_sym, .{ .method = .{ .builtin = &builtinKernelNil } });

    const freeze_sym = try vm.intern("freeze");
    try vm.kernel_module.methods.put(freeze_sym, .{ .method = .{ .builtin = &builtinKernelFreeze } });

    const frozen_sym = try vm.intern("frozen?");
    try vm.kernel_module.methods.put(frozen_sym, .{ .method = .{ .builtin = &builtinKernelFrozen } });

    const singleton_class_sym = try vm.intern("singleton_class");
    try vm.kernel_module.methods.put(singleton_class_sym, .{ .method = .{ .builtin = &builtinKernelSingletonClass } });

    const backtick_sym = try vm.intern("`");
    try vm.kernel_module.methods.put(backtick_sym, .{ .method = .{ .builtin = &builtinKernelBacktick } });

    const dir_sym = try vm.intern("__dir__");
    try vm.kernel_module.methods.put(dir_sym, .{ .method = .{ .builtin = &builtinKernelDir } });

    const exitstatus_sym = try vm.intern("exitstatus");
    try vm.process_status_class.module.methods.put(exitstatus_sym, .{ .method = .{ .builtin = &builtinProcessStatusExitstatus } });

    const fork_sym = try vm.intern("fork");
    try vm.kernel_module.methods.put(fork_sym, .{ .method = .{ .builtin = &builtinKernelFork } });
}

pub fn builtinKernelRequire(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const feature = try vm.coerceToPath(args[0], "no implicit conversion into String");

    // Builtin libraries whose classes are registered at VM startup:
    // `require 'name'` is a no-op after the first call, matching Ruby's "already loaded" semantics.
    const builtin_libs = [_][]const u8{"socket"};
    for (builtin_libs) |lib| {
        if (std.mem.eql(u8, feature, lib)) {
            const key = vm.allocator.dupe(u8, lib) catch return error.Fatal;
            if (vm.loaded_files.contains(key)) {
                vm.allocator.free(key);
                return Value.boolean(false);
            }
            vm.loaded_files.put(key, {}) catch return error.Fatal;
            return Value.boolean(true);
        }
    }

    const absolute_path = vm.searchLoadPath(feature) catch {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        return error.Unwind;
    } orelse {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        return error.Unwind;
    };

    if (vm.loaded_files.contains(absolute_path)) {
        vm.allocator.free(absolute_path);
        return Value.boolean(false);
    }

    vm.loaded_files.put(absolute_path, {}) catch return error.Fatal;

    vm.loadFile(absolute_path) catch |err| {
        _ = vm.loaded_files.remove(absolute_path);
        vm.allocator.free(absolute_path);
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

    return Value.boolean(true);
}

pub fn builtinKernelEval(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 4);
    const source_value = try args[0].coerceToStringValue(vm, "no implicit conversion into String");
    const source_obj = source_value.toStringObject();

    const binding_arg = if (args.len >= 2) args[1] else Value.nil();
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
            .parent_env = binding_obj.env,
            .lexical_scope = binding_obj.lexical_scope,
            .dir_returns_nil = filename == null,
        },
    );
}

pub fn builtinKernelBinding(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    if (vm.frames.items.len > 0) {
        const frame = vm.currentFrame();
        return Value.fromObject(try vm.createBinding(frame.self_value, frame.ep, vm.current_lexical_scope));
    }

    return Value.fromObject(try vm.createBinding(receiver, null, vm.current_lexical_scope));
}

pub fn builtinKernelRequireRelative(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const relative_path = try vm.coerceToPath(args[0], "no implicit conversion into String");

    const current_file = blk: {
        if (vm.frames.items.len > 0) {
            if (vm.currentFrame().chunk.source_file) |source_file| break :blk source_file;
        }
        break :blk vm.current_loading_file orelse {
            const exc = vm.createException(vm.load_error_class, "cannot infer basepath") catch return error.Fatal;
            vm.pending_exception = exc;
            return error.Unwind;
        };
    };

    const current_dir = std.fs.path.dirname(current_file) orelse ".";
    const full_path = std.fs.path.join(vm.allocator, &[_][]const u8{ current_dir, relative_path }) catch return error.Fatal;
    defer vm.allocator.free(full_path);

    var absolute_path: ?[]const u8 = null;
    if (vm.fileExists(full_path)) {
        absolute_path = vm.resolveAbsolutePath(full_path) catch return error.Fatal;
    } else {
        const with_rb = std.fmt.allocPrint(vm.allocator, "{s}.rb", .{full_path}) catch return error.Fatal;
        defer vm.allocator.free(with_rb);
        if (vm.fileExists(with_rb)) {
            absolute_path = vm.resolveAbsolutePath(with_rb) catch return error.Fatal;
        }
    }

    if (absolute_path == null) {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{relative_path}) catch return error.Fatal;
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const resolved_path = absolute_path.?;

    if (vm.loaded_files.contains(resolved_path)) {
        vm.allocator.free(resolved_path);
        return Value.boolean(false);
    }

    vm.loaded_files.put(resolved_path, {}) catch return error.Fatal;
    vm.loadFile(resolved_path) catch |err| {
        _ = vm.loaded_files.remove(resolved_path);
        vm.allocator.free(resolved_path);
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

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
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        return error.Unwind;
    }

    vm.loaded_paths.append(vm.allocator, absolute_path.?) catch return error.Fatal;
    vm.loadFile(absolute_path.?) catch |err| {
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

    return Value.boolean(true);
}

pub fn builtinKernelPuts(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const stdout_target = vm.globals.get("$stdout") orelse return error.Fatal;
    _ = try vm.callMethodByName(stdout_target, "puts", args, null);
    return Value.nil();
}

pub fn builtinKernelPrint(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    const stdout_target = vm.globals.get("$stdout") orelse return error.Fatal;
    _ = try vm.callMethodByName(stdout_target, "print", args, null);
    _ = try vm.callMethodByName(stdout_target, "flush", &[_]Value{}, null);
    return Value.nil();
}

pub fn builtinKernelProc(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Proc object without a block",
        );
        vm.pending_exception = exc;
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
        vm.pending_exception = exc;
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
    return vm.raiseFromArgs(args, "No exception to re-raise");
}

pub fn builtinKernelIsA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    if (arg.isClass()) {
        const cls = arg.toClassObject();
        var current: ?*ClassObject = vm.getClass(receiver);
        while (current) |c| {
            if (c == cls) return Value.boolean(true);
            current = c.superclass;
        }
        return Value.boolean(false);
    } else if (arg.isModule()) {
        const mod = arg.toModuleObject();
        var current: ?*ClassObject = vm.getClass(receiver);
        while (current) |c| {
            if (&c.module == mod) return Value.boolean(true);
            for (c.module.prepended_modules.items) |m| {
                if (m == mod) return Value.boolean(true);
            }
            for (c.module.included_modules.items) |m| {
                if (m == mod) return Value.boolean(true);
            }
            current = c.superclass;
        }
        return Value.boolean(false);
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
        Value.fromObject(method_name_sym),
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
        const duplicate = try vm.newRegexp(regexp.pattern, regexp.options);
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

    _ = try vm.consumeKeywordArg("freeze");
    try vm.validateKeywordArgsConsumed();

    _ = try vm.callMethodByName(receiver, "initialize_copy", args[0..1], null);
    return receiver;
}

pub fn builtinKernelBlockGiven(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const frame = vm.currentFrame();
    return Value.boolean(frame.block != null);
}

pub fn builtinKernelAtExit(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const blk = try vm.requireBlock(block);
    const proc_val = try vm.newProc(blk);
    vm.at_exit_handlers.append(vm.gc_allocator, proc_val) catch return error.Fatal;
    return proc_val;
}

pub fn builtinKernelLoop(vm: *VM, _: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const blk = try vm.requireBlock(block);

    while (true) {
        const result = try vm.yieldToBlock(blk, &[_]Value{});
        if (result.break_occurred) return result.value;
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
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const result = try vm.yieldToBlock(blk, &[_]Value{receiver});
    if (result.break_occurred) return result.value;
    return receiver;
}

pub fn builtinKernelSend(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const name_str = try vm.coerceToMethodNameString(args[0]);
    const call_args = args[1..];
    return vm.callMethodByNameForwardingKeywords(receiver, name_str, call_args, block);
}

fn builtinKernelBoundMethodCall(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const target = try vm.getInstanceVariable(receiver, "@__method_receiver");
    const method_name_val = try vm.getInstanceVariable(receiver, "@__method_name");
    if (!method_name_val.isSymbol()) return error.Fatal;
    return vm.callMethodByNameForwardingKeywords(target, method_name_val.toSymbolObject().name, args, block);
}

fn builtinKernelBoundMethodOwner(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const stored_owner = try vm.getInstanceVariable(receiver, "@__method_owner");
    if (!stored_owner.isNil()) return stored_owner;

    const target = try vm.getInstanceVariable(receiver, "@__method_receiver");
    const method_name_val = try vm.getInstanceVariable(receiver, "@__method_name");
    if (!method_name_val.isSymbol()) return error.Fatal;

    const owner = (try resolveMethodOwnerValue(vm, target, method_name_val.toSymbolObject())) orelse {
        return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{method_name_val.toSymbolObject().name});
    };
    return owner;
}

fn builtinKernelBoundMethodToProc(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return receiver;
}

fn builtinKernelBoundMethodArity(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return try vm.getInstanceVariable(receiver, "@__method_arity");
}

fn builtinKernelBoundMethodUnbind(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const target = try vm.getInstanceVariable(receiver, "@__method_receiver");
    const method_name_val = try vm.getInstanceVariable(receiver, "@__method_name");
    if (!method_name_val.isSymbol()) return error.Fatal;
    const owner = try vm.getInstanceVariable(receiver, "@__method_owner");

    const resolved = (try vm.findMethod(target, method_name_val.toSymbolObject())) orelse {
        return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{method_name_val.toSymbolObject().name});
    };

    return createMethodObject(vm, target, method_name_val.toSymbolObject(), resolved, owner);
}

fn createMethodObject(
    vm: *VM,
    receiver: Value,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
) VMError!Value {
    const method_obj = try vm.newInstance(vm.method_class);
    try vm.setInstanceVariable(method_obj, "@__method_receiver", receiver);
    try vm.setInstanceVariable(method_obj, "@__method_name", Value.fromObject(method_name));
    try vm.setInstanceVariable(method_obj, "@__method_arity", try vm.methodArityValue(resolved));
    try vm.setInstanceVariable(method_obj, "@__method_owner", owner);

    const singleton = try vm.getOrCreateSingletonClass(method_obj);
    const call_sym = try vm.intern("call");
    singleton.module.methods.put(call_sym, .{
        .method = .{ .builtin = &builtinKernelBoundMethodCall },
    }) catch return error.Fatal;

    const owner_sym = try vm.intern("owner");
    singleton.module.methods.put(owner_sym, .{
        .method = .{ .builtin = &builtinKernelBoundMethodOwner },
    }) catch return error.Fatal;

    const to_proc_sym = try vm.intern("to_proc");
    singleton.module.methods.put(to_proc_sym, .{
        .method = .{ .builtin = &builtinKernelBoundMethodToProc },
    }) catch return error.Fatal;

    const arity_sym = try vm.intern("arity");
    singleton.module.methods.put(arity_sym, .{
        .method = .{ .builtin = &builtinKernelBoundMethodArity },
    }) catch return error.Fatal;

    const unbind_sym = try vm.intern("unbind");
    singleton.module.methods.put(unbind_sym, .{
        .method = .{ .builtin = &builtinKernelBoundMethodUnbind },
    }) catch return error.Fatal;

    vm.bumpMethodStateVersion();
    return method_obj;
}

fn createBoundMethodObject(vm: *VM, receiver: Value, method_name: *SymbolObject, resolved: vm_mod.ResolvedMethod, owner: Value) VMError!Value {
    return createMethodObject(vm, receiver, method_name, resolved, owner);
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

    const owner = (try resolveMethodOwnerValue(vm, receiver, method_name)) orelse Value.fromObject(resolved.owner_class);
    return createBoundMethodObject(vm, receiver, method_name, resolved, owner);
}

pub fn builtinKernelSingletonMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const method_name = try vm.coerceToMethodNameSymbol(args[0]);
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

        if (body.isObject() and vm.getClass(body) == vm.method_class) {
            const method_name_val = try vm.getInstanceVariable(body, "@__method_name");
            const method_receiver = try vm.getInstanceVariable(body, "@__method_receiver");
            const method_owner = try vm.getInstanceVariable(body, "@__method_owner");
            if (!method_name_val.isSymbol()) return error.Fatal;

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

            const resolved = (try vm.findMethod(method_receiver, method_name_val.toSymbolObject())) orelse {
                return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{method_name_val.toSymbolObject().name});
            };
            var copied = resolved.entry;
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

    return Value.fromObject(name_sym);
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

pub fn builtinKernelInstanceVariableSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const name_str = try vm.coerceToIvarName(args[0]);
    vm.setInstanceVariable(receiver, name_str, args[1]) catch |err| {
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };
    return args[1];
}

pub fn builtinKernelToS(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const class_name_val = try module_builtin.builtinModuleToS(vm, Value.fromObject(vm.getClass(receiver)), &[_]Value{}, null);
    if (!class_name_val.isString()) return error.Fatal;

    const object_id = receiver.objectId();

    const str = std.fmt.allocPrint(vm.gc_allocator, "#<{s}:0x{x}>", .{ class_name_val.toStringObject().str, object_id }) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinKernelInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinKernelToS(vm, receiver, args, null);
}

pub fn builtinKernelHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const hash_value: i64 = @bitCast(receiver.hash());
    return Value.integer(hash_value);
}

fn builtinKernelHashConvert(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const arg = args[0];
    if (arg.isNil()) {
        return Value.fromObject(try vm.createHash());
    }

    if (arg.isArray() and arg.toArrayObject().elements.items.len == 0) {
        return Value.fromObject(try vm.createHash());
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

    if (receiver.isNil()) return Value.fromObject(vm.nil_class);
    if (receiver.isBool()) return Value.fromObject(if (receiver.toBool()) vm.true_class else vm.false_class);
    if (receiver.isInteger() or receiver.isFloat() or receiver.isSymbol()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't define singleton", .{});
    }
    if (vm.isCanonicalFStringValue(receiver)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't define singleton", .{});
    }

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    return Value.fromObject(singleton_class);
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

        return Value.fromObject(array_obj);
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
        vm.pending_exception = exc;
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
            vm.printUnhandledException();
            exitForkChild(vm, 1);
        },
        else => exitForkChild(vm, 1),
    }

    if (block_err) |err| {
        switch (err) {
            error.Unwind, error.UnhandledException => {
                if (vm.pending_exception != null) {
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
