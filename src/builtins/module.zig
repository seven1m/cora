const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodVisibility = value.MethodVisibility;
const SymbolObject = value.SymbolObject;

fn currentDefaultVisibility(vm: *VM) MethodVisibility {
    if (vm.current_lexical_scope) |scope| {
        return scope.default_method_visibility;
    }
    return .public;
}

fn normalizeVisibilityArgs(vm: *VM, args: []Value, names: *std.ArrayList(*SymbolObject)) VMError!void {
    if (args.len == 1 and args[0].data == .array) {
        for (args[0].data.array.elements.items) |elem| {
            const name_str: []const u8 = switch (elem.data) {
                .symbol => |sym| sym.name,
                .string => |str| str.str,
                else => {
                    const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
                    vm.pending_exception = exc;
                    return error.Unwind;
                },
            };
            names.append(vm.gc_allocator, try vm.intern(name_str)) catch return error.Fatal;
        }
        return;
    }

    for (args) |arg| {
        const name_str: []const u8 = switch (arg.data) {
            .symbol => |sym| sym.name,
            .string => |str| str.str,
            else => {
                const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
                vm.pending_exception = exc;
                return error.Unwind;
            },
        };
        names.append(vm.gc_allocator, try vm.intern(name_str)) catch return error.Fatal;
    }
}

fn setVisibility(vm: *VM, receiver: Value, args: []Value, visibility: MethodVisibility) VMError!Value {
    if (args.len == 0) {
        if (vm.current_lexical_scope) |scope| {
            scope.default_method_visibility = visibility;
        }
        return Value.nil();
    }

    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);
    try normalizeVisibilityArgs(vm, args, &names);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    for (names.items) |name_sym| {
        const entry = methods.get(name_sym) orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        };
        var updated = entry;
        updated.visibility = visibility;
        methods.put(name_sym, updated) catch return error.Fatal;
    }

    if (args.len == 1 and args[0].data != .array) {
        return Value{ .data = .{ .symbol = names.items[0] } };
    }

    if (args.len == 1 and args[0].data == .array) {
        return args[0];
    }

    const arr = try vm.createArray();
    for (names.items) |name_sym| {
        arr.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = name_sym } }) catch return error.Fatal;
    }
    return Value{ .data = .{ .array = arr } };
}

pub fn register(vm: *VM) !void {
    const include_sym = try vm.intern("include");
    try vm.object_class.module.methods.put(include_sym, .{ .method = .{ .builtin = &builtinModuleInclude } });

    const prepend_sym = try vm.intern("prepend");
    try vm.object_class.module.methods.put(prepend_sym, .{ .method = .{ .builtin = &builtinModulePrepend } });

    const define_method_sym = try vm.intern("define_method");
    try vm.module_class.module.methods.put(define_method_sym, .{ .method = .{ .builtin = &builtinModuleDefineMethod } });

    const attr_reader_sym = try vm.intern("attr_reader");
    try vm.module_class.module.methods.put(attr_reader_sym, .{ .method = .{ .builtin = &builtinModuleAttrReader } });

    const attr_writer_sym = try vm.intern("attr_writer");
    try vm.module_class.module.methods.put(attr_writer_sym, .{ .method = .{ .builtin = &builtinModuleAttrWriter } });

    const attr_accessor_sym = try vm.intern("attr_accessor");
    try vm.module_class.module.methods.put(attr_accessor_sym, .{ .method = .{ .builtin = &builtinModuleAttrAccessor } });

    const alias_method_sym = try vm.intern("alias_method");
    try vm.module_class.module.methods.put(alias_method_sym, .{ .method = .{ .builtin = &builtinModuleAliasMethod } });

    const private_sym = try vm.intern("private");
    try vm.module_class.module.methods.put(private_sym, .{
        .method = .{ .builtin = &builtinModulePrivate },
        .visibility = .private,
    });

    const public_sym = try vm.intern("public");
    try vm.module_class.module.methods.put(public_sym, .{
        .method = .{ .builtin = &builtinModulePublic },
        .visibility = .private,
    });

    const protected_sym = try vm.intern("protected");
    try vm.module_class.module.methods.put(protected_sym, .{
        .method = .{ .builtin = &builtinModuleProtected },
        .visibility = .private,
    });
}

pub fn builtinModuleInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const class = receiver.data.class;
    const module = args[0].data.module;

    vm.includeModule(class, module) catch return error.Fatal;

    return receiver;
}

pub fn builtinModulePrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const class = receiver.data.class;
    const module = args[0].data.module;

    vm.prependModule(class, module) catch return error.Fatal;

    return receiver;
}

pub fn builtinModuleDefineMethod(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const blk = try vm.requireBlock(block);

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

    const name_sym = try vm.intern(name_str);
    const proc_val = try vm.newProc(blk);
    const visibility = currentDefaultVisibility(vm);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    methods.put(name_sym, .{
        .method = .{ .proc = proc_val.data.proc },
        .visibility = visibility,
    }) catch return error.Fatal;

    return Value{ .data = .{ .symbol = name_sym } };
}

pub fn builtinModuleAttrReader(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        var name_str: []const u8 = undefined;
        switch (arg.data) {
            .symbol => |sym| name_str = sym.name,
            .string => |str| name_str = str.str,
            else => {
                const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
                vm.pending_exception = exc;
                return error.Unwind;
            },
        }

        const method_sym = try vm.intern(name_str);
        const chunk_ptr = try vm.createAccessorChunk(name_str, .reader);
        methods.put(method_sym, .{
            .method = .{ .chunk = chunk_ptr },
            .visibility = visibility,
        }) catch return error.Fatal;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = method_sym } }) catch return error.Fatal;
    }

    return Value{ .data = .{ .array = result_array } };
}

pub fn builtinModuleAttrWriter(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        var name_str: []const u8 = undefined;
        switch (arg.data) {
            .symbol => |sym| name_str = sym.name,
            .string => |str| name_str = str.str,
            else => {
                const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
                vm.pending_exception = exc;
                return error.Unwind;
            },
        }

        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch return error.Fatal;
        const method_sym = try vm.intern(writer_name);
        const chunk_ptr = try vm.createAccessorChunk(name_str, .writer);
        methods.put(method_sym, .{
            .method = .{ .chunk = chunk_ptr },
            .visibility = visibility,
        }) catch return error.Fatal;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = method_sym } }) catch return error.Fatal;
    }

    return Value{ .data = .{ .array = result_array } };
}

pub fn builtinModuleAttrAccessor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        var name_str: []const u8 = undefined;
        switch (arg.data) {
            .symbol => |sym| name_str = sym.name,
            .string => |str| name_str = str.str,
            else => {
                const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
                vm.pending_exception = exc;
                return error.Unwind;
            },
        }

        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch return error.Fatal;

        const reader_sym = try vm.intern(name_str);
        const writer_sym = try vm.intern(writer_name);

        const reader_chunk = try vm.createAccessorChunk(name_str, .reader);
        const writer_chunk = try vm.createAccessorChunk(name_str, .writer);

        methods.put(reader_sym, .{
            .method = .{ .chunk = reader_chunk },
            .visibility = visibility,
        }) catch return error.Fatal;
        methods.put(writer_sym, .{
            .method = .{ .chunk = writer_chunk },
            .visibility = visibility,
        }) catch return error.Fatal;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = reader_sym } }) catch return error.Fatal;
        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = writer_sym } }) catch return error.Fatal;
    }

    return Value{ .data = .{ .array = result_array } };
}

pub fn builtinModuleAliasMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    // Extract new name
    var new_name_str: []const u8 = undefined;
    switch (args[0].data) {
        .symbol => |sym| new_name_str = sym.name,
        .string => |str| new_name_str = str.str,
        else => {
            const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
            vm.pending_exception = exc;
            return error.Unwind;
        },
    }

    // Extract old name
    var old_name_str: []const u8 = undefined;
    switch (args[1].data) {
        .symbol => |sym| old_name_str = sym.name,
        .string => |str| old_name_str = str.str,
        else => {
            const exc = try vm.createException(vm.type_error_class, "not a symbol nor a string");
            vm.pending_exception = exc;
            return error.Unwind;
        },
    }

    const new_name_sym = try vm.intern(new_name_str);
    const old_name_sym = try vm.intern(old_name_str);

    // Get method table from receiver (class or module)
    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    var lookup_class: *value.ClassObject = undefined;
    if (receiver.data == .class) {
        lookup_class = receiver.data.class;
    } else if (receiver.data == .module) {
        // For modules, look up in own methods only
        if (methods.get(old_name_sym)) |entry| {
            methods.put(new_name_sym, entry) catch return error.Fatal;
            return Value{ .data = .{ .symbol = new_name_sym } };
        }
        const msg = std.fmt.allocPrint(
            vm.gc_allocator,
            "undefined method '{s}'",
            .{old_name_str},
        ) catch return error.Fatal;
        const exc = try vm.createException(vm.name_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    } else {
        unreachable;
    }

    // Look up old method via lookupMethod (walks inheritance chain)
    if (vm.lookupMethod(lookup_class, old_name_sym)) |resolved| {
        methods.put(new_name_sym, resolved.entry) catch return error.Fatal;
    } else {
        const msg = std.fmt.allocPrint(
            vm.gc_allocator,
            "undefined method '{s}'",
            .{old_name_str},
        ) catch return error.Fatal;
        const exc = try vm.createException(vm.name_error_class, msg);
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return Value{ .data = .{ .symbol = new_name_sym } };
}

pub fn builtinModulePrivate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setVisibility(vm, receiver, args, .private);
}

pub fn builtinModulePublic(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setVisibility(vm, receiver, args, .public);
}

pub fn builtinModuleProtected(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setVisibility(vm, receiver, args, .protected);
}
