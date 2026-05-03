const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const method_reflection = @import("method_reflection.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodVisibility = value.MethodVisibility;
const SymbolObject = value.SymbolObject;
const ClassObject = value.ClassObject;
const MethodListFilter = method_reflection.MethodListFilter;

fn currentDefaultVisibility(vm: *VM) MethodVisibility {
    if (vm.current_lexical_scope) |scope| {
        return scope.default_method_visibility;
    }
    return .public;
}

fn normalizeVisibilityArgs(vm: *VM, args: []Value, names: *std.ArrayList(*SymbolObject)) VMError!void {
    if (args.len == 1 and args[0].isArray()) {
        for (args[0].toArrayObject().elements.items) |elem| {
            names.append(vm.gc_allocator, try vm.coerceToMethodNameSymbol(elem)) catch return error.Fatal;
        }
        return;
    }

    for (args) |arg| {
        names.append(vm.gc_allocator, try vm.coerceToMethodNameSymbol(arg)) catch return error.Fatal;
    }
}

fn getOwnDefinedMethodEntry(
    methods: *std.AutoHashMap(*SymbolObject, value.MethodEntry),
    name_sym: *SymbolObject,
) ?value.MethodEntry {
    const entry = methods.get(name_sym) orelse return null;
    if (entry.method == .undefined) return null;
    return entry;
}

fn appendConstantSymbolUnique(
    vm: *VM,
    out: *std.ArrayList(*SymbolObject),
    seen: *std.AutoHashMap(*SymbolObject, void),
    name_sym: *SymbolObject,
) VMError!void {
    if (seen.contains(name_sym)) return;
    seen.put(name_sym, {}) catch return error.Fatal;
    out.append(vm.gc_allocator, name_sym) catch return error.Fatal;
}

fn collectOwnConstantSymbols(
    vm: *VM,
    module_obj: *value.ModuleObject,
    out: *std.ArrayList(*SymbolObject),
    seen: *std.AutoHashMap(*SymbolObject, void),
) VMError!void {
    var it = module_obj.constants.iterator();
    while (it.next()) |entry| {
        if (module_obj.private_constants.contains(entry.key_ptr.*)) continue;
        try appendConstantSymbolUnique(vm, out, seen, entry.key_ptr.*);
    }
}

fn constantsTable(receiver: Value) ?*std.AutoHashMap(*SymbolObject, Value) {
    if (receiver.isClass()) return &receiver.toClassObject().module.constants;
    if (receiver.isModule()) return &receiver.toModuleObject().constants;
    return null;
}

fn privateConstantsTable(receiver: Value) ?*std.AutoHashMap(*SymbolObject, void) {
    if (receiver.isClass()) return &receiver.toClassObject().module.private_constants;
    if (receiver.isModule()) return &receiver.toModuleObject().private_constants;
    return null;
}

fn moduleFromValue(receiver: Value) ?*value.ModuleObject {
    if (receiver.isClass()) return &receiver.toClassObject().module;
    if (receiver.isModule()) return receiver.toModuleObject();
    return null;
}

fn lookupConstantOnModule(module_obj: *value.ModuleObject, name_sym: *SymbolObject) ?Value {
    if (module_obj.constants.get(name_sym)) |val| return val;

    var i = module_obj.prepended_modules.items.len;
    while (i > 0) {
        i -= 1;
        if (lookupConstantOnModule(module_obj.prepended_modules.items[i], name_sym)) |val| return val;
    }

    var j = module_obj.included_modules.items.len;
    while (j > 0) {
        j -= 1;
        if (lookupConstantOnModule(module_obj.included_modules.items[j], name_sym)) |val| return val;
    }

    return null;
}

fn lookupConstantOnReceiver(vm: *VM, receiver: Value, name_sym: *SymbolObject, inherit: bool) ?Value {
    if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        var first = true;
        while (current) |klass| {
            if (first or inherit) {
                if (lookupConstantOnModule(&klass.module, name_sym)) |val| return val;
            }
            if (!inherit and first) {
                if (klass == vm.object_class) {
                    if (lookupConstantOnModule(&vm.object_class.module, name_sym)) |val| return val;
                }
                break;
            }
            current = klass.superclass;
            first = false;
        }
        return null;
    }

    if (receiver.isModule()) {
        if (lookupConstantOnModule(receiver.toModuleObject(), name_sym)) |val| return val;
        if (inherit) {
            if (lookupConstantOnModule(&vm.object_class.module, name_sym)) |val| return val;
        }
        return null;
    }

    return null;
}

fn isValidConstantNameSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;

    const first = segment[0];
    if (!std.ascii.isUpper(first)) return false;

    for (segment[1..]) |byte| {
        if (byte >= 0x80) continue;
        if (std.ascii.isAlphanumeric(byte) or byte == '_') continue;
        return false;
    }

    return true;
}

fn constantNameString(vm: *VM, arg: Value) VMError![]const u8 {
    if (arg.isSymbol()) return arg.toSymbolObject().name;
    switch (try vm.probeToStringValue(arg)) {
        .string => |coerced| return coerced.toStringObject().str,
        .missing, .nil_result => {},
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "no implicit conversion of {s} into String", .{vm.className(arg)});
}

fn splitConstantName(allocator: std.mem.Allocator, name: []const u8, allow_root: bool) !std.ArrayList([]const u8) {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer parts.deinit(allocator);

    var offset: usize = if (allow_root and std.mem.startsWith(u8, name, "::")) 2 else 0;
    var segment_start = offset;

    while (offset <= name.len) : (offset += 1) {
        const at_end = offset == name.len;
        const at_sep = !at_end and offset + 1 < name.len and name[offset] == ':' and name[offset + 1] == ':';
        if (!at_end and !at_sep) continue;

        const segment = name[segment_start..offset];
        if (!isValidConstantNameSegment(segment)) return error.InvalidConstName;
        try parts.append(allocator, segment);

        if (at_sep) {
            offset += 1;
            segment_start = offset + 1;
        }
    }

    return parts;
}

fn constantPathDefined(vm: *VM, receiver: Value, name: []const u8, inherit: bool) VMError!bool {
    const rooted = std.mem.startsWith(u8, name, "::");
    var parts = splitConstantName(vm.gc_allocator, name, rooted) catch |err| switch (err) {
        error.InvalidConstName => return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name}),
        else => return error.Fatal,
    };
    defer parts.deinit(vm.gc_allocator);

    var current: Value = if (rooted) Value.fromObject(vm.object_class) else receiver;
    var first = true;
    for (parts.items) |part| {
        const name_sym = try vm.intern(part);
        const use_inherit = if (first and !rooted) inherit else true;
        _ = moduleFromValue(current) orelse return false;
        current = lookupConstantOnReceiver(vm, current, name_sym, use_inherit) orelse return false;
        first = false;
    }

    return true;
}

fn storedModuleName(receiver: Value) []const u8 {
    return if (receiver.isClass()) receiver.toClassObject().module.name.name else receiver.toModuleObject().name.name;
}

fn isSyntheticSingletonName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "#<Class:#");
}

fn isAnonymousStoredName(name: []const u8) bool {
    return std.mem.eql(u8, name, "<anonymous>");
}

fn findNestedConstantPath(
    vm: *VM,
    owner: Value,
    owner_path: []const u8,
    target: Value,
    seen: *std.AutoHashMap(usize, void),
) VMError!?[]const u8 {
    const constants = constantsTable(owner) orelse return null;
    const owner_key: usize = @intCast(owner.raw);
    if (seen.contains(owner_key)) return null;
    seen.put(owner_key, {}) catch return error.Fatal;

    var it = constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*;
        if (!child.isModule() and !child.isClass()) continue;

        const path = std.fmt.allocPrint(vm.gc_allocator, "{s}::{s}", .{ owner_path, entry.key_ptr.*.name }) catch return error.Fatal;
        if (child.raw == target.raw) return path;
    }

    it = constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*;
        if (!child.isModule() and !child.isClass()) continue;

        const path = std.fmt.allocPrint(vm.gc_allocator, "{s}::{s}", .{ owner_path, entry.key_ptr.*.name }) catch return error.Fatal;
        if (try findNestedConstantPath(vm, child, path, target, seen)) |found| return found;
    }

    return null;
}

fn findConstantPathFromObject(vm: *VM, target: Value) VMError!?[]const u8 {
    var seen = std.AutoHashMap(usize, void).init(vm.allocator);
    defer seen.deinit();

    var it = vm.object_class.module.constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*;
        if (!child.isModule() and !child.isClass()) continue;

        const path = entry.key_ptr.*.name;
        if (child.raw == target.raw) return path;
    }

    it = vm.object_class.module.constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*;
        if (!child.isModule() and !child.isClass()) continue;
        if (child.raw == Value.fromObject(vm.object_class).raw) continue;

        const path = entry.key_ptr.*.name;
        if (try findNestedConstantPath(vm, child, path, target, &seen)) |found| return found;
    }

    return null;
}

fn publicModuleName(vm: *VM, receiver: Value) VMError!?[]const u8 {
    if (receiver.isClass() and receiver.toClassObject().attached_object != null) return null;
    const stored_name = storedModuleName(receiver);
    if (isSyntheticSingletonName(stored_name)) return null;
    if (try findConstantPathFromObject(vm, receiver)) |path| return path;
    if (isAnonymousStoredName(stored_name)) return null;
    return stored_name;
}

fn basicObjectToS(vm: *VM, receiver: Value) VMError!Value {
    const class_val = Value.fromObject(vm.getClass(receiver));
    const class_name_val = try builtinModuleToS(vm, class_val, &[_]Value{}, null);
    if (!class_name_val.isString()) return error.Fatal;

    const text = std.fmt.allocPrint(
        vm.gc_allocator,
        "#<{s}:0x{x}>",
        .{ class_name_val.toStringObject().str, receiver.objectId() },
    ) catch return error.Fatal;
    return try vm.newString(text, false);
}

fn singletonAttachedObjectToS(vm: *VM, attached_object: Value) VMError!Value {
    if (attached_object.isClass() or attached_object.isModule()) {
        return builtinModuleToS(vm, attached_object, &[_]Value{}, null);
    }
    return basicObjectToS(vm, attached_object);
}

fn classIncludesModule(class_obj: *ClassObject, target: *value.ModuleObject) bool {
    var current: ?*ClassObject = class_obj;
    while (current) |klass| {
        var i = klass.module.prepended_modules.items.len;
        while (i > 0) {
            i -= 1;
            if (klass.module.prepended_modules.items[i] == target) return true;
        }

        var j = klass.module.included_modules.items.len;
        while (j > 0) {
            j -= 1;
            if (klass.module.included_modules.items[j] == target) return true;
        }

        current = klass.superclass;
    }
    return false;
}

fn collectInstanceMethods(
    vm: *VM,
    receiver: Value,
    filter: MethodListFilter,
    include_super: bool,
) VMError!Value {
    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);

    var seen: std.AutoHashMap(*SymbolObject, usize) = std.AutoHashMap(*SymbolObject, usize).init(vm.gc_allocator);
    defer seen.deinit();

    var blocked: std.AutoHashMap(*SymbolObject, void) = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer blocked.deinit();

    if (receiver.isModule()) {
        const module_obj = receiver.toModuleObject();
        try method_reflection.collectMethodsFromTable(vm, &module_obj.methods, filter, &names, &seen, &blocked);
    } else if (receiver.isClass()) {
        const class_obj = receiver.toClassObject();
        var current: ?*ClassObject = class_obj;
        while (current) |klass| {
            if (include_super) {
                var i = klass.module.prepended_modules.items.len;
                while (i > 0) {
                    i -= 1;
                    const prepended = klass.module.prepended_modules.items[i];
                    try method_reflection.collectMethodsFromTable(vm, &prepended.methods, filter, &names, &seen, &blocked);
                }
            }

            try method_reflection.collectMethodsFromTable(vm, &klass.module.methods, filter, &names, &seen, &blocked);

            if (include_super) {
                var j = klass.module.included_modules.items.len;
                while (j > 0) {
                    j -= 1;
                    const included = klass.module.included_modules.items[j];
                    try method_reflection.collectMethodsFromTable(vm, &included.methods, filter, &names, &seen, &blocked);
                }
            }

            if (!include_super) break;
            current = klass.superclass;
        }
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return method_reflection.sortedSymbolArray(vm, names.items);
}

fn setVisibility(vm: *VM, receiver: Value, args: []Value, visibility: MethodVisibility) VMError!Value {
    if (args.len == 0) {
        if (vm.current_lexical_scope) |scope| {
            scope.default_method_visibility = visibility;
            scope.module_function_mode = false;
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
        const entry = if (receiver.isClass()) blk: {
            const resolved = vm.lookupMethod(receiver.toClassObject(), name_sym) orelse break :blk null;
            break :blk resolved.entry;
        } else getOwnDefinedMethodEntry(methods, name_sym);
        const method_entry = entry orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        };
        var updated = method_entry;
        updated.visibility = visibility;
        methods.put(name_sym, updated) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (args.len == 1 and !args[0].isArray()) {
        return Value.fromObject(names.items[0]);
    }

    if (args.len == 1 and args[0].isArray()) {
        return args[0];
    }

    const arr = try vm.createArray();
    for (names.items) |name_sym| {
        arr.elements.append(vm.gc_allocator, Value.fromObject(name_sym)) catch return error.Fatal;
    }
    return Value.fromObject(arr);
}

fn raiseUndefinedMethodName(vm: *VM, name_sym: *SymbolObject) VMError!Value {
    const msg = std.fmt.allocPrint(
        vm.gc_allocator,
        "undefined method '{s}'",
        .{name_sym.name},
    ) catch return error.Fatal;
    const exc = try vm.createException(vm.name_error_class, msg);
    vm.pending_exception = exc;
    return error.Unwind;
}

fn setClassMethodVisibility(vm: *VM, receiver: Value, args: []Value, visibility: MethodVisibility) VMError!Value {
    if (args.len == 0) return Value.nil();

    if (!receiver.isClass() and !receiver.isModule()) {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);
    try normalizeVisibilityArgs(vm, args, &names);

    const singleton_class = try vm.getOrCreateSingletonClass(receiver);
    for (names.items) |name_sym| {
        const resolved = switch (vm.lookupMethodDetailed(singleton_class, name_sym)) {
            .found => |found| found,
            .undefined, .not_found => return raiseUndefinedMethodName(vm, name_sym),
        };
        var updated = resolved.entry;
        updated.visibility = visibility;
        singleton_class.module.methods.put(name_sym, updated) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (args.len == 1 and !args[0].isArray()) return Value.fromObject(names.items[0]);
    if (args.len == 1 and args[0].isArray()) return args[0];

    const arr = try vm.createArray();
    for (names.items) |name_sym| {
        arr.elements.append(vm.gc_allocator, Value.fromObject(name_sym)) catch return error.Fatal;
    }
    return Value.fromObject(arr);
}

fn copyMethodToModuleSingleton(vm: *VM, module_receiver: Value, name_sym: *SymbolObject, entry: value.MethodEntry) VMError!void {
    const singleton_class = try vm.getOrCreateSingletonClass(module_receiver);
    var singleton_entry = entry;
    singleton_entry.visibility = .public;
    singleton_class.module.methods.put(name_sym, singleton_entry) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(module_receiver);
    vm.bumpMethodStateVersion();
}

pub fn register(vm: *VM) !void {
    const include_sym = try vm.intern("include");
    try vm.module_class.module.methods.put(include_sym, .{ .method = .{ .builtin = &builtinModuleInclude } });

    const prepend_sym = try vm.intern("prepend");
    try vm.module_class.module.methods.put(prepend_sym, .{ .method = .{ .builtin = &builtinModulePrepend } });

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

    const undef_method_sym = try vm.intern("undef_method");
    try vm.module_class.module.methods.put(undef_method_sym, .{ .method = .{ .builtin = &builtinModuleUndefMethod } });

    const remove_method_sym = try vm.intern("remove_method");
    try vm.module_class.module.methods.put(remove_method_sym, .{ .method = .{ .builtin = &builtinModuleRemoveMethod } });

    const include_query_sym = try vm.intern("include?");
    try vm.module_class.module.methods.put(include_query_sym, .{ .method = .{ .builtin = &builtinModuleIncludeQ } });

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

    const module_function_sym = try vm.intern("module_function");
    try vm.module_class.module.methods.put(module_function_sym, .{
        .method = .{ .builtin = &builtinModuleFunction },
        .visibility = .private,
    });

    const private_class_method_sym = try vm.intern("private_class_method");
    try vm.module_class.module.methods.put(private_class_method_sym, .{ .method = .{ .builtin = &builtinModulePrivateClassMethod } });

    const public_class_method_sym = try vm.intern("public_class_method");
    try vm.module_class.module.methods.put(public_class_method_sym, .{ .method = .{ .builtin = &builtinModulePublicClassMethod } });

    const private_constant_sym = try vm.intern("private_constant");
    try vm.module_class.module.methods.put(private_constant_sym, .{ .method = .{ .builtin = &builtinModulePrivateConstant } });

    const public_constant_sym = try vm.intern("public_constant");
    try vm.module_class.module.methods.put(public_constant_sym, .{ .method = .{ .builtin = &builtinModulePublicConstant } });

    const case_equal_sym = try vm.intern("===");
    try vm.module_class.module.methods.put(case_equal_sym, .{ .method = .{ .builtin = &builtinModuleCaseEqual } });

    const constants_sym = try vm.intern("constants");
    try vm.module_class.module.methods.put(constants_sym, .{ .method = .{ .builtin = &builtinModuleConstants } });

    const const_defined_sym = try vm.intern("const_defined?");
    try vm.module_class.module.methods.put(const_defined_sym, .{ .method = .{ .builtin = &builtinModuleConstDefined } });

    const const_set_sym = try vm.intern("const_set");
    try vm.module_class.module.methods.put(const_set_sym, .{ .method = .{ .builtin = &builtinModuleConstSet } });

    const remove_const_sym = try vm.intern("remove_const");
    try vm.module_class.module.methods.put(remove_const_sym, .{ .method = .{ .builtin = &builtinModuleRemoveConst } });

    const ancestors_sym = try vm.intern("ancestors");
    try vm.module_class.module.methods.put(ancestors_sym, .{ .method = .{ .builtin = &builtinModuleAncestors } });

    const instance_methods_sym = try vm.intern("instance_methods");
    try vm.module_class.module.methods.put(instance_methods_sym, .{ .method = .{ .builtin = &builtinModuleInstanceMethods } });

    const private_instance_methods_sym = try vm.intern("private_instance_methods");
    try vm.module_class.module.methods.put(private_instance_methods_sym, .{ .method = .{ .builtin = &builtinModulePrivateInstanceMethods } });

    const protected_instance_methods_sym = try vm.intern("protected_instance_methods");
    try vm.module_class.module.methods.put(protected_instance_methods_sym, .{ .method = .{ .builtin = &builtinModuleProtectedInstanceMethods } });

    const public_instance_methods_sym = try vm.intern("public_instance_methods");
    try vm.module_class.module.methods.put(public_instance_methods_sym, .{ .method = .{ .builtin = &builtinModulePublicInstanceMethods } });

    const method_defined_sym = try vm.intern("method_defined?");
    try vm.module_class.module.methods.put(method_defined_sym, .{ .method = .{ .builtin = &builtinModuleMethodDefined } });

    const name_sym = try vm.intern("name");
    try vm.module_class.module.methods.put(name_sym, .{ .method = .{ .builtin = &builtinModuleName } });

    const to_s_sym = try vm.intern("to_s");
    try vm.module_class.module.methods.put(to_s_sym, .{ .method = .{ .builtin = &builtinModuleToS } });

    const inspect_sym = try vm.intern("inspect");
    try vm.module_class.module.methods.put(inspect_sym, .{ .method = .{ .builtin = &builtinModuleToS } });
}

pub fn builtinModuleCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const target = args[0];
    const receiver_module = if (receiver.isClass())
        &receiver.toClassObject().module
    else if (receiver.isModule())
        receiver.toModuleObject()
    else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    var current: ?*ClassObject = vm.getClass(target);
    while (current) |c| {
        if (&c.module == receiver_module) return Value.boolean(true);

        for (c.module.prepended_modules.items) |m| {
            if (m == receiver_module) return Value.boolean(true);
        }
        for (c.module.included_modules.items) |m| {
            if (m == receiver_module) return Value.boolean(true);
        }

        current = c.superclass;
    }

    return Value.boolean(false);
}

pub fn builtinModuleConstants(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const include_inherited = if (args.len == 1) args[0].is_truthy() else true;

    var constant_names: std.ArrayList(*SymbolObject) = .empty;
    defer constant_names.deinit(vm.gc_allocator);

    var seen: std.AutoHashMap(*SymbolObject, void) = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer seen.deinit();

    if (receiver.isModule()) {
        try collectOwnConstantSymbols(vm, receiver.toModuleObject(), &constant_names, &seen);
    } else if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        while (current) |klass| {
            try collectOwnConstantSymbols(vm, &klass.module, &constant_names, &seen);
            if (!include_inherited) break;
            current = klass.superclass;
        }
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    method_reflection.sortSymbolsByName(constant_names.items);

    const out = try vm.createArray();
    for (constant_names.items) |name_sym| {
        out.elements.append(vm.gc_allocator, Value.fromObject(name_sym)) catch return error.Fatal;
    }

    return Value.fromObject(out);
}

pub fn builtinModuleConstDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const inherit = if (args.len == 2) args[1].is_truthy() else true;
    const name = try constantNameString(vm, args[0]);

    if (std.mem.indexOf(u8, name, "::") != null) {
        return Value.boolean(try constantPathDefined(vm, receiver, name, inherit));
    }

    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    return Value.boolean(lookupConstantOnReceiver(vm, receiver, name_sym, inherit) != null);
}

pub fn builtinModuleConstSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const constants = constantsTable(receiver) orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    constants.put(name_sym, args[1]) catch return error.Fatal;
    return args[1];
}

pub fn builtinModuleRemoveConst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const constants = constantsTable(receiver) orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const private_constants = privateConstantsTable(receiver) orelse unreachable;

    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    const removed = constants.fetchRemove(name_sym) orelse {
        return vm.raiseExceptionFmt(vm.name_error_class, "constant {s}::{s} not defined", .{ storedModuleName(receiver), name });
    };
    _ = private_constants.remove(name_sym);
    return removed.value;
}

pub fn builtinModuleAncestors(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const out = try vm.createArray();

    if (receiver.isModule()) {
        out.elements.append(vm.gc_allocator, Value.fromObject(receiver.toModuleObject())) catch return error.Fatal;
    } else if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        while (current) |klass| {
            var i = klass.module.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const prepended = klass.module.prepended_modules.items[i];
                out.elements.append(vm.gc_allocator, Value.fromObject(prepended)) catch return error.Fatal;
            }

            out.elements.append(vm.gc_allocator, Value.fromObject(klass)) catch return error.Fatal;

            var j = klass.module.included_modules.items.len;
            while (j > 0) {
                j -= 1;
                const included = klass.module.included_modules.items[j];
                out.elements.append(vm.gc_allocator, Value.fromObject(included)) catch return error.Fatal;
            }

            current = klass.superclass;
        }
    } else {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    }

    return Value.fromObject(out);
}

pub fn builtinModuleInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectInstanceMethods(vm, receiver, .public_and_protected, include_super);
}

pub fn builtinModulePrivateInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectInstanceMethods(vm, receiver, .private_only, include_super);
}

pub fn builtinModuleProtectedInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectInstanceMethods(vm, receiver, .protected_only, include_super);
}

pub fn builtinModulePublicInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].is_truthy() else true;
    return collectInstanceMethods(vm, receiver, .public_only, include_super);
}

pub fn builtinModuleMethodDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const include_super = if (args.len == 2) args[1].is_truthy() else true;
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);

    const methods = try collectInstanceMethods(vm, receiver, .public_and_protected, include_super);
    const items = methods.toArrayObject().elements.items;
    for (items) |item| {
        if (item.isSymbol() and item.toSymbolObject() == name_sym) {
            return Value.boolean(true);
        }
    }
    return Value.boolean(false);
}

pub fn builtinModuleName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (try publicModuleName(vm, receiver)) |name| {
        return try vm.newString(name, true);
    }
    return Value.nil();
}

pub fn builtinModuleToS(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (receiver.isClass()) {
        if (receiver.toClassObject().attached_object) |attached_object| {
            const attached_str_val = try singletonAttachedObjectToS(vm, attached_object);
            if (!attached_str_val.isString()) return error.Fatal;

            const text = std.fmt.allocPrint(
                vm.gc_allocator,
                "#<Class:{s}>",
                .{attached_str_val.toStringObject().str},
            ) catch return error.Fatal;
            return try vm.newString(text, false);
        }
    }

    if (try publicModuleName(vm, receiver)) |name| {
        return try vm.newString(name, false);
    }

    const type_name = if (receiver.isClass()) "Class" else "Module";
    const text = std.fmt.allocPrint(vm.gc_allocator, "#<{s}:0x{x}>", .{ type_name, receiver.objectId() }) catch return error.Fatal;
    return try vm.newString(text, false);
}

pub fn builtinModuleIncludeQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const target_module = args[0].toModuleObject();

    if (receiver.isClass()) {
        return Value.boolean(classIncludesModule(receiver.toClassObject(), target_module));
    }

    if (receiver.isModule()) {
        return Value.boolean(false);
    }

    const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
    vm.pending_exception = exc;
    return error.Unwind;
}

pub fn builtinModuleInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const target = receiver.getModuleObject() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const module = args[0].toModuleObject();

    vm.includeModule(target, module) catch return error.Fatal;

    return receiver;
}

pub fn builtinModulePrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const target = receiver.getModuleObject() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const module = args[0].toModuleObject();

    vm.prependModule(target, module) catch return error.Fatal;

    return receiver;
}

pub fn builtinModuleDefineMethod(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const blk = try vm.requireBlock(block);

    const name_str = try vm.coerceToMethodNameString(args[0]);
    const name_sym = try vm.intern(name_str);
    const proc_val = try vm.newProc(blk);
    const visibility = currentDefaultVisibility(vm);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const module_function_mode = if (vm.current_lexical_scope) |scope| scope.module_function_mode else false;
    const effective_visibility: MethodVisibility = if (module_function_mode) .private else visibility;

    const entry: value.MethodEntry = .{
        .method = .{ .proc = proc_val.toProcObject() },
        .visibility = effective_visibility,
    };
    methods.put(name_sym, entry) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (module_function_mode and receiver.isModule()) {
        try copyMethodToModuleSingleton(vm, receiver, name_sym, entry);
    }

    return Value.fromObject(name_sym);
}

pub fn builtinModuleAttrReader(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        const name_str = try vm.coerceToMethodNameString(arg);
        const method_sym = try vm.intern(name_str);
        const chunk_ptr = try vm.createAccessorChunk(name_str, .reader);
        methods.put(method_sym, .{
            .method = .{ .chunk = chunk_ptr },
            .visibility = visibility,
        }) catch return error.Fatal;

        result_array.elements.append(vm.gc_allocator, Value.fromObject(method_sym)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(result_array);
}

pub fn builtinModuleAttrWriter(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        const name_str = try vm.coerceToMethodNameString(arg);
        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch return error.Fatal;
        defer vm.program.allocator.free(writer_name);
        const method_sym = try vm.intern(writer_name);
        const chunk_ptr = try vm.createAccessorChunk(name_str, .writer);
        methods.put(method_sym, .{
            .method = .{ .chunk = chunk_ptr },
            .visibility = visibility,
        }) catch return error.Fatal;

        result_array.elements.append(vm.gc_allocator, Value.fromObject(method_sym)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(result_array);
}

pub fn builtinModuleAttrAccessor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    const result_array = try vm.createArray();
    const visibility = currentDefaultVisibility(vm);

    for (args) |arg| {
        const name_str = try vm.coerceToMethodNameString(arg);
        const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch return error.Fatal;
        defer vm.program.allocator.free(writer_name);

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

        result_array.elements.append(vm.gc_allocator, Value.fromObject(reader_sym)) catch return error.Fatal;
        result_array.elements.append(vm.gc_allocator, Value.fromObject(writer_sym)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(result_array);
}

pub fn builtinModuleAliasMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const new_name_str = try vm.coerceToMethodNameString(args[0]);
    const old_name_str = try vm.coerceToMethodNameString(args[1]);

    const new_name_sym = try vm.intern(new_name_str);
    const old_name_sym = try vm.intern(old_name_str);

    // Get method table from receiver (class or module)
    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    var lookup_class: *value.ClassObject = undefined;
    if (receiver.isClass()) {
        lookup_class = receiver.toClassObject();
    } else if (receiver.isModule()) {
        // For modules, look up in own methods only
        if (getOwnDefinedMethodEntry(methods, old_name_sym)) |entry| {
            methods.put(new_name_sym, entry) catch return error.Fatal;
            vm.markIntegerChangedForReceiver(receiver);
            vm.bumpMethodStateVersion();
            return Value.fromObject(new_name_sym);
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
        vm.markIntegerChangedForReceiver(receiver);
        vm.bumpMethodStateVersion();
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

    return Value.fromObject(new_name_sym);
}

pub fn builtinModuleUndefMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    if (args.len == 0) return receiver;

    for (args) |arg| {
        const name_sym = try vm.coerceToMethodNameSymbol(arg);
        const exists = if (receiver.isClass())
            vm.lookupMethod(receiver.toClassObject(), name_sym) != null
        else if (receiver.isModule())
            getOwnDefinedMethodEntry(methods, name_sym) != null
        else
            unreachable;
        if (!exists) {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        }

        methods.put(name_sym, .{ .method = .{ .undefined = {} } }) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return receiver;
}

pub fn builtinModuleRemoveMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };

    for (args) |arg| {
        const name_sym = try vm.coerceToMethodNameSymbol(arg);
        _ = getOwnDefinedMethodEntry(methods, name_sym) orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        };
        _ = methods.remove(name_sym);
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return receiver;
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

pub fn builtinModulePrivateClassMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setClassMethodVisibility(vm, receiver, args, .private);
}

pub fn builtinModulePublicClassMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setClassMethodVisibility(vm, receiver, args, .public);
}

fn setConstantVisibility(vm: *VM, receiver: Value, args: []Value, private: bool) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const constants = constantsTable(receiver) orelse {
        const exc = try vm.createException(vm.type_error_class, "receiver is not a Module");
        vm.pending_exception = exc;
        return error.Unwind;
    };
    const private_constants = privateConstantsTable(receiver) orelse unreachable;

    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);
    try normalizeVisibilityArgs(vm, args, &names);

    for (names.items) |name_sym| {
        if (!constants.contains(name_sym)) {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "constant {s}::{s} not defined",
                .{ storedModuleName(receiver), name_sym.name },
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        }

        if (private) {
            private_constants.put(name_sym, {}) catch return error.Fatal;
        } else {
            _ = private_constants.remove(name_sym);
        }
    }

    return receiver;
}

pub fn builtinModulePrivateConstant(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setConstantVisibility(vm, receiver, args, true);
}

pub fn builtinModulePublicConstant(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    return setConstantVisibility(vm, receiver, args, false);
}

pub fn builtinModuleFunction(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (args.len == 0) {
        if (vm.current_lexical_scope) |scope| {
            scope.default_method_visibility = .private;
            scope.module_function_mode = true;
        }
        return Value.nil();
    }

    const methods = receiver.getModuleMethods() orelse unreachable;

    for (args) |arg| {
        const name_str = try vm.coerceToMethodNameString(arg);
        const name_sym = try vm.intern(name_str);
        const existing = getOwnDefinedMethodEntry(methods, name_sym) orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            const exc = try vm.createException(vm.name_error_class, msg);
            vm.pending_exception = exc;
            return error.Unwind;
        };

        try copyMethodToModuleSingleton(vm, receiver, name_sym, existing);

        var private_entry = existing;
        private_entry.visibility = .private;
        methods.put(name_sym, private_entry) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (args.len == 1) {
        return args[0];
    }

    const arr = try vm.createArray();
    for (args) |arg| {
        arr.elements.append(vm.gc_allocator, arg) catch return error.Fatal;
    }
    return Value.fromObject(arr);
}
