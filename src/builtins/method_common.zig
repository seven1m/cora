const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

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
    owner: BuiltinMethodFn,
    to_proc: BuiltinMethodFn,
    arity: BuiltinMethodFn,
    unbind: BuiltinMethodFn,
    source_location: BuiltinMethodFn,
};

pub const UnboundMethodBuiltins = struct {
    owner: BuiltinMethodFn,
    arity: BuiltinMethodFn,
    bind: BuiltinMethodFn,
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
    var current: ?*ClassObject = start_class;
    while (current) |klass| {
        var i = klass.module.prepended_modules.items.len;
        while (i > 0) {
            i -= 1;
            const prepended = klass.module.prepended_modules.items[i];
            if (Value.fromObject(prepended).raw != owner.raw) continue;
            if (prepended.methods.get(method_name_sym)) |entry| {
                return resolveMethodEntry(method_name_sym, klass, entry);
            }
            return null;
        }

        if (Value.fromObject(klass).raw == owner.raw) {
            if (klass.module.methods.get(method_name_sym)) |entry| {
                return resolveMethodEntry(method_name_sym, klass, entry);
            }
            return null;
        }

        i = klass.module.included_modules.items.len;
        while (i > 0) {
            i -= 1;
            const included = klass.module.included_modules.items[i];
            if (Value.fromObject(included).raw != owner.raw) continue;
            if (included.methods.get(method_name_sym)) |entry| {
                return resolveMethodEntry(method_name_sym, klass, entry);
            }
            return null;
        }

        current = klass.superclass;
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
    const message = std.fmt.allocPrint(vm.gc_allocator, "undefined method '{s}'", .{name_sym.name}) catch return error.Fatal;
    const exc = try vm.createException(vm.name_error_class, message);
    try vm.setInstanceVariable(Value.fromObject(exc), "@name", Value.fromObject(name_sym));
    vm.pending_exception = exc;
    return error.Unwind;
}

pub fn sourceLocationForResolvedMethod(vm: *VM, resolved: vm_mod.ResolvedMethod) VMError!Value {
    const method_chunk = switch (resolved.entry.method) {
        .chunk => |method_chunk| method_chunk,
        else => return Value.nil(),
    };

    const source = method_chunk.source_file orelse method_chunk.name;
    const body_line: i64 = if (method_chunk.line_info.items.len > 0 and method_chunk.line_info.items[0].line != 0)
        method_chunk.line_info.items[0].line
    else
        1;
    const line = if (body_line > 1) body_line - 1 else 1;

    const array = try vm.createArray();
    array.elements.append(vm.gc_allocator, try vm.newString(source, false)) catch return error.Fatal;
    array.elements.append(vm.gc_allocator, Value.integer(line)) catch return error.Fatal;
    return Value.fromObject(array);
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
    };

    const method_val = Value.fromObject(method_obj);
    const singleton = try vm.getOrCreateSingletonClass(method_val);

    const call_sym = try vm.intern("call");
    singleton.module.methods.put(call_sym, MethodEntry.builtin(builtins.call, .{ .variadic = 0 })) catch return error.Fatal;

    const owner_sym = try vm.intern("owner");
    singleton.module.methods.put(owner_sym, MethodEntry.builtin(builtins.owner, .{ .exact = 0 })) catch return error.Fatal;

    const to_proc_sym = try vm.intern("to_proc");
    singleton.module.methods.put(to_proc_sym, MethodEntry.builtin(builtins.to_proc, .{ .exact = 0 })) catch return error.Fatal;

    const arity_sym = try vm.intern("arity");
    singleton.module.methods.put(arity_sym, MethodEntry.builtin(builtins.arity, .{ .exact = 0 })) catch return error.Fatal;

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
    };

    const method_val = Value.fromObject(method_obj);
    const singleton = try vm.getOrCreateSingletonClass(method_val);

    const owner_sym = try vm.intern("owner");
    singleton.module.methods.put(owner_sym, MethodEntry.builtin(builtins.owner, .{ .exact = 0 })) catch return error.Fatal;

    const arity_sym = try vm.intern("arity");
    singleton.module.methods.put(arity_sym, MethodEntry.builtin(builtins.arity, .{ .exact = 0 })) catch return error.Fatal;

    const bind_sym = try vm.intern("bind");
    singleton.module.methods.put(bind_sym, MethodEntry.builtin(builtins.bind, .{ .exact = 1 })) catch return error.Fatal;

    const inspect_sym = try vm.intern("inspect");
    singleton.module.methods.put(inspect_sym, MethodEntry.builtin(builtins.inspect, .{ .exact = 0 })) catch return error.Fatal;

    const equal_sym = try vm.intern("==");
    singleton.module.methods.put(equal_sym, MethodEntry.builtin(builtins.equal, .{ .exact = 1 })) catch return error.Fatal;

    const source_location_sym = try vm.intern("source_location");
    singleton.module.methods.put(source_location_sym, MethodEntry.builtin(builtins.source_location, .{ .exact = 0 })) catch return error.Fatal;

    vm.bumpMethodStateVersion();
    return method_val;
}
