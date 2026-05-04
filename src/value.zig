const std = @import("std");
const prism = @import("prism.zig");
const bdwgc = @import("bdwgc");
const hash_map = @import("hash_map.zig");
const vm_mod = @import("vm.zig");
const Chunk = @import("chunk.zig").Chunk;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Method = vm_mod.Method;
const Block = vm_mod.Block;
const FiberValueStack = vm_mod.FiberValueStack;
const FiberFrameStack = vm_mod.FiberFrameStack;
const FiberEnvironmentStack = vm_mod.FiberEnvironmentStack;
const FiberCoro = vm_mod.FiberCoro;
const onigmo = @import("onigmo.zig");
const inspect_util = @import("inspect.zig");

const encoding = @import("encoding.zig");
const Encoding = encoding.Encoding;
const ValidityState = encoding.ValidityState;

pub const MethodVisibility = enum {
    public,
    private,
    protected,
};

// Object type tag for heap-allocated objects.
// Used to identify the concrete type of a heap pointer stored in a Value.
pub const ObjectTypeTag = enum(u8) {
    instance,
    binding,
    string,
    symbol,
    array,
    hash,
    range,
    exception,
    proc,
    fiber,
    io,
    regexp,
    match_data,
    big_integer,
    encoding_obj,
    enumerator,
    yielder,
    module,
    class,
    float,
    thread,
    mutex,
    queue,
};

pub const Object = struct {
    pub const FROZEN_FLAG = 0x1;

    type_tag: ObjectTypeTag,
    flags: u32,
    class: ?*ClassObject,
    singleton_class: ?*ClassObject,
    instance_variables: ?std.AutoHashMap(*SymbolObject, Value),
};

pub const SymbolObject = struct {
    object: Object,
    name: []const u8,
    encoding: Encoding = .{ .us_ascii = .{} },
};

pub const StringObject = struct {
    object: Object,
    str: []const u8,
    encoding: Encoding = .{ .utf8 = .{} },
    validity: ValidityState = .unknown,
    // TODO: Fold this into a unified string-flags bitfield if/when more string state flags are added.
    chilled_literal: bool = false,
    symbol_to_s_source: ?*SymbolObject = null,
};

pub const BigIntegerObject = struct {
    object: Object,
    value: std.math.big.int.Managed,
};

pub const FloatObject = struct {
    object: Object,
    val: f64,
};

pub const EncodingObject = struct {
    object: Object,
    encoding: Encoding,
};

pub const LexicalScope = struct {
    scope_module: union(enum) {
        module: *ModuleObject,
        class: *ClassObject,
    },
    parent: ?*LexicalScope,
    default_method_visibility: MethodVisibility = .public,
    module_function_mode: bool = false,

    pub fn getModule(self: *LexicalScope) *ModuleObject {
        switch (self.scope_module) {
            .module => |m| return m,
            .class => |c| return &c.module,
        }
    }
};

pub const ModuleObject = struct {
    object: Object,
    name: *SymbolObject,
    methods: std.AutoHashMap(*SymbolObject, MethodEntry),
    constants: std.AutoHashMap(*SymbolObject, ConstEntry),
    autoloads: std.AutoHashMap(*SymbolObject, []const u8),
    class_variables: std.AutoHashMap(*SymbolObject, Value),
    prepended_modules: std.ArrayList(*ModuleObject) = .empty,
    included_modules: std.ArrayList(*ModuleObject) = .empty,
};

pub const ConstantVisibility = enum(u8) {
    public = 0,
    private = 1,
};

pub const ConstFlags = packed struct(u16) {
    visibility: ConstantVisibility = .public,
    deprecated: bool = false,
    _padding: u7 = 0,
};

pub const ConstEntry = struct {
    value: Value,
    flags: ConstFlags = .{},
};

pub const MethodEntry = struct {
    method: Method,
    visibility: MethodVisibility = .public,
};

pub const ObjectType = enum {
    instance,
    string,
    array,
    hash,
    range,
    fiber,
    io,
};

pub const ClassObject = struct {
    module: ModuleObject,
    superclass: ?*ClassObject,
    attached_object: ?Value = null,
    object_type: ObjectType = .instance,
    struct_members: ?*ArrayObject = null,
};

pub const ArrayObject = struct {
    object: Object,
    elements: std.ArrayList(Value) = .empty,
};

pub const BindingObject = struct {
    object: Object,
    self_value: Value,
    env: ?*vm_mod.Environment,
    lexical_scope: ?*LexicalScope,
};

pub const HashEntry = struct {
    key: Value,
    value: Value,
};

pub const HashContext = struct {
    vm: *VM,

    pub const Error = VMError;

    pub fn hash(self: @This(), key: Value) VMError!u64 {
        return self.vm.hashKeyHash(key);
    }

    pub fn eql(self: @This(), a: Value, b: Value) VMError!bool {
        return self.vm.hashKeysEqual(a, b);
    }
};

pub const HashMapType = hash_map.HashMap(Value, usize, HashContext, hash_map.default_max_load_percentage);

pub const HashObject = struct {
    object: Object,
    map: HashMapType,
    entries: std.ArrayList(HashEntry) = .empty,
    default_value: ?Value = null,
    default_proc: ?*ProcObject = null,
    compare_by_identity: bool = false,
};

pub const RangeObject = struct {
    object: Object,
    begin: Value,
    end: Value,
    exclude_end: bool,
};

pub const ExceptionObject = struct {
    object: Object,
    message: *StringObject,
    backtrace: ?*ArrayObject,
    cause: ?*ExceptionObject,
    receiver: ?Value = null,
    key: ?Value = null,
};

pub const ProcObject = struct {
    object: Object,
    block: Block,
};

pub const FiberObject = struct {
    pub const CoroEvent = enum {
        none,
        yielded,
        returned,
        raised,
    };

    object: Object,
    state: enum { created, running, suspended, terminated },
    block: ?Block,
    stack: FiberValueStack,
    frames: FiberFrameStack,
    env_stack: FiberEnvironmentStack,
    current_lexical_scope: ?*LexicalScope = null,
    caller: ?*FiberObject = null,
    coro: ?*FiberCoro = null,
    coro_event: CoroEvent = .none,
    coro_result: Value = Value.nil(),
    coro_exception: ?*ExceptionObject = null,
    first_resume_args: [256]Value = undefined,
    first_resume_argc: usize = 0,
    fiber_locals: ?std.AutoHashMap(*SymbolObject, Value) = null,
    owner_thread: ?*ThreadObject = null,
    owner_vm: *VM,
};

pub const ThreadObject = struct {
    pub const State = enum {
        created,
        running,
        sleeping,
        aborting,
        terminated,
    };

    object: Object,
    state: State,
    block: ?Block,
    stack: FiberValueStack,
    frames: FiberFrameStack,
    env_stack: FiberEnvironmentStack,
    current_lexical_scope: ?*LexicalScope = null,
    coro: ?*FiberCoro = null,
    // Result/exception communication
    result: Value = Value.nil(),
    exception: ?*ExceptionObject = null,
    terminated_normally: bool = false,
    // Thread-local storage
    fiber_locals: ?std.AutoHashMap(*SymbolObject, Value) = null,
    thread_variables: ?std.AutoHashMap(*SymbolObject, Value) = null,
    // Metadata
    name: ?[]const u8 = null,
    priority: i8 = 0,
    report_on_exception: bool = true,
    abort_on_exception: bool = false,
    kill_requested: bool = false,
    preempt_requested: bool = false,
    ops_until_preempt: u32 = 0,
    args: ?[]Value = null,
    main_fiber: ?*FiberObject = null,
    current_fiber: ?*FiberObject = null,
    owner_vm: *VM,
};

pub const MutexObject = struct {
    object: Object,
    state: State = .unlocked,
    owner_thread: ?*ThreadObject = null,
    owner_fiber: ?*FiberObject = null,

    pub const State = enum {
        unlocked,
        locked,
    };
};

pub const QueueObject = struct {
    object: Object,
    items: std.ArrayList(Value) = .empty,
    read_index: usize = 0,
    waiters: std.ArrayList(*ThreadObject) = .empty,
    closed: bool = false,
};

pub const IoObject = struct {
    object: Object,
    fd: i32,
    owns_fd: bool,
    closed: bool = false,
    readable: bool,
    writable: bool,
    append: bool,
};

pub const RegexpObject = struct {
    object: Object,
    pattern: []const u8,
    encoding: Encoding,
    options: u16,
    regex: onigmo.OnigRegex,
};

pub const MatchDataObject = struct {
    object: Object,
    regexp: *RegexpObject,
    source: *StringObject,
    captures: std.ArrayList(Value) = .empty,
    begin_byte_offsets: std.ArrayList(i64) = .empty,
    end_byte_offsets: std.ArrayList(i64) = .empty,
};

pub const EnumeratorObject = struct {
    object: Object,
    kind: Kind,
    method_args: ?*ArrayObject,
    size: ?Value,
    size_fn: ?SizeFn,
    fiber: ?*FiberObject,
    lookahead_values: ?*ArrayObject,
    has_lookahead_values: bool,

    pub const SizeFn = *const fn (vm: *VM, receiver: Value, method_args: ?*ArrayObject) VMError!Value;

    pub const Kind = union(enum) {
        method: struct {
            receiver: Value,
            method_name: *SymbolObject,
        },
        generator: struct {
            proc: *ProcObject,
        },
    };
};

pub const YielderObject = struct {
    object: Object,
    block: Block,
};

// =============================================================================
// Value: CRuby-style tagged u64
//
// Encoding:
//   Bit 0 = 1: Fixnum (i63). Extract: arithmetic_shift_right(raw, 1)
//   raw == 0x00: false
//   raw == 0x02: true
//   raw == 0x04: nil
//   raw == 0x06: undef
//   (raw & 7) == 0 and raw > 0x06: heap object pointer (8-byte aligned)
//
// Truthiness (CRuby RTEST trick):
//   (raw & ~0x04) != 0  →  only false(0) and nil(4) are falsy
// =============================================================================

pub const Value = struct {
    raw: u64,

    // -- Special constants --
    pub const FALSE = Value{ .raw = 0x00 };
    pub const TRUE = Value{ .raw = 0x02 };
    pub const NIL = Value{ .raw = 0x04 };
    pub const UNDEF = Value{ .raw = 0x06 };

    // -- Constructors --

    pub inline fn nil() Value {
        return NIL;
    }

    pub inline fn boolean(v: bool) Value {
        return if (v) TRUE else FALSE;
    }

    pub inline fn integer(v: i64) Value {
        return .{ .raw = (@as(u64, @bitCast(v)) << 1) | 1 };
    }

    pub inline fn float(v: f64) Value {
        _ = v;
        // Float boxing deferred - not needed for fib.rb
        @panic("float values not yet implemented");
    }

    pub inline fn fromObject(ptr: anytype) Value {
        return .{ .raw = @intFromPtr(ptr) };
    }

    // -- Type checks --

    pub inline fn isInteger(self: Value) bool {
        return (self.raw & 1) == 1;
    }

    pub inline fn isNil(self: Value) bool {
        return self.raw == NIL.raw;
    }

    pub inline fn isTrue(self: Value) bool {
        return self.raw == TRUE.raw;
    }

    pub inline fn isFalse(self: Value) bool {
        return self.raw == FALSE.raw;
    }

    pub inline fn isBool(self: Value) bool {
        return self.raw == TRUE.raw or self.raw == FALSE.raw;
    }

    pub inline fn isObject(self: Value) bool {
        return (self.raw & 7) == 0 and self.raw > UNDEF.raw;
    }

    pub inline fn is_truthy(self: Value) bool {
        return (self.raw & ~@as(u64, 0x04)) != 0;
    }

    // -- Extractors --

    pub inline fn toInteger(self: Value) i64 {
        return @as(i64, @bitCast(self.raw)) >> 1;
    }

    pub inline fn toBool(self: Value) bool {
        return self.raw == TRUE.raw;
    }

    pub inline fn toObject(self: Value, comptime T: type) *T {
        return @ptrFromInt(self.raw);
    }

    // Convenience: read the ObjectTypeTag from a heap object
    pub inline fn objectTypeTag(self: Value) ObjectTypeTag {
        const obj: *Object = @ptrFromInt(self.raw);
        return obj.type_tag;
    }

    // -- Type-specific checks for heap objects --

    pub inline fn isString(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .string;
    }

    pub inline fn isBinding(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .binding;
    }

    pub inline fn isSymbol(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .symbol;
    }

    pub inline fn isArray(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .array;
    }

    pub inline fn isHash(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .hash;
    }

    pub inline fn isClass(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .class;
    }

    pub inline fn isModule(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .module;
    }

    pub inline fn isProc(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .proc;
    }

    pub inline fn isFiber(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .fiber;
    }

    pub inline fn isException(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .exception;
    }

    pub inline fn isFloat(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .float;
    }

    pub inline fn isBigInteger(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .big_integer;
    }

    pub inline fn isRange(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .range;
    }

    pub inline fn isRegexp(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .regexp;
    }

    pub inline fn isInstance(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .instance;
    }

    pub inline fn isIo(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .io;
    }

    pub inline fn isEncoding(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .encoding_obj;
    }

    pub inline fn isMatchData(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .match_data;
    }

    pub inline fn isEnumerator(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .enumerator;
    }

    pub inline fn isYielder(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .yielder;
    }

    pub inline fn isThread(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .thread;
    }

    pub inline fn isMutex(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .mutex;
    }

    pub inline fn isQueue(self: Value) bool {
        return self.isObject() and self.objectTypeTag() == .queue;
    }

    // -- Convenience extractors for heap types --

    pub inline fn toStringObject(self: Value) *StringObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toSymbolObject(self: Value) *SymbolObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toArrayObject(self: Value) *ArrayObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toBindingObject(self: Value) *BindingObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toHashObject(self: Value) *HashObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toClassObject(self: Value) *ClassObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toModuleObject(self: Value) *ModuleObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toProcObject(self: Value) *ProcObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toFiberObject(self: Value) *FiberObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toExceptionObject(self: Value) *ExceptionObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toFloatObject(self: Value) *FloatObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toBigIntegerObject(self: Value) *BigIntegerObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toRangeObject(self: Value) *RangeObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toRegexpObject(self: Value) *RegexpObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toIoObject(self: Value) *IoObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toEncodingObject(self: Value) *EncodingObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toMatchDataObject(self: Value) *MatchDataObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toEnumeratorObject(self: Value) *EnumeratorObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toYielderObject(self: Value) *YielderObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toThreadObject(self: Value) *ThreadObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toMutexObject(self: Value) *MutexObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toQueueObject(self: Value) *QueueObject {
        return @ptrFromInt(self.raw);
    }

    pub inline fn toInstanceObject(self: Value) *Object {
        return @ptrFromInt(self.raw);
    }

    // -- Object protocol --

    pub fn getObjectPointer(self: Value) ?*Object {
        if (!self.isObject()) return null;
        return @ptrFromInt(self.raw);
    }

    pub fn getSingletonClass(self: Value) ?*ClassObject {
        const obj_ptr = self.getObjectPointer() orelse return null;
        return obj_ptr.singleton_class;
    }

    pub fn getModuleObject(self: Value) ?*ModuleObject {
        if (!self.isObject()) return null;
        const tag = self.objectTypeTag();
        if (tag == .class) return &self.toClassObject().module;
        if (tag == .module) return self.toModuleObject();
        return null;
    }

    pub fn getModuleMethods(self: Value) ?*std.AutoHashMap(*SymbolObject, MethodEntry) {
        const module_obj = self.getModuleObject() orelse return null;
        return &module_obj.methods;
    }

    pub fn objectId(self: Value) i64 {
        if (self.isInteger()) return (self.toInteger() << 1) | 1;
        if (self.isNil()) return 8;
        if (self.isTrue()) return 20;
        if (self.isFalse()) return 0;
        if (self.isObject()) return @intCast(self.raw);
        return 0;
    }

    pub fn isFrozen(self: Value) bool {
        // Primitives are always frozen
        if (self.isInteger() or self.isNil() or self.isBool()) return true;
        if (!self.isObject()) return true;
        const tag = self.objectTypeTag();
        // Encoding objects are always frozen singletons.
        if (tag == .encoding_obj) return true;
        const obj = self.getObjectPointer().?;
        return (obj.flags & Object.FROZEN_FLAG) != 0;
    }

    pub fn freeze(self: Value) void {
        if (!self.isObject()) return;
        const obj = self.getObjectPointer().?;
        obj.flags |= Object.FROZEN_FLAG;
    }

    // -- Numeric helpers --

    pub fn isNumeric(self: Value) bool {
        if (self.isInteger()) return true;
        if (self.isObject()) {
            const tag = self.objectTypeTag();
            return tag == .float or tag == .big_integer;
        }
        return false;
    }

    pub fn ensureInteger(self: Value, vm_instance: *VM) VMError!void {
        if (self.isInteger() or self.isBigInteger()) return;
        return vm_instance.raiseExceptionFmt(vm_instance.type_error_class, "argument is not numeric", .{});
    }

    pub fn integerToF64(self: Value) f64 {
        if (self.isInteger()) return @as(f64, @floatFromInt(self.toInteger()));
        if (self.isBigInteger()) return self.toBigIntegerObject().value.toFloat(f64, .nearest_even)[0];
        unreachable;
    }

    pub fn integerToI64(self: Value, vm_instance: *VM, range_error_msg: []const u8) VMError!i64 {
        if (self.isInteger()) return self.toInteger();
        if (self.isBigInteger()) return self.toBigIntegerObject().value.toInt(i64) catch
            return vm_instance.raiseExceptionFmt(vm_instance.range_error_class, "{s}", .{range_error_msg});
        unreachable;
    }

    pub fn integerArgToI64(self: Value, vm_instance: *VM, type_error_msg: []const u8, range_error_msg: []const u8) VMError!i64 {
        if (self.isInteger()) return self.toInteger();
        if (self.isBigInteger()) return self.toBigIntegerObject().value.toInt(i64) catch
            return vm_instance.raiseExceptionFmt(vm_instance.range_error_class, "{s}", .{range_error_msg});
        return vm_instance.raiseExceptionFmt(vm_instance.type_error_class, "{s}", .{type_error_msg});
    }

    pub fn integerToManaged(self: Value, vm_instance: *VM) VMError!std.math.big.int.Managed {
        if (self.isInteger()) return std.math.big.int.Managed.initSet(vm_instance.allocator, self.toInteger()) catch return error.Fatal;
        if (self.isBigInteger()) return self.toBigIntegerObject().value.cloneWithDifferentAllocator(vm_instance.allocator) catch return error.Fatal;
        unreachable;
    }

    pub fn coerceToIntegerValue(
        self: Value,
        vm_instance: *VM,
        missing_type_error_message: []const u8,
        non_integer_type_error_message: []const u8,
    ) VMError!Value {
        if (self.isInteger() or self.isBigInteger()) return self;

        const has_to_int = try vm_instance.respondsToMethodByName(self, "to_int", true);
        const coerced = if (has_to_int)
            try vm_instance.callMethodByName(self, "to_int", &[_]Value{}, null)
        else
            vm_instance.callMethodByName(self, "to_int", &[_]Value{}, null) catch |err| {
                if (err == error.Unwind and
                    vm_instance.pending_exception != null and
                    vm_instance.pending_exception.?.object.class == vm_instance.no_method_error_class)
                {
                    const exc = try vm_instance.createException(
                        vm_instance.type_error_class,
                        missing_type_error_message,
                    );
                    vm_instance.pending_exception = exc;
                    return error.Unwind;
                }
                return err;
            };

        if (!coerced.isInteger() and !coerced.isBigInteger()) {
            const exc = try vm_instance.createException(vm_instance.type_error_class, non_integer_type_error_message);
            vm_instance.pending_exception = exc;
            return error.Unwind;
        }

        return coerced;
    }

    pub fn coerceToI64ViaToInt(
        self: Value,
        vm_instance: *VM,
        missing_type_error_message: []const u8,
        non_integer_type_error_message: []const u8,
        range_error_message: []const u8,
    ) VMError!i64 {
        const coerced = try self.coerceToIntegerValue(
            vm_instance,
            missing_type_error_message,
            non_integer_type_error_message,
        );
        return coerced.integerToI64(vm_instance, range_error_message);
    }

    // -- String coercion --

    /// Canonical implicit String coercion (`to_str`).
    /// Use this for APIs that require String-like objects and should raise TypeError on failure.
    pub fn coerceToStringValue(self: Value, vm_instance: *VM, type_error_message: []const u8) VMError!Value {
        return switch (try vm_instance.probeToStringValue(self)) {
            .string => |coerced| coerced,
            .missing, .nil_result => {
                const exc = try vm_instance.createException(vm_instance.type_error_class, type_error_message);
                vm_instance.pending_exception = exc;
                return error.Unwind;
            },
        };
    }

    /// Byte-slice variant of `coerceToStringValue`.
    pub fn coerceToStr(self: Value, vm_instance: *VM, type_error_message: []const u8) VMError![]const u8 {
        const coerced = try self.coerceToStringValue(vm_instance, type_error_message);
        return coerced.toStringObject().str;
    }

    /// Match-source coercion: nil => null, Symbol => String, otherwise implicit String coercion.
    pub fn coerceToMatchSource(self: Value, vm_instance: *VM) VMError!?Value {
        if (self.isNil()) return null;
        if (self.isString()) return self;
        if (self.isSymbol()) return try vm_instance.newString(self.toSymbolObject().name, false);
        return try self.coerceToStringValue(vm_instance, "no implicit conversion into String");
    }

    pub fn inspect(self: Value, vm_instance: *VM) VMError!Value {
        const raw = try vm_instance.callMethodByName(self, "inspect", &.{}, null);
        const string_value = if (raw.isString()) raw else blk: {
            const to_s_value = try vm_instance.callMethodByName(raw, "to_s", &.{}, null);
            if (to_s_value.isString()) break :blk to_s_value;

            const class_name = vm_instance.getClass(raw).module.name.name;
            const text = std.fmt.allocPrint(vm_instance.gc_allocator, "#<{s}:0x{x}>", .{ class_name, raw.objectId() }) catch return error.Fatal;
            break :blk try vm_instance.newString(text, false);
        };

        const string_obj = string_value.toStringObject();
        const target_encoding = vm_instance.inspectTargetEncoding();
        if (string_obj.encoding.isAsciiOnlyString(string_obj.str) or string_obj.encoding.eql(target_encoding)) {
            return string_value;
        }

        const escaped = inspect_util.escapeStringBytes(vm_instance.allocator, string_obj.str, string_obj.encoding) catch return error.Fatal;
        defer vm_instance.allocator.free(escaped);
        return try vm_instance.newStringWithEncoding(escaped, false, .{ .us_ascii = .{} });
    }

    // -- Display --

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        if (self.isInteger()) {
            try writer.print("{d}", .{self.toInteger()});
        } else if (self.isNil()) {
            try writer.print("nil", .{});
        } else if (self.isBool()) {
            try writer.print("{s}", .{if (self.toBool()) "true" else "false"});
        } else if (self.isObject()) {
            const tag = self.objectTypeTag();
            switch (tag) {
                .binding => try writer.print("#<Binding:0x{x}>", .{self.raw}),
                .string => try writer.print("\"{s}\"", .{self.toStringObject().str}),
                .symbol => try writer.print(":{s}", .{self.toSymbolObject().name}),
                .module => try writer.print("<Module {s}>", .{self.toModuleObject().name.name}),
                .class => try writer.print("<Class {s}>", .{self.toClassObject().module.name.name}),
                .encoding_obj => try writer.print("#<Encoding:{s}>", .{self.toEncodingObject().encoding.name()}),
                .instance => try writer.print("<{s} instance>", .{self.toInstanceObject().class.?.module.name.name}),
                .array => {
                    const a = self.toArrayObject();
                    try writer.print("[", .{});
                    for (a.elements.items, 0..) |elem, idx| {
                        if (idx > 0) try writer.print(", ", .{});
                        try elem.format(writer);
                    }
                    try writer.print("]", .{});
                },
                .exception => {
                    const e = self.toExceptionObject();
                    try writer.print("#<{s}: {s}>", .{ e.object.class.?.module.name.name, e.message.str });
                },
                .hash => {
                    const h = self.toHashObject();
                    try writer.print("{{", .{});
                    for (h.entries.items, 0..) |entry, idx| {
                        if (idx > 0) try writer.print(", ", .{});
                        try entry.key.format(writer);
                        try writer.print("=>", .{});
                        try entry.value.format(writer);
                    }
                    try writer.print("}}", .{});
                },
                .proc => try writer.print("#<Proc:0x{x}>", .{self.raw}),
                .fiber => try writer.print("#<Fiber:0x{x}>", .{self.raw}),
                .io => try writer.print("#<IO:fd {d}>", .{self.toIoObject().fd}),
                .match_data => {
                    const m = self.toMatchDataObject();
                    if (m.captures.items.len > 0 and m.captures.items[0].isString()) {
                        try writer.print("#<MatchData {s}>", .{m.captures.items[0].toStringObject().str});
                    } else {
                        try writer.print("#<MatchData>", .{});
                    }
                },
                .range => try writer.print("#<Range>", .{}),
                .regexp => try writer.print("/{s}/", .{self.toRegexpObject().pattern}),
                .enumerator => try writer.print("#<Enumerator:0x{x}>", .{self.raw}),
                .yielder => try writer.print("#<Enumerator::Yielder:0x{x}>", .{self.raw}),
                .big_integer => try writer.print("{}", .{self.toBigIntegerObject().value}),
                .float => try writer.print("{d}", .{self.toFloatObject().val}),
                .thread => try writer.print("#<Thread:0x{x}>", .{self.raw}),
                .mutex => try writer.print("#<Mutex:0x{x}>", .{self.raw}),
                .queue => try writer.print("#<Thread::Queue:0x{x}>", .{self.raw}),
            }
        } else {
            try writer.print("<unknown>", .{});
        }
    }

    // -- Hashing --

    pub fn hash(self: Value) u64 {
        if (self.isInteger()) return @bitCast(self.toInteger());
        if (self.isNil()) return 0;
        if (self.isBool()) return if (self.toBool()) 1 else 0;
        if (!self.isObject()) return 0;

        const tag = self.objectTypeTag();
        return switch (tag) {
            .big_integer => blk: {
                const b = self.toBigIntegerObject();
                if (b.value.toInt(i64)) |i| {
                    break :blk @bitCast(i);
                } else |_| {
                    const limbs = b.value.toConst().limbs;
                    const limbs_bytes = std.mem.sliceAsBytes(limbs);
                    const sign_seed: u64 = if (b.value.isPositive()) 0 else 1;
                    break :blk std.hash.Wyhash.hash(sign_seed, limbs_bytes);
                }
            },
            .symbol => @intFromPtr(self.toSymbolObject()),
            .string => std.hash.Wyhash.hash(0, self.toStringObject().str),
            .regexp => std.hash.Wyhash.hash(@as(u64, self.toRegexpObject().options), self.toRegexpObject().pattern),
            .float => @bitCast(self.toFloatObject().val),
            else => self.raw,
        };
    }

    // -- Equality --

    pub fn eql(self: Value, other: Value) bool {
        // Fast path: identical raw values
        if (self.raw == other.raw) return true;

        // Both integers
        if (self.isInteger() and other.isInteger()) return false; // already checked raw equality

        // Both objects of the same type
        if (self.isObject() and other.isObject()) {
            const self_tag = self.objectTypeTag();
            const other_tag = other.objectTypeTag();
            if (self_tag != other_tag) return false;
            return switch (self_tag) {
                .big_integer => self.toBigIntegerObject().value.eql(other.toBigIntegerObject().value),
                .string => std.mem.eql(u8, self.toStringObject().str, other.toStringObject().str),
                .regexp => std.mem.eql(u8, self.toRegexpObject().pattern, other.toRegexpObject().pattern) and
                    self.toRegexpObject().options == other.toRegexpObject().options,
                .float => self.toFloatObject().val == other.toFloatObject().val,
                else => self.hash() == other.hash(),
            };
        }

        return false;
    }
};
