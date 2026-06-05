const std = @import("std");
const ancestry = @import("../ancestry.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const method_common = @import("method_common.zig");
const method_reflection = @import("method_reflection.zig");
const unbound_method = @import("unbound_method.zig");
const warning_builtin = @import("warning.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const MethodEntry = value.MethodEntry;
const MethodVisibility = value.MethodVisibility;
const SymbolObject = value.SymbolObject;
const ClassObject = value.ClassObject;
const MethodListFilter = method_reflection.MethodListFilter;
const MethodQueryFilter = enum {
    public_and_protected,
    private_only,
    protected_only,
    public_only,
};

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
        if (entry.value_ptr.*.flags.visibility == .private) continue;
        try appendConstantSymbolUnique(vm, out, seen, entry.key_ptr.*);
    }

    var autoload_it = module_obj.autoloads.iterator();
    while (autoload_it.next()) |entry| {
        if (module_obj.constants.get(entry.key_ptr.*)) |const_entry| {
            if (const_entry.flags.visibility == .private) continue;
        }
        try appendConstantSymbolUnique(vm, out, seen, entry.key_ptr.*);
    }
}

fn constantsTable(receiver: Value) ?*std.AutoHashMap(*SymbolObject, value.ConstEntry) {
    if (receiver.isClass()) return &receiver.toClassObject().module.constants;
    if (receiver.isModule()) return &receiver.toModuleObject().constants;
    return null;
}

fn autoloadTable(receiver: Value) ?*std.AutoHashMap(*SymbolObject, []const u8) {
    if (receiver.isClass()) return &receiver.toClassObject().module.autoloads;
    if (receiver.isModule()) return &receiver.toModuleObject().autoloads;
    return null;
}

fn moduleFromValue(receiver: Value) ?*value.ModuleObject {
    if (receiver.isClass()) return &receiver.toClassObject().module;
    if (receiver.isModule()) return receiver.toModuleObject();
    return null;
}

fn constantEntryOnModule(module_obj: *value.ModuleObject, name_sym: *SymbolObject) ?value.ConstEntry {
    return module_obj.constants.get(name_sym);
}

fn lookupConstantOnModule(module_obj: *value.ModuleObject, name_sym: *SymbolObject) ?Value {
    if (module_obj.origin != module_obj) {
        var prepends = module_obj.super;
        while (prepends) |node| : (prepends = node.super) {
            if (node.is_origin_iclass) break;
            if (!ancestry.isVisibleAncestor(node)) continue;
            const owner = ancestry.visibleModule(node);
            if (owner.constants.get(name_sym)) |entry| return entry.value;
        }
    }

    if (constantEntryOnModule(module_obj, name_sym)) |entry| return entry.value;

    var current = if (module_obj.origin == module_obj) module_obj.super else module_obj.origin.super;
    while (current) |node| : (current = node.super) {
        if (node.object.type_tag == .class) break;
        if (!ancestry.isVisibleAncestor(node)) continue;
        const owner = ancestry.visibleModule(node);
        if (owner.constants.get(name_sym)) |entry| return entry.value;
    }

    return null;
}

fn lookupAutoloadOnModule(module_obj: *value.ModuleObject, name_sym: *SymbolObject) ?[]const u8 {
    if (module_obj.origin != module_obj) {
        var prepends = module_obj.super;
        while (prepends) |node| : (prepends = node.super) {
            if (node.is_origin_iclass) break;
            if (!ancestry.isVisibleAncestor(node)) continue;
            const owner = ancestry.visibleModule(node);
            if (owner.autoloads.get(name_sym)) |path| return path;
        }
    }

    if (module_obj.autoloads.get(name_sym)) |path| return path;

    var current = if (module_obj.origin == module_obj) module_obj.super else module_obj.origin.super;
    while (current) |node| : (current = node.super) {
        if (node.object.type_tag == .class) break;
        if (!ancestry.isVisibleAncestor(node)) continue;
        const owner = ancestry.visibleModule(node);
        if (owner.autoloads.get(name_sym)) |path| return path;
    }

    return null;
}

fn lookupConstantOnReceiver(vm: *VM, receiver: Value, name_sym: *SymbolObject, inherit: bool) ?Value {
    if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        while (current) |klass| {
            if (lookupConstantOnModule(&klass.module, name_sym)) |val| return val;
            if (!inherit) break;
            current = klass.superclass;
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

fn lookupAutoloadOnReceiver(vm: *VM, receiver: Value, name_sym: *SymbolObject, inherit: bool) ?[]const u8 {
    if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        while (current) |klass| {
            if (lookupAutoloadOnModule(&klass.module, name_sym)) |path| return path;
            if (!inherit) break;
            current = klass.superclass;
        }
        return null;
    }

    if (receiver.isModule()) {
        if (lookupAutoloadOnModule(receiver.toModuleObject(), name_sym)) |path| return path;
        if (inherit) {
            if (lookupAutoloadOnModule(&vm.object_class.module, name_sym)) |path| return path;
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

fn classVariableNameString(vm: *VM, arg: Value) VMError![]const u8 {
    const name = try constantNameString(vm, arg);
    if (name.len < 3 or name[0] != '@' or name[1] != '@') {
        return vm.raiseExceptionFmt(vm.name_error_class, "`{s}' is not allowed as a class variable name", .{name});
    }
    return name;
}

fn evalFilename(vm: *VM, source_file_arg: ?Value) VMError![]const u8 {
    if (source_file_arg) |arg| {
        return arg.coerceToStr(vm, "no implicit conversion into String");
    }

    if (vm.currentRubyCallerFrame()) |frame| {
        const caller_source = frame.chunk.source_file orelse "(eval)";
        const caller_line = vm.backtraceLineForFrame(frame);
        return std.fmt.allocPrint(vm.gc_allocator, "(eval at {s}:{d})", .{ caller_source, caller_line }) catch return error.Fatal;
    }

    return "(eval)";
}

fn evalLineOffset(vm: *VM, lineno_arg: ?Value) VMError!u32 {
    if (lineno_arg == null or lineno_arg.?.isNil()) return 0;
    const lineno = try lineno_arg.?.coerceToI64ViaToInt(
        vm,
        "no implicit conversion into Integer",
        "can't convert to Integer (to_int gives non-Integer)",
        "bignum too big to convert into `long'",
    );
    if (lineno <= 1) return 0;
    return @intCast(lineno - 1);
}

fn coerceEvalSourceValue(vm: *VM, arg: Value) VMError!Value {
    return switch (try vm.probeToStringValue(arg)) {
        .string => |coerced| coerced,
        .missing, .nil_result => vm.raiseExceptionFmt(
            vm.type_error_class,
            "no implicit conversion of {s} into String",
            .{vm.className(arg)},
        ),
    };
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

    var current: Value = if (rooted) Value.fromObject(&vm.object_class.module.object) else receiver;
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

fn getConstantPath(vm: *VM, receiver: Value, name: []const u8, inherit: bool) VMError!Value {
    const rooted = std.mem.startsWith(u8, name, "::");
    var parts = splitConstantName(vm.gc_allocator, name, rooted) catch |err| switch (err) {
        error.InvalidConstName => return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name}),
        else => return error.Fatal,
    };
    defer parts.deinit(vm.gc_allocator);

    var current: Value = if (rooted) Value.fromObject(&vm.object_class.module.object) else receiver;
    var first = true;
    for (parts.items) |part| {
        const name_sym = try vm.intern(part);
        const use_inherit = if (first and !rooted) inherit else true;
        _ = moduleFromValue(current) orelse {
            return vm.raiseExceptionFmt(vm.name_error_class, "uninitialized constant {s}", .{name});
        };
        current = lookupConstantOnReceiver(vm, current, name_sym, use_inherit) orelse {
            return vm.raiseExceptionFmt(vm.name_error_class, "uninitialized constant {s}", .{name});
        };
        first = false;
    }

    return current;
}

fn storedModuleName(receiver: Value) []const u8 {
    return if (receiver.isClass()) receiver.toClassObject().module.name.name else receiver.toModuleObject().name.name;
}

fn warnDeprecatedConstant(vm: *VM, receiver: Value, name_sym: *SymbolObject) VMError!void {
    if (!vm.warning_deprecated_enabled) return;
    const module_obj = moduleFromValue(receiver) orelse return;
    const entry = module_obj.constants.get(name_sym) orelse return;
    if (!entry.flags.deprecated) return;

    const module_name = storedModuleName(receiver);
    const warning = std.fmt.allocPrint(
        vm.allocator,
        "warning: constant {s}::{s} is deprecated\n",
        .{ module_name, name_sym.name },
    ) catch return error.Fatal;
    defer vm.allocator.free(warning);
    try warning_builtin.writeWarning(vm, warning);
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
        const child = entry.value_ptr.*.value;
        if (!child.isModule() and !child.isClass()) continue;

        const path = std.fmt.allocPrint(vm.gc_allocator, "{s}::{s}", .{ owner_path, entry.key_ptr.*.name }) catch return error.Fatal;
        if (child.raw == target.raw) return path;
    }

    it = constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*.value;
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
        const child = entry.value_ptr.*.value;
        if (!child.isModule() and !child.isClass()) continue;

        const path = entry.key_ptr.*.name;
        if (child.raw == target.raw) return path;
    }

    it = vm.object_class.module.constants.iterator();
    while (it.next()) |entry| {
        const child = entry.value_ptr.*.value;
        if (!child.isModule() and !child.isClass()) continue;
        if (child.raw == Value.fromObject(&vm.object_class.module.object).raw) continue;

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

fn moduleMethodErrorOwnerName(vm: *VM, receiver: Value) VMError![]const u8 {
    if (receiver.isClass()) {
        if (receiver.toClassObject().attached_object) |attached_object| {
            if (attached_object.isClass() or attached_object.isModule()) {
                const attached_str_val = try builtinModuleToS(vm, attached_object, &[_]Value{}, null);
                if (!attached_str_val.isString()) return error.Fatal;
                return attached_str_val.toStringObject().str;
            }
        }
    }

    const receiver_str_val = try builtinModuleToS(vm, receiver, &[_]Value{}, null);
    if (!receiver_str_val.isString()) return error.Fatal;
    return receiver_str_val.toStringObject().str;
}

fn basicObjectToS(vm: *VM, receiver: Value) VMError!Value {
    const receiver_class = vm.getClass(receiver);
    const class_val = Value.fromObject(&receiver_class.module.object);
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
    return classLookupChainContains(class_obj, target);
}

fn moduleLookupChainContains(module_obj: *value.ModuleObject, target: *value.ModuleObject) bool {
    if (module_obj == target) return true;
    var current = module_obj.super;
    while (current) |node| : (current = node.super) {
        if (node == target) return true;
        if (node.object.type_tag == .iclass and node.origin == target.origin and !node.is_origin_iclass) return true;
    }
    return false;
}

fn classLookupChainContains(class_obj: *ClassObject, target: *value.ModuleObject) bool {
    var current: ?*value.ModuleObject = &class_obj.module;
    while (current) |node| : (current = node.super) {
        if (node == target) return true;
        if (node.object.type_tag == .iclass and node.origin == target.origin and !node.is_origin_iclass) return true;
    }
    return false;
}

fn receiverModuleForComparison(vm: *VM, receiver: Value) VMError!*value.ModuleObject {
    if (receiver.isClass()) return &receiver.toClassObject().module;
    if (receiver.isModule()) return receiver.toModuleObject();

    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
}

fn moduleLookupChainContainsValue(target: Value, module_obj: *value.ModuleObject) VMError!bool {
    if (target.isClass()) return classLookupChainContains(target.toClassObject(), module_obj);
    if (target.isModule()) return moduleLookupChainContains(target.toModuleObject(), module_obj);
    return error.Fatal;
}

const ModuleComparison = enum {
    equal,
    receiver_ancestor,
    receiver_descendant,
    unrelated,
};

fn compareModules(vm: *VM, receiver: Value, other: Value) VMError!ModuleComparison {
    const receiver_module = try receiverModuleForComparison(vm, receiver);
    const other_module = if (other.isClass())
        &other.toClassObject().module
    else if (other.isModule())
        other.toModuleObject()
    else {
        return vm.raiseExceptionFmt(vm.type_error_class, "compared with non class/module", .{});
    };

    if (receiver_module == other_module) return .equal;

    if (try moduleLookupChainContainsValue(other, receiver_module)) return .receiver_ancestor;
    if (try moduleLookupChainContainsValue(receiver, other_module)) return .receiver_descendant;
    return .unrelated;
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
        if (include_super)
            try method_reflection.collectModuleAncestryMethods(vm, module_obj, filter, true, &names, &seen, &blocked)
        else
            try method_reflection.collectMethodsFromTable(vm, &module_obj.origin.methods, filter, &names, &seen, &blocked);
    } else if (receiver.isClass()) {
        const class_obj = receiver.toClassObject();
        try method_reflection.collectClassChainMethods(vm, class_obj, include_super, filter, true, &names, &seen, &blocked);
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    }

    return method_reflection.sortedSymbolArray(vm, names.items);
}

const InstanceMethodLookup = struct {
    resolved: vm_mod.ResolvedMethod,
    owner: Value,
};

const InstanceMethodLookupResult = union(enum) {
    found: InstanceMethodLookup,
    undefined,
    not_found,
};

fn methodEntryMatchesQuery(entry: value.MethodEntry, filter: MethodQueryFilter) bool {
    if (entry.method == .undefined) return false;
    return switch (filter) {
        .public_and_protected => entry.visibility == .public or entry.visibility == .protected,
        .private_only => entry.visibility == .private,
        .protected_only => entry.visibility == .protected,
        .public_only => entry.visibility == .public,
    };
}

fn resolveModuleMethodLookup(module_obj: *value.ModuleObject, owner_class: *ClassObject, name_sym: *SymbolObject) InstanceMethodLookupResult {
    var current: ?*value.ModuleObject = module_obj;
    while (current) |node| : (current = node.super) {
        if (ancestry.methodTableOwner(node).methods.get(name_sym)) |entry| {
            return switch (entry.method) {
                .undefined => .undefined,
                else => .{ .found = .{
                    .resolved = .{
                        .name = name_sym,
                        .owner_class = owner_class,
                        .entry = entry,
                    },
                    .owner = ancestry.visibleValue(node),
                } },
            };
        }
    }
    return .not_found;
}

fn resolveInstanceMethodLookup(vm: *VM, receiver: Value, name_sym: *SymbolObject) InstanceMethodLookupResult {
    if (receiver.isModule()) {
        return resolveModuleMethodLookup(receiver.toModuleObject(), vm.object_class, name_sym);
    }

    if (receiver.isClass()) {
        var current: ?*value.ModuleObject = &receiver.toClassObject().module;
        var owner_class = receiver.toClassObject();
        while (current) |node| : (current = node.super) {
            if (node.object.type_tag == .class) owner_class = @fieldParentPtr("module", node);
            if (ancestry.methodTableOwner(node).methods.get(name_sym)) |entry| {
                return switch (entry.method) {
                    .undefined => .undefined,
                    else => .{ .found = .{
                        .resolved = .{
                            .name = name_sym,
                            .owner_class = owner_class,
                            .entry = entry,
                        },
                        .owner = ancestry.visibleValue(node),
                    } },
                };
            }
        }
        return .not_found;
    }

    return .not_found;
}

fn ownMethodDefined(
    receiver: Value,
    name_sym: *SymbolObject,
    filter: MethodQueryFilter,
) bool {
    const methods = receiver.getModuleMethods() orelse return false;
    const entry = methods.get(name_sym) orelse return false;
    return methodEntryMatchesQuery(entry, filter);
}

fn methodDefined(
    vm: *VM,
    receiver: Value,
    name_sym: *SymbolObject,
    filter: MethodQueryFilter,
    include_super: bool,
) bool {
    if (!include_super) return ownMethodDefined(receiver, name_sym, filter);
    return switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
        .found => |lookup| methodEntryMatchesQuery(lookup.resolved.entry, filter),
        .undefined, .not_found => false,
    };
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
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    for (names.items) |name_sym| {
        const entry = if (receiver.isClass()) blk: {
            const resolved = vm.lookupMethod(receiver.toClassObject(), name_sym) orelse break :blk null;
            break :blk resolved.entry;
        } else switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
            .found => |lookup| lookup.resolved.entry,
            .undefined, .not_found => null,
        };
        const method_entry = entry orelse {
            return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{name_sym.name});
        };
        var updated = method_entry;
        updated.visibility = visibility;
        methods.put(name_sym, updated) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (args.len == 1 and !args[0].isArray()) {
        return Value.fromObject(&names.items[0].object);
    }

    if (args.len == 1 and args[0].isArray()) {
        return args[0];
    }

    const arr = try vm.createArray();
    for (names.items) |name_sym| {
        arr.elements.append(vm.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

fn raiseUndefinedMethodName(vm: *VM, name_sym: *SymbolObject) VMError!Value {
    return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{name_sym.name});
}

fn methodBodiesMatch(a: MethodEntry, b: MethodEntry) bool {
    return switch (a.method) {
        .chunk => |a_chunk| switch (b.method) {
            .chunk => |b_chunk| a_chunk == b_chunk,
            else => false,
        },
        .proc => |a_proc| switch (b.method) {
            .proc => |b_proc| a_proc == b_proc,
            else => false,
        },
        .builtin => |a_builtin| switch (b.method) {
            .builtin => |b_builtin| a_builtin.function == b_builtin.function,
            else => false,
        },
        .undefined => b.method == .undefined,
    };
}

fn methodSupportsRuby2Keywords(entry: MethodEntry) bool {
    return switch (entry.method) {
        .chunk => |ch| ch.rest_param_index != null and
            ch.post_required_count == 0 and
            !ch.no_keywords and
            ch.required_keywords.items.len == 0 and
            ch.optional_keywords.items.len == 0 and
            ch.keyword_rest_index == null,
        .proc => |proc_obj| switch (proc_obj.block.kind) {
            .chunk => |chunk_blk| blk: {
                const ch = chunk_blk.chunk;
                break :blk ch.rest_param_index != null and
                    ch.post_required_count == 0 and
                    !ch.no_keywords and
                    ch.required_keywords.items.len == 0 and
                    ch.optional_keywords.items.len == 0 and
                    ch.keyword_rest_index == null;
            },
            else => false,
        },
        .builtin, .undefined => false,
    };
}

fn markRuby2KeywordsEntries(methods: *std.AutoHashMap(*SymbolObject, MethodEntry), target: MethodEntry) void {
    var iter = methods.iterator();
    while (iter.next()) |method_entry| {
        if (!methodBodiesMatch(method_entry.value_ptr.*, target)) continue;
        method_entry.value_ptr.ruby2_keywords = true;
    }
}

fn setClassMethodVisibility(vm: *VM, receiver: Value, args: []Value, visibility: MethodVisibility) VMError!Value {
    if (args.len == 0) return Value.nil();

    if (!receiver.isClass() and !receiver.isModule()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
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

    if (args.len == 1 and !args[0].isArray()) return Value.fromObject(&names.items[0].object);
    if (args.len == 1 and args[0].isArray()) return args[0];

    const arr = try vm.createArray();
    for (names.items) |name_sym| {
        arr.elements.append(vm.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

pub fn builtinModuleRuby2Keywords(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    for (args) |arg| {
        const name_sym = try vm.coerceToMethodNameSymbol(arg);
        const found = switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
            .found => |resolved| resolved,
            .undefined, .not_found => return raiseUndefinedMethodName(vm, name_sym),
        };

        if (!methodSupportsRuby2Keywords(found.resolved.entry)) {
            const warning = std.fmt.allocPrint(
                vm.allocator,
                "warning: Skipping set of ruby2_keywords flag for {s} (method accepts keywords or post arguments or method does not accept argument splat)\n",
                .{name_sym.name},
            ) catch return error.Fatal;
            defer vm.allocator.free(warning);
            try warning_builtin.writeWarning(vm, warning);
            continue;
        }

        if (found.owner.getModuleMethods()) |owner_methods| {
            markRuby2KeywordsEntries(owner_methods, found.resolved.entry);
        } else {
            markRuby2KeywordsEntries(methods, found.resolved.entry);
        }
    }

    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();
    return Value.nil();
}

fn copyMethodToModuleSingleton(vm: *VM, module_receiver: Value, name_sym: *SymbolObject, entry: value.MethodEntry) VMError!void {
    const singleton_class = try vm.getOrCreateSingletonClass(module_receiver);
    var singleton_entry = entry;
    singleton_entry.visibility = .public;
    singleton_class.module.methods.put(name_sym, singleton_entry) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(module_receiver);
    vm.bumpMethodStateVersion();
}

fn moduleFunctionLookup(vm: *VM, receiver: Value, name_sym: *SymbolObject) ?value.MethodEntry {
    switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
        .found => |found| return found.resolved.entry,
        .undefined, .not_found => {},
    }

    if (receiver.isModule()) {
        const resolved = vm.lookupMethod(vm.module_class, name_sym) orelse return null;
        return resolved.entry;
    }

    return null;
}

/// Default no-op callback for Module#method_added
pub fn builtinModuleMethodAdded(_: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    _ = args; // name symbol
    return Value.nil();
}

/// Default no-op callback for Module#singleton_method_added
pub fn builtinModuleSingletonMethodAdded(_: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    _ = args; // name symbol
    return Value.nil();
}

pub fn register(vm: *VM) !void {
    const module_singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.module_class.module.object));
    const nesting_sym = try vm.intern("nesting");
    try module_singleton.module.methods.put(nesting_sym, value.MethodEntry.builtin(&builtinModuleNesting, .{ .exact = 0 }));

    const include_sym = try vm.intern("include");
    try vm.module_class.module.methods.put(include_sym, value.MethodEntry.builtin(&builtinModuleInclude, .{ .variadic = 0 }));

    const append_features_sym = try vm.intern("append_features");
    try vm.module_class.module.methods.put(append_features_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleAppendFeatures, .{ .exact = 1 }, .private));

    const included_sym = try vm.intern("included");
    try vm.module_class.module.methods.put(included_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleIncluded, .{ .exact = 1 }, .private));

    const extend_object_sym = try vm.intern("extend_object");
    try vm.module_class.module.methods.put(extend_object_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleExtendObject, .{ .exact = 1 }, .private));

    const extended_sym = try vm.intern("extended");
    try vm.module_class.module.methods.put(extended_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleExtended, .{ .exact = 1 }, .private));

    const prepend_sym = try vm.intern("prepend");
    try vm.module_class.module.methods.put(prepend_sym, value.MethodEntry.builtin(&builtinModulePrepend, .{ .variadic = 0 }));

    const define_method_sym = try vm.intern("define_method");
    try vm.module_class.module.methods.put(define_method_sym, value.MethodEntry.builtin(&builtinModuleDefineMethod, .{ .variadic = 0 }));

    const attr_reader_sym = try vm.intern("attr_reader");
    try vm.module_class.module.methods.put(attr_reader_sym, value.MethodEntry.builtin(&builtinModuleAttrReader, .{ .variadic = 0 }));

    const attr_writer_sym = try vm.intern("attr_writer");
    try vm.module_class.module.methods.put(attr_writer_sym, value.MethodEntry.builtin(&builtinModuleAttrWriter, .{ .variadic = 0 }));

    const attr_accessor_sym = try vm.intern("attr_accessor");
    try vm.module_class.module.methods.put(attr_accessor_sym, value.MethodEntry.builtin(&builtinModuleAttrAccessor, .{ .variadic = 0 }));

    const attr_sym = try vm.intern("attr");
    try vm.module_class.module.methods.put(attr_sym, value.MethodEntry.builtin(&builtinModuleAttr, .{ .variadic = 0 }));

    const alias_method_sym = try vm.intern("alias_method");
    try vm.module_class.module.methods.put(alias_method_sym, value.MethodEntry.builtin(&builtinModuleAliasMethod, .{ .exact = 2 }));

    const undef_method_sym = try vm.intern("undef_method");
    try vm.module_class.module.methods.put(undef_method_sym, value.MethodEntry.builtin(&builtinModuleUndefMethod, .{ .variadic = 0 }));

    const remove_method_sym = try vm.intern("remove_method");
    try vm.module_class.module.methods.put(remove_method_sym, value.MethodEntry.builtin(&builtinModuleRemoveMethod, .{ .variadic = 0 }));

    const include_query_sym = try vm.intern("include?");
    try vm.module_class.module.methods.put(include_query_sym, value.MethodEntry.builtin(&builtinModuleIncludeQ, .{ .exact = 1 }));

    const private_sym = try vm.intern("private");
    try vm.module_class.module.methods.put(private_sym, value.MethodEntry.builtinWithVisibility(&builtinModulePrivate, .{ .variadic = 0 }, .private));

    const public_sym = try vm.intern("public");
    try vm.module_class.module.methods.put(public_sym, value.MethodEntry.builtinWithVisibility(&builtinModulePublic, .{ .variadic = 0 }, .private));

    const protected_sym = try vm.intern("protected");
    try vm.module_class.module.methods.put(protected_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleProtected, .{ .variadic = 0 }, .private));

    const module_function_sym = try vm.intern("module_function");
    try vm.module_class.module.methods.put(module_function_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleFunction, .{ .variadic = 0 }, .private));
    try vm.class_class.module.methods.put(module_function_sym, .{ .method = .{ .undefined = {} } });

    const method_added_sym = try vm.intern("method_added");
    try vm.module_class.module.methods.put(method_added_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleMethodAdded, .{ .exact = 1 }, .private));

    const singleton_method_added_sym = try vm.intern("singleton_method_added");
    try vm.module_class.module.methods.put(singleton_method_added_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleSingletonMethodAdded, .{ .exact = 1 }, .private));

    const ruby2_keywords_sym = try vm.intern("ruby2_keywords");
    try vm.module_class.module.methods.put(ruby2_keywords_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleRuby2Keywords, .{ .variadic = 0 }, .private));

    const private_class_method_sym = try vm.intern("private_class_method");
    try vm.module_class.module.methods.put(private_class_method_sym, value.MethodEntry.builtin(&builtinModulePrivateClassMethod, .{ .variadic = 0 }));

    const public_class_method_sym = try vm.intern("public_class_method");
    try vm.module_class.module.methods.put(public_class_method_sym, value.MethodEntry.builtin(&builtinModulePublicClassMethod, .{ .variadic = 0 }));

    const private_constant_sym = try vm.intern("private_constant");
    try vm.module_class.module.methods.put(private_constant_sym, value.MethodEntry.builtin(&builtinModulePrivateConstant, .{ .variadic = 0 }));

    const public_constant_sym = try vm.intern("public_constant");
    try vm.module_class.module.methods.put(public_constant_sym, value.MethodEntry.builtin(&builtinModulePublicConstant, .{ .variadic = 0 }));

    const deprecate_constant_sym = try vm.intern("deprecate_constant");
    try vm.module_class.module.methods.put(deprecate_constant_sym, value.MethodEntry.builtin(&builtinModuleDeprecateConstant, .{ .variadic = 0 }));

    const case_equal_sym = try vm.intern("===");
    try vm.module_class.module.methods.put(case_equal_sym, value.MethodEntry.builtin(&builtinModuleCaseEqual, .{ .exact = 1 }));

    const greater_than_sym = try vm.intern(">");
    try vm.module_class.module.methods.put(greater_than_sym, value.MethodEntry.builtin(&builtinModuleGreaterThan, .{ .exact = 1 }));

    const greater_than_equal_sym = try vm.intern(">=");
    try vm.module_class.module.methods.put(greater_than_equal_sym, value.MethodEntry.builtin(&builtinModuleGreaterThanEqual, .{ .exact = 1 }));

    const less_than_sym = try vm.intern("<");
    try vm.module_class.module.methods.put(less_than_sym, value.MethodEntry.builtin(&builtinModuleLessThan, .{ .exact = 1 }));

    const less_than_equal_sym = try vm.intern("<=");
    try vm.module_class.module.methods.put(less_than_equal_sym, value.MethodEntry.builtin(&builtinModuleLessThanEqual, .{ .exact = 1 }));

    const constants_sym = try vm.intern("constants");
    try vm.module_class.module.methods.put(constants_sym, value.MethodEntry.builtin(&builtinModuleConstants, .{ .variadic = 0 }));

    const const_defined_sym = try vm.intern("const_defined?");
    try vm.module_class.module.methods.put(const_defined_sym, value.MethodEntry.builtin(&builtinModuleConstDefined, .{ .variadic = 0 }));

    const const_set_sym = try vm.intern("const_set");
    try vm.module_class.module.methods.put(const_set_sym, value.MethodEntry.builtin(&builtinModuleConstSet, .{ .exact = 2 }));

    const inherited_sym = try vm.intern("inherited");
    try vm.module_class.module.methods.put(inherited_sym, value.MethodEntry.builtin(&builtinModuleInherited, .{ .exact = 1 }));

    const autoload_sym = try vm.intern("autoload");
    try vm.module_class.module.methods.put(autoload_sym, value.MethodEntry.builtin(&builtinModuleAutoload, .{ .exact = 2 }));

    const autoload_q_sym = try vm.intern("autoload?");
    try vm.module_class.module.methods.put(autoload_q_sym, value.MethodEntry.builtin(&builtinModuleAutoloadQ, .{ .variadic = 0 }));

    const remove_const_sym = try vm.intern("remove_const");
    try vm.module_class.module.methods.put(remove_const_sym, value.MethodEntry.builtin(&builtinModuleRemoveConst, .{ .exact = 1 }));

    const const_get_sym = try vm.intern("const_get");
    try vm.module_class.module.methods.put(const_get_sym, value.MethodEntry.builtin(&builtinModuleConstGet, .{ .variadic = 0 }));

    const module_eval_sym = try vm.intern("module_eval");
    try vm.module_class.module.methods.put(module_eval_sym, value.MethodEntry.builtin(&builtinModuleEval, .{ .variadic = 0 }));

    const class_eval_sym = try vm.intern("class_eval");
    try vm.module_class.module.methods.put(class_eval_sym, value.MethodEntry.builtin(&builtinModuleEval, .{ .variadic = 0 }));

    const module_exec_sym = try vm.intern("module_exec");
    try vm.module_class.module.methods.put(module_exec_sym, value.MethodEntry.builtin(&builtinModuleExec, .{ .variadic = 0 }));

    const class_exec_sym = try vm.intern("class_exec");
    try vm.module_class.module.methods.put(class_exec_sym, value.MethodEntry.builtin(&builtinModuleExec, .{ .variadic = 0 }));

    const class_variable_get_sym = try vm.intern("class_variable_get");
    try vm.module_class.module.methods.put(class_variable_get_sym, value.MethodEntry.builtin(&builtinModuleClassVariableGet, .{ .exact = 1 }));

    const class_variable_set_sym = try vm.intern("class_variable_set");
    try vm.module_class.module.methods.put(class_variable_set_sym, value.MethodEntry.builtin(&builtinModuleClassVariableSet, .{ .exact = 2 }));

    const class_variables_sym = try vm.intern("class_variables");
    try vm.module_class.module.methods.put(class_variables_sym, value.MethodEntry.builtin(&builtinModuleClassVariables, .{ .variadic = 0 }));

    const ancestors_sym = try vm.intern("ancestors");
    try vm.module_class.module.methods.put(ancestors_sym, value.MethodEntry.builtin(&builtinModuleAncestors, .{ .exact = 0 }));

    const instance_methods_sym = try vm.intern("instance_methods");
    try vm.module_class.module.methods.put(instance_methods_sym, value.MethodEntry.builtin(&builtinModuleInstanceMethods, .{ .variadic = 0 }));

    const private_instance_methods_sym = try vm.intern("private_instance_methods");
    try vm.module_class.module.methods.put(private_instance_methods_sym, value.MethodEntry.builtin(&builtinModulePrivateInstanceMethods, .{ .variadic = 0 }));

    const protected_instance_methods_sym = try vm.intern("protected_instance_methods");
    try vm.module_class.module.methods.put(protected_instance_methods_sym, value.MethodEntry.builtin(&builtinModuleProtectedInstanceMethods, .{ .variadic = 0 }));

    const public_instance_methods_sym = try vm.intern("public_instance_methods");
    try vm.module_class.module.methods.put(public_instance_methods_sym, value.MethodEntry.builtin(&builtinModulePublicInstanceMethods, .{ .variadic = 0 }));

    const instance_method_sym = try vm.intern("instance_method");
    try vm.module_class.module.methods.put(instance_method_sym, MethodEntry.builtin(&builtinModuleInstanceMethod, .{ .exact = 1 }));

    const method_defined_sym = try vm.intern("method_defined?");
    try vm.module_class.module.methods.put(method_defined_sym, value.MethodEntry.builtin(&builtinModuleMethodDefined, .{ .variadic = 0 }));

    const private_method_defined_sym = try vm.intern("private_method_defined?");
    try vm.module_class.module.methods.put(private_method_defined_sym, value.MethodEntry.builtin(&builtinModulePrivateMethodDefined, .{ .variadic = 0 }));

    const protected_method_defined_sym = try vm.intern("protected_method_defined?");
    try vm.module_class.module.methods.put(protected_method_defined_sym, value.MethodEntry.builtin(&builtinModuleProtectedMethodDefined, .{ .variadic = 0 }));

    const public_method_defined_sym = try vm.intern("public_method_defined?");
    try vm.module_class.module.methods.put(public_method_defined_sym, value.MethodEntry.builtin(&builtinModulePublicMethodDefined, .{ .variadic = 0 }));

    const name_sym = try vm.intern("name");
    try vm.module_class.module.methods.put(name_sym, value.MethodEntry.builtin(&builtinModuleName, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.module_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinModuleToS, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.module_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinModuleToS, .{ .exact = 0 }));

    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.module_class.module.methods.put(initialize_copy_sym, value.MethodEntry.builtinWithVisibility(&builtinModuleInitializeCopy, .{ .exact = 1 }, .private));
}

pub fn builtinModuleCaseEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const receiver_module = try receiverModuleForComparison(vm, receiver);
    return Value.boolean(classLookupChainContains(vm.getClass(args[0]), receiver_module));
}

pub fn builtinModuleInitializeCopy(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    const other = args[0];
    if (receiver.objectId() == other.objectId()) return receiver;
    try vm.guardNotFrozen(receiver);
    if (vm.getClass(receiver) != vm.getClass(other)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "initialize_copy should take same class object", .{});
    }

    if (receiver.isClass()) {
        if (!other.isClass()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "initialize_copy should take same class object", .{});
        }
        const receiver_class = receiver.toClassObject();
        const other_class = other.toClassObject();
        receiver_class.superclass = other_class.superclass;
        receiver_class.module.super = other_class.module.super;
        receiver_class.object_type = other_class.object_type;
        receiver_class.struct_members = other_class.struct_members;
        receiver_class.struct_keyword_init = other_class.struct_keyword_init;
        try vm.copyModuleMetadata(&other_class.module, &receiver_class.module, false);
        try vm.copySingletonClassMetadataWithFreeze(other, receiver, false);
        return receiver;
    }

    if (receiver.isModule()) {
        if (!other.isModule()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "initialize_copy should take same class object", .{});
        }
        try vm.copyModuleMetadata(other.toModuleObject(), receiver.toModuleObject(), false);
        try vm.copySingletonClassMetadataWithFreeze(other, receiver, false);
        return receiver;
    }

    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
}

pub fn builtinModuleGreaterThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return switch (try compareModules(vm, receiver, args[0])) {
        .receiver_ancestor => Value.boolean(true),
        .equal, .receiver_descendant => Value.boolean(false),
        .unrelated => Value.nil(),
    };
}

pub fn builtinModuleGreaterThanEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return switch (try compareModules(vm, receiver, args[0])) {
        .equal, .receiver_ancestor => Value.boolean(true),
        .receiver_descendant => Value.boolean(false),
        .unrelated => Value.nil(),
    };
}

pub fn builtinModuleLessThan(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return switch (try compareModules(vm, receiver, args[0])) {
        .receiver_descendant => Value.boolean(true),
        .equal, .receiver_ancestor => Value.boolean(false),
        .unrelated => Value.nil(),
    };
}

pub fn builtinModuleLessThanEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return switch (try compareModules(vm, receiver, args[0])) {
        .equal, .receiver_descendant => Value.boolean(true),
        .receiver_ancestor => Value.boolean(false),
        .unrelated => Value.nil(),
    };
}

pub fn builtinModuleConstants(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);

    const include_inherited = if (args.len == 1) args[0].isTruthy() else true;

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
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    }

    method_reflection.sortSymbolsByName(constant_names.items);

    const out = try vm.createArray();
    for (constant_names.items) |name_sym| {
        out.elements.append(vm.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
    }

    return Value.fromObject(&out.object);
}

pub fn builtinModuleClassVariables(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_inherited = if (args.len == 1) args[0].isTruthy() else true;

    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);

    var seen: std.AutoHashMap(*SymbolObject, void) = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer seen.deinit();

    if (receiver.isModule()) {
        var it = receiver.toModuleObject().class_variables.iterator();
        while (it.next()) |entry| {
            try appendConstantSymbolUnique(vm, &names, &seen, entry.key_ptr.*);
        }
    } else if (receiver.isClass()) {
        var current: ?*ClassObject = receiver.toClassObject();
        while (current) |klass| {
            var it = klass.module.class_variables.iterator();
            while (it.next()) |entry| {
                try appendConstantSymbolUnique(vm, &names, &seen, entry.key_ptr.*);
            }
            if (!include_inherited) break;
            current = klass.superclass;
        }
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    }

    method_reflection.sortSymbolsByName(names.items);

    const out = try vm.createArray();
    for (names.items) |name_sym| {
        out.elements.append(vm.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
    }

    return Value.fromObject(&out.object);
}

pub fn builtinModuleConstDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const inherit = if (args.len == 2) args[1].isTruthy() else true;
    const name = try constantNameString(vm, args[0]);

    if (std.mem.indexOf(u8, name, "::") != null) {
        return Value.boolean(try constantPathDefined(vm, receiver, name, inherit));
    }

    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    return Value.boolean(
        lookupConstantOnReceiver(vm, receiver, name_sym, inherit) != null or
            lookupAutoloadOnReceiver(vm, receiver, name_sym, inherit) != null,
    );
}

pub fn builtinModuleConstSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const constants = constantsTable(receiver) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    if (constants.getPtr(name_sym)) |entry| {
        entry.value = args[1];
    } else {
        constants.put(name_sym, .{ .value = args[1] }) catch return error.Fatal;
    }
    if (autoloadTable(receiver)) |table| {
        _ = table.remove(name_sym);
    }
    return args[1];
}

pub fn builtinModuleAutoload(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    try vm.resetLoadedFilesFromGlobal();

    try vm.guardNotFrozen(receiver);

    _ = constantsTable(receiver) orelse {
        unreachable; // receiver is not a Module
    };

    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const path = try vm.coerceToPath(args[1], "no implicit conversion into String");
    if (path.len == 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "empty file name", .{});
    }

    if (try vm.searchLoadPath(path)) |resolved| {
        defer vm.allocator.free(resolved);
        if (vm.loaded_files.contains(resolved)) {
            return Value.nil();
        }
    }

    const name_sym = try vm.intern(name);
    try vm.registerAutoload(moduleFromValue(receiver).?, name_sym, path);
    return Value.nil();
}

pub fn builtinModuleAutoloadQ(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);

    const inherit = if (args.len == 2) args[1].isTruthy() else true;
    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    const path = lookupAutoloadOnReceiver(vm, receiver, name_sym, inherit) orelse return Value.nil();
    return try vm.newString(path, false);
}

pub fn builtinModuleRemoveConst(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const constants = constantsTable(receiver) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    const name = try constantNameString(vm, args[0]);
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    if (autoloadTable(receiver)) |table| {
        if (table.fetchRemove(name_sym) != null) {
            try warnDeprecatedConstant(vm, receiver, name_sym);
            _ = constants.remove(name_sym);
            return Value.nil();
        }
    }
    const removed = constants.fetchRemove(name_sym) orelse {
        return vm.raiseExceptionFmt(vm.name_error_class, "constant {s}::{s} not defined", .{ storedModuleName(receiver), name });
    };
    try warnDeprecatedConstant(vm, receiver, name_sym);
    return removed.value.value;
}

pub fn builtinModuleAncestors(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);

    const out = try vm.createArray();

    if (receiver.isModule() or receiver.isClass()) {
        const start = receiver.getModuleObject().?;
        if (start.origin != start) {
            var current = start.super;
            while (current) |node| : (current = node.super) {
                if (node.is_origin_iclass) break;
                if (!ancestry.isVisibleAncestor(node)) continue;
                out.elements.append(vm.gc_allocator, ancestry.visibleValue(node)) catch return error.Fatal;
            }
        }
        out.elements.append(vm.gc_allocator, ancestry.visibleValue(start)) catch return error.Fatal;
        var current = if (start.origin == start) start.super else start.origin.super;
        while (current) |node| : (current = node.super) {
            if (!ancestry.isVisibleAncestor(node)) continue;
            out.elements.append(vm.gc_allocator, ancestry.visibleValue(node)) catch return error.Fatal;
        }
    } else {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    }

    return Value.fromObject(&out.object);
}

pub fn builtinModuleInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].isTruthy() else true;
    return collectInstanceMethods(vm, receiver, .public_and_protected, include_super);
}

pub fn builtinModulePrivateInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].isTruthy() else true;
    return collectInstanceMethods(vm, receiver, .private_only, include_super);
}

pub fn builtinModuleProtectedInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].isTruthy() else true;
    return collectInstanceMethods(vm, receiver, .protected_only, include_super);
}

pub fn builtinModulePublicInstanceMethods(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    const include_super = if (args.len == 1) args[0].isTruthy() else true;
    return collectInstanceMethods(vm, receiver, .public_only, include_super);
}

pub fn builtinModuleMethodDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const include_super = if (args.len == 2) args[1].isTruthy() else true;
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);
    return Value.boolean(methodDefined(vm, receiver, name_sym, .public_and_protected, include_super));
}

pub fn builtinModulePrivateMethodDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const include_super = if (args.len == 2) args[1].isTruthy() else true;
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);
    return Value.boolean(methodDefined(vm, receiver, name_sym, .private_only, include_super));
}

pub fn builtinModuleProtectedMethodDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const include_super = if (args.len == 2) args[1].isTruthy() else true;
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);
    return Value.boolean(methodDefined(vm, receiver, name_sym, .protected_only, include_super));
}

pub fn builtinModulePublicMethodDefined(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const include_super = if (args.len == 2) args[1].isTruthy() else true;
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);
    return Value.boolean(methodDefined(vm, receiver, name_sym, .public_only, include_super));
}

pub fn builtinModuleInstanceMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const name_sym = try vm.coerceToMethodNameSymbol(args[0]);

    return switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
        .found => |lookup| unbound_method.createUnboundMethodObject(vm, name_sym, lookup.resolved, lookup.owner),
        .undefined, .not_found => {
            return vm.raiseNameErrorFmt(name_sym, "undefined method '{s}'", .{name_sym.name});
        },
    };
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

    return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
}

pub fn builtinModuleAppendFeatures(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const receiver_module = receiver.getModuleObject() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    if (!args[0].isClass() and !args[0].isModule()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Module)", .{vm.className(args[0])});
    }
    const target = args[0].getModuleObject() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    vm.includeModule(target, receiver_module) catch return error.Fatal;
    return receiver;
}

pub fn builtinModuleInherited(_: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    _ = args;
    return Value.nil();
}

pub fn builtinModuleIncluded(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!args[0].isClass() and !args[0].isModule()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Module)", .{vm.className(args[0])});
    }
    return Value.nil();
}

pub fn builtinModuleExtendObject(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!receiver.isModule()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    }

    const singleton_class = try vm.getOrCreateSingletonClass(args[0]);
    if ((singleton_class.module.object.flags & value.Object.FROZEN_FLAG) != 0) {
        return vm.raiseExceptionFmt(vm.frozen_error_class, "can't modify frozen {s}", .{vm.className(args[0])});
    }

    try vm.includeModule(&singleton_class.module, receiver.toModuleObject());
    vm.markIntegerChangedForReceiver(args[0]);
    return args[0];
}

pub fn builtinModuleExtended(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    return Value.nil();
}

pub fn builtinModuleInclude(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);
    _ = receiver.getModuleObject() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    var i = args.len;
    while (i > 0) {
        i -= 1;
        if (!args[i].isClass() and !args[i].isModule()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Module)", .{vm.className(args[i])});
        }
        var hook_args = [_]Value{receiver};
        _ = try vm.callMethodByName(args[i], "append_features", hook_args[0..], null);
        _ = try vm.callMethodByName(args[i], "included", hook_args[0..], null);
    }

    return receiver;
}

pub fn builtinModulePrepend(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireSingleArg(args, .module, "Module");
    const target = receiver.getModuleObject() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    const module = args[0].toModuleObject();

    vm.prependModule(target, module) catch return error.Fatal;

    return receiver;
}

pub fn builtinModuleDefineMethod(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const name_str = try vm.coerceToMethodNameString(args[0]);
    const name_sym = try vm.intern(name_str);
    const visibility = currentDefaultVisibility(vm);

    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    const module_function_mode = if (vm.current_lexical_scope) |scope| scope.module_function_mode else false;
    const effective_visibility: MethodVisibility = if (module_function_mode) .private else visibility;

    const entry: value.MethodEntry = if (args.len == 2) blk: {
        const body = args[1];
        const method_name = if (body.isMethodObject())
            body.toMethodObject().name
        else if (body.isUnboundMethodObject())
            body.toUnboundMethodObject().name
        else
            null;
        const method_owner = if (body.isMethodObject())
            body.toMethodObject().owner
        else if (body.isUnboundMethodObject())
            body.toUnboundMethodObject().owner
        else
            null;

        if (method_name == null or method_owner == null) {
            return vm.raiseExceptionFmt(vm.type_error_class, "wrong argument type {s} (expected Proc/Method/UnboundMethod)", .{vm.className(body)});
        }

        const method_entry = method_common.methodEntryForOwner(method_owner.?, method_name.?) orelse {
            return vm.raiseExceptionFmt(vm.name_error_class, "undefined method '{s}'", .{method_name.?.name});
        };
        var copied = method_entry;
        copied.visibility = effective_visibility;
        break :blk copied;
    } else blk: {
        const proc_val = try vm.newProc(try vm.requireBlock(block));
        break :blk .{
            .method = .{ .proc = proc_val.toProcObject() },
            .visibility = effective_visibility,
        };
    };
    methods.put(name_sym, entry) catch return error.Fatal;
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    if (module_function_mode and receiver.isModule()) {
        try copyMethodToModuleSingleton(vm, receiver, name_sym, entry);
    }

    try vm.triggerMethodAdded(receiver, name_sym);

    return Value.fromObject(&name_sym.object);
}

pub fn builtinModuleAttrReader(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
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
        try vm.triggerMethodAdded(receiver, method_sym);

        result_array.elements.append(vm.gc_allocator, Value.fromObject(&method_sym.object)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(&result_array.object);
}

pub fn builtinModuleAttrWriter(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
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
        try vm.triggerMethodAdded(receiver, method_sym);

        result_array.elements.append(vm.gc_allocator, Value.fromObject(&method_sym.object)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(&result_array.object);
}

pub fn builtinModuleAttrAccessor(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
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
        try vm.triggerMethodAdded(receiver, reader_sym);
        methods.put(writer_sym, .{
            .method = .{ .chunk = writer_chunk },
            .visibility = visibility,
        }) catch return error.Fatal;
        try vm.triggerMethodAdded(receiver, writer_sym);

        result_array.elements.append(vm.gc_allocator, Value.fromObject(&reader_sym.object)) catch return error.Fatal;
        result_array.elements.append(vm.gc_allocator, Value.fromObject(&writer_sym.object)) catch return error.Fatal;
    }
    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(&result_array.object);
}

pub fn builtinModuleAttr(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    const visibility = currentDefaultVisibility(vm);
    const result_array = try vm.createArray();

    var writable = false;
    var name_count = args.len;

    if (args.len > 0) {
        const last = args[args.len - 1];
        if (last.isBool()) {
            writable = last.isTrue();
            name_count = args.len - 1;
            if (writable) {
                const verbose = vm.globals.get("$VERBOSE") orelse Value.FALSE;
                if (verbose.isTruthy()) {
                    try warning_builtin.writeWarning(vm, "warning: boolean argument is obsoleted\n");
                }
            }
        }
    }

    for (args[0..name_count]) |arg| {
        const name_str = try vm.coerceToMethodNameString(arg);
        const reader_sym = try vm.intern(name_str);
        const reader_chunk = try vm.createAccessorChunk(name_str, .reader);
        methods.put(reader_sym, .{
            .method = .{ .chunk = reader_chunk },
            .visibility = visibility,
        }) catch return error.Fatal;
        try vm.triggerMethodAdded(receiver, reader_sym);
        result_array.elements.append(vm.gc_allocator, Value.fromObject(&reader_sym.object)) catch return error.Fatal;

        if (writable) {
            const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{name_str}) catch return error.Fatal;
            defer vm.program.allocator.free(writer_name);
            const writer_sym = try vm.intern(writer_name);
            const writer_chunk = try vm.createAccessorChunk(name_str, .writer);
            methods.put(writer_sym, .{
                .method = .{ .chunk = writer_chunk },
                .visibility = visibility,
            }) catch return error.Fatal;
            try vm.triggerMethodAdded(receiver, writer_sym);
            result_array.elements.append(vm.gc_allocator, Value.fromObject(&writer_sym.object)) catch return error.Fatal;
        }
    }

    vm.markIntegerChangedForReceiver(receiver);
    vm.bumpMethodStateVersion();

    return Value.fromObject(&result_array.object);
}

pub fn builtinModuleAliasMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);

    const new_name_str = try vm.coerceToMethodNameString(args[0]);
    const old_name_str = try vm.coerceToMethodNameString(args[1]);

    const new_name_sym = try vm.intern(new_name_str);
    const old_name_sym = try vm.intern(old_name_str);

    // Get method table from receiver (class or module)
    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    if (!receiver.isClass() and !receiver.isModule()) {
        unreachable;
    }

    switch (resolveInstanceMethodLookup(vm, receiver, old_name_sym)) {
        .found => |found| {
            methods.put(new_name_sym, found.resolved.entry) catch return error.Fatal;
            vm.markIntegerChangedForReceiver(receiver);
            vm.bumpMethodStateVersion();
        },
        else => {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{old_name_str},
            ) catch return error.Fatal;
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
        },
    }

    return Value.fromObject(&new_name_sym.object);
}

pub fn builtinModuleUndefMethod(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const methods = receiver.getModuleMethods() orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    if (args.len == 0) return receiver;

    var names: std.ArrayList(*SymbolObject) = .empty;
    defer names.deinit(vm.gc_allocator);
    for (args) |arg| {
        names.append(vm.gc_allocator, try vm.coerceToMethodNameSymbol(arg)) catch return error.Fatal;
    }

    try vm.guardNotFrozen(receiver);

    for (names.items) |name_sym| {
        const exists = switch (resolveInstanceMethodLookup(vm, receiver, name_sym)) {
            .found, .undefined => true,
            .not_found => false,
        };
        if (!exists) {
            const owner_kind = if (receiver.isClass()) "class" else "module";
            const owner_name = try moduleMethodErrorOwnerName(vm, receiver);
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}' for {s} '{s}'",
                .{ name_sym.name, owner_kind, owner_name },
            ) catch return error.Fatal;
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
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
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };

    for (args) |arg| {
        const name_sym = try vm.coerceToMethodNameSymbol(arg);
        _ = getOwnDefinedMethodEntry(methods, name_sym) orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
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
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
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
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
        }

        if (constants.getPtr(name_sym)) |entry| {
            entry.flags.visibility = if (private) .private else .public;
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

pub fn builtinModuleDeprecateConstant(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireMinArgCount(args, 1);

    const constants = constantsTable(receiver) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
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
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
        }
        if (constants.getPtr(name_sym)) |entry| {
            entry.flags.deprecated = true;
        }
    }

    return receiver;
}

pub fn builtinModuleConstGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const inherit = if (args.len == 2) args[1].isTruthy() else true;
    const name = try constantNameString(vm, args[0]);

    if (std.mem.indexOf(u8, name, "::") != null) {
        return getConstantPath(vm, receiver, name, inherit);
    }
    if (!isValidConstantNameSegment(name)) {
        return vm.raiseExceptionFmt(vm.name_error_class, "wrong constant name {s}", .{name});
    }

    const name_sym = try vm.intern(name);
    const constant_value = lookupConstantOnReceiver(vm, receiver, name_sym, inherit) orelse {
        return vm.raiseExceptionFmt(vm.name_error_class, "uninitialized constant {s}::{s}", .{ storedModuleName(receiver), name });
    };
    try warnDeprecatedConstant(vm, receiver, name_sym);
    return constant_value;
}

pub fn builtinModuleNesting(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const out = try vm.createArray();
    var scope = vm.current_lexical_scope;
    while (scope) |current| {
        const scope_value = switch (current.scope_module) {
            .module => |module_obj| Value.fromObject(&module_obj.object),
            .class => |class_obj| Value.fromObject(&class_obj.module.object),
        };
        out.elements.append(vm.gc_allocator, scope_value) catch return error.Fatal;
        scope = current.parent;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinModuleEval(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (block) |blk| {
        try vm.requireArgCount(args, 0);
        const proc_obj = (try vm.newProc(blk)).toProcObject();
        const chunk_blk = switch (proc_obj.block.kind) {
            .chunk => |cb| cb,
            else => unreachable,
        };
        const lexical_scope = try vm.createLexicalScope(receiver, vm.current_lexical_scope);
        const saved_scope = chunk_blk.chunk.lexical_scope;
        chunk_blk.chunk.lexical_scope = lexical_scope;
        defer chunk_blk.chunk.lexical_scope = saved_scope;
        var block_args = [_]Value{receiver};
        return vm.callProcObject(proc_obj, block_args[0..], null, receiver, receiver);
    }

    try vm.requireArgCountRange(args, 1, 3);
    const source_value = try coerceEvalSourceValue(vm, args[0]);
    const lexical_scope = try vm.createLexicalScope(receiver, vm.current_lexical_scope);
    return vm.evalSourceWithEncodingAndContext(
        source_value.toStringObject().str,
        try evalFilename(vm, if (args.len >= 2) args[1] else null),
        source_value.toStringObject().encoding,
        .{
            .self_value = receiver,
            .parent_ep = if (vm.currentRubyCallerFrame()) |frame| frame.ep else null,
            .lexical_scope = lexical_scope,
            .line_offset = try evalLineOffset(vm, if (args.len >= 3) args[2] else null),
        },
    );
}

pub fn builtinModuleExec(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    const blk = try vm.requireBlock(block);
    const proc_obj = (try vm.newProc(blk)).toProcObject();
    return vm.callProcObject(proc_obj, args, null, receiver, receiver);
}

pub fn builtinModuleClassVariableGet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const receiver_module = moduleFromValue(receiver) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    const name = try classVariableNameString(vm, args[0]);
    const name_sym = try vm.intern(name);
    return vm.lookupClassVariable(receiver_module, if (receiver.isClass()) receiver.toClassObject() else null, name_sym) orelse
        vm.raiseExceptionFmt(vm.name_error_class, "uninitialized class variable {s} in {s}", .{ name, storedModuleName(receiver) });
}

pub fn builtinModuleClassVariableSet(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const receiver_module = moduleFromValue(receiver) orelse {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Module", .{});
    };
    const name = try classVariableNameString(vm, args[0]);
    const name_sym = try vm.intern(name);
    receiver_module.class_variables.put(name_sym, args[1]) catch return error.Fatal;
    return args[1];
}

pub fn builtinModuleFunction(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    if (receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "module_function must be called for modules", .{});
    }

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
        const existing = moduleFunctionLookup(vm, receiver, name_sym) orelse {
            const msg = std.fmt.allocPrint(
                vm.gc_allocator,
                "undefined method '{s}'",
                .{name_sym.name},
            ) catch return error.Fatal;
            return vm.raiseExceptionFmt(vm.name_error_class, "{s}", .{msg});
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
    return Value.fromObject(&arr.object);
}
