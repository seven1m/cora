const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");

const VM = vm_mod.VM;
const MethodEntry = value.MethodEntry;

const argf = @import("argf.zig");
const array = @import("array.zig");
const basic_object = @import("basic_object.zig");
const binding_builtin = @import("binding.zig");
const class_builtin = @import("class.zig");
const condition_variable = @import("condition_variable.zig");
const data = @import("data.zig");
const encoding = @import("encoding.zig");
const enumerator = @import("enumerator.zig");
const env = @import("env.zig");
const etc = @import("etc.zig");
const exception = @import("exception.zig");
const false_class = @import("false_class.zig");
const dir = @import("dir.zig");
const enumerable = @import("enumerable.zig");
const file = @import("file.zig");
const float = @import("float.zig");
const hash = @import("hash.zig");
const io = @import("io.zig");
const integer = @import("integer.zig");
const kernel = @import("kernel.zig");
const match_data = @import("match_data.zig");
const marshal = @import("marshal.zig");
const module_builtin = @import("module.zig");
const nil_class = @import("nil_class.zig");
const numeric = @import("numeric.zig");
const object = @import("object.zig");
const proc_builtin = @import("proc.zig");
const process = @import("process.zig");
const rbconfig = @import("rbconfig.zig");
const signal = @import("signal.zig");
const fiber = @import("fiber.zig");
const thread = @import("thread.zig");
const mutex = @import("mutex.zig");
const object_space = @import("object_space.zig");
const queue = @import("queue.zig");
const random = @import("random.zig");
const rational = @import("rational.zig");
const time = @import("time.zig");
const warning = @import("warning.zig");
const range = @import("range.zig");
const regexp = @import("regexp.zig");
const socket = @import("socket.zig");
const struct_builtin = @import("struct.zig");
const string = @import("string.zig");
const stringio = @import("stringio.zig");
const symbol = @import("symbol.zig");
const true_class = @import("true_class.zig");

pub fn registerAll(vm: *VM) !void {
    try basic_object.register(vm);
    try kernel.register(vm);
    try object.register(vm);
    try class_builtin.register(vm);
    try module_builtin.register(vm);
    try binding_builtin.register(vm);
    try integer.register(vm);
    try numeric.register(vm);
    try float.register(vm);
    try array.register(vm);
    try hash.register(vm);
    try io.register(vm);
    try file.register(vm);
    try dir.register(vm);
    try enumerable.register(vm);
    try argf.register(vm);
    try env.register(vm);
    try etc.register(vm);
    try process.register(vm);
    try rbconfig.register(vm);
    try signal.register(vm);
    try warning.register(vm);
    try marshal.register(vm);
    try proc_builtin.register(vm);
    try struct_builtin.register(vm);
    try fiber.register(vm);
    try thread.register(vm);
    try mutex.register(vm);
    try condition_variable.register(vm);
    try data.register(vm);
    try object_space.register(vm);
    try queue.register(vm);
    try random.register(vm);
    try rational.register(vm);
    try time.register(vm);
    try range.register(vm);
    try regexp.register(vm);
    try socket.register(vm);
    try match_data.register(vm);
    try string.register(vm);
    try stringio.register(vm);
    try symbol.register(vm);
    try nil_class.register(vm);
    try true_class.register(vm);
    try false_class.register(vm);
    try exception.register(vm);
    try encoding.register(vm);
    try enumerator.register(vm);
}

pub fn registerMainSelf(vm: *VM) !void {
    const main_singleton = try vm.getOrCreateSingletonClass(vm.main_self);
    const include_sym = try vm.intern("include");
    const private_sym = try vm.intern("private");
    const public_sym = try vm.intern("public");

    main_singleton.module.methods.put(
        include_sym,
        MethodEntry.builtinWithVisibility(&module_builtin.builtinMainInclude, .{ .variadic = 0 }, .private),
    ) catch return error.Fatal;
    main_singleton.module.methods.put(
        private_sym,
        MethodEntry.builtinWithVisibility(&module_builtin.builtinMainPrivate, .{ .variadic = 0 }, .private),
    ) catch return error.Fatal;
    main_singleton.module.methods.put(
        public_sym,
        MethodEntry.builtinWithVisibility(&module_builtin.builtinMainPublic, .{ .variadic = 0 }, .private),
    ) catch return error.Fatal;
}
