const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;

pub fn register(vm: *VM) !void {
    const class_new_sym = try vm.intern("new");
    const class_class_val = Value{ .data = .{ .class = vm.class_class } };
    const class_singleton = try vm.getOrCreateSingletonClass(class_class_val);
    try class_singleton.module.methods.put(class_new_sym, .{ .method = .{ .builtin = &builtinClassNew } });
}

pub fn builtinClassNew(vm: *VM, receiver: Value, args: []Value, block: ?Block) VMError!Value {
    _ = switch (receiver.data) {
        .class => receiver.data.class,
        else => return vm.raiseExceptionFmt(vm.type_error_class, "receiver is not a Class", .{}),
    };

    if (args.len > 1) {
        return vm.raiseExceptionFmt(
            vm.argument_error_class,
            "wrong number of arguments (given {d}, expected 0..1)",
            .{args.len},
        );
    }

    var superclass: *ClassObject = vm.object_class;
    if (args.len == 1) {
        superclass = switch (args[0].data) {
            .class => args[0].data.class,
            else => return vm.raiseExceptionFmt(vm.type_error_class, "superclass must be a Class", .{}),
        };
    }

    const anonymous_name = try vm.intern("<anonymous>");
    const class_val = try vm.newClass(anonymous_name, superclass);

    if (block) |blk| {
        blk.chunk.lexical_scope = try vm.createLexicalScope(class_val, vm.current_lexical_scope);

        var class_body_block = blk;
        class_body_block.defining_self = class_val;
        const yield_result = try vm.yieldToBlock(class_body_block, &[_]Value{});
        if (yield_result.break_occurred) {
            return yield_result.value;
        }
    }

    return class_val;
}
