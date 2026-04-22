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
const SymbolObject = value.SymbolObject;
const MethodListFilter = method_reflection.MethodListFilter;

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

    method_reflection.sortSymbolsByName(names.items);

    const out = try vm.createArray();
    for (names.items) |name_sym| {
        out.elements.append(vm.gc_allocator, Value.fromObject(name_sym)) catch return error.Fatal;
    }

    return Value.fromObject(out);
}

fn resolveMethodOwnerValue(vm: *VM, receiver: Value, method_name_sym: *SymbolObject) VMError!?Value {
    const scanClass = struct {
        fn run(vm_inner: *VM, class_obj: *ClassObject, name_sym: *SymbolObject) ?Value {
            var current: ?*ClassObject = class_obj;
            while (current) |klass| {
                var i = klass.prepended_modules.items.len;
                while (i > 0) {
                    i -= 1;
                    const prepended = klass.prepended_modules.items[i];
                    if (prepended.methods.get(name_sym)) |entry| {
                        if (entry.method == .undefined) return null;
                        return Value.fromObject(prepended);
                    }
                }

                if (klass.module.methods.get(name_sym)) |entry| {
                    if (entry.method == .undefined) return null;
                    return Value.fromObject(klass);
                }

                i = klass.included_modules.items.len;
                while (i > 0) {
                    i -= 1;
                    const included = klass.included_modules.items[i];
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

    const hash_sym = try vm.intern("hash");
    try vm.kernel_module.methods.put(hash_sym, .{ .method = .{ .builtin = &builtinKernelHash } });

    const p_sym = try vm.intern("p");
    try vm.kernel_module.methods.put(p_sym, .{ .method = .{ .builtin = &builtinKernelP } });

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

    const to_enum_sym = try vm.intern("to_enum");
    try vm.kernel_module.methods.put(to_enum_sym, .{ .method = .{ .builtin = &builtinKernelToEnum } });

    const enum_for_sym = try vm.intern("enum_for");
    try vm.kernel_module.methods.put(enum_for_sym, .{ .method = .{ .builtin = &builtinKernelEnumFor } });

    const define_singleton_method_sym = try vm.intern("define_singleton_method");
    try vm.kernel_module.methods.put(define_singleton_method_sym, .{ .method = .{ .builtin = &builtinKernelDefineSingletonMethod } });

    const methods_sym = try vm.intern("methods");
    try vm.kernel_module.methods.put(methods_sym, .{ .method = .{ .builtin = &builtinKernelMethods } });

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
            for (c.prepended_modules.items) |m| {
                if (m == mod) return Value.boolean(true);
            }
            for (c.included_modules.items) |m| {
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

    const method_obj = try vm.newInstance(vm.object_class);
    try vm.setInstanceVariable(method_obj, "@__method_receiver", receiver);
    try vm.setInstanceVariable(method_obj, "@__method_name", Value.fromObject(method_name));
    try vm.setInstanceVariable(method_obj, "@__method_arity", try vm.methodArityValue(resolved));

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

    vm.bumpMethodStateVersion();
    return method_obj;
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
    try vm.requireArgCount(args, 1);
    const blk = try vm.requireBlock(block);

    const name_str = try vm.coerceToMethodNameString(args[0]);
    const name_sym = try vm.intern(name_str);
    const proc_val = try vm.newProc(blk);

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    singleton_class.module.methods.put(name_sym, .{
        .method = .{ .proc = proc_val.toProcObject() },
    }) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(name_sym);
}

pub fn builtinKernelMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectKernelMethods(vm, receiver, .public_and_protected, include_super);
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

    var child = std.process.Child.init(&argv, vm.allocator);
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch |err| {
        const msg = std.fmt.allocPrint(vm.gc_allocator, "failed to execute command: {s}", .{@errorName(err)}) catch return error.Fatal;
        const exc = try vm.createException(vm.runtime_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const stdout_bytes = child.stdout.?.readToEndAlloc(vm.allocator, 16 * 1024 * 1024) catch |err| {
        const msg = std.fmt.allocPrint(vm.gc_allocator, "failed to read command output: {s}", .{@errorName(err)}) catch return error.Fatal;
        const exc = try vm.createException(vm.runtime_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    };
    defer vm.allocator.free(stdout_bytes);

    const term = child.wait() catch |err| {
        const msg = std.fmt.allocPrint(vm.gc_allocator, "failed to wait for command: {s}", .{@errorName(err)}) catch return error.Fatal;
        const exc = try vm.createException(vm.runtime_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const exitstatus: i64 = switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => |sig| 128 + @as(i64, @intCast(sig)),
        .Stopped => |sig| 128 + @as(i64, @intCast(sig)),
        else => 1,
    };
    try vm.setLastProcessStatus(exitstatus);

    return try vm.newString(stdout_bytes, false);
}

pub fn builtinProcessStatusExitstatus(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return vm.getInstanceVariable(receiver, "@exitstatus");
}

fn sleepSecondsArg(vm: *VM, arg: Value) VMError!f64 {
    if (arg.isInteger()) return arg.integerToF64();
    if (arg.isFloat()) return arg.toFloatObject().val;
    return vm.raiseExceptionFmt(vm.type_error_class, "can't convert into Float", .{});
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
        const result = vm.yieldToBlock(blk, &[_]Value{}) catch {
            if (vm.stdout) |out| _ = out.flush() catch {};
            if (vm.stderr) |err_out| _ = err_out.flush() catch {};
            std.c._exit(1);
        };
        _ = result;
        if (vm.stdout) |out| _ = out.flush() catch {};
        if (vm.stderr) |err_out| _ = err_out.flush() catch {};
        std.c._exit(0);
    }

    return Value.nil();
}
