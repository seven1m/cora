const std = @import("std");
const ancestry = @import("../ancestry.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = value.Value;
const SymbolObject = value.SymbolObject;
const ClassObject = value.ClassObject;

pub const MethodListFilter = enum {
    public_and_protected,
    private_only,
    protected_only,
    public_only,
};

pub fn methodMatchesFilter(entry: value.MethodEntry, filter: MethodListFilter) bool {
    if (entry.method == .undefined) return false;
    return switch (filter) {
        .public_and_protected => entry.visibility == .public or entry.visibility == .protected,
        .private_only => entry.visibility == .private,
        .protected_only => entry.visibility == .protected,
        .public_only => entry.visibility == .public,
    };
}

pub fn collectMethodsFromTable(
    vm: *VM,
    methods: *std.AutoHashMap(*SymbolObject, value.MethodEntry),
    filter: MethodListFilter,
    out: *std.ArrayList(*SymbolObject),
    seen: *std.AutoHashMap(*SymbolObject, usize),
    blocked: *std.AutoHashMap(*SymbolObject, void),
) VMError!void {
    var it = methods.iterator();
    while (it.next()) |bucket| {
        const name_sym = bucket.key_ptr.*;
        const entry = bucket.value_ptr.*;

        if (entry.method == .undefined) {
            blocked.put(name_sym, {}) catch return error.Fatal;
            if (seen.get(name_sym)) |idx| {
                _ = out.swapRemove(idx);
                _ = seen.remove(name_sym);
                if (idx < out.items.len) {
                    const swapped = out.items[idx];
                    seen.put(swapped, idx) catch return error.Fatal;
                }
            }
            continue;
        }

        if (blocked.contains(name_sym)) continue;
        if (!methodMatchesFilter(entry, filter)) continue;
        if (seen.contains(name_sym)) continue;

        out.append(vm.gc_allocator, name_sym) catch return error.Fatal;
        seen.put(name_sym, out.items.len - 1) catch return error.Fatal;
    }
}

pub fn collectModuleAncestryMethods(
    vm: *VM,
    module_obj: *value.ModuleObject,
    filter: MethodListFilter,
    include_mixin_ancestors: bool,
    out: *std.ArrayList(*SymbolObject),
    seen: *std.AutoHashMap(*SymbolObject, usize),
    blocked: *std.AutoHashMap(*SymbolObject, void),
) VMError!void {
    if (!include_mixin_ancestors) {
        return collectMethodsFromTable(vm, &module_obj.origin.methods, filter, out, seen, blocked);
    }

    var current: ?*value.ModuleObject = module_obj;
    while (current) |node| : (current = node.super) {
        try collectMethodsFromTable(vm, &node.methods, filter, out, seen, blocked);
    }
}

pub fn collectClassChainMethods(
    vm: *VM,
    start_class: *ClassObject,
    include_super: bool,
    filter: MethodListFilter,
    include_mixin_ancestors: bool,
    out: *std.ArrayList(*SymbolObject),
    seen: *std.AutoHashMap(*SymbolObject, usize),
    blocked: *std.AutoHashMap(*SymbolObject, void),
) VMError!void {
    if (!include_mixin_ancestors) {
        return collectMethodsFromTable(vm, &start_class.module.origin.methods, filter, out, seen, blocked);
    }

    var current: ?*value.ModuleObject = &start_class.module;
    while (current) |node| : (current = node.super) {
        try collectMethodsFromTable(vm, &node.methods, filter, out, seen, blocked);
        if (!include_super) {
            if (node != &start_class.module and node.object.type_tag == .class) break;
            if (node.object.type_tag == .class and ancestry.nextVisibleClass(node.super) != null) {
                break;
            }
        }
    }
}

pub fn sortSymbolsByName(symbols: []*SymbolObject) void {
    std.sort.pdq(*SymbolObject, symbols, {}, struct {
        fn lessThan(_: void, a: *SymbolObject, b: *SymbolObject) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);
}

pub fn sortedSymbolArray(vm: *VM, symbols: []*SymbolObject) VMError!Value {
    sortSymbolsByName(symbols);

    const out = try vm.createArray();
    for (symbols) |name_sym| {
        out.elements.append(vm.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}
