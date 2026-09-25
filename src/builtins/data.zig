const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const class_builtin = @import("class.zig");
const kernel_builtin = @import("kernel.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;

pub fn register(vm: *VM) !void {
    const data_class_val = Value.fromObject(&vm.data_class.module.object);
    const data_singleton = try vm.getOrCreateSingletonClass(data_class_val);

    const define_sym = try vm.intern("define");
    try data_singleton.module.methods.put(define_sym, value.MethodEntry.builtin(&builtinDataDefine, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.data_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinDataInitialize, .{ .variadic = 0 }, .private));
    const initialize_copy_sym = try vm.intern("initialize_copy");
    try vm.data_class.module.methods.put(initialize_copy_sym, value.MethodEntry.builtinWithVisibility(&builtinDataInitializeCopy, .{ .exact = 1 }, .private));

    const members_sym = try vm.intern("members");
    try vm.data_class.module.methods.put(members_sym, value.MethodEntry.builtin(&builtinDataMembers, .{ .exact = 0 }));

    const inspect_entry = value.MethodEntry.builtin(&builtinDataInspect, .{ .exact = 0 });
    const inspect_sym = try vm.intern("inspect");
    try vm.data_class.module.methods.put(inspect_sym, inspect_entry);
    const to_s_sym = try vm.intern("to_s");
    try vm.data_class.module.methods.put(to_s_sym, inspect_entry);

    const to_h_sym = try vm.intern("to_h");
    try vm.data_class.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinDataToH, .{ .exact = 0 }));

    const with_sym = try vm.intern("with");
    try vm.data_class.module.methods.put(with_sym, value.MethodEntry.keywordBuiltin(&builtinDataWith, .{ .variadic = 0 }));

    const eq_sym = try vm.intern("==");
    try vm.data_class.module.methods.put(eq_sym, value.MethodEntry.builtin(&builtinDataEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.data_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinDataEql, .{ .exact = 1 }));

    const hash_sym = try vm.intern("hash");
    try vm.data_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinDataHash, .{ .exact = 0 }));

    const deconstruct_sym = try vm.intern("deconstruct");
    try vm.data_class.module.methods.put(deconstruct_sym, value.MethodEntry.builtin(&builtinDataDeconstruct, .{ .exact = 0 }));

    const deconstruct_keys_sym = try vm.intern("deconstruct_keys");
    try vm.data_class.module.methods.put(deconstruct_keys_sym, value.MethodEntry.builtin(&builtinDataDeconstructKeys, .{ .exact = 1 }));
}

fn dataMembersForClass(class: *value.ClassObject) ?*value.ArrayObject {
    var current: ?*value.ClassObject = class;
    while (current) |data_class| {
        if (data_class.data_members) |members| return members;
        current = data_class.superclass;
    }
    return null;
}

fn memberNames(vm: *VM, receiver: Value) VMError![]const []const u8 {
    const stored = dataMembersForClass(vm.getClass(receiver)) orelse return &[_][]const u8{};
    const names = vm.allocator.alloc([]const u8, stored.elements.items.len) catch return error.Fatal;
    for (stored.elements.items, 0..) |elem, i| {
        names[i] = elem.toStringObject().str;
    }
    return names;
}

fn memberValues(vm: *VM, receiver: Value, members: []const []const u8) VMError![]Value {
    const vals = vm.allocator.alloc(Value, members.len) catch return error.Fatal;
    const stored = receiver.getObjectPointer().?.data_values;
    for (vals, 0..) |*val, i| {
        val.* = if (stored) |array| (if (i < array.elements.items.len) array.elements.items[i] else Value.nil()) else Value.nil();
    }
    return vals;
}

fn builtinDataReader(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const called_name = vm.currentFrame().method_name orelse return error.Fatal;
    const called_symbol = try vm.intern(called_name);
    const resolved = try vm.findMethod(receiver, called_symbol) orelse return error.Fatal;
    const name = (resolved.entry.original_name orelse called_symbol).name;
    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const index = memberIndex(members, name) orelse return error.Fatal;
    const stored = receiver.getObjectPointer().?.data_values orelse return Value.nil();
    if (index >= stored.elements.items.len) return Value.nil();
    return stored.elements.items[index];
}

pub fn builtinDataDefine(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = receiver;
    _ = block;

    var members_list: std.ArrayList([]const u8) = .empty;
    defer members_list.deinit(vm.allocator);
    for (args) |arg| {
        const sym_val = try vm.callMethodByName(arg, "to_sym", &[_]Value{}, null);
        members_list.append(vm.allocator, sym_val.toSymbolObject().name) catch return error.Fatal;
    }

    const subclass = try vm.newClass(try vm.intern("Data"), vm.data_class);

    const arr = try vm.createArray();
    const subclass_value = Value.fromObject(&subclass.toClassObject().module.object);
    for (members_list.items) |name| {
        arr.elements.append(vm.gc_allocator, try vm.newString(name, false)) catch return error.Fatal;
        const member_sym = try vm.intern(name);
        subclass.toClassObject().module.methods.put(member_sym, value.MethodEntry.builtin(&builtinDataReader, .{ .exact = 0 })) catch return error.Fatal;
        try vm.triggerMethodAdded(subclass_value, member_sym);
    }
    subclass.toClassObject().data_members = arr;

    const subclass_singleton = try vm.getOrCreateSingletonClass(subclass_value);
    const class_members_sym = try vm.intern("members");
    subclass_singleton.module.methods.put(class_members_sym, value.MethodEntry.builtin(&builtinDataClassMembers, .{ .exact = 0 })) catch return error.Fatal;
    const new_sym = try vm.intern("new");
    const constructor = value.MethodEntry.keywordBuiltin(&builtinDataNew, .{ .variadic = 0 });
    subclass_singleton.module.methods.put(new_sym, constructor) catch return error.Fatal;
    const bracket_sym = try vm.intern("[]");
    subclass_singleton.module.methods.put(bracket_sym, constructor) catch return error.Fatal;

    return subclass_value;
}

fn builtinDataNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (vm.keywordArgsGiven()) {
        try vm.requireArgCount(args, 0);
        return class_builtin.builtinClassNew(vm, receiver, args, block);
    }

    const instance = try vm.newObjectForClass(receiver.toClassObject());
    const members = try memberNames(vm, instance);
    defer vm.allocator.free(members);
    try vm.requireArgCountRange(args, 0, members.len);

    const keys = vm.allocator.alloc(Value, args.len) catch return error.Fatal;
    defer vm.allocator.free(keys);
    for (members[0..args.len], 0..) |name, i| {
        const symbol = try vm.intern(name);
        keys[i] = Value.fromObject(&symbol.object);
    }
    _ = try vm.callMethodByNameWithKeywords(instance, "initialize", &.{}, keys, args, block);
    return instance;
}

pub fn builtinDataInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.guardNotFrozen(receiver);
    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const values = try vm.createArray();

    if (args.len > 0) {
        try vm.requireArgCount(args, members.len);
        for (args) |val| {
            values.elements.append(vm.gc_allocator, val) catch return error.Fatal;
        }
        try vm.validateKeywordArgsConsumed();
    } else {
        for (members) |name| {
            const val = (try vm.consumeKeywordArg(name)) orelse
                return vm.raiseExceptionFmt(vm.argument_error_class, "missing keyword: :{s}", .{name});
            values.elements.append(vm.gc_allocator, val) catch return error.Fatal;
        }
        try vm.validateKeywordArgsConsumed();
    }

    if (members.len == 0) {
        try vm.requireArgCount(args, 0);
        try vm.validateKeywordArgsConsumed();
    }

    receiver.getObjectPointer().?.data_values = values;
    var frozen = receiver;
    frozen.freeze();
    return receiver;
}

fn builtinDataInitializeCopy(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = try kernel_builtin.builtinKernelInitializeCopy(vm, receiver, args, block);
    if (receiver.raw != args[0].raw) {
        receiver.getObjectPointer().?.data_values = args[0].getObjectPointer().?.data_values;
        var frozen = receiver;
        frozen.freeze();
    }
    return receiver;
}

pub fn builtinDataMembers(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);

    const out = try vm.createArray();
    for (members) |name| {
        const sym = try vm.intern(name);
        out.elements.append(vm.gc_allocator, Value.fromObject(&sym.object)) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinDataClassMembers(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const class = if (receiver.isClass()) receiver.toClassObject() else vm.getClass(receiver);
    const out = try vm.createArray();
    if (dataMembersForClass(class)) |stored| {
        for (stored.elements.items) |elem| {
            const sym = try vm.intern(elem.toStringObject().str);
            out.elements.append(vm.gc_allocator, Value.fromObject(&sym.object)) catch return error.Fatal;
        }
    }
    return Value.fromObject(&out.object);
}

pub fn builtinDataToH(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try memberNames(vm, receiver);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    const hash_val = try vm.createHash();
    for (members, 0..) |name, i| {
        const sym = try vm.intern(name);
        try vm.hashSetEntry(hash_val, Value.fromObject(&sym.object), vals[i]);
    }
    return Value.fromObject(&hash_val.object);
}

pub fn builtinDataInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try memberNames(vm, receiver);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(vm.allocator);
    buf.appendSlice(vm.allocator, "#<data ") catch return error.Fatal;

    const class_name = vm.className(receiver);
    buf.appendSlice(vm.allocator, class_name) catch return error.Fatal;

    for (members, 0..) |name, i| {
        if (i == 0) {
            buf.appendSlice(vm.allocator, " ") catch return error.Fatal;
        } else {
            buf.appendSlice(vm.allocator, ", ") catch return error.Fatal;
        }
        buf.appendSlice(vm.allocator, name) catch return error.Fatal;
        buf.appendSlice(vm.allocator, "=") catch return error.Fatal;
        const inspected = try vals[i].inspect(vm);
        buf.appendSlice(vm.allocator, inspected.toStringObject().str) catch return error.Fatal;
    }
    buf.appendSlice(vm.allocator, ">") catch return error.Fatal;
    return vm.newString(buf.items, false);
}

pub fn builtinDataWith(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!vm.keywordArgsGiven()) return receiver;

    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    const keys = vm.allocator.alloc(Value, members.len) catch return error.Fatal;
    defer vm.allocator.free(keys);
    for (members, 0..) |name, i| {
        const symbol = try vm.intern(name);
        keys[i] = Value.fromObject(&symbol.object);
        if (try vm.consumeKeywordArg(name)) |override| vals[i] = override;
    }
    try vm.validateKeywordArgsConsumed();

    const instance = try vm.newObjectForClass(vm.getClass(receiver));
    _ = try vm.callMethodByNameWithKeywords(instance, "initialize", &.{}, keys, vals, null);
    return instance;
}

pub fn builtinDataEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];

    if (vm.getClass(receiver) != vm.getClass(other)) return Value.boolean(false);
    if (receiver.raw == other.raw) return Value.boolean(true);

    if (try vm.enterRecursionGuard(.data_equal, receiver, other)) return Value.boolean(true);
    defer vm.leaveRecursionGuard(.data_equal, receiver, other);

    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const self_vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(self_vals);
    const other_vals = try memberValues(vm, other, members);
    defer vm.allocator.free(other_vals);

    for (members, 0..) |_, i| {
        var eq_args = [_]Value{other_vals[i]};
        const eq_result = try vm.callMethodByName(self_vals[i], "==", &eq_args, null);
        if (!eq_result.isTruthy()) return Value.boolean(false);
    }
    return Value.boolean(true);
}

pub fn builtinDataEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];

    if (vm.getClass(receiver) != vm.getClass(other)) return Value.boolean(false);
    if (receiver.raw == other.raw) return Value.boolean(true);

    if (try vm.enterRecursionGuard(.data_eql, receiver, other)) return Value.boolean(true);
    defer vm.leaveRecursionGuard(.data_eql, receiver, other);

    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const self_vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(self_vals);
    const other_vals = try memberValues(vm, other, members);
    defer vm.allocator.free(other_vals);

    for (members, 0..) |_, i| {
        if (!try vm.hashKeysEqual(self_vals[i], other_vals[i])) return Value.boolean(false);
    }
    return Value.boolean(true);
}

pub fn builtinDataHash(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try memberNames(vm, receiver);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    var h: u64 = @intFromPtr(vm.getClass(receiver));
    for (vals) |val| {
        const hash_val = try vm.callMethodByName(val, "hash", &[_]Value{}, null);
        h ^= @bitCast(hash_val.toInteger());
    }
    return Value.integer(@intCast(@as(i64, @bitCast(h))));
}

pub fn builtinDataDeconstruct(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);
    const arr = try vm.createArray();
    for (vals) |val| {
        arr.elements.append(vm.gc_allocator, val) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

fn memberIndex(members: []const []const u8, name: []const u8) ?usize {
    for (members, 0..) |member, i| {
        if (std.mem.eql(u8, member, name)) return i;
    }
    return null;
}

pub fn builtinDataDeconstructKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const members = try memberNames(vm, receiver);
    defer vm.allocator.free(members);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    const result = try vm.createHash();
    const result_val = Value.fromObject(&result.object);

    if (args[0].isNil()) {
        for (members, 0..) |name, i| {
            const sym = try vm.intern(name);
            try vm.hashSetEntry(result, Value.fromObject(&sym.object), vals[i]);
        }
        return result_val;
    }

    if (!args[0].isArray()) {
        return vm.raiseExceptionFmt(
            vm.type_error_class,
            "wrong argument type {s} (expected Array or nil)",
            .{vm.className(args[0])},
        );
    }
    const keys = args[0].toArrayObject().elements.items;

    if (keys.len > members.len) return result_val;

    for (keys) |key| {
        if (key.isSymbol()) {
            const idx = memberIndex(members, key.toSymbolObject().name) orelse return result_val;
            try vm.hashSetEntry(result, key, vals[idx]);
        } else if (key.isString()) {
            const idx = memberIndex(members, key.toStringObject().str) orelse return result_val;
            try vm.hashSetEntry(result, key, vals[idx]);
        } else {
            switch (try vm.probeToStringValue(key)) {
                .string => |coerced| {
                    const idx = memberIndex(members, coerced.toStringObject().str) orelse return result_val;
                    try vm.hashSetEntry(result, coerced, vals[idx]);
                },
                .missing, .nil_result => {
                    const inspected = try key.inspect(vm);
                    return vm.raiseExceptionFmt(
                        vm.type_error_class,
                        "{s} is not a symbol nor a string",
                        .{inspected.toStringObject().str},
                    );
                },
            }
        }
    }

    return result_val;
}
