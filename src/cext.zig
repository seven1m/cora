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

pub export var rb_eException: VALUE = 0;
pub export var rb_eStandardError: VALUE = 0;
pub export var rb_eRuntimeError: VALUE = 0;
pub export var rb_eArgError: VALUE = 0;
pub export var rb_eTypeError: VALUE = 0;
pub export var rb_eNameError: VALUE = 0;
pub export var rb_eNoMethodError: VALUE = 0;
pub export var rb_eNoMemError: VALUE = 0;
pub export var rb_eNoMemoryError: VALUE = 0;
pub export var rb_eScriptError: VALUE = 0;
pub export var rb_eSyntaxError: VALUE = 0;
pub export var rb_eLoadError: VALUE = 0;
pub export var rb_eNotImpError: VALUE = 0;
pub export var rb_eSystemCallError: VALUE = 0;
pub export var rb_eFatal: VALUE = 0;
pub export var rb_eSignal: VALUE = 0;
pub export var rb_eInterrupt: VALUE = 0;
pub export var rb_eSystemExit: VALUE = 0;
pub export var rb_eLocalJumpError: VALUE = 0;
pub export var rb_eSysStackError: VALUE = 0;
pub export var rb_eRangeError: VALUE = 0;
pub export var rb_eFloatDomainError: VALUE = 0;
pub export var rb_eZeroDivError: VALUE = 0;
pub export var rb_eFrozenError: VALUE = 0;
pub export var rb_eThreadError: VALUE = 0;
pub export var rb_eKeyError: VALUE = 0;
pub export var rb_eIndexError: VALUE = 0;
pub export var rb_eStopIteration: VALUE = 0;
pub export var rb_eEOFError: VALUE = 0;
pub export var rb_eEncodingError: VALUE = 0;
pub export var rb_eEncCompatError: VALUE = 0;

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

    rb_eException = rb_cException;
    rb_eStandardError = rb_cStandardError;
    rb_eRuntimeError = rb_cRuntimeError;
    rb_eArgError = rb_cArgumentError;
    rb_eTypeError = rb_cTypeError;
    rb_eNameError = rb_cNameError;
    rb_eNoMethodError = rb_cNoMethodError;
    // NoMemoryError, ScriptError, fatal, SystemStackError, FloatDomainError
    // not separately defined on VM, map to closest parent
    rb_eNoMemError = Value.fromObject(&vm.standard_error_class.module.object).raw;
    rb_eNoMemoryError = rb_eNoMemError;
    rb_eScriptError = Value.fromObject(&vm.standard_error_class.module.object).raw;
    rb_eSyntaxError = Value.fromObject(&vm.syntax_error_class.module.object).raw;
    rb_eLoadError = Value.fromObject(&vm.load_error_class.module.object).raw;
    rb_eNotImpError = Value.fromObject(&vm.not_implemented_error_class.module.object).raw;
    rb_eSystemCallError = Value.fromObject(&vm.system_call_error_class.module.object).raw;
    rb_eFatal = Value.fromObject(&vm.exception_class.module.object).raw;
    rb_eSignal = Value.fromObject(&vm.signal_exception_class.module.object).raw;
    rb_eInterrupt = Value.fromObject(&vm.interrupt_class.module.object).raw;
    rb_eSystemExit = Value.fromObject(&vm.system_exit_class.module.object).raw;
    rb_eLocalJumpError = Value.fromObject(&vm.local_jump_error_class.module.object).raw;
    rb_eSysStackError = Value.fromObject(&vm.system_call_error_class.module.object).raw;
    rb_eRangeError = Value.fromObject(&vm.range_error_class.module.object).raw;
    rb_eFloatDomainError = Value.fromObject(&vm.range_error_class.module.object).raw;
    rb_eZeroDivError = Value.fromObject(&vm.zero_division_error_class.module.object).raw;
    rb_eFrozenError = Value.fromObject(&vm.frozen_error_class.module.object).raw;
    rb_eThreadError = Value.fromObject(&vm.thread_error_class.module.object).raw;
    rb_eKeyError = Value.fromObject(&vm.key_error_class.module.object).raw;
    rb_eIndexError = Value.fromObject(&vm.index_error_class.module.object).raw;
    rb_eStopIteration = Value.fromObject(&vm.stop_iteration_class.module.object).raw;
    rb_eEOFError = Value.fromObject(&vm.eof_error_class.module.object).raw;
    rb_eEncodingError = Value.fromObject(&vm.encoding_error_class.module.object).raw;
    rb_eEncCompatError = Value.fromObject(&vm.encoding_compatibility_error_class.module.object).raw;
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

// ─── String functions ───────────────────────────────────────────────────────

export fn rb_str_new(ptr: [*c]const u8, len: c_long) VALUE {
    const vm = getVM();
    const s: []const u8 = if (ptr != null) ptr[0..@intCast(len)] else &.{};
    const val = vm.newString(s, false) catch return 0;
    return val.raw;
}

export fn rb_str_new2(ptr: [*c]const u8) VALUE {
    const vm = getVM();
    const s = if (ptr != null) std.mem.span(ptr) else "";
    const val = vm.newString(s, false) catch return 0;
    return val.raw;
}

export fn rb_usascii_str_new_cstr(ptr: [*c]const u8) VALUE {
    const vm = getVM();
    const s = if (ptr != null) std.mem.span(ptr) else "";
    const val = vm.newString(s, false) catch return 0;
    return val.raw;
}

export fn rb_enc_str_new(ptr: [*c]const u8, len: c_long, enc_ptr: ?*anyopaque) VALUE {
    _ = enc_ptr;
    return rb_str_new(ptr, len);
}

export fn rb_utf8_str_new_cstr(ptr: [*c]const u8) VALUE {
    return rb_str_new2(ptr);
}

export fn rb_string_value_cstr(ptr: *VALUE) ?[*]u8 {
    const val = Value{ .raw = ptr.* };
    if (!val.isString()) {
        const vm = getVM();
        var empty_args = [_]Value{};
        const str_val = vm.callMethodByName(val, "to_s", &empty_args, null) catch return null;
        if (!str_val.isString()) return null;
        ptr.* = str_val.raw;
        const coerced = Value{ .raw = ptr.* };
        return @constCast(coerced.toStringObject().str.ptr);
    }
    return @constCast(val.toStringObject().str.ptr);
}

export fn rb_string_value_ptr(ptr: *VALUE) ?[*]u8 {
    return rb_string_value_cstr(ptr);
}

export fn rb_string_value(ptr: *VALUE) VALUE {
    _ = rb_string_value_cstr(ptr);
    return ptr.*;
}

export fn rb_str_export_to_enc(str_raw: VALUE, enc_ptr: ?*anyopaque) VALUE {
    _ = enc_ptr;
    return str_raw;
}

// ─── Array functions ────────────────────────────────────────────────────────

export fn rb_ary_new() VALUE {
    const vm = getVM();
    const arr = vm.createArray() catch return 0;
    return Value.fromObject(&arr.object).raw;
}

export fn rb_ary_new3(n: c_long, ...) VALUE {
    const vm = getVM();
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const arr = vm.createArray() catch return 0;
    var i: c_long = 0;
    while (i < n) : (i += 1) {
        arr.elements.append(vm.gc_allocator, Value{ .raw = @cVaArg(&ap, VALUE) }) catch return 0;
    }
    return Value.fromObject(&arr.object).raw;
}

export fn rb_ary_new4(n: c_long, elts: [*c]const VALUE) VALUE {
    const vm = getVM();
    const arr = vm.createArray() catch return 0;
    if (elts != null and n > 0) {
        const slice = elts[0..@intCast(n)];
        for (slice) |e| {
            arr.elements.append(vm.gc_allocator, Value{ .raw = e }) catch return 0;
        }
    }
    return Value.fromObject(&arr.object).raw;
}

export fn rb_ary_push(ary_raw: VALUE, item_raw: VALUE) VALUE {
    const vm = getVM();
    const val = Value{ .raw = ary_raw };
    const arr = val.toArrayObject();
    arr.elements.append(vm.gc_allocator, Value{ .raw = item_raw }) catch return 0;
    return ary_raw;
}

export fn rb_ary_entry(ary_raw: VALUE, offset: c_long) VALUE {
    const val = Value{ .raw = ary_raw };
    const arr = val.toArrayObject();
    if (arr.elements.items.len == 0) return 0; // Qnil
    const idx: usize = if (offset >= 0) @intCast(offset) else @intCast(@as(isize, @intCast(arr.elements.items.len)) + offset);
    if (idx >= arr.elements.items.len) return 0;
    return arr.elements.items[idx].raw;
}

export fn rb_ary_const_ptr(ary_raw: VALUE) ?[*]const VALUE {
    const val = Value{ .raw = ary_raw };
    const arr = val.toArrayObject();
    return @ptrCast(arr.elements.items.ptr);
}

// ─── Symbol / ID functions ──────────────────────────────────────────────────

export fn rb_intern(name: [*c]const u8) VALUE {
    const vm = getVM();
    const s = if (name != null) std.mem.span(name) else "";
    const sym = vm.intern(s) catch return 0;
    return Value.fromObject(&sym.object).raw;
}

fn symName(id: VALUE) []const u8 {
    const val = Value{ .raw = id };
    if (val.isSymbol()) return val.toSymbolObject().name;
    return "?";
}

// ─── Method dispatch ────────────────────────────────────────────────────────

export fn rb_funcall(recv_raw: VALUE, mid: VALUE, argc: c_int, ...) VALUE {
    const vm = getVM();
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const name = symName(mid);
    var args_buf: [16]Value = undefined;
    var args: []Value = args_buf[0..@intCast(argc)];
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        args[@intCast(i)] = Value{ .raw = @cVaArg(&ap, VALUE) };
    }
    const result = vm.callMethodByName(Value{ .raw = recv_raw }, name, args, null) catch return 0;
    return result.raw;
}

export fn rb_funcallv(recv_raw: VALUE, mid: VALUE, argc: c_int, argv: [*c]const VALUE) VALUE {
    const vm = getVM();
    const name = symName(mid);
    const args: []Value = if (argv != null and argc > 0)
        @as([*]Value, @ptrCast(@constCast(argv)))[0..@intCast(argc)]
    else
        &[_]Value{};
    const result = vm.callMethodByName(Value{ .raw = recv_raw }, name, args, null) catch return 0;
    return result.raw;
}

export fn rb_attr_get(obj_raw: VALUE, id: VALUE) VALUE {
    const vm = getVM();
    const name = symName(id);
    const ivar = vm.getInstanceVariable(Value{ .raw = obj_raw }, name) catch return 0;
    return ivar.raw;
}

export fn rb_ivar_get(obj_raw: VALUE, id: VALUE) VALUE {
    const vm = getVM();
    const name = symName(id);
    const ivar = vm.getInstanceVariable(Value{ .raw = obj_raw }, name) catch return 0;
    return ivar.raw;
}

export fn rb_ivar_set(obj_raw: VALUE, id: VALUE, val_raw: VALUE) VALUE {
    const vm = getVM();
    const name = symName(id);
    vm.setInstanceVariable(Value{ .raw = obj_raw }, name, Value{ .raw = val_raw }) catch return 0;
    return val_raw;
}

export fn rb_respond_to(obj_raw: VALUE, id: VALUE) c_int {
    const vm = getVM();
    const name = symName(id);
    const result = vm.checkCallMethodByName(Value{ .raw = obj_raw }, name, false, &[_]Value{}, null) catch return 0;
    return @intFromBool(result != null);
}

export fn rb_class_of(obj_raw: VALUE) VALUE {
    const vm = getVM();
    return Value.fromObject(&vm.getClass(Value{ .raw = obj_raw }).module.object).raw;
}

export fn rb_obj_class(obj_raw: VALUE) VALUE {
    return rb_class_of(obj_raw);
}

export fn rb_class_new_instance(argc: c_int, argv: [*c]const VALUE, klass_raw: VALUE) VALUE {
    const vm = getVM();
    const klass: *value.ClassObject = @ptrFromInt(klass_raw);
    const instance = vm.newObjectForClass(klass) catch return 0;
    const args: []Value = if (argv != null and argc > 0)
        @as([*]Value, @ptrCast(@constCast(argv)))[0..@intCast(argc)]
    else
        &[_]Value{};
    _ = vm.callMethodByNameForwardingKeywords(instance, "initialize", args, null) catch return 0;
    return instance.raw;
}

export fn rb_obj_alloc(klass_raw: VALUE) VALUE {
    const vm = getVM();
    const klass: *value.ClassObject = @ptrFromInt(klass_raw);
    const instance = vm.newObjectForClass(klass) catch return 0;
    return instance.raw;
}

// ─── Constants ──────────────────────────────────────────────────────────────

export fn rb_const_get(klass_raw: VALUE, id: VALUE) VALUE {
    const vm = getVM();
    const name = symName(id);
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else if (klass.raw == rb_cModule) @as(*value.ModuleObject, @ptrFromInt(klass_raw)) else return 0;
    const sym = vm.intern(name) catch return 0;
    if (mod.constants.get(sym)) |entry| return entry.value.raw;
    return 0;
}

export fn rb_const_get_at(klass_raw: VALUE, id: VALUE) VALUE {
    return rb_const_get(klass_raw, id);
}

export fn rb_define_const(klass_raw: VALUE, name_ptr: [*c]const u8, val_raw: VALUE) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else if (klass.raw == rb_cModule) @as(*value.ModuleObject, @ptrFromInt(klass_raw)) else return;
    const sym = vm.intern(name) catch return;
    mod.constants.put(sym, .{ .value = Value{ .raw = val_raw } }) catch return;
}

// ─── Module/class definition ────────────────────────────────────────────────

export fn rb_define_module(name_ptr: [*c]const u8) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    // Return existing constant if already defined
    if (vm.object_class.module.constants.get(sym)) |entry| {
        return entry.value.raw;
    }
    const val = vm.newModule(sym) catch return 0;
    vm.object_class.module.constants.put(sym, .{ .value = val }) catch return 0;
    return val.raw;
}

export fn rb_define_module_under(outer_raw: VALUE, name_ptr: [*c]const u8) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    const outer = Value{ .raw = outer_raw };
    const val = vm.newModule(sym) catch return 0;
    const mod = if (outer.isClass()) &outer.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(outer_raw));
    mod.constants.put(sym, .{ .value = val }) catch return 0;
    return val.raw;
}

export fn rb_define_class_under(outer_raw: VALUE, name_ptr: [*c]const u8, super_raw: VALUE) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    const super_class: ?*value.ClassObject = if (super_raw != 0) @ptrFromInt(super_raw) else null;
    const val = vm.newClass(sym, super_class) catch return 0;
    const outer = Value{ .raw = outer_raw };
    const mod = if (outer.isClass()) &outer.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(outer_raw));
    mod.constants.put(sym, .{ .value = val }) catch return 0;
    return val.raw;
}

export fn rb_define_alloc_func(klass_raw: VALUE, func: ?*anyopaque) void {
    if (klass_raw == 0 or func == null) return;
    const class_ptr: *value.ClassObject = @ptrFromInt(klass_raw);
    class_ptr.cext_alloc_func = func;
}

export fn rb_define_singleton_method(obj_raw: VALUE, name_ptr: [*c]const u8, func: ?*anyopaque, argc: c_int) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    if (name.len == 0 or func == null) return;
    const singleton = vm.getOrCreateSingletonClass(Value{ .raw = obj_raw }) catch return;
    const sym = vm.intern(name) catch return;
    const entry = value.MethodEntry{
        .method = .{ .cext = .{ .func = func.?, .argc = argc } },
        .visibility = .public,
    };
    singleton.module.methods.put(sym, entry) catch @panic("OOM in rb_define_singleton_method");
}

export fn rb_define_module_function(mod_raw: VALUE, name_ptr: [*c]const u8, func: ?*anyopaque, argc: c_int) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    if (name.len == 0 or func == null) return;
    const mod = Value{ .raw = mod_raw };
    const sym = vm.intern(name) catch return;
    const entry = value.MethodEntry{
        .method = .{ .cext = .{ .func = func.?, .argc = argc } },
        .visibility = .public,
    };
    if (mod.isClass()) {
        mod.toClassObject().module.methods.put(sym, entry) catch @panic("OOM");
    } else {
        const mod_obj: *value.ModuleObject = @ptrFromInt(mod_raw);
        mod_obj.methods.put(sym, entry) catch @panic("OOM");
    }
    vm.method_state_version += 1;
    // Also define as singleton method
    const singleton = vm.getOrCreateSingletonClass(mod) catch return;
    singleton.module.methods.put(sym, entry) catch @panic("OOM");
}

export fn rb_define_private_method(klass_raw: VALUE, name_ptr: [*c]const u8, func: ?*anyopaque, argc: c_int) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    if (klass_raw == 0 or name.len == 0 or func == null) return;
    const sym = vm.intern(name) catch return;
    const class_ptr: *value.ClassObject = @ptrFromInt(klass_raw);
    const entry = value.MethodEntry{
        .method = .{ .cext = .{ .func = func.?, .argc = argc } },
        .visibility = .private,
    };
    class_ptr.module.methods.put(sym, entry) catch @panic("OOM in rb_define_private_method");
    vm.method_state_version += 1;
}

// ─── Exceptions ─────────────────────────────────────────────────────────────

export fn rb_raise(exc_raw: VALUE, fmt: [*c]const u8, ...) void {
    const vm = getVM();
    const msg_raw = if (fmt != null) std.mem.span(fmt) else "";
    _ = vm.raiseExceptionFmt(@ptrFromInt(exc_raw), "{s}", .{msg_raw}) catch {};
}

export fn rb_exc_raise(exc_raw: VALUE) void {
    const vm = getVM();
    const val = Value{ .raw = exc_raw };
    vm.setPendingException(val.toExceptionObject());
}

export fn rb_exc_set_message(exc_raw: VALUE, msg_raw: VALUE) void {
    _ = exc_raw;
    _ = msg_raw;
}

export fn rb_protect(proc: ?*const fn (VALUE) callconv(.c) VALUE, data: VALUE, state: *c_int) VALUE {
    state.* = 0;
    if (proc) |p| {
        return p(data);
    }
    return 0;
}

export fn rb_ensure(b_proc: ?*const fn (VALUE) callconv(.c) VALUE, data1: VALUE, e_proc: ?*const fn (VALUE) callconv(.c) VALUE, data2: VALUE) VALUE {
    var result: VALUE = 0;
    if (b_proc) |bp| {
        result = bp(data1);
    }
    if (e_proc) |ep| {
        _ = ep(data2);
    }
    return result;
}

export fn rb_jump_tag(state: c_int) void {
    _ = state;
}

// ─── Argument scanning ──────────────────────────────────────────────────────

export fn rb_scan_args(argc: c_int, argv: [*c]const VALUE, fmt: [*c]const u8, ...) c_int {
    _ = argc;
    _ = argv;
    _ = fmt;
    return 0;
}

// ─── Encoding ───────────────────────────────────────────────────────────────

export fn rb_utf8_encoding() ?*anyopaque {
    return @constCast(&encoding_instances[@intFromEnum(enc.Encoding.utf8)]);
}

export fn rb_usascii_encoding() ?*anyopaque {
    return @constCast(&encoding_instances[@intFromEnum(enc.Encoding.us_ascii)]);
}

export fn rb_ascii8bit_encoding() ?*anyopaque {
    return @constCast(&encoding_instances[@intFromEnum(enc.Encoding.ascii_8bit)]);
}

export fn rb_default_internal_encoding() ?*anyopaque {
    const vm = getVM();
    if (vm.default_internal_encoding) |enc_obj| {
        return @constCast(&encoding_instances[@intFromEnum(enc_obj.encoding)]);
    }
    return null;
}

export fn rb_default_external_encoding() ?*anyopaque {
    const vm = getVM();
    const e = vm.default_external_encoding.encoding;
    return @constCast(&encoding_instances[@intFromEnum(e)]);
}

export fn rb_utf8_encindex() c_int {
    return @intFromEnum(enc.Encoding.utf8);
}

export fn rb_usascii_encindex() c_int {
    return @intFromEnum(enc.Encoding.us_ascii);
}

export fn rb_ascii8bit_encindex() c_int {
    return @intFromEnum(enc.Encoding.ascii_8bit);
}

export fn rb_enc_get_index(obj_raw: VALUE) c_int {
    const val = Value{ .raw = obj_raw };
    if (val.isString()) {
        return @intCast(@intFromEnum(val.toStringObject().encoding));
    }
    return @intFromEnum(enc.Encoding.us_ascii);
}

export fn rb_to_encoding_index(enc_val: VALUE) c_int {
    const val = Value{ .raw = enc_val };
    if (val.isEncoding()) {
        return @intCast(@intFromEnum(val.toEncodingObject().encoding));
    }
    return @intFromEnum(enc.Encoding.us_ascii);
}

export fn rb_enc_find_index(name: [*c]const u8) c_int {
    const s = if (name != null) std.mem.span(name) else "";
    var upper_buf: [64]u8 = undefined;
    const upper = std.ascii.upperString(&upper_buf, s);
    if (std.mem.eql(u8, upper, "UTF-8") or std.mem.eql(u8, upper, "UTF8")) return @intFromEnum(enc.Encoding.utf8);
    if (std.mem.eql(u8, upper, "US-ASCII") or std.mem.eql(u8, upper, "ASCII")) return @intFromEnum(enc.Encoding.us_ascii);
    if (std.mem.eql(u8, upper, "ASCII-8BIT") or std.mem.eql(u8, upper, "BINARY")) return @intFromEnum(enc.Encoding.ascii_8bit);
    if (std.mem.eql(u8, upper, "UTF-16LE")) return @intFromEnum(enc.Encoding.utf16le);
    if (std.mem.eql(u8, upper, "UTF-16BE")) return @intFromEnum(enc.Encoding.utf16be);
    if (std.mem.eql(u8, upper, "UTF-32LE")) return @intFromEnum(enc.Encoding.utf32le);
    if (std.mem.eql(u8, upper, "UTF-32BE")) return @intFromEnum(enc.Encoding.utf32be);
    if (std.mem.eql(u8, upper, "ISO-8859-1")) return @intFromEnum(enc.Encoding.iso_8859_1);
    return -1;
}

export fn rb_enc_associate_index(obj_raw: VALUE, idx: c_int) void {
    _ = obj_raw;
    _ = idx;
}

export fn rb_enc_get(obj_raw: VALUE) ?*anyopaque {
    return rb_enc_from_index(rb_enc_get_index(obj_raw));
}

export fn rb_enc_left_char_head(str: [*c]const u8, start: [*c]const u8, end: [*c]const u8, enc_ptr: ?*anyopaque) ?[*]u8 {
    _ = start;
    _ = end;
    _ = enc_ptr;
    return @constCast(str);
}

// ─── Memory ─────────────────────────────────────────────────────────────────

export fn xmalloc(size: usize) ?*anyopaque {
    const ptr = std.c.malloc(size);
    if (ptr == null) @panic("xmalloc: out of memory");
    return ptr;
}

export fn xcalloc(n: usize, size: usize) ?*anyopaque {
    const ptr = std.c.calloc(n, size);
    if (ptr == null) @panic("xcalloc: out of memory");
    return ptr;
}

export fn xrealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    const new_ptr = std.c.realloc(ptr, size);
    if (new_ptr == null) @panic("xrealloc: out of memory");
    return new_ptr;
}

export fn xfree(ptr: ?*anyopaque) void {
    std.c.free(ptr);
}

// ─── Type checking ──────────────────────────────────────────────────────────

export fn Check_Type(obj_raw: VALUE, t: c_int) void {
    _ = obj_raw;
    _ = t;
}

// ─── TypedData ──────────────────────────────────────────────────────────────

export fn TypedData_Wrap_Struct(klass_raw: VALUE, ty: ?*const anyopaque, data: ?*anyopaque) VALUE {
    const vm = getVM();
    _ = ty;
    const klass: *value.ClassObject = @ptrFromInt(klass_raw);
    const obj = vm.newInstance(klass) catch return 0;
    if (data) |d| {
        vm.setInstanceVariable(obj, "@data", Value.integer(@as(i64, @intCast(@intFromPtr(d))))) catch {};
    }
    return obj.raw;
}

export fn rb_data_typed_object_alloc(klass_raw: VALUE, ty: ?*const anyopaque) VALUE {
    _ = ty;
    return TypedData_Wrap_Struct(klass_raw, null, null);
}

export fn Check_TypedStruct(obj_raw: VALUE, ty: ?*const anyopaque) ?*anyopaque {
    _ = ty;
    const vm = getVM();
    const data_val = vm.getInstanceVariable(Value{ .raw = obj_raw }, "@data") catch return null;
    if (data_val.isInteger()) {
        return @ptrFromInt(@as(usize, @intCast(data_val.toInteger())));
    }
    return null;
}

// ─── Require ────────────────────────────────────────────────────────────────

export fn rb_require(name: [*c]const u8) void {
    const vm = getVM();
    var args = [_]Value{Value{ .raw = rb_str_new2(name) }};
    _ = vm.callMethodByName(vm.main_self, "require", &args, null) catch {};
}

export fn rb_path_to_class(path_raw: VALUE) VALUE {
    const vm = getVM();
    const val = Value{ .raw = path_raw };
    if (val.isString()) {
        const resolved = vm.resolveConstantPath(val.toStringObject().str) catch return 0;
        return if (resolved) |r| r.raw else 0;
    }
    return 0;
}

// ─── Integer conversion ─────────────────────────────────────────────────────

export fn RARRAY_LEN(ary_raw: VALUE) c_long {
    const val = Value{ .raw = ary_raw };
    const arr = val.toArrayObject();
    return @intCast(arr.elements.items.len);
}

export fn INT2NUM(v: c_long) VALUE {
    return Value.integer(v).raw;
}

export fn NUM2INT(v_raw: VALUE) c_long {
    const val = Value{ .raw = v_raw };
    return val.toInteger();
}

export fn NUM2LONG(v_raw: VALUE) c_long {
    return NUM2INT(v_raw);
}

export fn SIZET2NUM(v: usize) VALUE {
    return Value.integer(@intCast(v)).raw;
}

export fn LONG2NUM(v: c_long) VALUE {
    return INT2NUM(v);
}

export fn UINT2NUM(v: c_uint) VALUE {
    return Value.integer(v).raw;
}

export fn ULONG2NUM(v: c_ulong) VALUE {
    return Value.integer(@intCast(v)).raw;
}
