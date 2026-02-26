const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    const class_new_sym = try vm.intern("new");
    const class_class_val = Value.fromObject(vm.class_class);
    const class_singleton = try vm.getOrCreateSingletonClass(class_class_val);
    try class_singleton.module.methods.put(class_new_sym, .{ .method = .{ .builtin = &builtinClassNew } });

    const class_equal_sym = try vm.intern("==");
    try vm.class_class.module.methods.put(class_equal_sym, .{ .method = .{ .builtin = &builtinClassEqual } });
}

pub fn builtinClassNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    if (!receiver.isClass()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{});
    }

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

pub fn builtinClassEqual(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (!receiver.isClass() or !args[0].isClass()) {
        return Value.boolean(false);
    }
    return Value.boolean(receiver.toClassObject() == args[0].toClassObject());
}
