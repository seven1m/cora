const vm_mod = @import("../vm.zig");

const VM = vm_mod.VM;

const array = @import("array.zig");
const basic_object = @import("basic_object.zig");
const encoding = @import("encoding.zig");
const exception = @import("exception.zig");
const false_class = @import("false_class.zig");
const hash = @import("hash.zig");
const integer = @import("integer.zig");
const kernel = @import("kernel.zig");
const module_builtin = @import("module.zig");
const nil_class = @import("nil_class.zig");
const object = @import("object.zig");
const proc_builtin = @import("proc.zig");
const range = @import("range.zig");
const string = @import("string.zig");
const symbol = @import("symbol.zig");
const true_class = @import("true_class.zig");

pub fn registerAll(vm: *VM) !void {
    try basic_object.register(vm);
    try kernel.register(vm);
    try object.register(vm);
    try module_builtin.register(vm);
    try integer.register(vm);
    try array.register(vm);
    try hash.register(vm);
    try proc_builtin.register(vm);
    try range.register(vm);
    try string.register(vm);
    try symbol.register(vm);
    try nil_class.register(vm);
    try true_class.register(vm);
    try false_class.register(vm);
    try exception.register(vm);
    try encoding.register(vm);
}
