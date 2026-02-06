const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const Method = vm_mod.Method;
const SymbolObject = value.SymbolObject;

pub fn register(vm: *VM) !void {
    const include_sym = try vm.intern("include");
    try vm.object_class.module.methods.put(include_sym, .{ .builtin = &builtinModuleInclude });

    const prepend_sym = try vm.intern("prepend");
    try vm.object_class.module.methods.put(prepend_sym, .{ .builtin = &builtinModulePrepend });

    const define_method_sym = try vm.intern("define_method");
    try vm.module_class.module.methods.put(define_method_sym, .{ .builtin = &builtinModuleDefineMethod });

    const attr_reader_sym = try vm.intern("attr_reader");
    try vm.module_class.module.methods.put(attr_reader_sym, .{ .builtin = &builtinModuleAttrReader });

    const attr_writer_sym = try vm.intern("attr_writer");
    try vm.module_class.module.methods.put(attr_writer_sym, .{ .builtin = &builtinModuleAttrWriter });

    const attr_accessor_sym = try vm.intern("attr_accessor");
    try vm.module_class.module.methods.put(attr_accessor_sym, .{ .builtin = &builtinModuleAttrAccessor });
}

pub fn builtinModuleInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const class = receiver.data.class;
    const module = args[0].data.module;

    vm.includeModule(class, module) catch return error.Unwind;

    return receiver;
}

pub fn builtinModulePrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const class = receiver.data.class;
    const module = args[0].data.module;

    vm.prependModule(class, module) catch return error.Unwind;

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

    const name_sym = vm.intern(name_str) catch unreachable;
    const proc_val = vm.newProc(blk);

    if (receiver.data == .class) {
        receiver.data.class.module.methods.put(name_sym, .{ .proc = proc_val.data.proc }) catch unreachable;
    } else if (receiver.data == .module) {
        receiver.data.module.methods.put(name_sym, .{ .proc = proc_val.data.proc }) catch unreachable;
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return Value{ .data = .{ .symbol = name_sym } };
}

pub fn builtinModuleAttrReader(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    var methods: *std.AutoHashMap(*SymbolObject, Method) = undefined;
    if (receiver.data == .class) {
        methods = &receiver.data.class.module.methods;
    } else if (receiver.data == .module) {
        methods = &receiver.data.module.methods;
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const result_array = try vm.createArray();

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

        const method_sym = vm.intern(name_str) catch unreachable;
        const chunk_ptr = try vm.createAccessorChunk(name_str, .reader);
        methods.put(method_sym, .{ .chunk = chunk_ptr }) catch unreachable;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = method_sym } }) catch unreachable;
    }

    return Value{ .data = .{ .array = result_array } };
}

pub fn builtinModuleAttrWriter(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    var methods: *std.AutoHashMap(*SymbolObject, Method) = undefined;
    if (receiver.data == .class) {
        methods = &receiver.data.class.module.methods;
    } else if (receiver.data == .module) {
        methods = &receiver.data.module.methods;
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const result_array = try vm.createArray();

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

        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch unreachable;
        const method_sym = vm.intern(writer_name) catch unreachable;
        const chunk_ptr = try vm.createAccessorChunk(name_str, .writer);
        methods.put(method_sym, .{ .chunk = chunk_ptr }) catch unreachable;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = method_sym } }) catch unreachable;
    }

    return Value{ .data = .{ .array = result_array } };
}

pub fn builtinModuleAttrAccessor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        const exc = try vm.createException(vm.argument_error_class, "wrong number of arguments (given 0, expected 1)");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    var methods: *std.AutoHashMap(*SymbolObject, Method) = undefined;
    if (receiver.data == .class) {
        methods = &receiver.data.class.module.methods;
    } else if (receiver.data == .module) {
        methods = &receiver.data.module.methods;
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    const result_array = try vm.createArray();

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

        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch unreachable;

        const reader_sym = vm.intern(name_str) catch unreachable;
        const writer_sym = vm.intern(writer_name) catch unreachable;

        const reader_chunk = try vm.createAccessorChunk(name_str, .reader);
        const writer_chunk = try vm.createAccessorChunk(name_str, .writer);

        methods.put(reader_sym, .{ .chunk = reader_chunk }) catch unreachable;
        methods.put(writer_sym, .{ .chunk = writer_chunk }) catch unreachable;

        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = reader_sym } }) catch unreachable;
        result_array.elements.append(vm.gc_allocator, Value{ .data = .{ .symbol = writer_sym } }) catch unreachable;
    }

    return Value{ .data = .{ .array = result_array } };
}
