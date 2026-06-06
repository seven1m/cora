const std = @import("std");
const value = @import("value.zig");
const Value = value.Value;
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const enc = @import("encoding.zig");
const cext_globals = @import("cext_globals.zig");

pub const VALUE = u64;

fn getVM() *VM {
    return @ptrCast(@alignCast(cext_globals.getCurrentVM()));
}

pub export var rb_cString: VALUE = 0;

pub export var rb_cObject: VALUE = 0;
pub export var rb_cArray: VALUE = 0;
pub export var rb_cHash: VALUE = 0;
pub export var rb_cInteger: VALUE = 0;
pub export var rb_cFloat: VALUE = 0;
pub export var rb_cSymbol: VALUE = 0;
pub export var rb_cRange: VALUE = 0;
pub export var rb_cRegexp: VALUE = 0;
pub export var rb_cClass: VALUE = 0;
pub export var rb_cModule: VALUE = 0;
pub export var rb_cProc: VALUE = 0;
pub export var rb_cNilClass: VALUE = 0;
pub export var rb_cTrueClass: VALUE = 0;
pub export var rb_cFalseClass: VALUE = 0;
pub export var rb_cNumeric: VALUE = 0;
pub export var rb_cStruct: VALUE = 0;
pub export var rb_cDir: VALUE = 0;
pub export var rb_cFile: VALUE = 0;
pub export var rb_cIO: VALUE = 0;
pub export var rb_cTime: VALUE = 0;
pub export var rb_cThread: VALUE = 0;
pub export var rb_cFiber: VALUE = 0;
pub export var rb_cEncoding: VALUE = 0;
pub export var rb_cEnumerator: VALUE = 0;
pub export var rb_cException: VALUE = 0;
pub export var rb_cStandardError: VALUE = 0;
pub export var rb_cRuntimeError: VALUE = 0;
pub export var rb_cArgumentError: VALUE = 0;
pub export var rb_cTypeError: VALUE = 0;
pub export var rb_cNameError: VALUE = 0;
pub export var rb_cNoMethodError: VALUE = 0;

pub export var rb_mKernel: VALUE = 0;
pub export var rb_mProcess: VALUE = 0;
pub export var rb_mSignal: VALUE = 0;
pub export var rb_mWarning: VALUE = 0;
pub export var rb_mMarshal: VALUE = 0;
pub export var rb_mErrno: VALUE = 0;

pub fn setupGlobals(vm: *VM) void {
    cext_globals.setCurrentVM(vm);

    rb_cString = Value.fromObject(&vm.string_class.module.object).raw;
    rb_cObject = Value.fromObject(&vm.object_class.module.object).raw;
    rb_cArray = Value.fromObject(&vm.array_class.module.object).raw;
    rb_cHash = Value.fromObject(&vm.hash_class.module.object).raw;
    rb_cInteger = Value.fromObject(&vm.integer_class.module.object).raw;
    rb_cFloat = Value.fromObject(&vm.float_class.module.object).raw;
    rb_cSymbol = Value.fromObject(&vm.symbol_class.module.object).raw;
    rb_cRange = Value.fromObject(&vm.range_class.module.object).raw;
    rb_cRegexp = Value.fromObject(&vm.regexp_class.module.object).raw;
    rb_cClass = Value.fromObject(&vm.class_class.module.object).raw;
    rb_cModule = Value.fromObject(&vm.module_class.module.object).raw;
    rb_cProc = Value.fromObject(&vm.proc_class.module.object).raw;
    rb_cNilClass = Value.fromObject(&vm.nil_class.module.object).raw;
    rb_cTrueClass = Value.fromObject(&vm.true_class.module.object).raw;
    rb_cFalseClass = Value.fromObject(&vm.false_class.module.object).raw;
    rb_cNumeric = Value.fromObject(&vm.numeric_class.module.object).raw;
    rb_cStruct = Value.fromObject(&vm.struct_class.module.object).raw;
    rb_cDir = Value.fromObject(&vm.dir_class.module.object).raw;
    rb_cFile = Value.fromObject(&vm.file_class.module.object).raw;
    rb_cIO = Value.fromObject(&vm.io_class.module.object).raw;
    rb_cTime = Value.fromObject(&vm.time_class.module.object).raw;
    rb_cThread = Value.fromObject(&vm.thread_class.module.object).raw;
    rb_cFiber = Value.fromObject(&vm.fiber_class.module.object).raw;
    rb_cEncoding = Value.fromObject(&vm.encoding_class.module.object).raw;
    rb_cEnumerator = Value.fromObject(&vm.enumerator_class.module.object).raw;
    rb_cException = Value.fromObject(&vm.exception_class.module.object).raw;
    rb_cStandardError = Value.fromObject(&vm.standard_error_class.module.object).raw;
    rb_cRuntimeError = Value.fromObject(&vm.runtime_error_class.module.object).raw;
    rb_cArgumentError = Value.fromObject(&vm.argument_error_class.module.object).raw;
    rb_cTypeError = Value.fromObject(&vm.type_error_class.module.object).raw;
    rb_cNameError = Value.fromObject(&vm.name_error_class.module.object).raw;
    rb_cNoMethodError = Value.fromObject(&vm.no_method_error_class.module.object).raw;

    rb_mKernel = Value.fromObject(&vm.kernel_module.object).raw;
    rb_mProcess = Value.fromObject(&vm.process_module.object).raw;
    rb_mSignal = Value.fromObject(&vm.signal_module.object).raw;
    rb_mWarning = Value.fromObject(&vm.warning_module.object).raw;
    rb_mMarshal = Value.fromObject(&vm.marshal_module.object).raw;
    rb_mErrno = Value.fromObject(&vm.errno_module.object).raw;
}

const encoding_instances = blk: {
    const tags = std.meta.tags(enc.Encoding);
    var instances: [tags.len]enc.Encoding = undefined;
    for (tags, 0..) |tag, i| {
        instances[i] = @unionInit(enc.Encoding, @tagName(tag), .{});
    }
    break :blk instances;
};

export fn rb_define_method(klass: VALUE, name_ptr: [*:0]const u8, func: ?*anyopaque, argc: c_int) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);

    if (klass == 0 or name.len == 0 or func == null) return;

    const sym = vm.intern(name) catch return;
    const class_ptr: *value.ClassObject = @ptrFromInt(klass);

    const entry = value.MethodEntry{
        .method = .{ .cext = .{ .func = func.?, .argc = argc } },
        .visibility = .public,
    };

    class_ptr.module.methods.put(sym, entry) catch @panic("OOM in rb_define_method");
    vm.method_state_version += 1;
}

export fn rb_string_ptr(str_raw: VALUE) ?[*]u8 {
    const val = Value{ .raw = str_raw };
    if (val.isString()) {
        return @constCast(val.toStringObject().str.ptr);
    }
    return null;
}

export fn rb_string_len(str_raw: VALUE) c_long {
    const val = Value{ .raw = str_raw };
    if (val.isString()) {
        return @intCast(val.toStringObject().str.len);
    }
    return 0;
}

export fn rb_encoding_get(str_raw: VALUE) c_int {
    const val = Value{ .raw = str_raw };
    if (val.isString()) {
        return @intCast(@intFromEnum(val.toStringObject().encoding));
    }
    return 0;
}

export fn rb_enc_from_index(idx: c_int) ?*anyopaque {
    const i: usize = @intCast(@max(idx, 0));
    if (i < encoding_instances.len) {
        return @constCast(&encoding_instances[i]);
    }
    return @constCast(&encoding_instances[0]);
}

export fn rb_enc_codepoint_len(p: [*]const u8, e: [*]const u8, len_p: *c_int, enc_opaque: ?*anyopaque) c_uint {
    if (@intFromPtr(p) >= @intFromPtr(e)) {
        len_p.* = 0;
        return 0;
    }

    const remaining: usize = @intFromPtr(e) - @intFromPtr(p);
    const opaque_ptr: *anyopaque = enc_opaque orelse @ptrCast(@constCast(&encoding_instances[0]));
    const enc_ptr: *const enc.Encoding = @ptrCast(@alignCast(opaque_ptr));
    const slice = p[0..remaining];
    var byte_index: usize = 0;
    const result = enc_ptr.nextCodepoint(slice, &byte_index);

    if (result.len == 0) {
        len_p.* = 1;
        return 0;
    }

    len_p.* = @intCast(result.len);
    return result.codepoint;
}

export fn rb_isspace(c: c_uint) c_int {
    return @intFromBool(c == ' ' or ('\t' <= c and c <= '\r'));
}
