const std = @import("std");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const class_builtin = @import("class.zig");
const module_builtin = @import("module.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;
const SymbolObject = value.SymbolObject;

fn getStructMembersForClass(vm: *VM, class_obj: *ClassObject) VMError!*value.ArrayObject {
    var current: ?*ClassObject = class_obj;
    while (current) |klass| {
        if (klass.struct_members) |members| return members;
        current = klass.superclass;
    }
    return vm.raiseExceptionFmt(vm.type_error_class, "uninitialized struct", .{});
}

fn getStructMembersForReceiver(vm: *VM, receiver: Value) VMError!*value.ArrayObject {
    return getStructMembersForClass(vm, vm.getClass(receiver));
}

fn structKeywordInitForClass(class_obj: *ClassObject) ?bool {
    var current: ?*ClassObject = class_obj;
    while (current) |klass| {
        if (klass.struct_members != null) return klass.struct_keyword_init;
        current = klass.superclass;
    }
    return null;
}

fn duplicateMembersArray(vm: *VM, members: *value.ArrayObject) VMError!Value {
    const out = try vm.createArray();
    for (members.elements.items) |member| {
        out.elements.append(vm.gc_allocator, member) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

fn structSize(vm: *VM, receiver: Value) VMError!usize {
    return (try getStructMembersForReceiver(vm, receiver)).elements.items.len;
}

fn structIndexForMemberName(vm: *VM, members: *value.ArrayObject, name: []const u8) VMError!?usize {
    const name_sym = try vm.intern(name);
    for (members.elements.items, 0..) |member, idx| {
        if (member.toSymbolObject() == name_sym) return idx;
    }
    return null;
}

fn resolveStructIndex(vm: *VM, members: *value.ArrayObject, key: Value) VMError!usize {
    if (key.isInteger()) {
        const len: i64 = @intCast(members.elements.items.len);
        var index = key.toInteger();
        if (index < 0) index += len;
        if (index < 0 or index >= len) {
            return vm.raiseExceptionFmt(vm.index_error_class, "offset {d} outside of struct", .{key.toInteger()});
        }
        return @intCast(index);
    }

    const name = try vm.coerceToMethodNameString(key);
    return (try structIndexForMemberName(vm, members, name)) orelse
        return vm.raiseExceptionFmt(vm.name_error_class, "no member '{s}' in struct", .{name});
}

fn structMemberReaderValue(vm: *VM, receiver: Value, member: *SymbolObject) VMError!Value {
    return vm.callMethodByName(receiver, member.name, &.{}, null);
}

fn structMemberWriter(vm: *VM, receiver: Value, member: *SymbolObject, arg: Value) VMError!Value {
    const writer_name = std.fmt.allocPrint(vm.program.allocator, "{s}=", .{member.name}) catch return error.Fatal;
    defer vm.program.allocator.free(writer_name);
    var call_args = [_]Value{arg};
    return vm.callMethodByName(receiver, writer_name, call_args[0..], null);
}

fn defineStructSubclassSingletonMethods(vm: *VM, class_value: Value) VMError!void {
    const singleton = try vm.getOrCreateSingletonClass(class_value);
    const new_sym = try vm.intern("new");
    singleton.module.methods.put(new_sym, .{ .method = .{ .builtin = .{ .function = &class_builtin.builtinClassNew, .arity = .{ .variadic = 0 } } } }) catch return error.Fatal;

    const bracket_sym = try vm.intern("[]");
    singleton.module.methods.put(bracket_sym, .{ .method = .{ .builtin = .{ .function = &builtinStructSubclassSquareBrackets, .arity = .{ .variadic = 0 } } } }) catch return error.Fatal;

    const members_sym = try vm.intern("members");
    singleton.module.methods.put(members_sym, .{ .method = .{ .builtin = .{ .function = &builtinStructClassMembers, .arity = .{ .exact = 0 } } } }) catch return error.Fatal;
}

fn runStructSubclassBody(vm: *VM, struct_val: Value, block: Block) VMError!void {
    _ = switch (block.kind) {
        .chunk => |chunk_blk| chunk_blk_result: {
            chunk_blk.chunk.lexical_scope = try vm.createLexicalScope(struct_val, vm.current_lexical_scope);

            const class_body_block = Block{
                .kind = .{ .chunk = .{
                    .chunk = chunk_blk.chunk,
                    .defining_ep = chunk_blk.defining_ep,
                    .defining_self = struct_val,
                } },
            };
            break :chunk_blk_result try vm.yieldToBlock(class_body_block, &[_]Value{});
        },
        .symbol => try vm.yieldToBlock(block, &[_]Value{}),
        .receiver_builtin => try vm.yieldToBlock(block, &[_]Value{}),
        .builtin => try vm.yieldToBlock(block, &[_]Value{}),
        .callable => try vm.yieldToBlock(block, &[_]Value{}),
    };
}

fn normalizeStructMember(vm: *VM, arg: Value) VMError!*SymbolObject {
    const name_sym = try vm.coerceToMethodNameSymbol(arg);
    if (std.mem.endsWith(u8, name_sym.name, "=")) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "invalid struct member: {s}", .{name_sym.name});
    }
    return name_sym;
}

pub fn register(vm: *VM) !void {
    const struct_singleton = try vm.getOrCreateSingletonClass(Value.fromObject(&vm.struct_class.module.object));

    const new_sym = try vm.intern("new");
    try struct_singleton.module.methods.put(new_sym, value.MethodEntry.builtin(&builtinStructNew, .{ .variadic = 0 }));

    const bracket_sym = try vm.intern("[]");
    try struct_singleton.module.methods.put(bracket_sym, value.MethodEntry.builtin(&builtinStructNew, .{ .variadic = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.struct_class.module.methods.put(initialize_sym, value.MethodEntry.builtin(&builtinStructInitialize, .{ .variadic = 0 }));

    const instance_members_sym = try vm.intern("members");
    try vm.struct_class.module.methods.put(instance_members_sym, value.MethodEntry.builtin(&builtinStructMembers, .{ .exact = 0 }));

    const aref_sym = try vm.intern("[]");
    try vm.struct_class.module.methods.put(aref_sym, value.MethodEntry.builtin(&builtinStructAref, .{ .exact = 1 }));

    const aset_sym = try vm.intern("[]=");
    try vm.struct_class.module.methods.put(aset_sym, value.MethodEntry.builtin(&builtinStructAset, .{ .exact = 2 }));

    const to_a_sym = try vm.intern("to_a");
    try vm.struct_class.module.methods.put(to_a_sym, value.MethodEntry.builtin(&builtinStructToA, .{ .exact = 0 }));

    const values_sym = try vm.intern("values");
    try vm.struct_class.module.methods.put(values_sym, value.MethodEntry.builtin(&builtinStructToA, .{ .exact = 0 }));

    const size_sym = try vm.intern("size");
    try vm.struct_class.module.methods.put(size_sym, value.MethodEntry.builtin(&builtinStructSize, .{ .exact = 0 }));

    const length_sym = try vm.intern("length");
    try vm.struct_class.module.methods.put(length_sym, value.MethodEntry.builtin(&builtinStructSize, .{ .exact = 0 }));

    const each_sym = try vm.intern("each");
    try vm.struct_class.module.methods.put(each_sym, value.MethodEntry.builtin(&builtinStructEach, .{ .exact = 0 }));

    const each_pair_sym = try vm.intern("each_pair");
    try vm.struct_class.module.methods.put(each_pair_sym, value.MethodEntry.builtin(&builtinStructEachPair, .{ .exact = 0 }));

    const inspect_sym = try vm.intern("inspect");
    try vm.struct_class.module.methods.put(inspect_sym, value.MethodEntry.builtin(&builtinStructInspect, .{ .exact = 0 }));

    const to_s_sym = try vm.intern("to_s");
    try vm.struct_class.module.methods.put(to_s_sym, value.MethodEntry.builtin(&builtinStructInspect, .{ .exact = 0 }));

    const equal_sym = try vm.intern("==");
    try vm.struct_class.module.methods.put(equal_sym, value.MethodEntry.builtin(&builtinStructEqual, .{ .exact = 1 }));

    const eql_sym = try vm.intern("eql?");
    try vm.struct_class.module.methods.put(eql_sym, value.MethodEntry.builtin(&builtinStructEql, .{ .exact = 1 }));
}

pub fn builtinStructNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());

    const receiver_class = receiver.toClassObject();
    if (receiver_class != vm.struct_class) {
        return class_builtin.builtinClassNew(vm, receiver, args, block);
    }

    var keyword_init: ?Value = null;
    try vm.consumeKeywordArgs(.{"keyword_init"}, .{&keyword_init});
    try vm.validateKeywordArgsConsumed();

    var member_start: usize = 0;
    var name_arg: ?Value = null;
    if (args.len > 0 and !args[0].isSymbol()) {
        _ = try args[0].coerceToStr(vm, "first struct member or class name is not a symbol nor a string");
        name_arg = args[0];
        member_start = 1;
    }

    const members = try vm.createArray();
    var seen = std.AutoHashMap(*SymbolObject, void).init(vm.gc_allocator);
    defer seen.deinit();

    for (args[member_start..]) |arg| {
        const member_sym = try normalizeStructMember(vm, arg);
        if (seen.contains(member_sym)) {
            return vm.raiseExceptionFmt(vm.argument_error_class, "duplicate member: {s}", .{member_sym.name});
        }
        seen.put(member_sym, {}) catch return error.Fatal;
        members.elements.append(vm.gc_allocator, Value.fromObject(&member_sym.object)) catch return error.Fatal;
    }

    const class_name = if (name_arg) |name| try name.coerceToStr(vm, "class name is not a string") else "<anonymous>";
    const class_name_sym = try vm.intern(class_name);
    const struct_val = try vm.newClass(class_name_sym, vm.struct_class);
    struct_val.toClassObject().struct_members = members;
    struct_val.toClassObject().struct_keyword_init = if (keyword_init) |value_arg| value_arg.isTruthy() else null;

    if (name_arg) |name| {
        var const_args = [_]Value{ name, struct_val };
        _ = try module_builtin.builtinModuleConstSet(vm, receiver, const_args[0..], null);
    }

    _ = try module_builtin.builtinModuleAttrAccessor(vm, struct_val, members.elements.items, null);
    try defineStructSubclassSingletonMethods(vm, struct_val);

    if (block) |blk| {
        try runStructSubclassBody(vm, struct_val, blk);
    }

    return struct_val;
}

pub fn builtinStructSubclassSquareBrackets(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    return class_builtin.builtinClassNew(vm, receiver, args, block);
}

pub fn builtinStructClassMembers(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    std.debug.assert(receiver.isClass());
    return duplicateMembersArray(vm, try getStructMembersForClass(vm, receiver.toClassObject()));
}

pub fn builtinStructInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    const members = try getStructMembersForReceiver(vm, receiver);
    const keyword_init = structKeywordInitForClass(vm.getClass(receiver));

    if (keyword_init == true) {
        if (args.len != 0) {
            return vm.raiseArgumentErrorWrongArgCount(args.len, 0);
        }

        var i: usize = 0;
        while (i < members.elements.items.len) : (i += 1) {
            const member = members.elements.items[i].toSymbolObject();
            const arg = (try vm.consumeKeywordArg(member.name)) orelse Value.nil();
            _ = try structMemberWriter(vm, receiver, member, arg);
        }
        try vm.validateKeywordArgsConsumed();
        return Value.nil();
    }

    try vm.requireArgCountRange(args, 0, members.elements.items.len);

    for (members.elements.items, 0..) |member, idx| {
        const arg = if (idx < args.len) args[idx] else Value.nil();
        _ = try structMemberWriter(vm, receiver, member.toSymbolObject(), arg);
    }

    return Value.nil();
}

pub fn builtinStructMembers(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return duplicateMembersArray(vm, try getStructMembersForReceiver(vm, receiver));
}

pub fn builtinStructAref(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const members = try getStructMembersForReceiver(vm, receiver);
    const index = try resolveStructIndex(vm, members, args[0]);
    return structMemberReaderValue(vm, receiver, members.elements.items[index].toSymbolObject());
}

pub fn builtinStructAset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const members = try getStructMembersForReceiver(vm, receiver);
    const index = try resolveStructIndex(vm, members, args[0]);
    return structMemberWriter(vm, receiver, members.elements.items[index].toSymbolObject(), args[1]);
}

pub fn builtinStructToA(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try getStructMembersForReceiver(vm, receiver);
    const out = try vm.createArray();
    for (members.elements.items) |member| {
        out.elements.append(vm.gc_allocator, try structMemberReaderValue(vm, receiver, member.toSymbolObject())) catch return error.Fatal;
    }
    return Value.fromObject(&out.object);
}

pub fn builtinStructSize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    return Value.integer(@intCast(try structSize(vm, receiver)));
}

pub fn builtinStructEach(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try getStructMembersForReceiver(vm, receiver);
    if (block == null) {
        return vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each"), &.{}, Value.integer(@intCast(members.elements.items.len)));
    }

    for (members.elements.items) |member| {
        const value_arg = [_]Value{try structMemberReaderValue(vm, receiver, member.toSymbolObject())};
        _ = try vm.yieldToBlock(block.?, value_arg[0..]);
    }

    return receiver;
}

pub fn builtinStructEachPair(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const members = try getStructMembersForReceiver(vm, receiver);
    if (block == null) {
        return vm.createMethodEnumeratorWithSize(receiver, try vm.intern("each_pair"), &.{}, Value.integer(@intCast(members.elements.items.len)));
    }

    for (members.elements.items) |member| {
        const value_arg = try structMemberReaderValue(vm, receiver, member.toSymbolObject());
        const yield_args = [_]Value{ Value.fromObject(&member.toSymbolObject().object), value_arg };
        _ = try vm.yieldToBlock(block.?, yield_args[0..]);
    }

    return receiver;
}

pub fn builtinStructInspect(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const receiver_class = vm.getClass(receiver);
    const class_name = try vm.callMethodByName(Value.fromObject(&receiver_class.module.object), "name", &.{}, null);
    const members = try getStructMembersForReceiver(vm, receiver);

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(vm.allocator);

    buffer.appendSlice(vm.allocator, "#<struct") catch return error.Fatal;
    if (class_name.isString()) {
        const class_name_segment = std.fmt.allocPrint(vm.allocator, " {s}", .{class_name.toStringObject().str}) catch return error.Fatal;
        defer vm.allocator.free(class_name_segment);
        buffer.appendSlice(vm.allocator, class_name_segment) catch return error.Fatal;
    }

    for (members.elements.items, 0..) |member, idx| {
        const inspected = try (try structMemberReaderValue(vm, receiver, member.toSymbolObject())).inspect(vm);
        const member_segment = std.fmt.allocPrint(vm.allocator, "{s}{s}={s}", .{
            if (idx == 0) " " else ", ",
            member.toSymbolObject().name,
            inspected.toStringObject().str,
        }) catch return error.Fatal;
        defer vm.allocator.free(member_segment);
        buffer.appendSlice(vm.allocator, member_segment) catch return error.Fatal;
    }

    buffer.append(vm.allocator, '>') catch return error.Fatal;
    return vm.newString(buffer.items, false);
}

pub fn builtinStructEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isObject()) return Value.boolean(false);
    if (vm.getClass(receiver) != vm.getClass(other)) return Value.boolean(false);

    const members = try getStructMembersForReceiver(vm, receiver);
    for (members.elements.items) |member| {
        const left = try structMemberReaderValue(vm, receiver, member.toSymbolObject());
        const right = try structMemberReaderValue(vm, other, member.toSymbolObject());
        if (!try vm.valueEquals(left, right)) return Value.boolean(false);
    }

    return Value.boolean(true);
}

pub fn builtinStructEql(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const other = args[0];
    if (!other.isObject()) return Value.boolean(false);
    if (vm.getClass(receiver) != vm.getClass(other)) return Value.boolean(false);

    const members = try getStructMembersForReceiver(vm, receiver);
    for (members.elements.items) |member| {
        const left = try structMemberReaderValue(vm, receiver, member.toSymbolObject());
        const right = try structMemberReaderValue(vm, other, member.toSymbolObject());
        if (!try vm.hashKeysEqual(left, right)) return Value.boolean(false);
    }

    return Value.boolean(true);
}
