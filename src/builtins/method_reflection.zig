const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
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
    var current: ?*ClassObject = start_class;
    while (current) |klass| {
        if (include_mixin_ancestors) {
            var i = klass.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const prepended = klass.prepended_modules.items[i];
                try collectMethodsFromTable(vm, &prepended.methods, filter, out, seen, blocked);
            }
        }

        try collectMethodsFromTable(vm, &klass.module.methods, filter, out, seen, blocked);

        if (include_mixin_ancestors) {
            var j = klass.included_modules.items.len;
            while (j > 0) {
                j -= 1;
                const included = klass.included_modules.items[j];
                try collectMethodsFromTable(vm, &included.methods, filter, out, seen, blocked);
            }
        }

        if (!include_super) break;
        current = klass.superclass;
    }
}

pub fn sortSymbolsByName(symbols: []*SymbolObject) void {
    std.sort.pdq(*SymbolObject, symbols, {}, struct {
        fn lessThan(_: void, a: *SymbolObject, b: *SymbolObject) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);
}
