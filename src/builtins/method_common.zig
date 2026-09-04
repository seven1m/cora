const std = @import("std");
const ancestry = @import("../ancestry.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const kernel = @import("kernel.zig");

pub const VM = vm_mod.VM;
pub const VMError = vm_mod.VMError;
pub const Block = vm_mod.Block;
pub const Value = value.Value;
pub const ClassObject = value.ClassObject;
pub const BuiltinArity = value.BuiltinArity;
pub const MethodEntry = value.MethodEntry;
pub const MethodObject = value.MethodObject;
pub const SymbolObject = value.SymbolObject;
pub const UnboundMethodObject = value.UnboundMethodObject;

pub const BuiltinMethodFn = *const fn (*VM, Value, []Value, ?Block) VMError!Value;

pub const BoundMethodBuiltins = struct {
    call: BuiltinMethodFn,
    equal: BuiltinMethodFn,
    owner: BuiltinMethodFn,
    to_proc: BuiltinMethodFn,
    arity: BuiltinMethodFn,
    parameters: BuiltinMethodFn,
    unbind: BuiltinMethodFn,
    source_location: BuiltinMethodFn,
};

pub fn entriesHaveSameImplementation(lhs: MethodEntry, rhs: MethodEntry) bool {
    if (std.meta.activeTag(lhs.method) != std.meta.activeTag(rhs.method)) return false;

    return switch (lhs.method) {
        .chunk => |lhs_chunk| lhs_chunk == rhs.method.chunk,
        .builtin => |lhs_builtin| blk: {
            const rhs_builtin = rhs.method.builtin;
            break :blk lhs_builtin.function == rhs_builtin.function and
                std.meta.eql(lhs_builtin.arity, rhs_builtin.arity);
        },
        .cext => |lhs_cext| blk: {
            const rhs_cext = rhs.method.cext;
            break :blk lhs_cext.func == rhs_cext.func and lhs_cext.argc == rhs_cext.argc;
        },
        .proc => |lhs_proc| lhs_proc == rhs.method.proc,
        .missing => |lhs_name| lhs_name == rhs.method.missing,
        .undefined => true,
    };
}

pub fn boundMethodsEqual(lhs: *MethodObject, rhs: *MethodObject) bool {
    return lhs.receiver.raw == rhs.receiver.raw and
        entriesHaveSameImplementation(lhs.entry, rhs.entry);
}

pub const UnboundMethodBuiltins = struct {
    owner: BuiltinMethodFn,
    arity: BuiltinMethodFn,
    parameters: BuiltinMethodFn,
    bind: BuiltinMethodFn,
    bind_call: BuiltinMethodFn,
    inspect: BuiltinMethodFn,
    equal: BuiltinMethodFn,
    source_location: BuiltinMethodFn,
};

fn resolveMethodEntry(
    method_name: *SymbolObject,
    owner_class: *ClassObject,
    entry: MethodEntry,
) ?vm_mod.ResolvedMethod {
    return switch (entry.method) {
        .undefined => null,
        else => .{
            .name = method_name,
            .owner_class = owner_class,
            .entry = entry,
        },
    };
}

pub fn resolveMethodOwnerValue(vm: *VM, receiver: Value, method_name_sym: *SymbolObject) VMError!?Value {
    const scanClass = struct {
        fn run(class_obj: *ClassObject, name_sym: *SymbolObject) ?Value {
            var current: ?*value.ModuleObject = &class_obj.module;
            while (current) |node| : (current = node.super) {
                if (ancestry.methodTableOwner(node).methods.get(name_sym)) |entry| {
                    if (entry.method == .undefined) return null;
                    return ancestry.visibleValue(node);
                }
            }

            return null;
        }
    }.run;

    if (receiver.getObjectPointer() != null) {
        const singleton_class = try vm.getOrCreateSingletonClass(receiver);
        if (scanClass(singleton_class, method_name_sym)) |owner| return owner;
    }

    return scanClass(vm.getClass(receiver), method_name_sym);
}

fn scanClassForExactMethod(
    start_class: *ClassObject,
    owner: Value,
    method_name_sym: *SymbolObject,
) ?vm_mod.ResolvedMethod {
    var current: ?*value.ModuleObject = &start_class.module;
    var owner_class = start_class;
    while (current) |node| : (current = node.super) {
        if (node.object.type_tag == .class) owner_class = @fieldParentPtr("module", node);
        const node_owner = ancestry.visibleValue(node);
        if (node_owner.raw != owner.raw) continue;
        if (ancestry.methodTableOwner(node).methods.get(method_name_sym)) |entry| {
            return resolveMethodEntry(method_name_sym, owner_class, entry);
        }
        return null;
    }

    return null;
}

pub fn resolveExactMethodForReceiver(vm: *VM, receiver: Value, owner: Value, method_name_sym: *SymbolObject) VMError!?vm_mod.ResolvedMethod {
    if (receiver.getSingletonClass()) |singleton_class| {
        if (scanClassForExactMethod(singleton_class, owner, method_name_sym)) |resolved| return resolved;
    }
    return scanClassForExactMethod(vm.getClass(receiver), owner, method_name_sym);
}

pub fn methodEntryForOwner(owner: Value, method_name_sym: *SymbolObject) ?MethodEntry {
    if (owner.isClass()) return owner.toClassObject().module.methods.get(method_name_sym);
    if (owner.isModule()) return owner.toModuleObject().methods.get(method_name_sym);
    return null;
}

pub fn ownerDisplayName(owner: Value) []const u8 {
    if (owner.isClass()) return owner.toClassObject().module.name.name;
    if (owner.isModule()) return owner.toModuleObject().name.name;
    return "Object";
}

pub fn ownerDisplayNameFull(vm: *VM, owner: Value) VMError![]const u8 {
    if (owner.isClass() or owner.isModule()) {
        const name_val = try vm.callMethodByName(owner, "name", &[_]Value{}, null);
        if (name_val.isString()) return name_val.toStringObject().str;
    }
    return ownerDisplayName(owner);
}

pub fn raiseUndefinedMethodName(vm: *VM, name_sym: *SymbolObject) VMError!Value {
    return vm.raiseNameErrorFmt(name_sym, "undefined method '{s}'", .{name_sym.name});
}

pub fn sourceLocationForResolvedMethod(vm: *VM, resolved: vm_mod.ResolvedMethod) VMError!Value {
    const method_chunk = switch (resolved.entry.method) {
        .chunk => |method_chunk| method_chunk,
        .proc => |proc_obj| switch (proc_obj.block.kind) {
            .chunk => |chunk_block| chunk_block.chunk,
            else => return Value.nil(),
        },
        else => return Value.nil(),
    };

    const source = method_chunk.source_file orelse method_chunk.name;
    const line: i64 = method_chunk.declaration_line;

    const array = try vm.createArray();
    array.elements.append(vm.gc_allocator, try vm.newString(source, false)) catch return error.Fatal;
    array.elements.append(vm.gc_allocator, Value.integer(line)) catch return error.Fatal;
    return Value.fromObject(&array.object);
}

fn appendParameterDescriptor(vm: *VM, array: *value.ArrayObject, kind_name: []const u8) VMError!void {
    const descriptor = try vm.createArray();
    descriptor.elements.append(vm.gc_allocator, Value.fromObject(&(try vm.intern(kind_name)).object)) catch return error.Fatal;
    array.elements.append(vm.gc_allocator, Value.fromObject(&descriptor.object)) catch return error.Fatal;
}

pub fn parametersForResolvedMethod(vm: *VM, resolved: vm_mod.ResolvedMethod) VMError!Value {
    const out = try vm.createArray();

    switch (resolved.entry.method) {
        .chunk => |method_chunk| {
            for (0..method_chunk.arity) |_| {
                try appendParameterDescriptor(vm, out, "req");
            }
            for (method_chunk.optional_params.items) |_| {
                try appendParameterDescriptor(vm, out, "opt");
            }
            if (method_chunk.rest_param_index != null) {
                try appendParameterDescriptor(vm, out, "rest");
            }
            for (0..method_chunk.post_required_count) |_| {
                try appendParameterDescriptor(vm, out, "req");
            }
            for (method_chunk.required_keywords.items) |_| {
                try appendParameterDescriptor(vm, out, "keyreq");
            }
            for (method_chunk.optional_keywords.items) |_| {
                try appendParameterDescriptor(vm, out, "key");
            }
            if (method_chunk.keyword_rest_index != null) {
                try appendParameterDescriptor(vm, out, "keyrest");
            }
            if (method_chunk.block_param_index != null) {
                try appendParameterDescriptor(vm, out, "block");
            }
        },
        .proc => |proc_obj| switch (proc_obj.block.kind) {
            .chunk => |chunk_blk| {
                const chunk_method: vm_mod.ResolvedMethod = .{
                    .name = resolved.name,
                    .owner_class = resolved.owner_class,
                    .entry = .{ .method = .{ .chunk = chunk_blk.chunk }, .visibility = resolved.entry.visibility },
                };
                return parametersForResolvedMethod(vm, chunk_method);
            },
            .receiver_builtin => |builtin_data| {
                for (0..@intCast(builtin_data.arity)) |_| {
                    try appendParameterDescriptor(vm, out, "req");
                }
            },
            .symbol, .builtin, .callable => {
                try appendParameterDescriptor(vm, out, "rest");
            },
        },
        .builtin => |builtin_method| switch (builtin_method.arity) {
            .exact => |count| {
                for (0..count) |_| {
                    try appendParameterDescriptor(vm, out, "req");
                }
            },
            .variadic => |required| {
                for (0..required) |_| {
                    try appendParameterDescriptor(vm, out, "req");
                }
                try appendParameterDescriptor(vm, out, "rest");
            },
        },
        .cext => |cext_method| {
            const arity: i32 = @intCast(cext_method.argc);
            if (arity >= 0) {
                for (0..@intCast(arity)) |_| {
                    try appendParameterDescriptor(vm, out, "req");
                }
            } else {
                const required: u32 = @intCast(-arity - 1);
                for (0..required) |_| {
                    try appendParameterDescriptor(vm, out, "req");
                }
                try appendParameterDescriptor(vm, out, "rest");
            }
        },
        .missing => try appendParameterDescriptor(vm, out, "rest"),
        .undefined => unreachable,
    }

    return Value.fromObject(&out.object);
}

/// Check whether `bind_target` is a valid receiver for an UnboundMethod whose
/// owner is `owner` (a Class or Module Value).  Mirrors Ruby's is_a? semantics:
/// the target must be an instance of the owner class or include the owner module.
pub fn isCompatibleBindTarget(vm: *VM, bind_target: Value, owner: Value) bool {
    var is_a_args = [1]Value{owner};
    const result = kernel.builtinKernelIsA(vm, bind_target, &is_a_args, null) catch return false;
    return result.isTruthy();
}

pub fn createBoundMethodObject(
    vm: *VM,
    receiver: Value,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
    builtins: BoundMethodBuiltins,
) VMError!Value {
    const method_obj = vm.gc_allocator.create(MethodObject) catch return error.Fatal;
    method_obj.* = .{
        .object = .{
            .type_tag = .method,
            .flags = 0,
            .class = vm.method_class,
            .singleton_class = null,
            .instance_variables = null,
        },
        .receiver = receiver,
        .name = method_name,
        .arity = try vm.methodArityValue(resolved),
        .owner = owner,
        .entry = resolved.entry,
    };

    const method_val = Value.fromObject(&method_obj.object);
    const singleton = try vm.getOrCreateSingletonClass(method_val);

    const call_sym = try vm.intern("call");
    singleton.module.methods.put(call_sym, MethodEntry.builtin(builtins.call, .{ .variadic = 0 })) catch return error.Fatal;

    const equal_sym = try vm.intern("==");
    const equal_entry = MethodEntry.builtin(builtins.equal, .{ .exact = 1 });
    singleton.module.methods.put(equal_sym, equal_entry) catch return error.Fatal;

    const eql_sym = try vm.intern("eql?");
    singleton.module.methods.put(eql_sym, equal_entry) catch return error.Fatal;

    const owner_sym = try vm.intern("owner");
    singleton.module.methods.put(owner_sym, MethodEntry.builtin(builtins.owner, .{ .exact = 0 })) catch return error.Fatal;

    const to_proc_sym = try vm.intern("to_proc");
    singleton.module.methods.put(to_proc_sym, MethodEntry.builtin(builtins.to_proc, .{ .exact = 0 })) catch return error.Fatal;

    const arity_sym = try vm.intern("arity");
    singleton.module.methods.put(arity_sym, MethodEntry.builtin(builtins.arity, .{ .exact = 0 })) catch return error.Fatal;

    const parameters_sym = try vm.intern("parameters");
    singleton.module.methods.put(parameters_sym, MethodEntry.builtin(builtins.parameters, .{ .exact = 0 })) catch return error.Fatal;

    const unbind_sym = try vm.intern("unbind");
    singleton.module.methods.put(unbind_sym, MethodEntry.builtin(builtins.unbind, .{ .exact = 0 })) catch return error.Fatal;

    const source_location_sym = try vm.intern("source_location");
    singleton.module.methods.put(source_location_sym, MethodEntry.builtin(builtins.source_location, .{ .exact = 0 })) catch return error.Fatal;

    vm.bumpMethodStateVersion();
    return method_val;
}

pub fn createUnboundMethodObject(
    vm: *VM,
    method_name: *SymbolObject,
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
    builtins: UnboundMethodBuiltins,
) VMError!Value {
    const method_obj = vm.gc_allocator.create(UnboundMethodObject) catch return error.Fatal;
    method_obj.* = .{
        .object = .{
            .type_tag = .unbound_method,
            .flags = 0,
            .class = vm.unbound_method_class,
            .singleton_class = null,
            .instance_variables = null,
        },
        .name = method_name,
        .arity = try vm.methodArityValue(resolved),
        .owner = owner,
        .entry = resolved.entry,
    };

    const method_val = Value.fromObject(&method_obj.object);
    const singleton = try vm.getOrCreateSingletonClass(method_val);

    const owner_sym = try vm.intern("owner");
    singleton.module.methods.put(owner_sym, MethodEntry.builtin(builtins.owner, .{ .exact = 0 })) catch return error.Fatal;

    const arity_sym = try vm.intern("arity");
    singleton.module.methods.put(arity_sym, MethodEntry.builtin(builtins.arity, .{ .exact = 0 })) catch return error.Fatal;

    const parameters_sym = try vm.intern("parameters");
    singleton.module.methods.put(parameters_sym, MethodEntry.builtin(builtins.parameters, .{ .exact = 0 })) catch return error.Fatal;

    const bind_sym = try vm.intern("bind");
    singleton.module.methods.put(bind_sym, MethodEntry.builtin(builtins.bind, .{ .exact = 1 })) catch return error.Fatal;

    const bind_call_sym = try vm.intern("bind_call");
    singleton.module.methods.put(bind_call_sym, MethodEntry.builtin(builtins.bind_call, .{ .variadic = 1 })) catch return error.Fatal;

    const inspect_sym = try vm.intern("inspect");
    singleton.module.methods.put(inspect_sym, MethodEntry.builtin(builtins.inspect, .{ .exact = 0 })) catch return error.Fatal;

    const equal_sym = try vm.intern("==");
    singleton.module.methods.put(equal_sym, MethodEntry.builtin(builtins.equal, .{ .exact = 1 })) catch return error.Fatal;

    const source_location_sym = try vm.intern("source_location");
    singleton.module.methods.put(source_location_sym, MethodEntry.builtin(builtins.source_location, .{ .exact = 0 })) catch return error.Fatal;

    vm.bumpMethodStateVersion();
    return method_val;
}
