const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    const puts_sym = try vm.intern("puts");
    try vm.kernel_module.methods.put(puts_sym, .{ .builtin = &builtinKernelPuts });

    const proc_sym = try vm.intern("proc");
    try vm.kernel_module.methods.put(proc_sym, .{ .builtin = &builtinKernelProc });

    const lambda_sym = try vm.intern("lambda");
    try vm.kernel_module.methods.put(lambda_sym, .{ .builtin = &builtinKernelLambda });

    const require_sym = try vm.intern("require");
    try vm.kernel_module.methods.put(require_sym, .{ .builtin = &builtinKernelRequire });

    const require_relative_sym = try vm.intern("require_relative");
    try vm.kernel_module.methods.put(require_relative_sym, .{ .builtin = &builtinKernelRequireRelative });

    const load_sym = try vm.intern("load");
    try vm.kernel_module.methods.put(load_sym, .{ .builtin = &builtinKernelLoad });

    const instance_variable_get_sym = try vm.intern("instance_variable_get");
    try vm.kernel_module.methods.put(instance_variable_get_sym, .{ .builtin = &builtinKernelInstanceVariableGet });

    const instance_variable_set_sym = try vm.intern("instance_variable_set");
    try vm.kernel_module.methods.put(instance_variable_set_sym, .{ .builtin = &builtinKernelInstanceVariableSet });

    const to_s_sym = try vm.intern("to_s");
    try vm.kernel_module.methods.put(to_s_sym, .{ .builtin = &builtinKernelToS });

    const inspect_sym = try vm.intern("inspect");
    try vm.kernel_module.methods.put(inspect_sym, .{ .builtin = &builtinKernelInspect });

    const p_sym = try vm.intern("p");
    try vm.kernel_module.methods.put(p_sym, .{ .builtin = &builtinKernelP });

    const raise_sym = try vm.intern("raise");
    try vm.kernel_module.methods.put(raise_sym, .{ .builtin = &builtinKernelRaise });

    const is_a_sym = try vm.intern("is_a?");
    try vm.kernel_module.methods.put(is_a_sym, .{ .builtin = &builtinKernelIsA });

    const block_given_sym = try vm.intern("block_given?");
    try vm.kernel_module.methods.put(block_given_sym, .{ .builtin = &builtinKernelBlockGiven });

    const send_sym = try vm.intern("send");
    try vm.kernel_module.methods.put(send_sym, .{ .builtin = &builtinKernelSend });
}

pub fn builtinKernelRequire(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .string) {
        const msg = std.fmt.allocPrint(vm.allocator, "no implicit conversion into String", .{}) catch return error.Fatal;
        const exc = vm.createException(vm.type_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
    }

    const feature = args[0].data.string.str;

    const absolute_path = vm.searchLoadPath(feature) catch {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
    } orelse {
        const msg = std.fmt.allocPrint(vm.allocator, "cannot load such file -- {s}", .{feature}) catch return error.Fatal;
        const exc = vm.createException(vm.load_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
    };

    if (vm.loaded_files.contains(absolute_path)) {
        return Value.boolean(false);
    }

    vm.loaded_files.put(absolute_path, {}) catch return error.Fatal;

    vm.loadFile(absolute_path) catch |err| {
        _ = vm.loaded_files.remove(absolute_path);
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

    return Value.boolean(true);
}

pub fn builtinKernelRequireRelative(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .string) {
        const msg = std.fmt.allocPrint(vm.allocator, "no implicit conversion into String", .{}) catch return error.Fatal;
        const exc = vm.createException(vm.type_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
    }

    const relative_path = args[0].data.string.str;

    const current_file = vm.current_loading_file orelse {
        const exc = vm.createException(vm.load_error_class, "cannot infer basepath") catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
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
        try vm.unwindStack();
        return error.Unwind;
    }

    const resolved_path = absolute_path.?;

    if (vm.loaded_files.contains(resolved_path)) {
        return Value.boolean(false);
    }

    vm.loaded_files.put(resolved_path, {}) catch return error.Fatal;
    vm.loadFile(resolved_path) catch |err| {
        _ = vm.loaded_files.remove(resolved_path);
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

    return Value.boolean(true);
}

pub fn builtinKernelLoad(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (args[0].data != .string) {
        const msg = std.fmt.allocPrint(vm.allocator, "no implicit conversion into String", .{}) catch return error.Fatal;
        const exc = vm.createException(vm.type_error_class, msg) catch return error.Fatal;
        vm.pending_exception = exc;
        try vm.unwindStack();
        return error.Unwind;
    }

    const filename = args[0].data.string.str;

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
        try vm.unwindStack();
        return error.Unwind;
    }

    vm.loadFile(absolute_path.?) catch |err| {
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };

    return Value.boolean(true);
}

pub fn builtinKernelPuts(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        // puts with no args prints empty line
        vm.stdout.?.print("\n", .{}) catch return VMError.Fatal;
        _ = vm.stdout.?.flush() catch {};
        return Value.nil();
    }

    for (args) |arg| {
        if (arg.data == .array) {
            // Special case: flatten arrays, call to_s on each element
            for (arg.data.array.elements.items) |elem| {
                const str_val = try vm.callMethodByName(elem, "to_s", &[_]Value{}, null);
                if (str_val.data != .string) {
                    const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
                    vm.pending_exception = exc;
                    return error.Unwind;
                }
                vm.stdout.?.print("{s}\n", .{str_val.data.string.str}) catch return VMError.Fatal;
            }
        } else {
            // Normal case: call to_s on the argument
            const str_val = try vm.callMethodByName(arg, "to_s", &[_]Value{}, null);
            if (str_val.data != .string) {
                const exc = try vm.createException(vm.type_error_class, "to_s did not return String");
                vm.pending_exception = exc;
                return error.Unwind;
            }
            vm.stdout.?.print("{s}\n", .{str_val.data.string.str}) catch return VMError.Fatal;
        }
    }
    _ = vm.stdout.?.flush() catch {};

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

    var blk = block orelse {
        const exc = try vm.createException(
            vm.argument_error_class,
            "tried to create Lambda without a block",
        );
        vm.pending_exception = exc;
        return error.Unwind;
    };

    // Mark the chunk as a lambda
    blk.chunk.is_lambda = true;

    return try vm.newProc(blk);
}

pub fn builtinKernelRaise(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        // Re-raise current exception
        if (vm.pending_exception) |exc| {
            try vm.raise(.{ .data = .{ .exception = exc } });
        } else {
            // No exception to re-raise - raise RuntimeError
            const exc = try vm.createException(vm.runtime_error_class, "No exception to re-raise");
            try vm.raise(.{ .data = .{ .exception = exc } });
        }
    } else if (args.len == 1) {
        const arg = args[0];
        switch (arg.data) {
            .exception => {
                // Already an exception, raise it
                try vm.raise(arg);
            },
            .class => |cls| {
                // Exception class with empty message
                const exc = try vm.createException(cls, "");
                try vm.raise(.{ .data = .{ .exception = exc } });
            },
            .string => |str| {
                // String message - create RuntimeError
                const exc = try vm.createException(vm.runtime_error_class, str.str);
                try vm.raise(.{ .data = .{ .exception = exc } });
            },
            else => {
                const exc = try vm.createException(vm.type_error_class, "exception class/object expected");
                vm.pending_exception = exc;
                return error.Unwind;
            },
        }
    } else if (args.len == 2) {
        const class_arg = args[0];
        const message = args[1];

        if (class_arg.data != .class) {
            const exc = try vm.createException(vm.type_error_class, "exception class/object expected");
            vm.pending_exception = exc;
            return error.Unwind;
        }

        const msg_str = if (message.data == .string)
            message.data.string.str
        else
            "";

        const exc = try vm.createException(class_arg.data.class, msg_str);
        try vm.raise(.{ .data = .{ .exception = exc } });
    } else {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return Value.nil();
}

pub fn builtinKernelIsA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const arg = args[0];

    switch (arg.data) {
        .class => |cls| {
            var current: ?*ClassObject = vm.getClass(receiver);
            while (current) |c| {
                if (c == cls) return Value.boolean(true);
                current = c.superclass;
            }
            return Value.boolean(false);
        },
        .module => |mod| {
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
        },
        else => return vm.raiseExceptionFmt(vm.type_error_class, "class or module required", .{}),
    }
}

pub fn builtinKernelBlockGiven(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const frame = vm.currentFrame();
    return Value.boolean(frame.block != null);
}

pub fn builtinKernelSend(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const name_arg = args[0];
    var name_str: []const u8 = undefined;

    switch (name_arg.data) {
        .symbol => |sym| name_str = sym.name,
        .string => |str| name_str = str.str,
        else => {
            const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
            vm.pending_exception = exc;
            return error.Unwind;
        },
    }

    const call_args = args[1..];
    return vm.callMethodByName(receiver, name_str, call_args, block);
}

pub fn builtinKernelInstanceVariableGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const name_arg = args[0];
    var name_str: []const u8 = undefined;

    switch (name_arg.data) {
        .symbol => |sym| {
            name_str = sym.name;
        },
        .string => |str| {
            name_str = str.str;
        },
        else => {
            const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
            vm.pending_exception = exc;
            return error.Unwind;
        },
    }

    if (name_str.len <= 1 or name_str[0] != '@') {
        const msg = std.fmt.allocPrint(vm.allocator, "'{s}' is not allowed as an instance variable name", .{name_str}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = try vm.createException(vm.argument_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return vm.getInstanceVariable(receiver, name_str) catch return error.Fatal;
}

pub fn builtinKernelInstanceVariableSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const name_arg = args[0];
    var name_str: []const u8 = undefined;

    switch (name_arg.data) {
        .symbol => |sym| {
            name_str = sym.name;
        },
        .string => |str| {
            name_str = str.str;
        },
        else => {
            const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
            vm.pending_exception = exc;
            return error.Unwind;
        },
    }

    if (name_str.len <= 1 or name_str[0] != '@') {
        const msg = std.fmt.allocPrint(vm.allocator, "'{s}' is not allowed as an instance variable name", .{name_str}) catch return error.Fatal;
        defer vm.allocator.free(msg);
        const exc = try vm.createException(vm.argument_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    }

    vm.setInstanceVariable(receiver, name_str, args[1]) catch |err| {
        if (err == error.Unwind and vm.pending_exception != null) return error.Unwind;
        return error.Fatal;
    };
    return args[1];
}

pub fn builtinKernelToS(vm: *VM, receiver: Value, _: []Value, _: ?Block) VMError!Value {
    const class = vm.getClass(receiver);
    const class_name = class.module.name.name;

    const object_id = receiver.objectId();

    const str = std.fmt.allocPrint(vm.gc_allocator, "#<{s}:0x{x}>", .{ class_name, object_id }) catch return error.Fatal;
    return try vm.newString(str, false);
}

pub fn builtinKernelInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return builtinKernelToS(vm, receiver, args, null);
}

pub fn builtinKernelP(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        vm.stdout.?.print("\n", .{}) catch return error.Fatal;
        _ = vm.stdout.?.flush() catch {};
        return Value.nil();
    }

    for (args, 0..) |arg, idx| {
        const inspected = try vm.callMethodByName(arg, "inspect", &[_]Value{}, null);
        if (inspected.data != .string) {
            const exc = try vm.createException(vm.type_error_class, "inspect did not return String");
            vm.pending_exception = exc;
            return error.Unwind;
        }

        if (idx > 0) {
            vm.stdout.?.print("\n", .{}) catch return error.Fatal;
        }
        vm.stdout.?.print("{s}", .{inspected.data.string.str}) catch return error.Fatal;
    }
    vm.stdout.?.print("\n", .{}) catch return error.Fatal;
    _ = vm.stdout.?.flush() catch {};

    if (args.len == 1) {
        return args[0];
    } else {
        const array_obj = vm.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_obj.* = .{
            .object = .{ .flags = 0, .class = vm.array_class, .singleton_class = null, .instance_variables = null },
            .elements = .empty,
        };

        for (args) |arg| {
            array_obj.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
        }

        return .{ .data = .{ .array = array_obj } };
    }
}
