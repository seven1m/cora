const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const array_builtin = @import("array.zig");
const std = @import("std");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    const class_new_sym = try vm.intern("new");
    try vm.class_class.module.methods.put(class_new_sym, value.MethodEntry.builtin(&builtinClassNew, .{ .variadic = 0 }));

    const class_allocate_sym = try vm.intern("allocate");
    try vm.class_class.module.methods.put(class_allocate_sym, value.MethodEntry.builtin(&builtinClassAllocate, .{ .exact = 0 }));

    const class_equal_sym = try vm.intern("==");
    try vm.class_class.module.methods.put(class_equal_sym, value.MethodEntry.builtin(&builtinClassEqual, .{ .exact = 1 }));

    const class_superclass_sym = try vm.intern("superclass");
    try vm.class_class.module.methods.put(class_superclass_sym, value.MethodEntry.builtin(&builtinClassSuperclass, .{ .exact = 0 }));

    const initialize_sym = try vm.intern("initialize");
    try vm.class_class.module.methods.put(initialize_sym, value.MethodEntry.builtinWithVisibility(&builtinClassInitialize, .{ .variadic = 0 }, .private));
}

fn singletonClassName(vm: *VM, class_ptr: *ClassObject) ?[]const u8 {
    if (class_ptr == vm.symbol_class) return "Symbol";
    if (class_ptr == vm.nil_class) return "NilClass";
    if (class_ptr == vm.true_class) return "TrueClass";
    if (class_ptr == vm.false_class) return "FalseClass";
    if (class_ptr == vm.rational_class) return "Rational";
    return null;
}

fn isUninitializedClass(vm: *VM, class_ptr: *ClassObject) bool {
    return class_ptr != vm.basic_object_class and class_ptr.superclass == null;
}

pub fn builtinClassNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    std.debug.assert(receiver.isClass());

    const class_ptr = receiver.toClassObject();

    if (isUninitializedClass(vm, class_ptr)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "can't instantiate uninitialized class", .{});
    }

    if (singletonClassName(vm, class_ptr)) |name| {
        return vm.raiseExceptionFmt(vm.no_method_error_class, "undefined method 'new' for {s}", .{name});
    }

    if (class_ptr == vm.module_class) {
        try vm.requireArgCount(args, 0);

        const anonymous_name = try vm.intern("<anonymous>");
        const module_val = try vm.newModule(anonymous_name);

        if (block) |blk| {
            _ = switch (blk.kind) {
                .chunk => |chunk_blk| chunk_blk_result: {
                    chunk_blk.chunk.lexical_scope = try vm.createLexicalScope(module_val, vm.current_lexical_scope);

                    const module_body_block = Block{
                        .kind = .{ .chunk = .{
                            .chunk = chunk_blk.chunk,
                            .defining_ep = chunk_blk.defining_ep,
                            .defining_self = module_val,
                        } },
                    };
                    break :chunk_blk_result try vm.yieldToBlock(module_body_block, &[_]Value{});
                },
                .receiver_builtin => try vm.yieldToBlock(blk, &[_]Value{}),
                .symbol => try vm.yieldToBlock(blk, &[_]Value{}),
                .builtin => try vm.yieldToBlock(blk, &[_]Value{}),
                .callable => try vm.yieldToBlock(blk, &[_]Value{}),
            };
        }

        return module_val;
    }

    // Class.new([superclass]) creates anonymous classes.
    if (class_ptr == vm.class_class) {
        try vm.requireArgCountRange(args, 0, 1);

        var superclass: *ClassObject = vm.object_class;
        if (args.len == 1) {
            if (!args[0].isClass()) {
                return vm.raiseExceptionFmt(vm.type_error_class, "superclass must be a Class", .{});
            }
            superclass = args[0].toClassObject();
            if (superclass.attached_object != null) {
                return vm.raiseExceptionFmt(vm.type_error_class, "can't make subclass of singleton class", .{});
            }
        }

        const anonymous_name = try vm.intern("<anonymous>");
        const class_val = try vm.newClass(anonymous_name, superclass);

        // Call superclass.inherited(new_class)
        const superclass_val = if (args.len == 1) args[0] else Value.nil();
        if (!superclass_val.isNil() and superclass_val.isClass()) {
            var inherited_args = [_]Value{class_val};
            _ = try vm.callMethodByName(superclass_val, "inherited", inherited_args[0..], null);
        }

        if (block) |blk| {
            _ = switch (blk.kind) {
                .chunk => |chunk_blk| chunk_blk_result: {
                    chunk_blk.chunk.lexical_scope = try vm.createLexicalScope(class_val, vm.current_lexical_scope);

                    const class_body_block = Block{
                        .kind = .{ .chunk = .{
                            .chunk = chunk_blk.chunk,
                            .defining_ep = chunk_blk.defining_ep,
                            .defining_self = class_val,
                        } },
                    };
                    break :chunk_blk_result try vm.yieldToBlock(class_body_block, &[_]Value{});
                },
                .receiver_builtin => try vm.yieldToBlock(blk, &[_]Value{}),
                .symbol => try vm.yieldToBlock(blk, &[_]Value{}),
                .builtin => try vm.yieldToBlock(blk, &[_]Value{}),
                .callable => try vm.yieldToBlock(blk, &[_]Value{}),
            };
        }

        return class_val;
    }

    // OtherClass.new(...) instantiates OtherClass and calls initialize.
    const instance = try vm.newObjectForClass(class_ptr);

    const initialize_sym = try vm.intern("initialize");
    if (try vm.findMethod(instance, initialize_sym)) |resolved| {
        if (resolved.entry.method == .builtin and resolved.entry.method.builtin.function == &array_builtin.builtinArrayInitialize) {
            return try vm.invokeBuiltinMethodForwardingKeywords(resolved.entry.method.builtin, instance, "initialize", args, block);
        }
    }

    _ = try vm.callMethodByNameForwardingKeywords(instance, "initialize", args, block);
    return instance;
}

pub fn builtinClassEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!receiver.isClass() or !args[0].isClass()) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.toClassObject() == args[0].toClassObject());
}

pub fn builtinClassSuperclass(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    std.debug.assert(receiver.isClass());
    const class_ptr = receiver.toClassObject();
    if (isUninitializedClass(vm, class_ptr)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "uninitialized class", .{});
    }
    const superclass = class_ptr.superclass orelse return Value.nil();
    return Value.fromObject(&superclass.module.object);
}

pub fn builtinClassInitialize(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 0, 1);
    std.debug.assert(receiver.isClass());

    const class_ptr = receiver.toClassObject();
    if (!isUninitializedClass(vm, class_ptr)) {
        return vm.raiseExceptionFmt(vm.type_error_class, "already initialized class", .{});
    }

    var superclass = vm.object_class;
    if (args.len == 1) {
        if (!args[0].isClass()) {
            return vm.raiseExceptionFmt(vm.type_error_class, "superclass must be an instance of Class", .{});
        }
        superclass = args[0].toClassObject();
        if (superclass == vm.class_class) {
            return vm.raiseExceptionFmt(vm.type_error_class, "can't make subclass of Class", .{});
        }
    }

    class_ptr.superclass = superclass;
    class_ptr.module.super = &superclass.module;
    class_ptr.object_type = superclass.object_type;

    var inherited_args = [_]Value{receiver};
    _ = try vm.callMethodByName(Value.fromObject(&superclass.module.object), "inherited", inherited_args[0..], null);

    if (block) |blk| {
        _ = switch (blk.kind) {
            .chunk => |chunk_blk| chunk_blk_result: {
                chunk_blk.chunk.lexical_scope = try vm.createLexicalScope(receiver, vm.current_lexical_scope);
                const class_body_block = Block{
                    .kind = .{ .chunk = .{
                        .chunk = chunk_blk.chunk,
                        .defining_ep = chunk_blk.defining_ep,
                        .defining_self = receiver,
                    } },
                };
                break :chunk_blk_result try vm.yieldToBlock(class_body_block, &[_]Value{});
            },
            .receiver_builtin, .symbol, .builtin, .callable => try vm.yieldToBlock(blk, &[_]Value{}),
        };
    }

    return receiver;
}

pub fn builtinClassAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    std.debug.assert(receiver.isClass());

    const class_ptr = receiver.toClassObject();
    if (singletonClassName(vm, class_ptr)) |name| {
        return vm.raiseExceptionFmt(vm.type_error_class, "allocator undefined for {s}", .{name});
    }
    if (class_ptr == vm.class_class) {
        const anonymous_name = try vm.intern("<anonymous>");
        return vm.newClass(anonymous_name, null);
    }
    if (class_ptr.object_type == .string) {
        return vm.newStringForClassWithEncoding(class_ptr, "", false, .{ .ascii_8bit = .{} });
    }

    return vm.newObjectForClass(class_ptr);
}
