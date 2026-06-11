const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

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

    const members_sym = try vm.intern("members");
    try vm.data_class.module.methods.put(members_sym, value.MethodEntry.builtin(&builtinDataMembers, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.data_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinDataInspect, .{ .exact = 0 }));

    const to_h_sym = try vm.intern("to_h");
    try vm.data_class.module.methods.put(to_h_sym, value.MethodEntry.builtin(&builtinDataToH, .{ .exact = 0 }));

    const with_sym = try vm.intern("with");
    try vm.data_class.module.methods.put(with_sym, value.MethodEntry.builtin(&builtinDataWith, .{ .variadic = 0 }));

    const eq_sym = try vm.intern("==");
    try vm.data_class.module.methods.put(eq_sym, value.MethodEntry.builtin(&builtinDataEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.data_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinDataEqual, .{ .exact = 1 }));

    const hash_sym = try vm.intern("hash");
    try vm.data_class.module.methods.put(hash_sym, value.MethodEntry.builtin(&builtinDataHash, .{ .exact = 0 }));

    const deconstruct_sym = try vm.intern("deconstruct");
    try vm.data_class.module.methods.put(deconstruct_sym, value.MethodEntry.builtin(&builtinDataDeconstruct, .{ .exact = 0 }));

    const deconstruct_keys_sym = try vm.intern("deconstruct_keys");
    try vm.data_class.module.methods.put(deconstruct_keys_sym, value.MethodEntry.builtin(&builtinDataDeconstructKeys, .{ .exact = 1 }));
}

fn memberNames(vm: *VM, receiver: Value) VMError![]const []const u8 {
    const stored = try vm.getInstanceVariable(receiver, "@_data_members");
    if (stored.isArray()) {
        const arr = stored.toArrayObject();
        var names = vm.allocator.alloc([]const u8, arr.elements.items.len) catch return error.Fatal;
        for (arr.elements.items, 0..) |elem, i| {
            names[i] = elem.toStringObject().str;
        }
        return names;
    }
    return &[_][]const u8{};
}

fn memberValues(vm: *VM, receiver: Value, members: []const []const u8) VMError![]const Value {
    var vals = vm.allocator.alloc(Value, members.len) catch return error.Fatal;
    for (members, 0..) |name, i| {
        const ivar_name = std.fmt.allocPrint(vm.allocator, "@{s}", .{name}) catch return error.Fatal;
        defer vm.allocator.free(ivar_name);
        vals[i] = try vm.getInstanceVariable(receiver, ivar_name);
    }
    return vals;
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

    var members_vals = std.ArrayList(Value).empty;
    defer members_vals.deinit(vm.allocator);
    for (members_list.items) |name| {
        members_vals.append(vm.allocator, try vm.newString(name, false)) catch return error.Fatal;
    }
    const arr = try vm.createArray();
    arr.elements = members_vals;
    try vm.setInstanceVariable(Value.fromObject(&subclass.toClassObject().module.object), "@_data_members", Value.fromObject(&arr.object));

    return Value.fromObject(&subclass.toClassObject().module.object);
}

pub fn builtinDataInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    // Simple data initializer: pairs of (name, value) become ivars.
    var i: usize = 0;
    while (i + 1 < args.len) : (i += 2) {
        const name_val = args[i];
        const val = args[i + 1];
        const name = if (name_val.isSymbol()) name_val.toSymbolObject().name else try name_val.coerceToStr(vm, "invalid member name");
        const ivar_name = std.fmt.allocPrint(vm.allocator, "@{s}", .{name}) catch return error.Fatal;
        defer vm.allocator.free(ivar_name);
        try vm.setInstanceVariable(receiver, ivar_name, val);
    }
    return receiver;
}

pub fn builtinDataMembers(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const stored = try vm.getInstanceVariable(receiver, "@_data_members");
    return stored;
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
    // Clone and re-initialize with overrides
    const members = try memberNames(vm, receiver);
    const vals = try memberValues(vm, receiver, members);
    defer vm.allocator.free(vals);

    var new_args = std.ArrayList(Value).empty;
    defer new_args.deinit(vm.allocator);

    for (members, 0..) |name, i| {
        new_args.append(vm.allocator, try vm.newString(name, false)) catch return error.Fatal;
        new_args.append(vm.allocator, vals[i]) catch return error.Fatal;
    }

    // Apply keyword overrides from args
    var ki: usize = 0;
    while (ki + 1 < args.len) : (ki += 2) {
        const key = args[ki];
        if (key.isSymbol()) {
            const key_name = key.toSymbolObject().name;
            for (members, 0..) |m, mi| {
                if (std.mem.eql(u8, m, key_name)) {
                    new_args.items[mi * 2 + 1] = args[ki + 1];
                }
            }
        }
    }

    const instance = try vm.newObjectForClass(vm.getClass(receiver));
    _ = try vm.callMethodByNameForwardingKeywords(instance, "initialize", new_args.items, null);
    return instance;
}

pub fn builtinDataEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];

    if (vm.getClass(receiver) != vm.getClass(other)) return Value.boolean(false);

    const members = try memberNames(vm, receiver);
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
    const vals = try memberValues(vm, receiver, members);
    const arr = try vm.createArray();
    for (vals) |val| {
        arr.elements.append(vm.gc_allocator, val) catch return error.Fatal;
    }
    return Value.fromObject(&arr.object);
}

pub fn builtinDataDeconstructKeys(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    _ = args;
    const members = try memberNames(vm, receiver);
    const vals = try memberValues(vm, receiver, members);
    const hash_val = try vm.createHash();
    for (members, 0..) |name, i| {
        const sym = try vm.intern(name);
        try vm.hashSetEntry(hash_val, Value.fromObject(&sym.object), vals[i]);
    }
    return Value.fromObject(&hash_val.object);
}
