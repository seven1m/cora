const std = @import("std");
const value = @import("value.zig");
const Value = value.Value;
const StringObject = value.StringObject;
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const enc = @import("encoding.zig");
const cext_globals = @import("cext_globals.zig");
const onigmo = @import("onigmo.zig");

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

pub export var rb_cRational: VALUE = 0;
pub export var rb_mComparable: VALUE = 0;

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

    rb_cRational = Value.fromObject(&vm.rational_class.module.object).raw;
    const comparable_sym = vm.intern("Comparable") catch return;
    if (vm.object_class.module.constants.get(comparable_sym)) |entry| {
        rb_mComparable = entry.value.raw;
    }
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

fn allocMutableString(vm: *VM, len: usize) VALUE {
    const buf = vm.gc_allocator_atomic.alloc(u8, len) catch return 0;
    @memset(buf, 0);
    const string_obj = vm.gc_allocator.create(StringObject) catch return 0;
    string_obj.* = .{
        .object = .{ .type_tag = .string, .flags = 0, .class = vm.string_class, .singleton_class = null, .instance_variables = null },
        .str = buf,
        .encoding = .{ .utf8 = .{} },
    };
    return Value.fromObject(&string_obj.object).raw;
}

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

export fn rb_utf8_str_new(ptr: [*c]const u8, len: c_long) VALUE {
    return rb_str_new(ptr, len);
}

export fn rb_utf8_str_new_cstr(ptr: [*c]const u8) VALUE {
    return rb_str_new2(ptr);
}

export fn rb_str_buf_new(len: c_long) VALUE {
    const vm = getVM();
    return allocMutableString(vm, @intCast(@max(len, 0)));
}

export fn rb_str_set_len(str_raw: VALUE, len: c_long) void {
    if (len < 0) return;
    const str = Value{ .raw = str_raw };
    if (!str.isString()) return;
    const obj = str.toStringObject();
    const new_len: usize = @intCast(len);
    if (new_len <= obj.str.len) {
        obj.str = obj.str[0..new_len];
    }
}

export fn rb_str_tmp_new(len: c_long) VALUE {
    return rb_str_buf_new(len);
}

export fn rb_str_catf(str_raw: VALUE, fmt: [*c]const u8, ...) VALUE {
    if (fmt == null) return str_raw;
    const vm = getVM();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    const str = Value{ .raw = str_raw };
    if (str.isString()) {
        out.appendSlice(vm.allocator, str.toStringObject().str) catch return str_raw;
    }

    const fmt_slice = std.mem.span(fmt);
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var i: usize = 0;
    while (i < fmt_slice.len) : (i += 1) {
        if (fmt_slice[i] != '%') {
            out.append(vm.allocator, fmt_slice[i]) catch return str_raw;
            continue;
        }
        i += 1;
        if (i >= fmt_slice.len) break;
        if (fmt_slice[i] == '%') {
            out.append(vm.allocator, '%') catch return str_raw;
            continue;
        }
        if (fmt_slice[i] == 'l' and i + 1 < fmt_slice.len and fmt_slice[i + 1] == 'd') {
            const val = @cVaArg(&ap, c_long);
            out.print(vm.allocator, "{d}", .{val}) catch return str_raw;
            i += 1;
            continue;
        }
        if (fmt_slice[i] == 's') {
            const cstr = @cVaArg(&ap, [*c]const u8);
            out.appendSlice(vm.allocator, if (cstr != null) std.mem.span(cstr) else "") catch return str_raw;
            continue;
        }
        if (fmt_slice[i] == 'c') {
            const ch = @cVaArg(&ap, c_int);
            out.append(vm.allocator, @intCast(ch)) catch return str_raw;
            continue;
        }
        out.append(vm.allocator, fmt_slice[i]) catch return str_raw;
    }

    const result = vm.newString(out.items, false) catch return str_raw;
    return result.raw;
}

export fn rb_str_intern(str_raw: VALUE) VALUE {
    const vm = getVM();
    const str = Value{ .raw = str_raw };
    if (!str.isString()) return 0;
    const sym = vm.intern(str.toStringObject().str) catch return 0;
    return Value.fromObject(&sym.object).raw;
}

export fn rb_str_concat(str_raw: VALUE, str2_raw: VALUE) VALUE {
    return rb_str_append(str_raw, str2_raw);
}

export fn rb_str_substr(str_raw: VALUE, beg: c_long, len: c_long) VALUE {
    return rb_str_subseq(str_raw, beg, len);
}

export fn rb_str_new_shared(str_raw: VALUE) VALUE {
    return rb_str_dup(str_raw);
}

export fn rb_str_freeze(str_raw: VALUE) VALUE {
    return rb_obj_freeze(str_raw);
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

export fn rb_str_cat2(str_raw: VALUE, ptr: [*c]const u8) VALUE {
    if (ptr == null) return str_raw;
    return rb_str_cat(str_raw, ptr, @intCast(std.mem.span(ptr).len));
}

export fn rb_str_dump(str_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "dump", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_sprintf(fmt: [*c]const u8, ...) VALUE {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    if (fmt == null) return 0;
    const vm = getVM();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    const s = std.mem.span(fmt);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '%') {
            out.append(vm.allocator, s[i]) catch return 0;
            continue;
        }
        i += 1;
        if (i >= s.len) break;
        if (s[i] == '%') {
            out.append(vm.allocator, '%') catch return 0;
            continue;
        }
        if (s[i] == 'l' and i + 1 < s.len and s[i + 1] == 'd') {
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{@cVaArg(&ap, c_long)}) catch return 0;
            out.appendSlice(vm.allocator, rendered) catch return 0;
            i += 1;
            continue;
        }
        if (s[i] == 'd') {
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{@cVaArg(&ap, c_int)}) catch return 0;
            out.appendSlice(vm.allocator, rendered) catch return 0;
            continue;
        }
        if (s[i] == 's') {
            const ptr = @cVaArg(&ap, [*c]const u8);
            out.appendSlice(vm.allocator, if (ptr != null) std.mem.span(ptr) else "(null)") catch return 0;
            continue;
        }
        out.append(vm.allocator, '%') catch return 0;
        out.append(vm.allocator, s[i]) catch return 0;
    }
    const str_val = vm.newString(out.items, false) catch return 0;
    return str_val.raw;
}

export fn rb_vsprintf(fmt: [*c]const u8, ap: std.builtin.VaList) VALUE {
    _ = ap;
    if (fmt == null) return 0;
    const vm = getVM();
    const str_val = vm.newString(std.mem.span(fmt), false) catch return 0;
    return str_val.raw;
}

export fn rb_sym2str(symbol_raw: VALUE) VALUE {
    const vm = getVM();
    const symbol = Value{ .raw = symbol_raw };
    if (!symbol.isSymbol()) return 0;
    const str_val = vm.newString(symbol.toSymbolObject().name, false) catch return 0;
    return str_val.raw;
}

export fn rb_check_hash_type(obj_raw: VALUE) VALUE {
    const vm = getVM();
    const obj = Value{ .raw = obj_raw };
    return switch (vm.probeToHash(obj) catch return 0) {
        .hash => |hash| hash.raw,
        else => Value.NIL.raw,
    };
}

export fn rb_get_kwargs(keyword_hash_raw: VALUE, table: [*c]const c_ulong, required: c_int, optional: c_int, values: [*c]VALUE) c_int {
    const vm = getVM();
    const keyword_hash = Value{ .raw = keyword_hash_raw };
    if (!keyword_hash.isHash() or values == null) return 0;

    const total: usize = @intCast(@max(required + optional, 0));
    var found: c_int = 0;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        values[i] = Value.NIL.raw;
        const key_raw = table[i];
        const key = Value{ .raw = key_raw };
        const value_raw = rb_hash_aref(keyword_hash_raw, key.raw);
        if (value_raw != Value.NIL.raw) {
            values[i] = value_raw;
            found += 1;
            continue;
        }
        if (required > 0 and i < @as(usize, @intCast(required))) {
            const name = if (key.isSymbol()) key.toSymbolObject().name else "keyword";
            _ = vm.raiseExceptionFmt(vm.argument_error_class, "missing keyword: {s}", .{name}) catch {};
            return -1;
        }
    }
    return found;
}

export fn rb_memerror() void {
    const vm = getVM();
    _ = vm.raiseExceptionFmt(vm.standard_error_class, "failed to allocate memory", .{}) catch {};
}

export fn rb_enc_strlen(head: [*c]const u8, tail: [*c]const u8, enc_ptr: ?*anyopaque) c_long {
    if (head == null or tail == null) return 0;
    const opaque_ptr: *anyopaque = enc_ptr orelse @ptrCast(@constCast(&encoding_instances[0]));
    const enc_obj: *const enc.Encoding = @ptrCast(@alignCast(opaque_ptr));
    var p = head;
    var len: c_long = 0;
    while (@intFromPtr(p) < @intFromPtr(tail)) {
        const remaining: usize = @intFromPtr(tail) - @intFromPtr(p);
        var byte_index: usize = 0;
        const result = enc_obj.nextCodepoint(p[0..remaining], &byte_index);
        p += if (result.len > 0) result.len else 1;
        len += 1;
    }
    return len;
}

export fn rb_enc_mbclen(p: [*c]const u8, e: [*c]const u8, enc_ptr: ?*anyopaque) c_int {
    if (p == null or e == null or @intFromPtr(p) >= @intFromPtr(e)) return 0;
    var len_out: c_int = 0;
    _ = rb_enc_codepoint_len(@ptrCast(p), @ptrCast(e), &len_out, enc_ptr);
    return len_out;
}

export fn rb_enc_check(str1_raw: VALUE, str2_raw: VALUE) ?*anyopaque {
    _ = str2_raw;
    return rb_enc_get(str1_raw);
}

export fn rb_memsearch(x0: ?*const anyopaque, m: c_long, y0: ?*const anyopaque, n: c_long, enc_ptr: ?*anyopaque) c_long {
    _ = enc_ptr;
    if (x0 == null or y0 == null or m < 0 or n < 0) return -1;
    const needle_len: usize = @intCast(m);
    const haystack_len: usize = @intCast(n);
    const needle: []const u8 = @as([*]const u8, @ptrCast(x0.?))[0..needle_len];
    const haystack: []const u8 = @as([*]const u8, @ptrCast(y0.?))[0..haystack_len];
    const idx = std.mem.indexOf(u8, haystack, needle) orelse return -1;
    return @intCast(idx);
}

export fn rb_must_asciicompat(obj_raw: VALUE) void {
    const obj = Value{ .raw = obj_raw };
    if (!obj.isString()) return;
    if (!obj.toStringObject().encoding.isAsciiCompatible()) {
        const vm = getVM();
        _ = vm.raiseExceptionFmt(vm.encoding_error_class, "ASCII incompatible encoding", .{}) catch {};
    }
}

export fn rb_enc_raise(enc_ptr: ?*anyopaque, exc_raw: VALUE, fmt: [*c]const u8, ...) void {
    _ = enc_ptr;
    if (fmt == null) return;
    const vm = getVM();
    const exc: *value.ClassObject = @ptrFromInt(exc_raw);
    _ = vm.raiseExceptionFmt(exc, "{s}", .{std.mem.span(fmt)}) catch {};
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

export fn rb_ary_new_from_values(n: c_long, elts: [*c]const VALUE) VALUE {
    return rb_ary_new4(n, elts);
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

extern fn siglongjmp(buf: *anyopaque, val: c_int) noreturn;
extern fn __sigsetjmp(buf: *anyopaque, savesigs: c_int) c_int;
fn checkNLR(vm: *VM) void {
    if (vm.cext_jmp_buf) |buf| {
        if (vm.pendingControlFlow() != null) siglongjmp(buf, 1);
    }
}

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
    const saved_frame_count = vm.frames.items.len;
    const result = vm.callMethodByName(Value{ .raw = recv_raw }, name, args, null) catch |err| switch (err) {
        error.Unwind => { checkNLR(vm); return 0; },
        else => return 0,
    };
    checkNLR(vm);
    if (vm.frames.items.len < saved_frame_count) {
        checkNLR(vm);
    }
    return result.raw;
}

export fn rb_funcallv(recv_raw: VALUE, mid: VALUE, argc: c_int, argv: [*c]const VALUE) VALUE {
    const vm = getVM();
    const name = symName(mid);
    const args: []Value = if (argv != null and argc > 0)
        @as([*]Value, @ptrCast(@constCast(argv)))[0..@intCast(argc)]
    else
        &[_]Value{};
    const saved_frame_count = vm.frames.items.len;
    const result = vm.callMethodByName(Value{ .raw = recv_raw }, name, args, null) catch |err| switch (err) {
        error.Unwind => { checkNLR(vm); return 0; },
        else => return 0,
    };
    checkNLR(vm);
    if (vm.frames.items.len < saved_frame_count) {
        checkNLR(vm);
    }
    return result.raw;
}

export fn rb_proc_call_with_block(recv_raw: VALUE, argc: c_int, argv: [*c]const VALUE, block_raw: VALUE) VALUE {
    _ = block_raw;
    return rb_funcallv(recv_raw, rb_intern("call"), argc, argv);
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
    const method_name_sym = vm.intern(name) catch return 0;
    const resolved = vm.findMethod(Value{ .raw = obj_raw }, method_name_sym) catch return 0;
    if (resolved) |method| {
        return @intFromBool(method.entry.visibility != .private);
    }
    return 0;
}

export fn rb_class_of(obj_raw: VALUE) VALUE {
    const vm = getVM();
    return Value.fromObject(&vm.getClass(Value{ .raw = obj_raw }).module.object).raw;
}

export fn rb_type(obj_raw: VALUE) c_int {
    const val = Value{ .raw = obj_raw };
    if (val.isNil()) return 0x11;
    if (val.isBool()) return if (val.toBool()) 0x12 else 0x13;
    if (val.isInteger()) return 0x15;
    if (val.isSymbol()) return 0x14;
    if (val.isFloat()) return 0x04;
    return switch (val.objectTypeTag()) {
        .string => 0x05,
        .regexp => 0x06,
        .array => 0x07,
        .hash => 0x08,
        .class => 0x02,
        .module => 0x03,
        .match_data => 0x0d,
        .rational => 0x0f,
        else => 0x01,
    };
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
    vm.setConstant(mod, sym, Value{ .raw = val_raw }) catch return;
}

export fn rb_const_defined(klass_raw: VALUE, id: VALUE) c_int {
    const vm = getVM();
    const name = symName(id);
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else if (klass.raw == rb_cModule) @as(*value.ModuleObject, @ptrFromInt(klass_raw)) else return 0;
    const sym = vm.intern(name) catch return 0;
    return @intFromBool(mod.constants.contains(sym));
}

export fn rb_const_set(klass_raw: VALUE, id: VALUE, val_raw: VALUE) void {
    const vm = getVM();
    const name = symName(id);
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else if (klass.raw == rb_cModule) @as(*value.ModuleObject, @ptrFromInt(klass_raw)) else return;
    const sym = vm.intern(name) catch return;
    vm.setConstant(mod, sym, Value{ .raw = val_raw }) catch return;
}

export fn rb_alias(klass_raw: VALUE, dst: VALUE, src: VALUE) void {
    const vm = getVM();
    const dst_name = symName(dst);
    const src_name = symName(src);
    const dst_sym = vm.intern(dst_name) catch return;
    const src_sym = vm.intern(src_name) catch return;
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(klass_raw));
    if (mod.methods.get(src_sym)) |entry| {
        mod.methods.put(dst_sym, entry) catch return;
    }
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
    vm.setConstant(&vm.object_class.module, sym, val) catch return 0;
    return val.raw;
}

export fn rb_define_module_under(outer_raw: VALUE, name_ptr: [*c]const u8) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    const outer = Value{ .raw = outer_raw };
    const mod = if (outer.isClass()) &outer.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(outer_raw));
    if (mod.constants.get(sym)) |entry| {
        return entry.value.raw;
    }
    const val = vm.newModule(sym) catch return 0;
    vm.setConstant(mod, sym, val) catch return 0;
    return val.raw;
}

export fn rb_define_class_under(outer_raw: VALUE, name_ptr: [*c]const u8, super_raw: VALUE) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    const outer = Value{ .raw = outer_raw };
    const mod = if (outer.isClass()) &outer.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(outer_raw));
    if (mod.constants.get(sym)) |entry| {
        return entry.value.raw;
    }
    const super_class: ?*value.ClassObject = if (super_raw != 0) @ptrFromInt(super_raw) else null;
    const val = vm.newClass(sym, super_class) catch return 0;
    vm.setConstant(mod, sym, val) catch return 0;
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
    if (vm.cext_jmp_buf) |buf| {
        siglongjmp(buf, 1);
    }
}

export fn rb_exc_raise(exc_raw: VALUE) void {
    const vm = getVM();
    const val = Value{ .raw = exc_raw };
    vm.setPendingException(val.toExceptionObject());
    if (vm.cext_jmp_buf) |buf| {
        siglongjmp(buf, 1);
    }
}

export fn rb_exc_set_message(exc_raw: VALUE, msg_raw: VALUE) void {
    const exc = Value{ .raw = exc_raw };
    const msg = Value{ .raw = msg_raw };
    if (!exc.isException() or !msg.isString()) return;
    exc.toExceptionObject().message = msg.toStringObject();
}

export fn rb_exc_new_str(klass_raw: VALUE, msg_raw: VALUE) VALUE {
    const vm = getVM();
    const msg = Value{ .raw = msg_raw };
    if (!msg.isString()) return 0;
    const klass: *value.ClassObject = @ptrFromInt(klass_raw);
    const exc = vm.createException(klass, msg.toStringObject().str) catch return 0;
    return Value.fromObject(&exc.object).raw;
}

export fn rb_protect(proc: ?*const fn (VALUE) callconv(.c) VALUE, data: VALUE, state: *c_int) VALUE {
    const vm = getVM();
    state.* = 0;
    var jmp_buf: [200]u8 align(@alignOf(c_int)) = @splat(0);
    const prev_jmp = vm.cext_jmp_buf;
    vm.cext_jmp_buf = &jmp_buf;
    defer vm.cext_jmp_buf = prev_jmp;

    if (__sigsetjmp(&jmp_buf, 0) == 0) {
        if (proc) |p| {
            return p(data);
        }
        return 0;
    }
    state.* = 1;
    return Value.NIL.raw;
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

export fn rb_rescue(
    b_proc: ?*const fn (VALUE) callconv(.c) VALUE,
    data1: VALUE,
    r_proc: ?*const fn (VALUE, VALUE) callconv(.c) VALUE,
    data2: VALUE,
) VALUE {
    const vm = getVM();
    const result = if (b_proc) |bp| bp(data1) else 0;
    if (vm.pendingException()) |exc| {
        vm.setPendingException(null);
        if (r_proc) |rp| {
            return rp(data2, Value.fromObject(&exc.object).raw);
        }
    }
    return result;
}

export fn rb_jump_tag(state: c_int) void {
    if (state == 0) return;
    const vm = getVM();
    if (vm.cext_jmp_buf) |buf| {
        siglongjmp(buf, 1);
    }
}

// ─── Argument scanning ──────────────────────────────────────────────────────

export fn rb_scan_args(argc: c_int, argv: [*c]const VALUE, fmt: [*c]const u8, ...) c_int {
    const fmt_slice = if (fmt != null) std.mem.span(fmt) else "";
    var required: usize = 0;
    var optional: usize = 0;

    if (fmt_slice.len > 0 and std.ascii.isDigit(fmt_slice[0])) {
        required = @intCast(fmt_slice[0] - '0');
    }
    if (fmt_slice.len > 1 and std.ascii.isDigit(fmt_slice[1])) {
        optional = @intCast(fmt_slice[1] - '0');
    }

    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var consumed: usize = 0;
    var i: usize = 0;
    while (i < required) : (i += 1) {
        const out: *VALUE = @cVaArg(&ap, *VALUE);
        if (@as(usize, @intCast(argc)) > consumed and argv != null) {
            out.* = argv[consumed];
            consumed += 1;
        } else {
            out.* = Value.NIL.raw;
        }
    }

    i = 0;
    while (i < optional) : (i += 1) {
        const out: *VALUE = @cVaArg(&ap, *VALUE);
        if (@as(usize, @intCast(argc)) > consumed and argv != null) {
            out.* = argv[consumed];
            consumed += 1;
        } else {
            out.* = Value.NIL.raw;
        }
    }

    return argc;
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

export fn rb_enc_associate_index(obj_raw: VALUE, idx: c_int) VALUE {
    _ = idx;
    return obj_raw;
}

export fn rb_enc_get(obj_raw: VALUE) ?*anyopaque {
    return rb_enc_from_index(rb_enc_get_index(obj_raw));
}

export fn rb_enc_left_char_head(str: [*c]const u8, start: [*c]const u8, end: [*c]const u8, enc_ptr: ?*anyopaque) ?[*]u8 {
    const str_addr = @intFromPtr(str);
    const start_addr = @intFromPtr(start);
    const end_addr = @intFromPtr(end);

    if (start_addr <= str_addr) return @constCast(str);
    if (end_addr <= str_addr) return @constCast(str);

    const slice_len = end_addr - str_addr;
    const offset = @min(start_addr - str_addr, slice_len);
    if (offset == 0) return @constCast(str);

    const opaque_ptr: *anyopaque = enc_ptr orelse @ptrCast(@constCast(&encoding_instances[0]));
    const encoding: *const enc.Encoding = @ptrCast(@alignCast(opaque_ptr));
    const slice = str[0..slice_len];

    if (encoding.isSingleByte()) {
        return @constCast(str + offset);
    }

    var i: usize = 0;
    var last_boundary: usize = 0;
    while (i < offset) {
        last_boundary = i;
        const result = encoding.nextChar(slice, &i);
        if (result.len == 0) return @constCast(str + last_boundary);
        if (i > offset) return @constCast(str + last_boundary);
    }

    if (i == offset) return @constCast(str + offset);
    return @constCast(str + last_boundary);
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

export fn ruby_xmalloc(size: usize) ?*anyopaque {
    return xmalloc(size);
}

export fn ruby_xcalloc(n: usize, size: usize) ?*anyopaque {
    return xcalloc(n, size);
}

export fn ruby_xrealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return xrealloc(ptr, size);
}

export fn ruby_xrealloc2(ptr: ?*anyopaque, n: usize, size: usize) ?*anyopaque {
    return xrealloc(ptr, n * size);
}

export fn ruby_xfree(ptr: ?*anyopaque) void {
    xfree(ptr);
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

// ─── Yield ─────────────────────────────────────────────────────────────────

export fn rb_yield(val_raw: VALUE) VALUE {
    const vm = getVM();
    const current_frame = vm.currentFrame();
    if (current_frame.block) |blk| {
        const saved_frame_count = vm.frames.items.len;
        const result = vm.yieldToBlock(blk, &[_]Value{Value{ .raw = val_raw }}) catch |err| switch (err) {
            error.Unwind => { checkNLR(vm); return 0; },
            else => return 0,
        };
        if (result.non_local_return_occurred) {
            checkNLR(vm);
        }
        if (vm.frames.items.len < saved_frame_count) {
            checkNLR(vm);
        }
        return result.value.raw;
    }
    return 0;
}

export fn rb_yield_values(n: c_int, ...) VALUE {
    _ = n;
    return 0;
}

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

// ─── Module/class definition continued ──────────────────────────────────────

export fn rb_define_class(name_ptr: [*c]const u8, super_raw: VALUE) VALUE {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return 0;
    if (vm.object_class.module.constants.get(sym)) |entry| {
        return entry.value.raw;
    }
    const super_class: ?*value.ClassObject = if (super_raw != 0) @ptrFromInt(super_raw) else null;
    const val = vm.newClass(sym, super_class) catch return 0;
    vm.setConstant(&vm.object_class.module, sym, val) catch return 0;
    return val.raw;
}

export fn rb_include_module(klass_raw: VALUE, module_raw: VALUE) void {
    const vm = getVM();
    const klass = Value{ .raw = klass_raw };
    const target_mod = if (klass.isClass()) &klass.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(klass_raw));
    const module_mod: *value.ModuleObject = @ptrFromInt(module_raw);
    vm.includeModule(target_mod, module_mod) catch return;
}

export fn rb_define_alias(klass_raw: VALUE, new_name_ptr: [*c]const u8, old_name_ptr: [*c]const u8) void {
    const vm = getVM();
    const new_name = std.mem.span(new_name_ptr);
    const old_name = std.mem.span(old_name_ptr);
    const new_sym = vm.intern(new_name) catch return;
    const old_sym = vm.intern(old_name) catch return;
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(klass_raw));
    if (mod.methods.get(old_sym)) |entry| {
        mod.methods.put(new_sym, entry) catch return;
    }
}

export fn rb_singleton_class(obj_raw: VALUE) VALUE {
    const vm = getVM();
    const singleton = vm.getOrCreateSingletonClass(Value{ .raw = obj_raw }) catch return 0;
    return Value.fromObject(&singleton.module.object).raw;
}

// ─── Object type checking ────────────────────────────────────────────────────

export fn rb_obj_is_kind_of(obj_raw: VALUE, klass_raw: VALUE) VALUE {
    const vm = getVM();
    var args = [_]Value{Value{ .raw = klass_raw }};
    const result = vm.callMethodByName(Value{ .raw = obj_raw }, "kind_of?", &args, null) catch return 0;
    return result.raw;
}

export fn rb_cmpint(val_raw: VALUE, a_raw: VALUE, b_raw: VALUE) VALUE {
    _ = a_raw;
    _ = b_raw;
    const vm = getVM();
    const val = Value{ .raw = val_raw };
    if (val.isNil()) return 0;
    if (!val.isInteger()) {
        _ = vm.raiseExceptionFmt(@ptrFromInt(rb_eArgError), "comparison failed", .{}) catch {};
        return 0;
    }
    return val_raw;
}

// ─── Hash functions ──────────────────────────────────────────────────────────

export fn rb_hash_new() VALUE {
    const vm = getVM();
    const hash_obj = vm.createHash() catch return 0;
    return Value.fromObject(&hash_obj.object).raw;
}

export fn rb_hash_new_capa(capa: c_long) VALUE {
    _ = capa;
    return rb_hash_new();
}

export fn rb_hash_aref(hash_raw: VALUE, key_raw: VALUE) VALUE {
    const vm = getVM();
    const val = Value{ .raw = hash_raw };
    const hash_obj = val.toHashObject();
    const entry = vm.hashGetEntry(hash_obj, Value{ .raw = key_raw }) catch return 0;
    return if (entry) |e| e.value.raw else 0;
}

export fn rb_hash_aset(hash_raw: VALUE, key_raw: VALUE, val_raw: VALUE) VALUE {
    const vm = getVM();
    const val = Value{ .raw = hash_raw };
    const hash_obj = val.toHashObject();
    vm.hashSetEntry(hash_obj, Value{ .raw = key_raw }, Value{ .raw = val_raw }) catch return 0;
    return val_raw;
}

export fn rb_hash_delete(hash_raw: VALUE, key_raw: VALUE) VALUE {
    const vm = getVM();
    const val = Value{ .raw = hash_raw };
    const hash_obj = val.toHashObject();
    const deleted = vm.hashDeleteEntry(hash_obj, Value{ .raw = key_raw }) catch return 0;
    return if (deleted) |v| v.raw else 0;
}

export fn rb_hash_size(hash_raw: VALUE) c_long {
    const hash = Value{ .raw = hash_raw };
    if (!hash.isHash()) return 0;
    return @intCast(hash.toHashObject().entries.items.len);
}

export fn rb_hash_foreach(hash_raw: VALUE, func: ?*const fn (VALUE, VALUE, VALUE) callconv(.c) c_int, arg: VALUE) c_int {
    const hash = Value{ .raw = hash_raw };
    if (!hash.isHash() or func == null) return 0;
    for (hash.toHashObject().entries.items) |entry| {
        const result = func.?(entry.key.raw, entry.value.raw, arg);
        if (result != 0) return result;
    }
    return 0;
}

export fn rb_hash_bulk_insert(argc: c_long, argv: [*c]const VALUE, hash_raw: VALUE) void {
    if (argv == null or argc <= 0) return;
    var i: c_long = 0;
    while (i + 1 < argc) : (i += 2) {
        _ = rb_hash_aset(hash_raw, argv[@intCast(i)], argv[@intCast(i + 1)]);
    }
}

// ─── String functions continued ──────────────────────────────────────────────

export fn rb_str_append(str_raw: VALUE, str2_raw: VALUE) VALUE {
    const vm = getVM();
    var args = [_]Value{Value{ .raw = str2_raw }};
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "<<", &args, null) catch return str_raw;
    return result.raw;
}

export fn rb_str_dup(str_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "dup", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_str_cat(str_raw: VALUE, ptr: [*c]const u8, len: c_long) VALUE {
    if (ptr == null or len <= 0) return str_raw;
    const vm = getVM();
    const s = ptr[0..@intCast(len)];
    const str_val = vm.newString(s, false) catch return 0;
    var args = [_]Value{str_val};
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "<<", &args, null) catch return str_raw;
    return result.raw;
}

export fn rb_hash(obj_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = obj_raw }, "to_hash", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_float_new(v: f64) VALUE {
    const vm = getVM();
    const float_obj = vm.gc_allocator.create(value.FloatObject) catch return 0;
    float_obj.* = .{
        .object = .{ .type_tag = .float, .flags = 0, .class = vm.float_class, .singleton_class = null, .instance_variables = null },
        .val = v,
    };
    return Value.fromObject(&float_obj.object).raw;
}

export fn rb_enc_str_asciicompat_p(str_raw: VALUE) VALUE {
    _ = str_raw;
    return Value.TRUE.raw;
}

export fn rb_enc_str_coderange(str_raw: VALUE) c_int {
    const str = Value{ .raw = str_raw };
    if (!str.isString()) return 0;
    return if (str.toStringObject().encoding.isAsciiCompatible()) 2 else 0;
}

export fn rb_str_to_inum(str_raw: VALUE, base: c_int, badcheck: c_int) VALUE {
    const vm = getVM();
    var args = [_]Value{ Value.integer(base) };
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "to_i", &args, null) catch return 0;
    _ = badcheck;
    return result.raw;
}

export fn rb_str_subseq(str_raw: VALUE, beg: c_long, len: c_long) VALUE {
    const vm = getVM();
    var args = [_]Value{ Value.integer(beg), Value.integer(len) };
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "[]", &args, null) catch return 0;
    return result.raw;
}

export fn rb_str_new_frozen(str_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = str_raw }, "freeze", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_strlen_lit(ptr: [*c]const u8) c_long {
    if (ptr == null) return 0;
    return @intCast(std.mem.sliceTo(ptr, 0).len);
}

// ─── Regex ──────────────────────────────────────────────────────────────────

export fn rb_reg_new(source: [*c]const u8, len: c_long, options: c_int) VALUE {
    const vm = getVM();
    const s = if (source != null) source[0..@intCast(len)] else "";
    _ = options;
    var args = [_]Value{vm.newString(s, false) catch return 0};
    const result = vm.callMethodByName(vm.main_self, "Regexp", &args, null) catch return 0;
    return result.raw;
}

export fn rb_reg_nth_match(nth: c_long, match_raw: VALUE) VALUE {
    const vm = getVM();
    var args = [_]Value{ Value.integer(nth) };
    const result = vm.callMethodByName(Value{ .raw = match_raw }, "[]", &args, null) catch return 0;
    return result.raw;
}

export fn cora_rregexp_ptr(regexp_raw: VALUE) onigmo.OnigRegex {
    const regexp = Value{ .raw = regexp_raw };
    return regexp.toRegexpObject().regex;
}

export fn rb_reg_onig_match(
    re_raw: VALUE,
    str_raw: VALUE,
    match_fn: ?*const fn (reg: onigmo.OnigRegex, str: VALUE, regs: ?*anyopaque, args: ?*anyopaque) callconv(.c) isize,
    args: ?*anyopaque,
    regs: ?*anyopaque,
) isize {
    if (match_fn == null) return 0;
    const regexp = Value{ .raw = re_raw };
    const result = match_fn.?(regexp.toRegexpObject().regex, str_raw, regs, args);
    if (result < 0 and result != -1) {
        const vm = getVM();
        _ = vm.raiseExceptionFmt(vm.runtime_error_class, "regexp buffer overflow", .{}) catch {};
    }
    return result;
}

// ─── Warnings ────────────────────────────────────────────────────────────────

export fn rb_warn(fmt: [*c]const u8, ...) void {
    if (fmt == null) return;
    const msg = std.mem.span(fmt);
    const vm = getVM();
    var args = [_]Value{vm.newString(msg, false) catch return};
    _ = vm.callMethodByName(vm.main_self, "warn", &args, null) catch {};
}

export fn rb_warning(fmt: [*c]const u8, ...) c_int {
    _ = fmt;
    return 1;
}

export fn rb_usascii_str_new(ptr: [*c]const u8, len: c_long) VALUE {
    return rb_str_new(ptr, len);
}

export fn rb_float_value(v: VALUE) f64 {
    const val = Value{ .raw = v };
    if (val.isFloat()) {
        return val.toFloatObject().val;
    }
    return 0.0;
}

export fn rb_num2dbl(v: VALUE) f64 {
    const val = Value{ .raw = v };
    if (val.isFloat()) {
        return val.toFloatObject().val;
    }
    if (val.isInteger()) {
        return @floatFromInt(val.toInteger());
    }
    if (val.isRational()) {
        const rat = val.toRationalObject();
        const num = Value{ .raw = rat.numerator.raw };
        const den = Value{ .raw = rat.denominator.raw };
        if (num.isInteger() and den.isInteger()) {
            return @as(f64, @floatFromInt(num.toInteger())) / @as(f64, @floatFromInt(den.toInteger()));
        }
    }
    return 0.0;
}

export fn rb_cstr_to_dbl(str: [*c]const u8, badcheck: c_int) f64 {
    _ = badcheck;
    if (str == null) return 0.0;
    return std.fmt.parseFloat(f64, std.mem.span(str)) catch 0.0;
}

// ─── Array ───────────────────────────────────────────────────────────────────

export fn rb_ary_freeze(ary_raw: VALUE) VALUE {
    const vm = getVM();
    _ = vm.callMethodByName(Value{ .raw = ary_raw }, "freeze", &[_]Value{}, null) catch {};
    return ary_raw;
}

export fn rb_ary_new2(len: c_long) VALUE {
    _ = len;
    return rb_ary_new();
}

export fn rb_inspect(obj_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = obj_raw }, "inspect", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_class_name(klass_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = klass_raw }, "name", &[_]Value{}, null) catch return 0;
    return result.raw;
}

export fn rb_convert_type(obj_raw: VALUE, t: c_int, tname: [*c]const u8, method: [*c]const u8) VALUE {
    _ = tname;
    const vm = getVM();
    const meth = if (method != null) std.mem.span(method) else return 0;
    const result = vm.callMethodByName(Value{ .raw = obj_raw }, meth, &[_]Value{}, null) catch return 0;
    if (rb_type(result.raw) != t) return 0;
    return result.raw;
}

export fn rb_obj_hide(obj_raw: VALUE) VALUE {
    return obj_raw;
}

export fn rb_proc_arity(proc_raw: VALUE) c_int {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = proc_raw }, "arity", &[_]Value{}, null) catch return 0;
    if (result.isInteger()) return @intCast(result.toInteger());
    return 0;
}

export fn rb_errinfo() VALUE {
    const vm = getVM();
    if (vm.pendingException()) |exc| return Value.fromObject(&exc.object).raw;
    return Value.NIL.raw;
}

export fn rb_set_errinfo(val_raw: VALUE) void {
    const vm = getVM();
    const val = Value{ .raw = val_raw };
    if (val.isNil()) {
        vm.setPendingException(null);
    } else if (val.isException()) {
        vm.setPendingException(val.toExceptionObject());
    }
}

export fn rb_global_variable(obj: *VALUE) void {
    _ = obj;
}

export fn rb_gc_mark_movable(ptr: VALUE) void {
    _ = ptr;
}

export fn rb_gc_location(ptr: VALUE) VALUE {
    return ptr;
}

export fn rb_io_write(io_raw: VALUE, str_raw: VALUE) VALUE {
    const vm = getVM();
    var args = [_]Value{Value{ .raw = str_raw }};
    const result = vm.callMethodByName(Value{ .raw = io_raw }, "write", &args, null) catch return 0;
    return result.raw;
}

export fn rb_io_flush(io_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(Value{ .raw = io_raw }, "flush", &[_]Value{}, null) catch return io_raw;
    return result.raw;
}

export fn rb_obj_frozen_p(obj_raw: VALUE) c_int {
    const obj = Value{ .raw = obj_raw };
    return @intFromBool(obj.isFrozen());
}

export fn rb_struct_get(obj_raw: VALUE, idx: c_long) VALUE {
    const vm = getVM();
    var args = [_]Value{Value.integer(idx)};
    const result = vm.callMethodByName(Value{ .raw = obj_raw }, "[]", &args, null) catch return 0;
    return result.raw;
}

// ─── Freeze / check frozen ───────────────────────────────────────────────────

export fn rb_obj_freeze(obj_raw: VALUE) VALUE {
    const vm = getVM();
    _ = vm.callMethodByName(Value{ .raw = obj_raw }, "freeze", &[_]Value{}, null) catch {};
    return obj_raw;
}

export fn rb_str_modify(str_raw: VALUE) void {
    _ = str_raw;
}

export fn rb_check_frozen(obj_raw: VALUE) void {
    const val = Value{ .raw = obj_raw };
    if (val.isFrozen()) {
        const vm = getVM();
        _ = vm.raiseExceptionFmt(@ptrFromInt(rb_eFrozenError), "can't modify frozen object", .{}) catch {};
    }
}

export fn rb_check_arity(argc: c_int, min: c_int, max: c_int) void {
    _ = argc;
    _ = min;
    _ = max;
}

export fn rb_check_typeddata(obj_raw: VALUE, data_type: ?*const anyopaque) ?*anyopaque {
    _ = data_type;
    const vm = getVM();
    const data_val = vm.getInstanceVariable(Value{ .raw = obj_raw }, "@data") catch return null;
    if (data_val.isInteger()) {
        return @ptrFromInt(@as(usize, @intCast(data_val.toInteger())));
    }
    return null;
}

// ─── GC ──────────────────────────────────────────────────────────────────────

export fn rb_gc_mark(ptr: VALUE) void {
    _ = ptr;
}

export fn rb_gc_register_mark_object(obj: VALUE) void {
    _ = obj;
}

// ─── Marshal ─────────────────────────────────────────────────────────────────

export fn rb_marshal_load(source_raw: VALUE) VALUE {
    const vm = getVM();
    const result = vm.callMethodByName(vm.main_self, "Marshal", &[_]Value{}, null) catch return 0;
    if (result.raw == 0) return 0;
    var load_args = [_]Value{ Value{ .raw = source_raw } };
    const loaded = vm.callMethodByName(result, "load", &load_args, null) catch return 0;
    return loaded.raw;
}

// ─── Encoding ────────────────────────────────────────────────────────────────

export fn rb_enc_copy(dest_raw: VALUE, src_raw: VALUE) VALUE {
    _ = src_raw;
    return dest_raw;
}

export fn rb_enc_sprintf(enc_ptr: ?*anyopaque, fmt: [*c]const u8, ...) VALUE {
    _ = enc_ptr;
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    if (fmt == null) return 0;
    const vm = getVM();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);
    const s = std.mem.span(fmt);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '%') {
            out.append(vm.allocator, s[i]) catch return 0;
            continue;
        }
        i += 1;
        if (i >= s.len) break;
        if (s[i] == '%') {
            out.append(vm.allocator, '%') catch return 0;
            continue;
        }
        if (s[i] == 'l' and i + 1 < s.len and s[i + 1] == 'd') {
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{@cVaArg(&ap, c_long)}) catch return 0;
            out.appendSlice(vm.allocator, rendered) catch return 0;
            i += 1;
            continue;
        }
        if (s[i] == 'd') {
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{@cVaArg(&ap, c_int)}) catch return 0;
            out.appendSlice(vm.allocator, rendered) catch return 0;
            continue;
        }
        if (s[i] == 's') {
            const ptr = @cVaArg(&ap, [*c]const u8);
            out.appendSlice(vm.allocator, if (ptr != null) std.mem.span(ptr) else "(null)") catch return 0;
            continue;
        }
        out.append(vm.allocator, '%') catch return 0;
        out.append(vm.allocator, s[i]) catch return 0;
    }
    const str_val = vm.newString(out.items, false) catch return 0;
    return str_val.raw;
}

export fn rb_str_format(argc: c_int, argv: [*c]const VALUE, fmt_raw: VALUE) VALUE {
    const vm = getVM();
    const args: []Value = if (argv != null and argc > 0)
        @as([*]Value, @ptrCast(@constCast(argv)))[0..@intCast(argc)]
    else
        &[_]Value{};
    const result = vm.callMethodByName(Value{ .raw = fmt_raw }, "%", args, null) catch return 0;
    return result.raw;
}

// ─── System ──────────────────────────────────────────────────────────────────

export fn rb_sys_fail(msg: [*c]const u8) void {
    if (msg == null) return;
    const vm = getVM();
    _ = vm.raiseExceptionFmt(@ptrFromInt(rb_eSystemCallError), "{s}", .{std.mem.span(msg)}) catch {};
}

export fn rb_undef_method(klass_raw: VALUE, name_ptr: [*c]const u8) void {
    const vm = getVM();
    const name = std.mem.span(name_ptr);
    const sym = vm.intern(name) catch return;
    const klass = Value{ .raw = klass_raw };
    const mod = if (klass.isClass()) &klass.toClassObject().module else @as(*value.ModuleObject, @ptrFromInt(klass_raw));
    _ = mod.methods.remove(sym);
}

// ─── Intern ──────────────────────────────────────────────────────────────────

export fn rb_intern_const(name: [*c]const u8) VALUE {
    return rb_intern(name);
}

// ─── Integer ─────────────────────────────────────────────────────────────────

export fn rb_int_positive_pow(x: c_long, y: c_ulong) VALUE {
    var result: i64 = 1;
    var base: i64 = x;
    var exp: u64 = y;
    while (exp > 0) {
        if (exp & 1 == 1) {
            result = result *% base;
        }
        exp >>= 1;
        if (exp > 0) {
            base = base *% base;
        }
    }
    return Value.integer(result).raw;
}

export fn rb_cstr_to_inum(str: [*c]const u8, base: c_int, badcheck: c_int) VALUE {
    if (str == null) return 0;
    const vm = getVM();
    const s = vm.newString(std.mem.span(str), false) catch return 0;
    return rb_str_to_inum(s.raw, base, badcheck);
}

// ─── Match ───────────────────────────────────────────────────────────────────

export fn rb_match_busy(match_raw: VALUE) c_int {
    _ = match_raw;
    return 0;
}

// ─── Memory hash ─────────────────────────────────────────────────────────────

export fn rb_memhash(ptr: ?*const anyopaque, len: c_long) c_long {
    if (ptr == null or len <= 0) return 0;
    const bytes: [*]const u8 = @ptrCast(ptr);
    var h: u64 = 5381;
    var i: c_long = 0;
    while (i < len) : (i += 1) {
        h = ((h << 5) + h) + bytes[@intCast(i)];
    }
    return @intCast(h & 0x7fffffffffffffff);
}

// ─── Numeric coercion ────────────────────────────────────────────────────────

export fn rb_num_coerce_cmp(x_raw: VALUE, y_raw: VALUE, cmp_id: VALUE) VALUE {
    _ = cmp_id;
    const vm = getVM();
    var args = [_]Value{ Value{ .raw = y_raw } };
    const result = vm.callMethodByName(Value{ .raw = x_raw }, "<=>", &args, null) catch return 0;
    return result.raw;
}

// ─── Rational ────────────────────────────────────────────────────────────────

export fn rb_rational_new(num_raw: VALUE, den_raw: VALUE) VALUE {
    const vm = getVM();
    const rat = vm.newRationalValues(
        Value{ .raw = num_raw },
        Value{ .raw = den_raw },
    ) catch return 0;
    return rat.raw;
}

export fn rb_rational_new1(num_raw: VALUE) VALUE {
    return rb_rational_new(num_raw, INT2NUM(1));
}

export fn rb_rational_num(rat_raw: VALUE) VALUE {
    const val = Value{ .raw = rat_raw };
    if (val.isRational()) {
        return val.toRationalObject().numerator.raw;
    }
    return 0;
}

export fn rb_rational_den(rat_raw: VALUE) VALUE {
    const val = Value{ .raw = rat_raw };
    if (val.isRational()) {
        return val.toRationalObject().denominator.raw;
    }
    return 0;
}

export fn rb_rational_new2(num_raw: VALUE, den_raw: VALUE) VALUE {
    return rb_rational_new(num_raw, den_raw);
}

// ─── Backref ─────────────────────────────────────────────────────────────────

export fn rb_backref_get() VALUE {
    return Value.NIL.raw;
}

export fn rb_backref_set(val: VALUE) void {
    _ = val;
}

// ─── Category warn ───────────────────────────────────────────────────────────

export fn rb_category_warn(category: c_int, fmt: [*c]const u8, ...) void {
    _ = category;
    rb_warn(fmt);
}

// ─── Copy generic ivar ───────────────────────────────────────────────────────

export fn rb_copy_generic_ivar(clone_raw: VALUE, obj_raw: VALUE) void {
    _ = clone_raw;
    _ = obj_raw;
}

// ─── Temp buffer ─────────────────────────────────────────────────────────────

export fn rb_alloc_tmp_buffer(store: *volatile VALUE, size: usize) ?*anyopaque {
    const ptr = xmalloc(size);
    store.* = @intFromPtr(ptr);
    return ptr;
}

export fn rb_free_tmp_buffer(store: *volatile VALUE) void {
    if (store.* != 0) {
        xfree(@ptrFromInt(store.*));
        store.* = 0;
    }
}

// ─── Data scanning ───────────────────────────────────────────────────────────

export fn ruby_scan_digits(str_ptr: [*c]const u8, len: isize, base: c_int, retlen: ?*usize, overflow: ?*c_int) c_ulong {
    if (str_ptr == null or len <= 0) {
        if (retlen) |r| r.* = 0;
        return 0;
    }
    const str = str_ptr[0..@intCast(len)];
    var i: usize = 0;
    var result: c_ulong = 0;
    const b: c_ulong = @intCast(base);

    while (i < str.len) : (i += 1) {
        const c = str[i];
        const digit: c_ulong = if (c >= '0' and c <= '9')
            @intCast(c - '0')
        else if (c >= 'a' and c <= 'z')
            @intCast(c - 'a' + 10)
        else if (c >= 'A' and c <= 'Z')
            @intCast(c - 'A' + 10)
        else
            break;

        if (digit >= b) break;

        const prev = result;
        result = result *% b +% digit;
        if (overflow != null and result < prev) {
            overflow.?.* = 1;
        }
    }

    if (retlen) |r| r.* = i;
    return result;
}
