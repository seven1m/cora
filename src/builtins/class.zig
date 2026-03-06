const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    const class_new_sym = try vm.intern("new");
    try vm.class_class.module.methods.put(class_new_sym, .{ .method = .{ .builtin = &builtinClassNew } });

    const class_allocate_sym = try vm.intern("allocate");
    try vm.class_class.module.methods.put(class_allocate_sym, .{ .method = .{ .builtin = &builtinClassAllocate } });

    const class_equal_sym = try vm.intern("==");
    try vm.class_class.module.methods.put(class_equal_sym, .{ .method = .{ .builtin = &builtinClassEqual } });
}

pub fn builtinClassNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }

    const class_ptr = receiver.toClassObject();

    if (class_ptr == vm.module_class) {
        try vm.requireArgCount(args, 0);

        const anonymous_name = try vm.intern("<anonymous>");
        const module_val = try vm.newModule(anonymous_name);

        if (block) |blk| {
            const yield_result = switch (blk.kind) {
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
                .symbol => try vm.yieldToBlock(blk, &[_]Value{}),
                .builtin => try vm.yieldToBlock(blk, &[_]Value{}),
            };
            if (yield_result.break_occurred) return yield_result.value;
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
        }

        const anonymous_name = try vm.intern("<anonymous>");
        const class_val = try vm.newClass(anonymous_name, superclass);

        if (block) |blk| {
            const yield_result = switch (blk.kind) {
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
                .symbol => try vm.yieldToBlock(blk, &[_]Value{}),
                .builtin => try vm.yieldToBlock(blk, &[_]Value{}),
            };
            if (yield_result.break_occurred) return yield_result.value;
        }

        return class_val;
    }

    // OtherClass.new(...) instantiates OtherClass and calls initialize.
    const instance = try vm.newObjectForClass(class_ptr);
    const init_sym = try vm.intern("initialize");
    if (try vm.findMethod(instance, init_sym)) |_| {
        _ = try vm.callMethodByNameForwardingKeywords(instance, "initialize", args, block);
    } else if (args.len != 0) {
        try vm.requireArgCount(args, 0);
    }
    return instance;
}

pub fn builtinClassEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!receiver.isClass() or !args[0].isClass()) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.toClassObject() == args[0].toClassObject());
}

pub fn builtinClassAllocate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }

    const class_ptr = receiver.toClassObject();
    if (class_ptr.object_type == .string) {
        return vm.newStringForClassWithEncoding(class_ptr, "", false, .{ .ascii_8bit = .{} });
    }

    return vm.newObjectForClass(class_ptr);
}
