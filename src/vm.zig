const std = @import("std");
const builtin = @import("builtin");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const compiler = @import("compiler.zig");
const enc = @import("encoding.zig");
const fixed_buffer_list = @import("fixed_buffer_list.zig");
const inspect_util = @import("inspect.zig");
const jit = @import("jit.zig");
const onigmo = @import("onigmo.zig");
const recursion_guard = @import("recursion_guard.zig");
const signal_support = @import("signal_support.zig");
const value = @import("value.zig");
const prism = @import("prism.zig");
const builtins = @import("builtins/builtins.zig");
const comparable_builtin = @import("builtins/comparable.zig");
const warning_builtin = @import("builtins/warning.zig");
const zio = @import("zio");
const bdwgc = @import("bdwgc");

const Value = value.Value;
const Object = value.Object;
const ClassObject = value.ClassObject;
const FiberObject = value.FiberObject;
const ThreadObject = value.ThreadObject;
const LexicalScope = value.LexicalScope;
const MethodEntry = value.MethodEntry;
const MethodVisibility = value.MethodVisibility;
const StringObject = value.StringObject;
const BigIntegerObject = value.BigIntegerObject;
const SymbolObject = value.SymbolObject;
const MatchDataObject = value.MatchDataObject;
const Chunk = chunk.Chunk;
const CallSiteCache = chunk.CallSiteCache;
const BigInt = std.math.big.int.Managed;
const FixedBufferList = fixed_buffer_list.FixedBufferList;
const RecursionGuard = recursion_guard.RecursionGuard;
pub const RecursionGuardKind = recursion_guard.Kind;
const JitChunkStates = std.AutoHashMap(*Chunk, jit.State);

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn clock_gettime(clk_id: std.posix.CLOCK, tp: *std.posix.timespec) c_int;
extern "c" fn strerror(errnum: c_int) [*:0]const u8;

const MAX_FIBER_STACK_SIZE: usize = 8_192;
const MAX_FIBER_FRAMES: usize = 2048;
// ENV_DATA_SIZE: number of Value slots per frame above the locals region.
//   ep[0] = parent ep (raw ptr encoded as Value.raw, or 0 = no parent)
//   ep[1] = lexical scope, or tagged FrameScopeContext for eval-only metadata
//   ep[2] = locals_count (encoded as Value.integer so BDW won't chase it)
pub const ENV_DATA_SIZE: usize = 3;
const MAX_BUILTIN_KEYWORDS: usize = 256;
const SMALL_CALL_VALUES: usize = 16;
const DEFAULT_THREAD_PREEMPT_QUANTUM_OPS: u32 = 10_000;
const MAX_QUEUED_SIGNALS: usize = 128;
var queued_signal_counts: [MAX_QUEUED_SIGNALS]u32 = [_]u32{0} ** MAX_QUEUED_SIGNALS;

pub const SignalTrapMode = enum {
    system_default,
    default,
    ignore,
    ignore_nil,
    callable,
};

fn monotonicMilliseconds() i64 {
    var timespec: std.posix.timespec = undefined;
    if (clock_gettime(std.posix.CLOCK.MONOTONIC, &timespec) != 0) return 0;

    const seconds: i64 = @intCast(timespec.sec);
    const nanoseconds: i64 = @intCast(timespec.nsec);
    return seconds * 1_000 + @divTrunc(nanoseconds, 1_000_000);
}

fn signalHandler(sig: std.posix.SIG) callconv(.c) void {
    const signo: usize = @intCast(@intFromEnum(sig));
    if (signo < MAX_QUEUED_SIGNALS) {
        _ = @atomicRmw(u32, &queued_signal_counts[signo], .Add, 1, .seq_cst);
    }
}

fn installSignalHandler(sig: std.posix.SIG) void {
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &act, null);
}

fn setOsSignalMode(signo: c_int, mode: SignalTrapMode) void {
    if (std.posix.Sigaction == void or signo <= 0) return;
    const sig: std.posix.SIG = @enumFromInt(signo);
    const handler = switch (mode) {
        .system_default => std.posix.SIG.DFL,
        .ignore, .ignore_nil => std.posix.SIG.IGN,
        .default => if (signal_support.isVmDefaultSignal(signo)) signalHandler else std.posix.SIG.DFL,
        .callable => signalHandler,
    };
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &act, null);
}

fn initializeDefaultSignalTrapModes(vm: *VM) void {
    var signo: usize = 0;
    while (signo < MAX_QUEUED_SIGNALS) : (signo += 1) {
        vm.signal_trap_modes[signo] = .system_default;
        vm.signal_trap_callables[signo] = Value.nil();
    }

    var default_signo: c_int = 1;
    while (default_signo < MAX_QUEUED_SIGNALS) : (default_signo += 1) {
        if (signal_support.isVmDefaultSignal(default_signo)) {
            vm.signal_trap_modes[@intCast(default_signo)] = .default;
        }
    }
}

pub fn installDefaultSignalHandlers() void {
    if (std.posix.Sigaction == void) return;

    installSignalHandler(.INT);
    if (@hasField(std.posix.SIG, "TERM")) installSignalHandler(.TERM);
    if (@hasField(std.posix.SIG, "HUP")) installSignalHandler(.HUP);
    if (@hasField(std.posix.SIG, "QUIT")) installSignalHandler(.QUIT);
    if (@hasField(std.posix.SIG, "ALRM")) installSignalHandler(.ALRM);
    if (@hasField(std.posix.SIG, "USR1")) installSignalHandler(.USR1);
    if (@hasField(std.posix.SIG, "USR2")) installSignalHandler(.USR2);
}

pub fn requestSignal(signo: c_int) void {
    if (signo <= 0) return;
    const idx: usize = @intCast(signo);
    if (idx < MAX_QUEUED_SIGNALS) {
        _ = @atomicRmw(u32, &queued_signal_counts[idx], .Add, 1, .seq_cst);
    }
}

fn parseThreadPreemptQuantumOps() u32 {
    const value_z = getenv("CORA_THREAD_QUANTUM_OPS") orelse return DEFAULT_THREAD_PREEMPT_QUANTUM_OPS;
    const value_slice = std.mem.span(value_z);
    const parsed = std.fmt.parseInt(u32, value_slice, 10) catch return DEFAULT_THREAD_PREEMPT_QUANTUM_OPS;
    return if (parsed == 0) DEFAULT_THREAD_PREEMPT_QUANTUM_OPS else parsed;
}

fn rbConfigHostOs() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "mswin",
        else => @tagName(builtin.os.tag),
    };
}

fn rbConfigSharedLibraryExtension() []const u8 {
    return switch (builtin.os.tag) {
        .windows => "dll",
        .macos => "bundle",
        else => "so",
    };
}

pub const VMError = error{
    // Unhandled Ruby exception returned by VM.run()
    // Exception object is in pending_unwind.
    // Caller should probably call printUnhandledException().
    UnhandledException,

    // Unrecoverable VM error (e.g., OOM, corrupted bytecode)
    Fatal,

    // Triggers stack unwind internally
    // This shouldn't escape VM.run().
    Unwind,
};

pub const BuiltinMethod = struct {
    function: *const fn (*VM, Value, []Value, ?Block) VMError!Value,
    arity: value.BuiltinArity = .{ .exact = 0 },
};

pub const Method = union(enum) {
    chunk: *Chunk,
    builtin: BuiltinMethod,
    proc: *value.ProcObject,
    undefined: void,
};

const ReceiverCallStyle = bytecode.ReceiverCallStyle;

pub const ResolvedMethod = struct {
    name: *SymbolObject,
    owner_class: *ClassObject,
    entry: MethodEntry,
};

const LookupMethodResult = union(enum) {
    found: ResolvedMethod,
    undefined: void,
    not_found: void,
};

/// Heap-allocated environment: only created when a closure escapes its frame.
/// Layout mirrors the on-stack layout: env[0..locals_count-1] = locals,
/// env[locals_count..locals_count+ENV_DATA_SIZE-1] = env_data.
/// ep_ptr = env.ptr + locals_count  (same formula as on-stack).
pub const HeapEnv = struct {
    env: []Value, // GC-owned; len = locals_count + ENV_DATA_SIZE
};

const FRAME_SCOPE_CONTEXT_TAG: usize = 1;

const FrameScopeContext = struct {
    lexical_scope: ?*LexicalScope,
    class_variable_scope: ?*LexicalScope = null,
    method_definition_target: ?Value = null,
};

pub const Block = struct {
    pub const ChunkData = struct {
        chunk: *Chunk,
        defining_ep: [*]Value,
        defining_self: Value,
        return_target_ep: ?[*]Value,
        enclosing_block_proc: ?*value.ProcObject = null,
    };

    pub const ReceiverBuiltinData = struct {
        receiver: Value,
        func: *const fn (*VM, Value, []Value) VMError!Value,
        arity: i64,
    };

    kind: union(enum) {
        chunk: ChunkData,
        receiver_builtin: ReceiverBuiltinData,
        symbol: *SymbolObject,
        builtin: *const fn (*VM, []Value) VMError!Value,
        callable: Value,
    },
    source_proc: ?*value.ProcObject = null,
};

pub const CallFrame = struct {
    pub const FrameType = enum { method, lambda, proc, fiber, builtin };

    chunk: *Chunk,
    ip: usize,
    locals_base: usize, // vm.stack index of first local slot
    ep: [*]Value, // raw pointer to env_data[0]; locals at (ep-locals_count)..[ep-1]
    stack_base: usize, // vm.stack index where eval stack begins (= locals_base + locals_count + ENV_DATA_SIZE)
    self_value: Value,
    block: ?Block = null,
    frame_type: FrameType = .method,
    return_target_ep: ?[*]Value = null,
    break_target_frame_idx: ?usize = null,
    next_target_frame_idx: ?usize = null,
    method_name: ?[]const u8 = null,
    super_defining_class: ?*ClassObject = null,
    active_rescue_exceptions: usize = 0,
    forwarded_keyword_ctx: ?*BuiltinKeywordContext = null,
    dir_returns_nil: bool = false,
};

pub const FiberValueStack = FixedBufferList(Value, MAX_FIBER_STACK_SIZE);
pub const FiberFrameStack = FixedBufferList(CallFrame, MAX_FIBER_FRAMES);
pub const FiberCoro = zio.coro.Coroutine;
pub const FiberCoroContext = zio.coro.Context;

pub const PendingThrow = struct {
    tag: Value,
    value: Value,
};

const PendingControlFlow = struct {
    kind: Kind,
    value: Value,
    target_frame_idx: ?usize = null,
    target_ip: ?usize = null,
    value_placed: bool = false,

    const Kind = enum {
        return_,
        break_,
        next_,
        redo_,
        retry_,
    };
};

const PendingUnwind = union(enum) {
    exception: *value.ExceptionObject,
    throw_: PendingThrow,
    control_flow: PendingControlFlow,
};

const SavedUnwind = struct {
    pending_unwind: ?PendingUnwind = null,
};

pub const BuiltinKeywordContext = struct {
    kw_keys_storage: [256]Value = undefined,
    kw_values_storage: [256]Value = undefined,
    kw_keys: []const Value = &.{},
    kw_values: []const Value = &.{},
    consumed: [MAX_BUILTIN_KEYWORDS]bool = [_]bool{false} ** MAX_BUILTIN_KEYWORDS,
    cached_hash: ?Value = null,
    hash_materialized: bool = false,
};

pub const IndexedYieldContext = struct {
    block: Block,
    index: i64,
    previous: ?*IndexedYieldContext = null,
};

const TempValueSlice = struct {
    small: [SMALL_CALL_VALUES]Value = undefined,
    heap: ?[]Value = null,
    slice: []Value = &.{},

    fn initUninitialized(self: *TempValueSlice, vm: *VM, len: usize) VMError![]Value {
        if (len <= SMALL_CALL_VALUES) {
            self.slice = self.small[0..len];
            return self.slice;
        }

        const buf = vm.allocator.alloc(Value, len) catch return error.Fatal;
        self.heap = buf;
        self.slice = buf;
        return buf;
    }

    fn copyFrom(self: *TempValueSlice, vm: *VM, values: []const Value) VMError![]Value {
        const out = try self.initUninitialized(vm, values.len);
        if (values.len > 0) {
            @memcpy(out, values);
        }
        return out;
    }

    fn deinit(self: *TempValueSlice, allocator: std.mem.Allocator) void {
        if (self.heap) |buf| allocator.free(buf);
        self.heap = null;
        self.slice = &.{};
    }
};

const TempKeywordPairs = struct {
    keys: TempValueSlice = .{},
    values: TempValueSlice = .{},

    fn initUninitialized(self: *TempKeywordPairs, vm: *VM, len: usize) VMError!void {
        _ = try self.keys.initUninitialized(vm, len);
        errdefer self.keys.deinit(vm.allocator);
        _ = try self.values.initUninitialized(vm, len);
    }

    fn initFromHash(self: *TempKeywordPairs, vm: *VM, kw_hash: Value) VMError!void {
        const len = kw_hash.toHashObject().entries.items.len;
        try self.initUninitialized(vm, len);
        _ = try vm.extractKeywordPairsFromHash(kw_hash, self.keys.slice, self.values.slice);
    }

    fn deinit(self: *TempKeywordPairs, allocator: std.mem.Allocator) void {
        self.keys.deinit(allocator);
        self.values.deinit(allocator);
    }
};

const Ruby2KeywordsDispatch = struct {
    args: []const Value,
    kw_keys: ?[]const Value = null,
    kw_values: ?[]const Value = null,
};

const SymbolEncodingTag = std.meta.Tag(enc.Encoding);

const SymbolKey = struct {
    bytes: []const u8,
    encoding_tag: SymbolEncodingTag,
};

const SymbolKeyContext = struct {
    pub fn hash(_: SymbolKeyContext, key: SymbolKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(key.bytes);
        const tag_u8: u8 = @intFromEnum(key.encoding_tag);
        hasher.update(std.mem.asBytes(&tag_u8));
        return hasher.final();
    }

    pub fn eql(_: SymbolKeyContext, a: SymbolKey, b: SymbolKey) bool {
        return a.encoding_tag == b.encoding_tag and std.mem.eql(u8, a.bytes, b.bytes);
    }
};

const PackedPointerTargets = std.AutoHashMap(usize, *StringObject);

fn encodingKey(encoding_value: enc.Encoding) SymbolEncodingTag {
    return std.meta.activeTag(encoding_value);
}

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,
    gc_allocator_atomic: std.mem.Allocator,

    stack: *FiberValueStack,
    frames: *FiberFrameStack,

    symbols: std.HashMap(SymbolKey, *SymbolObject, SymbolKeyContext, std.hash_map.default_max_load_percentage),
    globals: std.StringHashMap(Value),
    fstring_cache: std.StringHashMap(Value),
    canonical_fstrings: std.ArrayList(Value) = .empty,
    packed_pointer_targets: std.AutoHashMap(*StringObject, PackedPointerTargets),
    errno_classes: std.AutoHashMap(c_int, *ClassObject),

    program: *compiler.CompiledProgram,

    current_lexical_scope: ?*LexicalScope = null,
    toplevel_lexical_scope: ?*LexicalScope = null,
    lexical_scopes: std.ArrayList(*LexicalScope) = .empty,
    frame_scope_contexts: std.ArrayList(*FrameScopeContext) = .empty,

    basic_object_class: *value.ClassObject,
    class_class: *value.ClassObject,
    integer_class: *value.ClassObject,
    float_class: *value.ClassObject,
    rational_class: *value.ClassObject,
    time_class: *value.ClassObject,
    random_class: *value.ClassObject,
    module_class: *value.ClassObject,
    numeric_class: *value.ClassObject,
    object_class: *value.ClassObject,
    string_class: *value.ClassObject,
    symbol_class: *value.ClassObject,
    io_class: *value.ClassObject,
    array_class: *value.ClassObject,
    hash_class: *value.ClassObject,
    file_class: *value.ClassObject,
    file_stat_class: *value.ClassObject,
    dir_class: *value.ClassObject,
    binding_class: *value.ClassObject,
    range_class: *value.ClassObject,
    proc_class: *value.ClassObject,
    struct_class: *value.ClassObject,
    fiber_class: *value.ClassObject,
    regexp_class: *value.ClassObject,
    match_data_class: *value.ClassObject,
    nil_class: *value.ClassObject,
    true_class: *value.ClassObject,
    false_class: *value.ClassObject,
    kernel_module: *value.ModuleObject,
    process_module: *value.ModuleObject,
    signal_module: *value.ModuleObject,
    warning_module: *value.ModuleObject,
    marshal_module: *value.ModuleObject,
    errno_module: *value.ModuleObject,
    warning_deprecated_enabled: bool = true,
    process_status_class: *value.ClassObject,
    main_self: Value,
    main_fiber: *value.FiberObject,
    current_fiber: *value.FiberObject,
    thread_class: *value.ClassObject,
    thread_backtrace_location_class: *value.ClassObject,
    thread_group_class: *value.ClassObject,
    mutex_class: *value.ClassObject,
    condition_variable_class: *value.ClassObject,
    queue_class: *value.ClassObject,
    sized_queue_class: *value.ClassObject,
    thread_error_class: *value.ClassObject,
    thread_kill_exception_class: *value.ClassObject,
    closed_queue_error_class: *value.ClassObject,
    uncaught_throw_error_class: *value.ClassObject,
    default_thread_group: Value = Value.nil(),
    main_thread: ?*value.ThreadObject = null,
    current_thread: ?*value.ThreadObject = null,
    thread_list: std.ArrayList(*value.ThreadObject) = .empty,
    runnable_queue: std.ArrayList(*value.ThreadObject) = .empty,
    thread_owned_mutexes: std.AutoHashMap(*value.ThreadObject, std.ArrayList(*value.MutexObject)) = undefined,
    mutex_waiters: std.AutoHashMap(*value.MutexObject, std.ArrayList(*value.ThreadObject)) = undefined,
    fiber_active_catches: std.AutoHashMap(*value.FiberObject, std.ArrayList(Value)) = undefined,
    thread_active_catches: std.AutoHashMap(*value.ThreadObject, std.ArrayList(Value)) = undefined,
    thread_preempt_quantum_ops: u32 = DEFAULT_THREAD_PREEMPT_QUANTUM_OPS,
    gc_thread_handle: ?*anyopaque = null,
    main_stack_base: ?*anyopaque = null,
    zio_main_context: FiberCoroContext = undefined,
    zio_stack_growth_ready: bool = false,
    zio_coroutines: std.ArrayList(*FiberCoro) = .empty,
    gc_registered_coro_stacks: std.AutoHashMap(*FiberCoro, void) = undefined,
    gc_vm_root_registered: bool = false,

    // Exception classes
    exception_class: *value.ClassObject,
    system_exit_class: *value.ClassObject,
    signal_exception_class: *value.ClassObject,
    interrupt_class: *value.ClassObject,
    system_call_error_class: *value.ClassObject,
    standard_error_class: *value.ClassObject,
    runtime_error_class: *value.ClassObject,
    syntax_error_class: *value.ClassObject,
    not_implemented_error_class: *value.ClassObject,
    frozen_error_class: *value.ClassObject,
    argument_error_class: *value.ClassObject,
    key_error_class: *value.ClassObject,
    type_error_class: *value.ClassObject,
    zero_division_error_class: *value.ClassObject,
    name_error_class: *value.ClassObject,
    no_method_error_class: *value.ClassObject,
    local_jump_error_class: *value.ClassObject,
    io_error_class: *value.ClassObject,
    eof_error_class: *value.ClassObject,
    fiber_error_class: *value.ClassObject,
    load_error_class: *value.ClassObject,
    io_eagain_wait_readable_class: *value.ClassObject,
    io_eagain_wait_writable_class: *value.ClassObject,
    encoding_error_class: *value.ClassObject,
    encoding_compatibility_error_class: *value.ClassObject,
    encoding_converter_not_found_error_class: *value.ClassObject,
    encoding_undefined_conversion_error_class: *value.ClassObject,
    encoding_invalid_byte_sequence_error_class: *value.ClassObject,
    range_error_class: *value.ClassObject,
    regexp_error_class: *value.ClassObject,
    index_error_class: *value.ClassObject,
    stop_iteration_class: *value.ClassObject,

    enumerator_class: *value.ClassObject,
    yielder_class: *value.ClassObject,
    method_class: *value.ClassObject,
    unbound_method_class: *value.ClassObject,

    // Encoding infrastructure
    encoding_class: *value.ClassObject,
    encoding_utf8: *value.EncodingObject,
    encoding_cesu8: *value.EncodingObject,
    encoding_ascii_8bit: *value.EncodingObject,
    encoding_us_ascii: *value.EncodingObject,
    encoding_shift_jis: *value.EncodingObject,
    encoding_windows_31j: *value.EncodingObject,
    encoding_euc_jp: *value.EncodingObject,
    encoding_cp437: *value.EncodingObject,
    encoding_iso_2022_jp: *value.EncodingObject,
    encoding_iso_8859_1: *value.EncodingObject,
    encoding_iso_8859_9: *value.EncodingObject,
    encoding_iso_8859_15: *value.EncodingObject,
    encoding_utf7: *value.EncodingObject,
    encoding_utf16: *value.EncodingObject,
    encoding_utf32: *value.EncodingObject,
    encoding_utf16le: *value.EncodingObject,
    encoding_utf16be: *value.EncodingObject,
    encoding_utf32le: *value.EncodingObject,
    encoding_utf32be: *value.EncodingObject,
    default_external_encoding: *value.EncodingObject,
    default_internal_encoding: ?*value.EncodingObject = null,

    // Exception/throw/control-flow unwind state.
    pending_unwind: ?PendingUnwind = null,
    pending_async_exceptions: std.ArrayList(*value.ExceptionObject) = .empty,
    pending_signal_traps: std.ArrayList(c_int) = .empty,
    rescued_exceptions: std.ArrayList(*value.ExceptionObject) = .empty,
    ensure_saved_unwinds: std.ArrayList(SavedUnwind) = .empty,
    active_catches: *std.ArrayList(Value),
    backtrace_limit: ?usize = null,

    builtin_keyword_ctx: ?*BuiltinKeywordContext = null,
    indexed_yield_ctx: ?*IndexedYieldContext = null,

    at_exit_handlers: std.ArrayList(Value) = .empty,
    skip_at_exit_handlers: bool = false,
    io_objects: std.ArrayList(*value.IoObject) = .empty,
    signal_trap_modes: [MAX_QUEUED_SIGNALS]SignalTrapMode = [_]SignalTrapMode{.system_default} ** MAX_QUEUED_SIGNALS,
    signal_trap_callables: [MAX_QUEUED_SIGNALS]Value = [_]Value{Value.nil()} ** MAX_QUEUED_SIGNALS,
    exit_signal_trap_mode: SignalTrapMode = .system_default,
    exit_signal_trap_callable: Value = Value.nil(),

    // File loading infrastructure
    loaded_files: std.StringHashMap(void) = undefined,
    require_in_progress: std.StringHashMap(*value.ThreadObject) = undefined,
    loaded_paths: std.ArrayList([]const u8) = .empty,
    load_path: ?*value.ArrayObject = null,
    current_loading_file: ?[]const u8 = null,
    env_object: ?Value = null,
    next_chunk_id: u16 = 1,
    method_state_version: u64 = 1,
    integer_changed: bool = false,
    random_counter: u64 = 0,
    recursion_guard: RecursionGuard = .{},
    disable_gems: bool = false,
    rubygems_loaded_on_miss: bool = false,
    tcc_jit_enabled: bool = false,
    dump_jit_source: bool = false,
    jit_chunk_states: JitChunkStates,
    io: std.Io,
    environ: std.process.Environ,

    // Buffered writers for production
    stdout_buffer: [4096]u8 = undefined,
    stderr_buffer: [4096]u8 = undefined,
    stdout_writer: ?std.Io.File.Writer = null,
    stderr_writer: ?std.Io.File.Writer = null,

    // Type-erased writers (tests can override these)
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,
    ruby_executable_path: ?[]const u8 = null,

    pub fn initEmpty(
        allocator: std.mem.Allocator,
        gc_allocator: std.mem.Allocator,
        gc_allocator_atomic: std.mem.Allocator,
        io: std.Io,
        environ: std.process.Environ,
    ) VM {
        return VM{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .gc_allocator_atomic = gc_allocator_atomic,
            .io = io,
            .environ = environ,
            .stack = undefined,
            .frames = undefined,
            .symbols = std.HashMap(SymbolKey, *SymbolObject, SymbolKeyContext, std.hash_map.default_max_load_percentage).init(gc_allocator),
            .globals = std.StringHashMap(Value).init(gc_allocator),
            .fstring_cache = std.StringHashMap(Value).init(gc_allocator),
            .canonical_fstrings = .empty,
            .packed_pointer_targets = std.AutoHashMap(*StringObject, PackedPointerTargets).init(gc_allocator),
            .errno_classes = std.AutoHashMap(c_int, *ClassObject).init(gc_allocator),
            .loaded_files = std.StringHashMap(void).init(gc_allocator),
            .require_in_progress = std.StringHashMap(*value.ThreadObject).init(allocator),
            .program = undefined,
            .current_lexical_scope = null,
            .toplevel_lexical_scope = null,
            .frame_scope_contexts = .empty,
            .basic_object_class = undefined,
            .class_class = undefined,
            .integer_class = undefined,
            .float_class = undefined,
            .rational_class = undefined,
            .time_class = undefined,
            .random_class = undefined,
            .module_class = undefined,
            .numeric_class = undefined,
            .object_class = undefined,
            .string_class = undefined,
            .symbol_class = undefined,
            .io_class = undefined,
            .array_class = undefined,
            .hash_class = undefined,
            .file_class = undefined,
            .file_stat_class = undefined,
            .dir_class = undefined,
            .binding_class = undefined,
            .range_class = undefined,
            .proc_class = undefined,
            .struct_class = undefined,
            .fiber_class = undefined,
            .regexp_class = undefined,
            .match_data_class = undefined,
            .nil_class = undefined,
            .true_class = undefined,
            .false_class = undefined,
            .kernel_module = undefined,
            .process_module = undefined,
            .signal_module = undefined,
            .warning_module = undefined,
            .marshal_module = undefined,
            .errno_module = undefined,
            .process_status_class = undefined,
            .main_fiber = undefined,
            .current_fiber = undefined,
            .thread_class = undefined,
            .thread_backtrace_location_class = undefined,
            .thread_group_class = undefined,
            .mutex_class = undefined,
            .condition_variable_class = undefined,
            .queue_class = undefined,
            .sized_queue_class = undefined,
            .thread_error_class = undefined,
            .thread_kill_exception_class = undefined,
            .closed_queue_error_class = undefined,
            .uncaught_throw_error_class = undefined,
            .default_thread_group = Value.nil(),
            .main_thread = null,
            .current_thread = null,
            .thread_list = .empty,
            .runnable_queue = .empty,
            .thread_owned_mutexes = std.AutoHashMap(*value.ThreadObject, std.ArrayList(*value.MutexObject)).init(allocator),
            .mutex_waiters = std.AutoHashMap(*value.MutexObject, std.ArrayList(*value.ThreadObject)).init(allocator),
            .fiber_active_catches = std.AutoHashMap(*value.FiberObject, std.ArrayList(Value)).init(allocator),
            .thread_active_catches = std.AutoHashMap(*value.ThreadObject, std.ArrayList(Value)).init(allocator),
            .thread_preempt_quantum_ops = DEFAULT_THREAD_PREEMPT_QUANTUM_OPS,
            .exception_class = undefined,
            .system_exit_class = undefined,
            .signal_exception_class = undefined,
            .interrupt_class = undefined,
            .system_call_error_class = undefined,
            .standard_error_class = undefined,
            .runtime_error_class = undefined,
            .syntax_error_class = undefined,
            .not_implemented_error_class = undefined,
            .frozen_error_class = undefined,
            .argument_error_class = undefined,
            .key_error_class = undefined,
            .type_error_class = undefined,
            .zero_division_error_class = undefined,
            .name_error_class = undefined,
            .no_method_error_class = undefined,
            .local_jump_error_class = undefined,
            .io_error_class = undefined,
            .eof_error_class = undefined,
            .fiber_error_class = undefined,
            .load_error_class = undefined,
            .io_eagain_wait_readable_class = undefined,
            .io_eagain_wait_writable_class = undefined,
            .encoding_error_class = undefined,
            .encoding_compatibility_error_class = undefined,
            .encoding_converter_not_found_error_class = undefined,
            .encoding_undefined_conversion_error_class = undefined,
            .encoding_invalid_byte_sequence_error_class = undefined,
            .range_error_class = undefined,
            .regexp_error_class = undefined,
            .index_error_class = undefined,
            .stop_iteration_class = undefined,
            .enumerator_class = undefined,
            .yielder_class = undefined,
            .method_class = undefined,
            .unbound_method_class = undefined,
            .encoding_class = undefined,
            .encoding_utf8 = undefined,
            .encoding_cesu8 = undefined,
            .encoding_ascii_8bit = undefined,
            .encoding_us_ascii = undefined,
            .encoding_shift_jis = undefined,
            .encoding_windows_31j = undefined,
            .encoding_euc_jp = undefined,
            .encoding_cp437 = undefined,
            .encoding_iso_2022_jp = undefined,
            .encoding_iso_8859_1 = undefined,
            .encoding_iso_8859_9 = undefined,
            .encoding_iso_8859_15 = undefined,
            .encoding_utf7 = undefined,
            .encoding_utf16 = undefined,
            .encoding_utf32 = undefined,
            .encoding_utf16le = undefined,
            .encoding_utf16be = undefined,
            .encoding_utf32le = undefined,
            .encoding_utf32be = undefined,
            .default_external_encoding = undefined,
            .default_internal_encoding = null,
            .main_self = undefined,
            .pending_unwind = null,
            .pending_signal_traps = .empty,
            .active_catches = undefined,
            .zio_main_context = undefined,
            .zio_stack_growth_ready = false,
            .zio_coroutines = .empty,
            .gc_registered_coro_stacks = std.AutoHashMap(*FiberCoro, void).init(allocator),
            .gc_vm_root_registered = false,
            .gc_thread_handle = null,
            .main_stack_base = null,
            .method_state_version = 1,
            .lexical_scopes = .empty,
            .builtin_keyword_ctx = null,
            .indexed_yield_ctx = null,
            .tcc_jit_enabled = false,
            .dump_jit_source = false,
            .jit_chunk_states = JitChunkStates.init(allocator),
            .ruby_executable_path = null,
        };
    }

    pub fn prepare(self: *VM, program: *compiler.CompiledProgram) VMError!void {
        self.program = program;
        try self.captureMainGcStackBase();
        self.registerVmRootForGc();
        self.zio_coroutines = .empty;
        zio.coro.setupStackGrowth() catch return error.Fatal;
        self.zio_stack_growth_ready = true;

        // Initialize file loading infrastructure. The Ruby-facing $LOAD_PATH
        // must wait until Array and String classes exist so those bootstrap
        // objects get valid dispatch classes.
        self.loaded_files = std.StringHashMap(void).init(self.allocator);
        self.loaded_paths = .empty;
        self.load_path = null;
        self.next_chunk_id = program.next_chunk_id;
        self.thread_preempt_quantum_ops = parseThreadPreemptQuantumOps();
        initializeDefaultSignalTrapModes(self);
        self.exit_signal_trap_mode = .system_default;
        self.exit_signal_trap_callable = Value.nil();

        if (program.main_chunk.source_file) |main_file| {
            const abs_path = try self.resolveAbsolutePath(main_file);
            try self.insertLoadedFile(abs_path);
            self.allocator.free(abs_path);
            self.current_loading_file = self.loaded_paths.items[self.loaded_paths.items.len - 1];
        }

        // --- Stage 1: Create Class and BasicObject ---
        const class_name_sym = try self.intern("Class");
        const class_class_val = try self.newClass(class_name_sym, null);
        self.class_class = class_class_val.toClassObject();
        self.class_class.module.object.class = self.class_class;

        const basic_object_name_sym = try self.intern("BasicObject");
        const basic_object_class_val = try self.newClass(basic_object_name_sym, null);
        self.basic_object_class = basic_object_class_val.toClassObject();

        // --- Stage 2: Create classes that inherit from BasicObject or Object ---
        const object_name_sym = try self.intern("Object");
        const object_class_val = try self.newClass(object_name_sym, self.basic_object_class);
        self.object_class = object_class_val.toClassObject();

        const module_name_sym = try self.intern("Module");
        const module_class_val = try self.newClass(module_name_sym, self.object_class);
        self.module_class = module_class_val.toClassObject();
        self.class_class.superclass = self.module_class;

        const numeric_name_sym = try self.intern("Numeric");
        const numeric_class_val = try self.newClass(numeric_name_sym, self.object_class);
        self.numeric_class = numeric_class_val.toClassObject();

        const integer_name_sym = try self.intern("Integer");
        const integer_class_val = try self.newClass(integer_name_sym, self.numeric_class);
        self.integer_class = integer_class_val.toClassObject();

        const float_name_sym = try self.intern("Float");
        const float_class_val = try self.newClass(float_name_sym, self.numeric_class);
        self.float_class = float_class_val.toClassObject();

        const rational_name_sym = try self.intern("Rational");
        const rational_class_val = try self.newClass(rational_name_sym, self.numeric_class);
        self.rational_class = rational_class_val.toClassObject();

        const time_name_sym = try self.intern("Time");
        const time_class_val = try self.newClassWithType(time_name_sym, self.object_class, .time);
        self.time_class = time_class_val.toClassObject();

        const random_name_sym = try self.intern("Random");
        const random_class_val = try self.newClass(random_name_sym, self.object_class);
        self.random_class = random_class_val.toClassObject();

        const string_name_sym = try self.intern("String");
        const string_class_val = try self.newClassWithType(string_name_sym, self.object_class, .string);
        self.string_class = string_class_val.toClassObject();

        const symbol_name_sym = try self.intern("Symbol");
        const symbol_class_val = try self.newClass(symbol_name_sym, self.object_class);
        self.symbol_class = symbol_class_val.toClassObject();
        {
            var it = self.symbols.valueIterator();
            while (it.next()) |sym_obj| {
                sym_obj.*.object.class = self.symbol_class;
            }
        }

        const io_name_sym = try self.intern("IO");
        const io_class_val = try self.newClassWithType(io_name_sym, self.object_class, .io);
        self.io_class = io_class_val.toClassObject();

        const array_name_sym = try self.intern("Array");
        const array_class_val = try self.newClassWithType(array_name_sym, self.object_class, .array);
        self.array_class = array_class_val.toClassObject();

        const hash_name_sym = try self.intern("Hash");
        const hash_class_val = try self.newClassWithType(hash_name_sym, self.object_class, .hash);
        self.hash_class = hash_class_val.toClassObject();

        self.load_path = try self.createArray();

        const file_name_sym = try self.intern("File");
        const file_class_val = try self.newClassWithType(file_name_sym, self.io_class, .io);
        self.file_class = file_class_val.toClassObject();

        const dir_name_sym = try self.intern("Dir");
        const dir_class_val = try self.newClass(dir_name_sym, self.object_class);
        self.dir_class = dir_class_val.toClassObject();

        const binding_name_sym = try self.intern("Binding");
        const binding_class_val = try self.newClass(binding_name_sym, self.object_class);
        self.binding_class = binding_class_val.toClassObject();

        const range_name_sym = try self.intern("Range");
        const range_class_val = try self.newClassWithType(range_name_sym, self.object_class, .range);
        self.range_class = range_class_val.toClassObject();

        const proc_name_sym = try self.intern("Proc");
        const proc_class_val = try self.newClass(proc_name_sym, self.object_class);
        self.proc_class = proc_class_val.toClassObject();

        const struct_name_sym = try self.intern("Struct");
        const struct_class_val = try self.newClass(struct_name_sym, self.object_class);
        self.struct_class = struct_class_val.toClassObject();

        const method_name_sym = try self.intern("Method");
        const method_class_val = try self.newClass(method_name_sym, self.object_class);
        self.method_class = method_class_val.toClassObject();

        const unbound_method_name_sym = try self.intern("UnboundMethod");
        const unbound_method_class_val = try self.newClass(unbound_method_name_sym, self.object_class);
        self.unbound_method_class = unbound_method_class_val.toClassObject();

        const fiber_name_sym = try self.intern("Fiber");
        const fiber_class_val = try self.newClassWithType(fiber_name_sym, self.object_class, .fiber);
        self.fiber_class = fiber_class_val.toClassObject();

        const thread_name_sym = try self.intern("Thread");
        const thread_class_val = try self.newClass(thread_name_sym, self.object_class);
        self.thread_class = thread_class_val.toClassObject();

        const thread_backtrace_name_sym = try self.intern("Backtrace");
        const thread_backtrace_module_val = try self.newModule(thread_backtrace_name_sym);

        const thread_backtrace_location_name_sym = try self.intern("Location");
        const thread_backtrace_location_class_val = try self.newClass(thread_backtrace_location_name_sym, self.object_class);
        self.thread_backtrace_location_class = thread_backtrace_location_class_val.toClassObject();

        const thread_group_name_sym = try self.intern("ThreadGroup");
        const thread_group_class_val = try self.newClass(thread_group_name_sym, self.object_class);
        self.thread_group_class = thread_group_class_val.toClassObject();
        self.default_thread_group = try self.newObjectForClass(self.thread_group_class);

        const mutex_name_sym = try self.intern("Mutex");
        const mutex_class_val = try self.newClass(mutex_name_sym, self.object_class);
        self.mutex_class = mutex_class_val.toClassObject();

        const condition_variable_name_sym = try self.intern("ConditionVariable");
        const condition_variable_class_val = try self.newClass(condition_variable_name_sym, self.object_class);
        self.condition_variable_class = condition_variable_class_val.toClassObject();

        const queue_name_sym = try self.intern("Queue");
        const queue_class_val = try self.newClass(queue_name_sym, self.object_class);
        self.queue_class = queue_class_val.toClassObject();

        const sized_queue_name_sym = try self.intern("SizedQueue");
        const sized_queue_class_val = try self.newClass(sized_queue_name_sym, self.queue_class);
        self.sized_queue_class = sized_queue_class_val.toClassObject();

        const regexp_name_sym = try self.intern("Regexp");
        const regexp_class_val = try self.newClass(regexp_name_sym, self.object_class);
        self.regexp_class = regexp_class_val.toClassObject();

        const match_data_name_sym = try self.intern("MatchData");
        const match_data_class_val = try self.newClass(match_data_name_sym, self.object_class);
        self.match_data_class = match_data_class_val.toClassObject();

        const nil_class_name_sym = try self.intern("NilClass");
        const nil_class_val = try self.newClass(nil_class_name_sym, self.object_class);
        self.nil_class = nil_class_val.toClassObject();

        const true_class_name_sym = try self.intern("TrueClass");
        const true_class_val = try self.newClass(true_class_name_sym, self.object_class);
        self.true_class = true_class_val.toClassObject();

        const false_class_name_sym = try self.intern("FalseClass");
        const false_class_val = try self.newClass(false_class_name_sym, self.object_class);
        self.false_class = false_class_val.toClassObject();

        const kernel_name_sym = try self.intern("Kernel");
        const kernel_module_val = try self.newModule(kernel_name_sym);
        self.kernel_module = kernel_module_val.toModuleObject();

        const process_name_sym = try self.intern("Process");
        const process_module_val = try self.newModule(process_name_sym);
        self.process_module = process_module_val.toModuleObject();

        const signal_name_sym = try self.intern("Signal");
        const signal_module_val = try self.newModule(signal_name_sym);
        self.signal_module = signal_module_val.toModuleObject();

        const warning_name_sym = try self.intern("Warning");
        const warning_module_val = try self.newModule(warning_name_sym);
        self.warning_module = warning_module_val.toModuleObject();

        const marshal_name_sym = try self.intern("Marshal");
        const marshal_module_val = try self.newModule(marshal_name_sym);
        self.marshal_module = marshal_module_val.toModuleObject();

        const errno_name_sym = try self.intern("Errno");
        const errno_module_val = try self.newModule(errno_name_sym);
        self.errno_module = errno_module_val.toModuleObject();

        const comparable_name_sym = try self.intern("Comparable");
        const comparable_module_val = try self.newModule(comparable_name_sym);

        const enumerable_name_sym = try self.intern("Enumerable");
        const enumerable_module_val = try self.newModule(enumerable_name_sym);

        const process_status_name_sym = try self.intern("InternalProcessStatus");
        const process_status_class_val = try self.newClass(process_status_name_sym, self.object_class);
        self.process_status_class = process_status_class_val.toClassObject();

        // Exception class hierarchy
        const exception_name_sym = try self.intern("Exception");
        const exception_class_val = try self.newClass(exception_name_sym, self.object_class);
        self.exception_class = exception_class_val.toClassObject();

        const system_exit_name_sym = try self.intern("SystemExit");
        const system_exit_class_val = try self.newClass(system_exit_name_sym, self.exception_class);
        self.system_exit_class = system_exit_class_val.toClassObject();

        const signal_exception_name_sym = try self.intern("SignalException");
        const signal_exception_class_val = try self.newClass(signal_exception_name_sym, self.exception_class);
        self.signal_exception_class = signal_exception_class_val.toClassObject();

        const interrupt_name_sym = try self.intern("Interrupt");
        const interrupt_class_val = try self.newClass(interrupt_name_sym, self.signal_exception_class);
        self.interrupt_class = interrupt_class_val.toClassObject();

        const standard_error_name_sym = try self.intern("StandardError");
        const standard_error_class_val = try self.newClass(standard_error_name_sym, self.exception_class);
        self.standard_error_class = standard_error_class_val.toClassObject();

        const system_call_error_name_sym = try self.intern("SystemCallError");
        const system_call_error_class_val = try self.newClass(system_call_error_name_sym, self.standard_error_class);
        self.system_call_error_class = system_call_error_class_val.toClassObject();

        const runtime_error_name_sym = try self.intern("RuntimeError");
        const runtime_error_class_val = try self.newClass(runtime_error_name_sym, self.standard_error_class);
        self.runtime_error_class = runtime_error_class_val.toClassObject();

        const syntax_error_name_sym = try self.intern("SyntaxError");
        const syntax_error_class_val = try self.newClass(syntax_error_name_sym, self.standard_error_class);
        self.syntax_error_class = syntax_error_class_val.toClassObject();

        const not_implemented_error_name_sym = try self.intern("NotImplementedError");
        const not_implemented_error_class_val = try self.newClass(not_implemented_error_name_sym, self.standard_error_class);
        self.not_implemented_error_class = not_implemented_error_class_val.toClassObject();

        const frozen_error_name_sym = try self.intern("FrozenError");
        const frozen_error_class_val = try self.newClass(frozen_error_name_sym, self.runtime_error_class);
        self.frozen_error_class = frozen_error_class_val.toClassObject();

        const argument_error_name_sym = try self.intern("ArgumentError");
        const argument_error_class_val = try self.newClass(argument_error_name_sym, self.standard_error_class);
        self.argument_error_class = argument_error_class_val.toClassObject();

        const uncaught_throw_error_name_sym = try self.intern("UncaughtThrowError");
        const uncaught_throw_error_class_val = try self.newClass(uncaught_throw_error_name_sym, self.argument_error_class);
        self.uncaught_throw_error_class = uncaught_throw_error_class_val.toClassObject();

        const type_error_name_sym = try self.intern("TypeError");
        const type_error_class_val = try self.newClass(type_error_name_sym, self.standard_error_class);
        self.type_error_class = type_error_class_val.toClassObject();

        const zero_division_error_name_sym = try self.intern("ZeroDivisionError");
        const zero_division_error_class_val = try self.newClass(zero_division_error_name_sym, self.standard_error_class);
        self.zero_division_error_class = zero_division_error_class_val.toClassObject();

        const name_error_name_sym = try self.intern("NameError");
        const name_error_class_val = try self.newClass(name_error_name_sym, self.standard_error_class);
        self.name_error_class = name_error_class_val.toClassObject();

        const no_method_error_name_sym = try self.intern("NoMethodError");
        const no_method_error_class_val = try self.newClass(no_method_error_name_sym, self.name_error_class);
        self.no_method_error_class = no_method_error_class_val.toClassObject();

        const local_jump_error_name_sym = try self.intern("LocalJumpError");
        const local_jump_error_class_val = try self.newClass(local_jump_error_name_sym, self.standard_error_class);
        self.local_jump_error_class = local_jump_error_class_val.toClassObject();

        const io_error_name_sym = try self.intern("IOError");
        const io_error_class_val = try self.newClass(io_error_name_sym, self.standard_error_class);
        self.io_error_class = io_error_class_val.toClassObject();

        const eof_error_name_sym = try self.intern("EOFError");
        const eof_error_class_val = try self.newClass(eof_error_name_sym, self.io_error_class);
        self.eof_error_class = eof_error_class_val.toClassObject();

        const fiber_error_name_sym = try self.intern("FiberError");
        const fiber_error_class_val = try self.newClass(fiber_error_name_sym, self.standard_error_class);
        self.fiber_error_class = fiber_error_class_val.toClassObject();

        const thread_error_name_sym = try self.intern("ThreadError");
        const thread_error_class_val = try self.newClass(thread_error_name_sym, self.standard_error_class);
        self.thread_error_class = thread_error_class_val.toClassObject();

        const thread_kill_name_sym = try self.intern("ThreadKillSignal");
        const thread_kill_class_val = try self.newClass(thread_kill_name_sym, self.exception_class);
        self.thread_kill_exception_class = thread_kill_class_val.toClassObject();

        const closed_queue_error_name_sym = try self.intern("ClosedQueueError");
        const closed_queue_error_class_val = try self.newClass(closed_queue_error_name_sym, self.standard_error_class);
        self.closed_queue_error_class = closed_queue_error_class_val.toClassObject();

        const load_error_name_sym = try self.intern("LoadError");
        const load_error_class_val = try self.newClass(load_error_name_sym, self.standard_error_class);
        self.load_error_class = load_error_class_val.toClassObject();

        const encoding_error_name_sym = try self.intern("EncodingError");
        const encoding_error_class_val = try self.newClass(encoding_error_name_sym, self.standard_error_class);
        self.encoding_error_class = encoding_error_class_val.toClassObject();
        const encoding_compatibility_error_name_sym = try self.intern("CompatibilityError");
        const encoding_compatibility_error_class_val = try self.newClass(encoding_compatibility_error_name_sym, self.encoding_error_class);
        self.encoding_compatibility_error_class = encoding_compatibility_error_class_val.toClassObject();
        const encoding_converter_not_found_error_name_sym = try self.intern("ConverterNotFoundError");
        const encoding_converter_not_found_error_class_val = try self.newClass(encoding_converter_not_found_error_name_sym, self.encoding_error_class);
        self.encoding_converter_not_found_error_class = encoding_converter_not_found_error_class_val.toClassObject();
        const encoding_undefined_conversion_error_name_sym = try self.intern("UndefinedConversionError");
        const encoding_undefined_conversion_error_class_val = try self.newClass(encoding_undefined_conversion_error_name_sym, self.encoding_error_class);
        self.encoding_undefined_conversion_error_class = encoding_undefined_conversion_error_class_val.toClassObject();
        const encoding_invalid_byte_sequence_error_name_sym = try self.intern("InvalidByteSequenceError");
        const encoding_invalid_byte_sequence_error_class_val = try self.newClass(encoding_invalid_byte_sequence_error_name_sym, self.encoding_error_class);
        self.encoding_invalid_byte_sequence_error_class = encoding_invalid_byte_sequence_error_class_val.toClassObject();

        const range_error_name_sym = try self.intern("RangeError");
        const range_error_class_val = try self.newClass(range_error_name_sym, self.standard_error_class);
        self.range_error_class = range_error_class_val.toClassObject();

        const regexp_error_name_sym = try self.intern("RegexpError");
        const regexp_error_class_val = try self.newClass(regexp_error_name_sym, self.standard_error_class);
        self.regexp_error_class = regexp_error_class_val.toClassObject();

        const index_error_name_sym = try self.intern("IndexError");
        const index_error_class_val = try self.newClass(index_error_name_sym, self.standard_error_class);
        self.index_error_class = index_error_class_val.toClassObject();

        const key_error_name_sym = try self.intern("KeyError");
        const key_error_class_val = try self.newClass(key_error_name_sym, self.index_error_class);
        self.key_error_class = key_error_class_val.toClassObject();

        const stop_iteration_name_sym = try self.intern("StopIteration");
        const stop_iteration_class_val = try self.newClass(stop_iteration_name_sym, self.index_error_class);
        self.stop_iteration_class = stop_iteration_class_val.toClassObject();

        const enoent_name_sym = try self.intern("ENOENT");
        const enoent_class_val = try self.newClass(enoent_name_sym, self.system_call_error_class);
        const eexist_name_sym = try self.intern("EEXIST");
        const eexist_class_val = try self.newClass(eexist_name_sym, self.system_call_error_class);
        const enotempty_name_sym = try self.intern("ENOTEMPTY");
        const enotempty_class_val = try self.newClass(enotempty_name_sym, self.system_call_error_class);
        const eacces_name_sym = try self.intern("EACCES");
        const eacces_class_val = try self.newClass(eacces_name_sym, self.system_call_error_class);
        const enosys_name_sym = try self.intern("ENOSYS");
        const enosys_class_val = try self.newClass(enosys_name_sym, self.system_call_error_class);
        const enotsup_name_sym = try self.intern("ENOTSUP");
        const enotsup_class_val = try self.newClass(enotsup_name_sym, self.system_call_error_class);
        const einprogress_name_sym = try self.intern("EINPROGRESS");
        const einprogress_class_val = try self.newClass(einprogress_name_sym, self.system_call_error_class);
        const eisconn_name_sym = try self.intern("EISCONN");
        const eisconn_class_val = try self.newClass(eisconn_name_sym, self.system_call_error_class);
        const eagain_name_sym = try self.intern("EAGAIN");
        const eagain_class_val = try self.newClass(eagain_name_sym, self.system_call_error_class);
        const ebadf_name_sym = try self.intern("EBADF");
        const ebadf_class_val = try self.newClass(ebadf_name_sym, self.system_call_error_class);
        const ebusy_name_sym = try self.intern("EBUSY");
        const ebusy_class_val = try self.newClass(ebusy_name_sym, self.system_call_error_class);
        const emfile_name_sym = try self.intern("EMFILE");
        const emfile_class_val = try self.newClass(emfile_name_sym, self.system_call_error_class);
        const eintr_name_sym = try self.intern("EINTR");
        const eintr_class_val = try self.newClass(eintr_name_sym, self.system_call_error_class);
        const eio_name_sym = try self.intern("EIO");
        const eio_class_val = try self.newClass(eio_name_sym, self.system_call_error_class);
        const eloop_name_sym = try self.intern("ELOOP");
        const eloop_class_val = try self.newClass(eloop_name_sym, self.system_call_error_class);
        const emlink_name_sym = try self.intern("EMLINK");
        const emlink_class_val = try self.newClass(emlink_name_sym, self.system_call_error_class);
        const enametoolong_name_sym = try self.intern("ENAMETOOLONG");
        const enametoolong_class_val = try self.newClass(enametoolong_name_sym, self.system_call_error_class);
        const enomem_name_sym = try self.intern("ENOMEM");
        const enomem_class_val = try self.newClass(enomem_name_sym, self.system_call_error_class);
        const enotconn_name_sym = try self.intern("ENOTCONN");
        const enotconn_class_val = try self.newClass(enotconn_name_sym, self.system_call_error_class);
        const enotsock_name_sym = try self.intern("ENOTSOCK");
        const enotsock_class_val = try self.newClass(enotsock_name_sym, self.system_call_error_class);
        const enotty_name_sym = try self.intern("ENOTTY");
        const enotty_class_val = try self.newClass(enotty_name_sym, self.system_call_error_class);
        const eoverflow_name_sym = try self.intern("EOVERFLOW");
        const eoverflow_class_val = try self.newClass(eoverflow_name_sym, self.system_call_error_class);
        const eperm_name_sym = try self.intern("EPERM");
        const eperm_class_val = try self.newClass(eperm_name_sym, self.system_call_error_class);
        const erange_name_sym = try self.intern("ERANGE");
        const erange_class_val = try self.newClass(erange_name_sym, self.system_call_error_class);
        const erofs_name_sym = try self.intern("EROFS");
        const erofs_class_val = try self.newClass(erofs_name_sym, self.system_call_error_class);
        const espipe_name_sym = try self.intern("ESPIPE");
        const espipe_class_val = try self.newClass(espipe_name_sym, self.system_call_error_class);
        const esrch_name_sym = try self.intern("ESRCH");
        const esrch_class_val = try self.newClass(esrch_name_sym, self.system_call_error_class);
        const enospc_name_sym = try self.intern("ENOSPC");
        const enospc_class_val = try self.newClass(enospc_name_sym, self.system_call_error_class);
        const eproto_name_sym = try self.intern("EPROTO");
        const eproto_class_val = try self.newClass(eproto_name_sym, self.system_call_error_class);
        const enoexec_name_sym = try self.intern("ENOEXEC");
        const enoexec_class_val = try self.newClass(enoexec_name_sym, self.system_call_error_class);
        const eilseq_name_sym = try self.intern("EILSEQ");
        const eilseq_class_val = try self.newClass(eilseq_name_sym, self.system_call_error_class);
        const echild_name_sym = try self.intern("ECHILD");
        const echild_class_val = try self.newClass(echild_name_sym, self.system_call_error_class);
        const einval_name_sym = try self.intern("EINVAL");
        const einval_class_val = try self.newClass(einval_name_sym, self.system_call_error_class);
        const enotdir_name_sym = try self.intern("ENOTDIR");
        const enotdir_class_val = try self.newClass(enotdir_name_sym, self.system_call_error_class);
        const eisdir_name_sym = try self.intern("EISDIR");
        const eisdir_class_val = try self.newClass(eisdir_name_sym, self.system_call_error_class);
        const eopnotsupp_name_sym = try self.intern("EOPNOTSUPP");
        const eopnotsupp_class_val = try self.newClass(eopnotsupp_name_sym, self.system_call_error_class);
        const exdev_name_sym = try self.intern("EXDEV");
        const exdev_class_val = try self.newClass(exdev_name_sym, self.system_call_error_class);
        const econnrefused_name_sym = try self.intern("ECONNREFUSED");
        const econnrefused_class_val = try self.newClass(econnrefused_name_sym, self.system_call_error_class);
        const ehostdown_name_sym = try self.intern("EHOSTDOWN");
        const ehostdown_class_val = try self.newClass(ehostdown_name_sym, self.system_call_error_class);
        const etimedout_name_sym = try self.intern("ETIMEDOUT");
        const etimedout_class_val = try self.newClass(etimedout_name_sym, self.system_call_error_class);
        const econnaborted_name_sym = try self.intern("ECONNABORTED");
        const econnaborted_class_val = try self.newClass(econnaborted_name_sym, self.system_call_error_class);
        const econnreset_name_sym = try self.intern("ECONNRESET");
        const econnreset_class_val = try self.newClass(econnreset_name_sym, self.system_call_error_class);
        const epipe_name_sym = try self.intern("EPIPE");
        const epipe_class_val = try self.newClass(epipe_name_sym, self.system_call_error_class);
        const enetunreach_name_sym = try self.intern("ENETUNREACH");
        const enetunreach_class_val = try self.newClass(enetunreach_name_sym, self.system_call_error_class);

        const io_readable_sym = try self.intern("READABLE");
        self.io_class.module.constants.put(io_readable_sym, .{ .value = Value.integer(0x001) }) catch return error.Fatal;
        const io_writable_sym = try self.intern("WRITABLE");
        self.io_class.module.constants.put(io_writable_sym, .{ .value = Value.integer(0x004) }) catch return error.Fatal;
        const io_priority_sym = try self.intern("PRIORITY");
        self.io_class.module.constants.put(io_priority_sym, .{ .value = Value.integer(0x002) }) catch return error.Fatal;

        const wait_readable_name_sym = try self.intern("WaitReadable");
        const wait_readable_module_val = try self.newModule(wait_readable_name_sym);
        const wait_readable_module = wait_readable_module_val.toModuleObject();
        self.io_class.module.constants.put(wait_readable_name_sym, .{ .value = wait_readable_module_val }) catch return error.Fatal;

        const wait_writable_name_sym = try self.intern("WaitWritable");
        const wait_writable_module_val = try self.newModule(wait_writable_name_sym);
        const wait_writable_module = wait_writable_module_val.toModuleObject();
        self.io_class.module.constants.put(wait_writable_name_sym, .{ .value = wait_writable_module_val }) catch return error.Fatal;

        const eagain_wait_readable_name_sym = try self.intern("EAGAINWaitReadable");
        const eagain_wait_readable_val = try self.newClass(eagain_wait_readable_name_sym, eagain_class_val.toClassObject());
        self.io_eagain_wait_readable_class = eagain_wait_readable_val.toClassObject();
        try self.includeModule(&self.io_eagain_wait_readable_class.module, wait_readable_module);
        self.io_class.module.constants.put(eagain_wait_readable_name_sym, .{ .value = eagain_wait_readable_val }) catch return error.Fatal;

        const eagain_wait_writable_name_sym = try self.intern("EAGAINWaitWritable");
        const eagain_wait_writable_val = try self.newClass(eagain_wait_writable_name_sym, eagain_class_val.toClassObject());
        self.io_eagain_wait_writable_class = eagain_wait_writable_val.toClassObject();
        try self.includeModule(&self.io_eagain_wait_writable_class.module, wait_writable_module);
        self.io_class.module.constants.put(eagain_wait_writable_name_sym, .{ .value = eagain_wait_writable_val }) catch return error.Fatal;

        const einprogress_wait_readable_name_sym = try self.intern("EINPROGRESSWaitReadable");
        const einprogress_wait_readable_val = try self.newClass(einprogress_wait_readable_name_sym, einprogress_class_val.toClassObject());
        try self.includeModule(&einprogress_wait_readable_val.toClassObject().module, wait_readable_module);
        self.io_class.module.constants.put(einprogress_wait_readable_name_sym, .{ .value = einprogress_wait_readable_val }) catch return error.Fatal;

        const einprogress_wait_writable_name_sym = try self.intern("EINPROGRESSWaitWritable");
        const einprogress_wait_writable_val = try self.newClass(einprogress_wait_writable_name_sym, einprogress_class_val.toClassObject());
        try self.includeModule(&einprogress_wait_writable_val.toClassObject().module, wait_writable_module);
        self.io_class.module.constants.put(einprogress_wait_writable_name_sym, .{ .value = einprogress_wait_writable_val }) catch return error.Fatal;

        const enumerator_name_sym = try self.intern("Enumerator");
        const enumerator_class_val = try self.newClass(enumerator_name_sym, self.object_class);
        self.enumerator_class = enumerator_class_val.toClassObject();

        const yielder_name_sym = try self.intern("Yielder");
        const yielder_class_val = try self.newClass(yielder_name_sym, self.object_class);
        self.yielder_class = yielder_class_val.toClassObject();

        // Encoding class and singleton encoding objects
        const encoding_name_sym = try self.intern("Encoding");
        const encoding_class_val = try self.newClass(encoding_name_sym, self.object_class);
        self.encoding_class = encoding_class_val.toClassObject();

        // Create singleton encoding objects
        self.encoding_utf8 = try self.createEncodingObject(.{ .utf8 = .{} });
        self.encoding_cesu8 = try self.createEncodingObject(.{ .cesu8 = .{} });
        self.encoding_ascii_8bit = try self.createEncodingObject(.{ .ascii_8bit = .{} });
        self.encoding_us_ascii = try self.createEncodingObject(.{ .us_ascii = .{} });
        self.encoding_shift_jis = try self.createEncodingObject(.{ .shift_jis = .{} });
        self.encoding_windows_31j = try self.createEncodingObject(.{ .windows_31j = .{} });
        self.encoding_euc_jp = try self.createEncodingObject(.{ .euc_jp = .{} });
        self.encoding_cp437 = try self.createEncodingObject(.{ .cp437 = .{} });
        self.encoding_iso_2022_jp = try self.createEncodingObject(.{ .iso_2022_jp = .{} });
        self.encoding_iso_8859_1 = try self.createEncodingObject(.{ .iso_8859_1 = .{} });
        self.encoding_iso_8859_9 = try self.createEncodingObject(.{ .iso_8859_9 = .{} });
        self.encoding_iso_8859_15 = try self.createEncodingObject(.{ .iso_8859_15 = .{} });
        self.encoding_utf7 = try self.createEncodingObject(.{ .utf7 = .{} });
        self.encoding_utf16 = try self.createEncodingObject(.{ .utf16 = .{} });
        self.encoding_utf32 = try self.createEncodingObject(.{ .utf32 = .{} });
        self.encoding_utf16le = try self.createEncodingObject(.{ .utf16le = .{} });
        self.encoding_utf16be = try self.createEncodingObject(.{ .utf16be = .{} });
        self.encoding_utf32le = try self.createEncodingObject(.{ .utf32le = .{} });
        self.encoding_utf32be = try self.createEncodingObject(.{ .utf32be = .{} });
        self.default_external_encoding = self.encoding_utf8;

        // --- Stage 3: Set Class's superclass to Module ---
        self.class_class.superclass = self.module_class;

        // --- Stage 4: Register constants in Object ---
        self.object_class.module.constants.put(class_name_sym, .{ .value = class_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(basic_object_name_sym, .{ .value = basic_object_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(object_name_sym, .{ .value = object_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(module_name_sym, .{ .value = module_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(numeric_name_sym, .{ .value = numeric_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(integer_name_sym, .{ .value = integer_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(float_name_sym, .{ .value = float_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(rational_name_sym, .{ .value = rational_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(time_name_sym, .{ .value = time_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(random_name_sym, .{ .value = random_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(string_name_sym, .{ .value = string_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(symbol_name_sym, .{ .value = symbol_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(io_name_sym, .{ .value = io_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(array_name_sym, .{ .value = array_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(hash_name_sym, .{ .value = hash_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(file_name_sym, .{ .value = file_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(dir_name_sym, .{ .value = dir_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(binding_name_sym, .{ .value = binding_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(range_name_sym, .{ .value = range_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(proc_name_sym, .{ .value = proc_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(struct_name_sym, .{ .value = struct_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(method_name_sym, .{ .value = method_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(unbound_method_name_sym, .{ .value = unbound_method_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(fiber_name_sym, .{ .value = fiber_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(thread_name_sym, .{ .value = thread_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(thread_group_name_sym, .{ .value = thread_group_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(mutex_name_sym, .{ .value = mutex_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(condition_variable_name_sym, .{ .value = condition_variable_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(queue_name_sym, .{ .value = queue_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(sized_queue_name_sym, .{ .value = sized_queue_class_val }) catch return error.Fatal;
        // Register Thread synchronization aliases.
        const default_name_sym = try self.intern("Default");
        thread_group_class_val.toClassObject().module.constants.put(default_name_sym, .{ .value = self.default_thread_group }) catch return error.Fatal;
        thread_class_val.toClassObject().module.constants.put(thread_backtrace_name_sym, .{ .value = thread_backtrace_module_val }) catch return error.Fatal;
        thread_backtrace_module_val.toModuleObject().constants.put(thread_backtrace_location_name_sym, .{ .value = thread_backtrace_location_class_val }) catch return error.Fatal;
        thread_class_val.toClassObject().module.constants.put(mutex_name_sym, .{ .value = mutex_class_val }) catch return error.Fatal;
        thread_class_val.toClassObject().module.constants.put(condition_variable_name_sym, .{ .value = condition_variable_class_val }) catch return error.Fatal;
        thread_class_val.toClassObject().module.constants.put(queue_name_sym, .{ .value = queue_class_val }) catch return error.Fatal;
        thread_class_val.toClassObject().module.constants.put(sized_queue_name_sym, .{ .value = sized_queue_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(regexp_name_sym, .{ .value = regexp_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(match_data_name_sym, .{ .value = match_data_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(nil_class_name_sym, .{ .value = nil_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(true_class_name_sym, .{ .value = true_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(false_class_name_sym, .{ .value = false_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(kernel_name_sym, .{ .value = kernel_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(process_name_sym, .{ .value = process_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(signal_name_sym, .{ .value = signal_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(warning_name_sym, .{ .value = warning_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(marshal_name_sym, .{ .value = marshal_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(errno_name_sym, .{ .value = errno_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(comparable_name_sym, .{ .value = comparable_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(enumerable_name_sym, .{ .value = enumerable_module_val }) catch return error.Fatal;
        self.object_class.module.constants.put(exception_name_sym, .{ .value = exception_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(system_exit_name_sym, .{ .value = system_exit_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(signal_exception_name_sym, .{ .value = signal_exception_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(interrupt_name_sym, .{ .value = interrupt_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(standard_error_name_sym, .{ .value = standard_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(system_call_error_name_sym, .{ .value = system_call_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(runtime_error_name_sym, .{ .value = runtime_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(syntax_error_name_sym, .{ .value = syntax_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(not_implemented_error_name_sym, .{ .value = not_implemented_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(frozen_error_name_sym, .{ .value = frozen_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(argument_error_name_sym, .{ .value = argument_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(uncaught_throw_error_name_sym, .{ .value = uncaught_throw_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(key_error_name_sym, .{ .value = key_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(type_error_name_sym, .{ .value = type_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(zero_division_error_name_sym, .{ .value = zero_division_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(name_error_name_sym, .{ .value = name_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(no_method_error_name_sym, .{ .value = no_method_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(local_jump_error_name_sym, .{ .value = local_jump_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(io_error_name_sym, .{ .value = io_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(eof_error_name_sym, .{ .value = eof_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(fiber_error_name_sym, .{ .value = fiber_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(thread_error_name_sym, .{ .value = thread_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(closed_queue_error_name_sym, .{ .value = closed_queue_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(load_error_name_sym, .{ .value = load_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(encoding_error_name_sym, .{ .value = encoding_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(range_error_name_sym, .{ .value = range_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(regexp_error_name_sym, .{ .value = regexp_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(index_error_name_sym, .{ .value = index_error_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(stop_iteration_name_sym, .{ .value = stop_iteration_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enoent_name_sym, .{ .value = enoent_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eexist_name_sym, .{ .value = eexist_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotempty_name_sym, .{ .value = enotempty_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eacces_name_sym, .{ .value = eacces_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enosys_name_sym, .{ .value = enosys_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotsup_name_sym, .{ .value = enotsup_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(einprogress_name_sym, .{ .value = einprogress_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eisconn_name_sym, .{ .value = eisconn_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eagain_name_sym, .{ .value = eagain_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(ebadf_name_sym, .{ .value = ebadf_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(ebusy_name_sym, .{ .value = ebusy_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(emfile_name_sym, .{ .value = emfile_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eintr_name_sym, .{ .value = eintr_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eio_name_sym, .{ .value = eio_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eloop_name_sym, .{ .value = eloop_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(emlink_name_sym, .{ .value = emlink_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enametoolong_name_sym, .{ .value = enametoolong_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enomem_name_sym, .{ .value = enomem_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotconn_name_sym, .{ .value = enotconn_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotsock_name_sym, .{ .value = enotsock_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotty_name_sym, .{ .value = enotty_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eoverflow_name_sym, .{ .value = eoverflow_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eperm_name_sym, .{ .value = eperm_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(erange_name_sym, .{ .value = erange_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(erofs_name_sym, .{ .value = erofs_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(espipe_name_sym, .{ .value = espipe_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(esrch_name_sym, .{ .value = esrch_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enospc_name_sym, .{ .value = enospc_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eproto_name_sym, .{ .value = eproto_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enoexec_name_sym, .{ .value = enoexec_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eilseq_name_sym, .{ .value = eilseq_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(echild_name_sym, .{ .value = echild_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(einval_name_sym, .{ .value = einval_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enotdir_name_sym, .{ .value = enotdir_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eisdir_name_sym, .{ .value = eisdir_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(eopnotsupp_name_sym, .{ .value = eopnotsupp_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(exdev_name_sym, .{ .value = exdev_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(econnrefused_name_sym, .{ .value = econnrefused_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(ehostdown_name_sym, .{ .value = ehostdown_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(etimedout_name_sym, .{ .value = etimedout_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(econnaborted_name_sym, .{ .value = econnaborted_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(econnreset_name_sym, .{ .value = econnreset_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(epipe_name_sym, .{ .value = epipe_class_val }) catch return error.Fatal;
        self.errno_module.constants.put(enetunreach_name_sym, .{ .value = enetunreach_class_val }) catch return error.Fatal;
        try self.registerErrnoClass(.NOENT, enoent_class_val.toClassObject());
        try self.registerErrnoClass(.EXIST, eexist_class_val.toClassObject());
        try self.registerErrnoClass(.NOTEMPTY, enotempty_class_val.toClassObject());
        try self.registerErrnoClass(.ACCES, eacces_class_val.toClassObject());
        try self.registerErrnoClass(.NOSYS, enosys_class_val.toClassObject());
        if (@hasField(std.posix.E, "NOTSUP")) {
            try self.registerErrnoClass(@field(std.posix.E, "NOTSUP"), enotsup_class_val.toClassObject());
        } else if (@hasField(std.posix.E, "OPNOTSUPP")) {
            try self.registerErrnoClass(@field(std.posix.E, "OPNOTSUPP"), enotsup_class_val.toClassObject());
        }
        try self.registerErrnoClass(.INPROGRESS, einprogress_class_val.toClassObject());
        try self.registerErrnoClass(.ISCONN, eisconn_class_val.toClassObject());
        try self.registerErrnoClass(.AGAIN, eagain_class_val.toClassObject());
        try self.registerErrnoClass(.BADF, ebadf_class_val.toClassObject());
        try self.registerErrnoClass(.BUSY, ebusy_class_val.toClassObject());
        try self.registerErrnoClass(.MFILE, emfile_class_val.toClassObject());
        try self.registerErrnoClass(.INTR, eintr_class_val.toClassObject());
        try self.registerErrnoClass(.IO, eio_class_val.toClassObject());
        try self.registerErrnoClass(.LOOP, eloop_class_val.toClassObject());
        try self.registerErrnoClass(.MLINK, emlink_class_val.toClassObject());
        try self.registerErrnoClass(.NAMETOOLONG, enametoolong_class_val.toClassObject());
        try self.registerErrnoClass(.NOMEM, enomem_class_val.toClassObject());
        try self.registerErrnoClass(.NOTCONN, enotconn_class_val.toClassObject());
        try self.registerErrnoClass(.NOTSOCK, enotsock_class_val.toClassObject());
        try self.registerErrnoClass(.NOTTY, enotty_class_val.toClassObject());
        try self.registerErrnoClass(.OVERFLOW, eoverflow_class_val.toClassObject());
        try self.registerErrnoClass(.PERM, eperm_class_val.toClassObject());
        try self.registerErrnoClass(.RANGE, erange_class_val.toClassObject());
        try self.registerErrnoClass(.ROFS, erofs_class_val.toClassObject());
        try self.registerErrnoClass(.SPIPE, espipe_class_val.toClassObject());
        try self.registerErrnoClass(.SRCH, esrch_class_val.toClassObject());
        try self.registerErrnoClass(.NOSPC, enospc_class_val.toClassObject());
        try self.registerErrnoClass(.PROTO, eproto_class_val.toClassObject());
        try self.registerErrnoClass(.NOEXEC, enoexec_class_val.toClassObject());
        if (@hasField(std.posix.E, "ILSEQ")) {
            try self.registerErrnoClass(@field(std.posix.E, "ILSEQ"), eilseq_class_val.toClassObject());
        }
        try self.registerErrnoClass(.CHILD, echild_class_val.toClassObject());
        try self.registerErrnoClass(.INVAL, einval_class_val.toClassObject());
        try self.registerErrnoClass(.NOTDIR, enotdir_class_val.toClassObject());
        try self.registerErrnoClass(.ISDIR, eisdir_class_val.toClassObject());
        try self.registerErrnoClass(.XDEV, exdev_class_val.toClassObject());
        try self.registerErrnoClass(.CONNREFUSED, econnrefused_class_val.toClassObject());
        if (@hasField(std.posix.E, "HOSTDOWN")) {
            try self.registerErrnoClass(@field(std.posix.E, "HOSTDOWN"), ehostdown_class_val.toClassObject());
        }
        try self.registerErrnoClass(.TIMEDOUT, etimedout_class_val.toClassObject());
        try self.registerErrnoClass(.CONNABORTED, econnaborted_class_val.toClassObject());
        try self.registerErrnoClass(.CONNRESET, econnreset_class_val.toClassObject());
        try self.registerErrnoClass(.PIPE, epipe_class_val.toClassObject());
        try self.registerErrnoClass(.NETUNREACH, enetunreach_class_val.toClassObject());
        self.object_class.module.constants.put(enumerator_name_sym, .{ .value = enumerator_class_val }) catch return error.Fatal;
        self.enumerator_class.module.constants.put(yielder_name_sym, .{ .value = yielder_class_val }) catch return error.Fatal;
        self.object_class.module.constants.put(encoding_name_sym, .{ .value = encoding_class_val }) catch return error.Fatal;
        const ruby_engine_sym = try self.intern("RUBY_ENGINE");
        const ruby_version_sym = try self.intern("RUBY_VERSION");
        const ruby_platform_sym = try self.intern("RUBY_PLATFORM");
        const ruby_patchlevel_sym = try self.intern("RUBY_PATCHLEVEL");
        const ruby_description_sym = try self.intern("RUBY_DESCRIPTION");
        const marshal_major_version_sym = try self.intern("MAJOR_VERSION");
        const marshal_minor_version_sym = try self.intern("MINOR_VERSION");
        const rbconfig_sym = try self.intern("RbConfig");
        const config_sym = try self.intern("CONFIG");
        const topdir_sym = try self.intern("TOPDIR");
        const rbconfig_ruby_engine = "cora";
        const rbconfig_ruby_version = "4.0.0";
        const rbconfig_prefix = "/usr";
        const rbconfig_libdir = "/usr/lib";
        const ruby_platform = comptime std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
        const rbconfig_rubylibprefix = rbconfig_libdir;
        const rbconfig_rubylibdir = comptime std.fmt.comptimePrint("{s}/ruby/{s}", .{ rbconfig_rubylibprefix, rbconfig_ruby_version });
        const rbconfig_archdir = comptime std.fmt.comptimePrint("{s}/{s}", .{ rbconfig_rubylibdir, ruby_platform });
        const rbconfig_sitelibdir = comptime std.fmt.comptimePrint("{s}/site_ruby/{s}", .{ rbconfig_rubylibprefix, rbconfig_ruby_version });
        const rbconfig_vendordir = comptime std.fmt.comptimePrint("{s}/vendor_ruby", .{rbconfig_rubylibprefix});
        const rbconfig_vendorlibdir = comptime std.fmt.comptimePrint("{s}/{s}", .{ rbconfig_vendordir, rbconfig_ruby_version });
        const rbconfig_mandir = comptime std.fmt.comptimePrint("{s}/share/man", .{rbconfig_prefix});
        const ruby_engine_val = try self.newString(rbconfig_ruby_engine, true);
        const ruby_version_val = try self.newString(rbconfig_ruby_version, true);
        const ruby_platform_val = try self.newString(ruby_platform, true);
        const ruby_description = comptime std.fmt.comptimePrint("cora 4.0.0p0 ({s}-{s})", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
        const ruby_description_val = try self.newString(ruby_description, true);
        const ruby_engine_version_sym = try self.intern("RUBY_ENGINE_VERSION");
        const ruby_copyright_sym = try self.intern("RUBY_COPYRIGHT");
        const ruby_release_date_sym = try self.intern("RUBY_RELEASE_DATE");
        const ruby_revision_sym = try self.intern("RUBY_REVISION");
        const ruby_engine_version_val = try self.newString(rbconfig_ruby_version, true);
        const ruby_copyright_val = try self.newString("Copyright 2026, Tim Morgan", true);
        const ruby_release_date_val = try self.newString("2026-01-01", true);
        const ruby_revision_val = try self.newString("0", true);
        self.object_class.module.constants.put(ruby_engine_sym, .{ .value = ruby_engine_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_version_sym, .{ .value = ruby_version_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_platform_sym, .{ .value = ruby_platform_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_patchlevel_sym, .{ .value = Value.integer(0) }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_description_sym, .{ .value = ruby_description_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_engine_version_sym, .{ .value = ruby_engine_version_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_copyright_sym, .{ .value = ruby_copyright_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_release_date_sym, .{ .value = ruby_release_date_val }) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_revision_sym, .{ .value = ruby_revision_val }) catch return error.Fatal;
        self.marshal_module.constants.put(marshal_major_version_sym, .{ .value = Value.integer(4) }) catch return error.Fatal;
        self.marshal_module.constants.put(marshal_minor_version_sym, .{ .value = Value.integer(8) }) catch return error.Fatal;

        const rbconfig_val = try self.newModule(rbconfig_sym);
        const rbconfig_module = rbconfig_val.toModuleObject();
        const rbconfig_config_obj = try self.createHash();
        const rbconfig_config_val = Value.fromObject(&rbconfig_config_obj.object);
        const rbconfig_config = rbconfig_config_val.toHashObject();
        try self.hashSetEntry(rbconfig_config, try self.newString("MAJOR", false), try self.newString("4", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("MINOR", false), try self.newString("0", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("TEENY", false), try self.newString("0", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("PATCHLEVEL", false), try self.newString("0", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("host_cpu", false), try self.newString(@tagName(builtin.cpu.arch), false));
        try self.hashSetEntry(rbconfig_config, try self.newString("host_os", false), try self.newString(rbConfigHostOs(), false));
        try self.hashSetEntry(rbconfig_config, try self.newString("host_vendor", false), try self.newString("unknown", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("arch", false), try self.newString(ruby_platform, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("DLEXT", false), try self.newString(rbConfigSharedLibraryExtension(), false));
        try self.hashSetEntry(rbconfig_config, try self.newString("SOEXT", false), try self.newString(rbConfigSharedLibraryExtension(), false));
        try self.hashSetEntry(rbconfig_config, try self.newString("ENABLE_SHARED", false), try self.newString("no", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("LIBRUBY", false), try self.newString("libcora-static.a", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("LIBRUBY_SO", false), try self.newString("libcora.so", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("LIBPATHENV", false), try self.newString("LD_LIBRARY_PATH", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("libdirname", false), try self.newString("libdir", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("libdir", false), try self.newString(rbconfig_libdir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("bindir", false), try self.newString("/usr/bin", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("prefix", false), try self.newString(rbconfig_prefix, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("platform", false), try self.newString(ruby_platform, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("target_os", false), try self.newString(rbConfigHostOs(), false));
        try self.hashSetEntry(rbconfig_config, try self.newString("ruby_version", false), try self.newString(rbconfig_ruby_version, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("ruby_install_name", false), try self.newString(rbconfig_ruby_engine, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("rubylibprefix", false), try self.newString(rbconfig_rubylibprefix, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("rubylibdir", false), try self.newString(rbconfig_rubylibdir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("archdir", false), try self.newString(rbconfig_archdir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("sitelibdir", false), try self.newString(rbconfig_sitelibdir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("vendordir", false), try self.newString(rbconfig_vendordir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("vendorlibdir", false), try self.newString(rbconfig_vendorlibdir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("sysconfdir", false), try self.newString("/etc", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("mandir", false), try self.newString(rbconfig_mandir, false));
        try self.hashSetEntry(rbconfig_config, try self.newString("EXECUTABLE_EXTS", false), try self.newString("", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("AR", false), try self.newString("ar", false));
        try self.hashSetEntry(rbconfig_config, try self.newString("STRIP", false), try self.newString("strip", false));
        rbconfig_module.constants.put(config_sym, .{ .value = rbconfig_config_val }) catch return error.Fatal;
        rbconfig_module.constants.put(topdir_sym, .{ .value = Value.nil() }) catch return error.Fatal;
        self.object_class.module.constants.put(rbconfig_sym, .{ .value = rbconfig_val }) catch return error.Fatal;
        try self.setArgv(&[_][]const u8{});

        const stdin_sym = try self.intern("STDIN");
        const stdout_sym = try self.intern("STDOUT");
        const stderr_sym = try self.intern("STDERR");
        const stdin_obj = try self.newIo(self.io_class, 0, .{ .owns_fd = false, .readable = true, .writable = false });
        const stdout_obj = try self.newIo(self.io_class, 1, .{ .owns_fd = false, .readable = false, .writable = true, .sync = true });
        const stderr_obj = try self.newIo(self.io_class, 2, .{ .owns_fd = false, .readable = false, .writable = true, .sync = true });
        self.object_class.module.constants.put(stdin_sym, .{ .value = stdin_obj }) catch return error.Fatal;
        self.object_class.module.constants.put(stdout_sym, .{ .value = stdout_obj }) catch return error.Fatal;
        self.object_class.module.constants.put(stderr_sym, .{ .value = stderr_obj }) catch return error.Fatal;
        try self.setGlobal("$stdin", stdin_obj);
        try self.setGlobal("$stdout", stdout_obj);
        try self.setGlobal("$stderr", stderr_obj);
        try self.setGlobal("$VERBOSE", Value.boolean(false));
        try self.setGlobal("$/", try self.newString("\n", false));
        try self.setGlobal("$-0", Value.nil());

        const env_obj = try self.newInstance(self.object_class);
        self.env_object = env_obj;
        const env_sym = try self.intern("ENV");
        self.object_class.module.constants.put(env_sym, .{ .value = env_obj }) catch return error.Fatal;

        // Register encoding constants on Encoding class
        const utf8_const_sym = try self.intern("UTF_8");
        const cesu8_const_sym = try self.intern("CESU_8");
        const ascii_8bit_const_sym = try self.intern("ASCII_8BIT");
        const binary_const_sym = try self.intern("BINARY");
        const us_ascii_const_sym = try self.intern("US_ASCII");
        const ascii_const_sym = try self.intern("ASCII");
        const shift_jis_const_sym = try self.intern("SHIFT_JIS");
        const shift_jis_mixed_const_sym = try self.intern("Shift_JIS");
        const sjis_const_sym = try self.intern("SJIS");
        const windows_31j_const_sym = try self.intern("Windows_31J");
        const euc_jp_const_sym = try self.intern("EUC_JP");
        const iso_8859_1_const_sym = try self.intern("ISO_8859_1");
        const iso_8859_2_const_sym = try self.intern("ISO_8859_2");
        const iso_8859_3_const_sym = try self.intern("ISO_8859_3");
        const iso_8859_4_const_sym = try self.intern("ISO_8859_4");
        const iso_8859_5_const_sym = try self.intern("ISO_8859_5");
        const iso_8859_6_const_sym = try self.intern("ISO_8859_6");
        const iso_8859_7_const_sym = try self.intern("ISO_8859_7");
        const iso_8859_8_const_sym = try self.intern("ISO_8859_8");
        const iso_8859_9_const_sym = try self.intern("ISO_8859_9");
        const iso8859_9_const_sym = try self.intern("ISO8859_9");
        const iso_8859_15_const_sym = try self.intern("ISO_8859_15");
        const utf7_const_sym = try self.intern("UTF_7");
        const utf16_const_sym = try self.intern("UTF_16");
        const utf16le_const_sym = try self.intern("UTF_16LE");
        const utf16be_const_sym = try self.intern("UTF_16BE");
        const utf32_const_sym = try self.intern("UTF_32");
        const utf32le_const_sym = try self.intern("UTF_32LE");
        const utf32be_const_sym = try self.intern("UTF_32BE");
        const iso_2022_jp_const_sym = try self.intern("ISO_2022_JP");
        const emacs_mule_const_sym = try self.intern("Emacs_Mule");
        const windows_1251_const_sym = try self.intern("Windows_1251");
        const converter_const_sym = try self.intern("Converter");

        const utf8_val = Value.fromObject(&self.encoding_utf8.object);
        const cesu8_val = Value.fromObject(&self.encoding_cesu8.object);
        const ascii_8bit_val = Value.fromObject(&self.encoding_ascii_8bit.object);
        const us_ascii_val = Value.fromObject(&self.encoding_us_ascii.object);
        const shift_jis_val = Value.fromObject(&self.encoding_shift_jis.object);
        const windows_31j_val = Value.fromObject(&self.encoding_windows_31j.object);
        const euc_jp_val = Value.fromObject(&self.encoding_euc_jp.object);
        const cp437_val = Value.fromObject(&self.encoding_cp437.object);
        const iso_8859_1_val = Value.fromObject(&self.encoding_iso_8859_1.object);
        const iso_8859_9_val = Value.fromObject(&self.encoding_iso_8859_9.object);
        const iso_8859_15_val = Value.fromObject(&self.encoding_iso_8859_15.object);
        const utf7_val = Value.fromObject(&self.encoding_utf7.object);
        const utf16_val = Value.fromObject(&self.encoding_utf16.object);
        const utf32_val = Value.fromObject(&self.encoding_utf32.object);
        const utf16le_val = Value.fromObject(&self.encoding_utf16le.object);
        const utf16be_val = Value.fromObject(&self.encoding_utf16be.object);
        const utf32le_val = Value.fromObject(&self.encoding_utf32le.object);
        const utf32be_val = Value.fromObject(&self.encoding_utf32be.object);
        const encoding_converter_class_val = try self.newClass(converter_const_sym, self.object_class);

        self.encoding_class.module.constants.put(utf8_const_sym, .{ .value = utf8_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(cesu8_const_sym, .{ .value = cesu8_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(ascii_8bit_const_sym, .{ .value = ascii_8bit_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(binary_const_sym, .{ .value = ascii_8bit_val }) catch return error.Fatal; // BINARY is alias for ASCII_8BIT
        self.encoding_class.module.constants.put(us_ascii_const_sym, .{ .value = us_ascii_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(ascii_const_sym, .{ .value = us_ascii_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(shift_jis_const_sym, .{ .value = shift_jis_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(shift_jis_mixed_const_sym, .{ .value = shift_jis_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(sjis_const_sym, .{ .value = windows_31j_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(windows_31j_const_sym, .{ .value = windows_31j_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(euc_jp_const_sym, .{ .value = euc_jp_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_1_const_sym, .{ .value = iso_8859_1_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_2_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_3_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_4_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_5_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_6_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_7_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_8_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_9_const_sym, .{ .value = iso_8859_9_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso8859_9_const_sym, .{ .value = iso_8859_9_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_15_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf7_const_sym, .{ .value = utf7_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16_const_sym, .{ .value = utf16_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16le_const_sym, .{ .value = utf16le_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16be_const_sym, .{ .value = utf16be_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32_const_sym, .{ .value = utf32_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32le_const_sym, .{ .value = utf32le_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32be_const_sym, .{ .value = utf32be_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_2022_jp_const_sym, .{ .value = Value.fromObject(&self.encoding_iso_2022_jp.object) }) catch return error.Fatal;
        self.encoding_class.module.constants.put(emacs_mule_const_sym, .{ .value = windows_31j_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(windows_1251_const_sym, .{ .value = iso_8859_15_val }) catch return error.Fatal;
        const ibm437_const_sym = try self.intern("IBM437");
        self.encoding_class.module.constants.put(ibm437_const_sym, .{ .value = cp437_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(converter_const_sym, .{ .value = encoding_converter_class_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_compatibility_error_name_sym, .{ .value = encoding_compatibility_error_class_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_converter_not_found_error_name_sym, .{ .value = encoding_converter_not_found_error_class_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_undefined_conversion_error_name_sym, .{ .value = encoding_undefined_conversion_error_class_val }) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_invalid_byte_sequence_error_name_sym, .{ .value = encoding_invalid_byte_sequence_error_class_val }) catch return error.Fatal;

        // --- Stage 5: Register built-in methods ---
        builtins.registerAll(self) catch return error.Fatal;
        comparable_builtin.register(self, comparable_module_val.toModuleObject()) catch return error.Fatal;
        self.integer_changed = false;
        self.struct_class.struct_members = try self.createArray();

        // Initialize last process status global.
        try self.setGlobal("$?", Value.nil());
        try self.clearLastMatch();
        try self.syncLoadedFeaturesGlobals();
        try self.syncLoadPathGlobals();

        try self.includeModule(&self.object_class.module, self.kernel_module);
        try self.includeModule(&self.array_class.module, enumerable_module_val.toModuleObject());
        try self.includeModule(&self.hash_class.module, enumerable_module_val.toModuleObject());
        try self.includeModule(&self.struct_class.module, enumerable_module_val.toModuleObject());
        try self.includeModule(&self.range_class.module, enumerable_module_val.toModuleObject());
        try self.includeModule(&self.enumerator_class.module, enumerable_module_val.toModuleObject());
        try self.includeModule(&self.string_class.module, comparable_module_val.toModuleObject());
        try self.includeModule(&self.symbol_class.module, comparable_module_val.toModuleObject());
        try self.includeModule(&self.time_class.module, comparable_module_val.toModuleObject());
        try self.includeModule(&self.rational_class.module, comparable_module_val.toModuleObject());

        // Create top-level self (Ruby "main" object)
        self.main_self = try self.newInstance(self.object_class);

        // --- Stage 6: Initialize top-level lexical scope ---
        self.current_lexical_scope = try self.createLexicalScope(Value.fromObject(&self.object_class.module.object), null);
        self.toplevel_lexical_scope = self.current_lexical_scope;
        const toplevel_binding = try self.createBinding(self.main_self, null, self.current_lexical_scope);
        const toplevel_binding_sym = try self.intern("TOPLEVEL_BINDING");
        self.object_class.module.constants.put(toplevel_binding_sym, .{ .value = Value.fromObject(&toplevel_binding.object) }) catch return error.Fatal;

        // --- Stage 7: Initialize main fiber and bind VM state to it ---
        const main_fiber_obj = self.gc_allocator.create(value.FiberObject) catch return error.Fatal;
        main_fiber_obj.object = .{ .type_tag = .fiber, .flags = 0, .class = self.fiber_class, .singleton_class = null, .instance_variables = null };
        main_fiber_obj.state = .running;
        main_fiber_obj.block = null;
        initFiberValueStackInPlace(&main_fiber_obj.stack);
        initFiberFrameStackInPlace(&main_fiber_obj.frames);
        main_fiber_obj.current_lexical_scope = self.current_lexical_scope;
        main_fiber_obj.caller = null;
        main_fiber_obj.coro = null;
        main_fiber_obj.coro_event = .none;
        main_fiber_obj.coro_result = Value.nil();
        main_fiber_obj.coro_exception = null;
        main_fiber_obj.first_resume_args = undefined;
        main_fiber_obj.first_resume_argc = 0;
        main_fiber_obj.fiber_locals = null;
        main_fiber_obj.owner_thread = null;
        main_fiber_obj.owner_vm = self;
        self.main_fiber = main_fiber_obj;
        self.current_fiber = main_fiber_obj;
        try self.ensureFiberCatchStack(main_fiber_obj);
        self.restoreFiberState(main_fiber_obj);
        self.zio_main_context = undefined;

        try self.buildProgramCallsiteDescriptors();
        try self.internProgramLiteralSymbols();
    }

    pub fn createLexicalScope(self: *VM, scope_module_val: Value, parent: ?*LexicalScope) VMError!*LexicalScope {
        const scope = self.allocator.create(LexicalScope) catch return error.Fatal;
        if (scope_module_val.isClass()) {
            scope.* = .{
                .scope_module = .{ .class = scope_module_val.toClassObject() },
                .parent = parent,
            };
        } else if (scope_module_val.isModule()) {
            scope.* = .{
                .scope_module = .{ .module = scope_module_val.toModuleObject() },
                .parent = parent,
            };
        } else unreachable;
        self.lexical_scopes.append(self.allocator, scope) catch return error.Fatal;
        return scope;
    }

    pub fn cloneLexicalScope(self: *VM, original: *LexicalScope, parent: ?*LexicalScope) VMError!*LexicalScope {
        const scope_module_val = switch (original.scope_module) {
            .class => |klass| Value.fromObject(&klass.module.object),
            .module => |mod| Value.fromObject(&mod.object),
        };
        const scope = try self.createLexicalScope(scope_module_val, parent);
        scope.default_method_visibility = original.default_method_visibility;
        scope.module_function_mode = original.module_function_mode;
        return scope;
    }

    inline fn frameScopeValue(
        self: *VM,
        lexical_scope: ?*LexicalScope,
        class_variable_scope: ?*LexicalScope,
        method_definition_target: ?Value,
    ) VMError!Value {
        if (class_variable_scope == null and method_definition_target == null) {
            return if (lexical_scope) |scope| .{ .raw = @intFromPtr(scope) } else .{ .raw = 0 };
        }

        const ctx = self.allocator.create(FrameScopeContext) catch return error.Fatal;
        errdefer self.allocator.destroy(ctx);
        ctx.* = .{
            .lexical_scope = lexical_scope,
            .class_variable_scope = class_variable_scope,
            .method_definition_target = method_definition_target,
        };
        self.frame_scope_contexts.append(self.allocator, ctx) catch return error.Fatal;
        return .{ .raw = @intFromPtr(ctx) | FRAME_SCOPE_CONTEXT_TAG };
    }

    // Create new stack-allocated environment
    // Dereference environment pointer, following forwarding pointer if needed
    /// Encode a [*]Value ep pointer as a Value for storage in env-data slots.
    /// Uses raw pointer bits directly; BDW GC conservatively scans these.
    pub inline fn encodeEp(ep: [*]Value) Value {
        return .{ .raw = @intFromPtr(ep) };
    }

    /// Decode a parent-ep Value back to a [*]Value pointer.
    /// Returns null if the slot is zero (no parent).
    pub inline fn decodeEp(v: Value) ?[*]Value {
        if (v.raw == 0) return null;
        return @ptrFromInt(v.raw);
    }

    /// Read the lexical scope from an ep's env-data[1] slot.
    pub inline fn epLexScope(ep: [*]Value) ?*LexicalScope {
        const raw = ep[1].raw;
        if (raw == 0) return null;
        if ((raw & FRAME_SCOPE_CONTEXT_TAG) != 0) return epFrameScopeContext(ep).?.lexical_scope;
        return @ptrFromInt(raw);
    }

    fn epFrameScopeContext(ep: [*]Value) ?*FrameScopeContext {
        const raw = ep[1].raw;
        if ((raw & FRAME_SCOPE_CONTEXT_TAG) == 0) return null;
        return @ptrFromInt(raw & ~@as(usize, FRAME_SCOPE_CONTEXT_TAG));
    }

    fn epClassVariableScope(ep: [*]Value) ?*LexicalScope {
        if (epFrameScopeContext(ep)) |ctx| {
            if (ctx.class_variable_scope) |scope| return scope;
            return ctx.lexical_scope;
        }
        return epLexScope(ep);
    }

    fn epMethodDefinitionTarget(ep: [*]Value) ?Value {
        return if (epFrameScopeContext(ep)) |ctx| ctx.method_definition_target else null;
    }

    /// Read the locals_count stored in env-data[2] of an ep.
    pub inline fn epLocalsCount(ep: [*]Value) u16 {
        return @intCast(ep[2].toInteger());
    }

    /// Get a pointer to local slot `idx` (0-based) from an ep and its locals_count.
    pub inline fn localSlot(ep: [*]Value, locals_count: u16, idx: u16) *Value {
        return @ptrCast(ep - locals_count + idx);
    }

    fn currentNonLocalReturnTarget(self: *VM) ?[*]Value {
        if (self.frames.items.len == 0) return null;

        var frame_idx = self.frames.items.len;
        while (frame_idx > 0) {
            frame_idx -= 1;
            const frame = self.frames.items[frame_idx];
            if (frame.frame_type != .method) continue;
            if (frame.method_name == null) continue;
            return frame.ep;
        }

        return null;
    }

    fn findActiveReturnTargetMethodFrameIndex(self: *VM, target_ep: [*]Value) ?usize {
        if (self.frames.items.len == 0) return null;

        const target_raw = @intFromPtr(target_ep);
        var frame_idx = self.frames.items.len;
        while (frame_idx > 0) {
            frame_idx -= 1;
            const frame = self.frames.items[frame_idx];
            if (frame.frame_type != .method) continue;
            if (@intFromPtr(frame.ep) == target_raw) return frame_idx;
        }

        return null;
    }

    fn startNonLocalReturn(self: *VM, frame_type: CallFrame.FrameType, return_target_ep: ?[*]Value, result: Value) VMError!void {
        if (frame_type == .fiber) {
            const exc = try self.createException(self.local_jump_error_class, "return from fiber");
            self.setPendingException(exc);
            return error.Unwind;
        }

        const target_ep = return_target_ep orelse {
            const exc = try self.createException(self.local_jump_error_class, "unexpected return");
            self.setPendingException(exc);
            return error.Unwind;
        };
        const target_frame_idx = self.findActiveReturnTargetMethodFrameIndex(target_ep) orelse {
            const exc = try self.createException(self.local_jump_error_class, "unexpected return");
            self.setPendingException(exc);
            return error.Unwind;
        };

        self.setPendingControlFlow(.{
            .kind = .return_,
            .value = result,
            .target_frame_idx = target_frame_idx,
        });
        return error.Unwind;
    }

    /// Promote the ep of a live frame to the GC heap (for closure capture).
    /// Returns the heap ep pointer.  Idempotent: if the ep already lives outside
    /// the fiber's value stack, it is returned as-is.
    fn promoteFrameToHeap(self: *VM, target_ep: [*]Value) VMError![*]Value {
        // Determine if ep is stack-resident by checking address range.
        const stack_start = @intFromPtr(&self.stack.storage[0]);
        const stack_end = stack_start + MAX_FIBER_STACK_SIZE * @sizeOf(Value);
        const ep_addr = @intFromPtr(target_ep);
        if (ep_addr < stack_start or ep_addr >= stack_end) {
            // Already on the heap — idempotent.
            return target_ep;
        }

        const locals_count = epLocalsCount(target_ep);
        const env_size: usize = locals_count + ENV_DATA_SIZE;

        // Allocate heap storage (locals + env_data), copy from stack.
        const heap_storage = self.gc_allocator.alloc(Value, env_size) catch return error.Fatal;
        const src_start: [*]Value = target_ep - locals_count;
        @memcpy(heap_storage, src_start[0..env_size]);

        const new_ep: [*]Value = heap_storage[locals_count..].ptr;

        // Recursively promote parent ep if it is also stack-resident.
        if (decodeEp(new_ep[0])) |parent_ep| {
            const promoted_parent = try self.promoteFrameToHeap(parent_ep);
            if (@intFromPtr(promoted_parent) != @intFromPtr(parent_ep))
                new_ep[0] = encodeEp(promoted_parent);
        }

        // Patch all live references that still point at target_ep.
        try self.updateEpReferences(target_ep, new_ep);

        return new_ep;
    }

    fn updateEpReferences(self: *VM, old_ep: [*]Value, new_ep: [*]Value) VMError!void {
        const old_raw = @intFromPtr(old_ep);
        const new_val = encodeEp(new_ep);

        for (self.frames.items) |*f| {
            if (@intFromPtr(f.ep) == old_raw) f.ep = new_ep;
            if (f.return_target_ep) |rte| {
                if (@intFromPtr(rte) == old_raw) f.return_target_ep = new_ep;
            }
            if (f.block) |*blk| {
                if (blk.kind == .chunk) {
                    if (@intFromPtr(blk.kind.chunk.defining_ep) == old_raw)
                        blk.kind.chunk.defining_ep = new_ep;
                    if (blk.kind.chunk.return_target_ep) |rte| {
                        if (@intFromPtr(rte) == old_raw)
                            blk.kind.chunk.return_target_ep = new_ep;
                    }
                }
            }
        }

        // Update parent_ep env-data slot (ep[0]) in all live on-stack frames.
        for (self.frames.items) |*f| {
            if (f.ep[0].raw == old_raw) f.ep[0] = new_val;
        }
    }

    fn autoloadTableForModule(module_obj: *value.ModuleObject) *std.AutoHashMap(*SymbolObject, []const u8) {
        return &module_obj.autoloads;
    }

    fn moduleDisplayNameForWarning(self: *VM, module_obj: *value.ModuleObject) VMError![]const u8 {
        _ = self;
        return module_obj.name.name;
    }

    fn warnDeprecatedConstant(self: *VM, module_obj: *value.ModuleObject, name_sym: *value.SymbolObject) VMError!void {
        if (!self.warning_deprecated_enabled) return;
        const entry = module_obj.constants.get(name_sym) orelse return;
        if (!entry.flags.deprecated) return;

        const module_name = try self.moduleDisplayNameForWarning(module_obj);
        const warning = std.fmt.allocPrint(
            self.allocator,
            "warning: constant {s}::{s} is deprecated\n",
            .{ module_name, name_sym.name },
        ) catch return error.Fatal;
        defer self.allocator.free(warning);
        try warning_builtin.writeWarning(self, warning);
    }

    fn raisePrivateConstantReference(self: *VM, module_obj: *value.ModuleObject, name_sym: *value.SymbolObject) VMError!void {
        const msg = std.fmt.allocPrint(
            self.gc_allocator,
            "private constant {s}::{s} referenced",
            .{ module_obj.name.name, name_sym.name },
        ) catch return error.Fatal;
        const exc = try self.createException(self.name_error_class, msg);
        self.setPendingException(exc);
        return error.Unwind;
    }

    pub fn autoloadTableForReceiver(self: *VM, receiver: Value) ?*std.AutoHashMap(*SymbolObject, []const u8) {
        _ = self;
        if (receiver.isClass()) return &receiver.toClassObject().module.autoloads;
        if (receiver.isModule()) return &receiver.toModuleObject().autoloads;
        return null;
    }

    pub fn registerAutoload(self: *VM, module_obj: *value.ModuleObject, name_sym: *value.SymbolObject, path: []const u8) VMError!void {
        const stored_path = self.gc_allocator_atomic.dupe(u8, path) catch return error.Fatal;
        autoloadTableForModule(module_obj).put(name_sym, stored_path) catch return error.Fatal;
    }

    pub fn clearAutoload(self: *VM, module_obj: *value.ModuleObject, name_sym: *value.SymbolObject) void {
        _ = self;
        _ = autoloadTableForModule(module_obj).remove(name_sym);
    }

    const TriggerAutoloadResult = union(enum) {
        missing,
        loaded: Value,
        attempted,
    };

    const LexicalConstantLookupResult = struct {
        value: ?Value = null,
        object_autoload_attempted: bool = false,
    };

    fn autoloadRequireReceiver(self: *VM) VMError!Value {
        return self.main_self;
    }

    fn triggerAutoload(self: *VM, module_obj: *value.ModuleObject, name_sym: *value.SymbolObject) VMError!TriggerAutoloadResult {
        const feature = autoloadTableForModule(module_obj).get(name_sym) orelse return .missing;
        const require_arg = try self.newString(feature, false);
        var require_args = [_]Value{require_arg};
        _ = try self.callMethodByName(try self.autoloadRequireReceiver(), "require", require_args[0..], null);
        if (module_obj.constants.get(name_sym)) |loaded| {
            self.clearAutoload(module_obj, name_sym);
            return .{ .loaded = loaded.value };
        }
        return .attempted;
    }

    fn findConstantInLexicalScope(self: *VM, scope: *LexicalScope, name: *value.SymbolObject) VMError!LexicalConstantLookupResult {
        var result = LexicalConstantLookupResult{};
        var current_scope: ?*LexicalScope = scope;
        while (current_scope) |s| {
            const module_obj = s.getModule();
            if (module_obj.constants.get(name)) |entry| {
                try self.warnDeprecatedConstant(module_obj, name);
                result.value = entry.value;
                return result;
            }
            switch (try self.triggerAutoload(module_obj, name)) {
                .missing => {},
                .loaded => |val| {
                    result.value = val;
                    return result;
                },
                .attempted => {
                    if (module_obj == &self.object_class.module) {
                        result.object_autoload_attempted = true;
                    }
                },
            }
            current_scope = s.parent;
        }

        // After the lexical scope chain, walk the ancestors (included modules +
        // superclass chain) of the innermost scope — matching Ruby's constant
        // lookup rule that the inheritance hierarchy of Module.nesting.first is
        // searched after the purely lexical pass.
        // Skip Object if autoload was already attempted during the lexical walk.
        switch (scope.scope_module) {
            .class => |klass| {
                if (try self.findConstantInClassAncestors(klass, name, result.object_autoload_attempted)) |val| {
                    result.value = val;
                    return result;
                }
            },
            .module => |mod| {
                if (try self.findConstantInModuleAncestors(mod, name)) |val| {
                    result.value = val;
                    return result;
                }
            },
        }

        return result;
    }

    /// Walk included modules (and their included modules recursively) of a
    /// module looking for a constant.  Does NOT re-check the module itself
    /// since the lexical scope walk already covered it.
    fn findConstantInModuleAncestors(self: *VM, mod: *value.ModuleObject, name: *value.SymbolObject) VMError!?Value {
        // Iterate from highest index (most recently included = highest priority)
        var i = mod.included_modules.items.len;
        while (i > 0) {
            i -= 1;
            const included = mod.included_modules.items[i];
            if (included.constants.get(name)) |entry| {
                try self.warnDeprecatedConstant(included, name);
                return entry.value;
            }
            switch (try self.triggerAutoload(included, name)) {
                .missing => {},
                .loaded => |val| return val,
                .attempted => {},
            }
            // Recurse into this included module's own included modules.
            if (try self.findConstantInModuleAncestors(included, name)) |val| {
                return val;
            }
        }
        return null;
    }

    /// Walk the ancestors of a class — prepended modules, included modules,
    /// then the superclass chain — looking for a constant.
    fn findConstantInClassAncestors(self: *VM, klass: *ClassObject, name: *value.SymbolObject, skip_object_autoload: bool) VMError!?Value {
        var current: ?*ClassObject = klass;
        var first = true;
        while (current) |cls| {
            defer current = cls.superclass;

            // Prepended modules (highest index = most recently prepended = first)
            var pi = cls.module.prepended_modules.items.len;
            while (pi > 0) {
                pi -= 1;
                const prepended = cls.module.prepended_modules.items[pi];
                if (prepended.constants.get(name)) |entry| {
                    try self.warnDeprecatedConstant(prepended, name);
                    return entry.value;
                }
                if (!skip_object_autoload or prepended != &self.object_class.module) {
                    switch (try self.triggerAutoload(prepended, name)) {
                        .missing => {},
                        .loaded => |val| return val,
                        .attempted => {},
                    }
                }
                if (try self.findConstantInModuleAncestors(prepended, name)) |val| {
                    return val;
                }
            }

            // The class itself — skip on the first iteration since the lexical
            // scope walk already checked it.
            if (!first) {
                if (cls.module.constants.get(name)) |entry| {
                    try self.warnDeprecatedConstant(&cls.module, name);
                    return entry.value;
                }
                if (!skip_object_autoload or &cls.module != &self.object_class.module) {
                    switch (try self.triggerAutoload(&cls.module, name)) {
                        .missing => {},
                        .loaded => |val| return val,
                        .attempted => {},
                    }
                }
            }
            first = false;

            // Included modules (highest index = most recently included = first)
            var ii = cls.module.included_modules.items.len;
            while (ii > 0) {
                ii -= 1;
                const included = cls.module.included_modules.items[ii];
                if (included.constants.get(name)) |entry| {
                    try self.warnDeprecatedConstant(included, name);
                    return entry.value;
                }
                switch (try self.triggerAutoload(included, name)) {
                    .missing => {},
                    .loaded => |val| return val,
                    .attempted => {},
                }
                if (try self.findConstantInModuleAncestors(included, name)) |val| {
                    return val;
                }
            }
        }
        return null;
    }

    fn resolveClassVariableContext(
        self: *VM,
        frame: *CallFrame,
    ) struct {
        module: *value.ModuleObject,
        start_class: ?*ClassObject,
    } {
        if (epClassVariableScope(frame.ep)) |scope| {
            return switch (scope.scope_module) {
                .class => |class_obj| .{
                    .module = &class_obj.module,
                    .start_class = class_obj,
                },
                .module => |module| .{
                    .module = module,
                    .start_class = null,
                },
            };
        }

        return .{
            .module = &self.object_class.module,
            .start_class = self.object_class,
        };
    }

    pub fn lookupClassVariable(
        _: *VM,
        owner_module: *value.ModuleObject,
        start_class: ?*ClassObject,
        name_sym: *value.SymbolObject,
    ) ?Value {
        if (owner_module.class_variables.get(name_sym)) |val| {
            return val;
        }

        if (start_class) |start| {
            var current = start.superclass;
            while (current) |klass| {
                if (klass.module.class_variables.get(name_sym)) |val| {
                    return val;
                }
                current = klass.superclass;
            }
        }

        return null;
    }

    pub fn currentEvalParentLocalNames(self: *VM) ?[]const []const u8 {
        const frame = self.currentRubyCallerFrame() orelse return null;
        if (frame.chunk.local_names.items.len == 0) return null;
        return frame.chunk.local_names.items;
    }

    pub fn currentRubyCallerLexicalScope(self: *VM) ?*LexicalScope {
        const frame = self.currentRubyCallerFrame() orelse return null;
        return epLexScope(frame.ep);
    }

    pub fn setupOutput(self: *VM) void {
        if (self.stdout == null) {
            // Use streaming mode: stdout is typically a pipe/tty where pwritev
            // fails (Unseekable), and positional mode handles that poorly across fork().
            self.stdout_writer = std.Io.File.stdout().writerStreaming(self.io, &self.stdout_buffer);
            self.stdout = &self.stdout_writer.?.interface;
        }

        if (self.stderr == null) {
            self.stderr_writer = std.Io.File.stderr().writerStreaming(self.io, &self.stderr_buffer);
            self.stderr = &self.stderr_writer.?.interface;
        }
    }

    pub fn setArgv(self: *VM, args: []const []const u8) VMError!void {
        const argv_array = try self.createArray();
        for (args) |arg| {
            const arg_str = try self.newString(arg, false);
            argv_array.elements.append(self.gc_allocator, arg_str) catch return error.Fatal;
        }

        const argv_sym = try self.intern("ARGV");
        self.object_class.module.constants.put(argv_sym, .{ .value = Value.fromObject(&argv_array.object) }) catch return error.Fatal;
    }

    pub fn setProgramName(self: *VM, program_name: []const u8) VMError!void {
        const program_name_value = try self.newString(program_name, false);
        try self.setGlobal("$0", program_name_value);
        try self.setGlobal("$PROGRAM_NAME", program_name_value);
    }

    pub fn setRubyExecutablePath(self: *VM, path: []const u8) VMError!void {
        self.ruby_executable_path = self.allocator.dupe(u8, path) catch return error.Fatal;
    }

    pub fn setInputRecordSeparator(self: *VM, separator: []const u8, frozen: bool) VMError!void {
        const separator_value = try self.newString(separator, frozen);
        try self.setGlobal("$/", separator_value);
        try self.setGlobal("$-0", separator_value);
    }

    pub fn currentEnvMap(self: *VM) VMError!std.process.Environ.Map {
        if (builtin.link_libc and builtin.os.tag != .windows) {
            var env_map = std.process.Environ.Map.init(self.allocator);
            errdefer env_map.deinit();

            var i: usize = 0;
            while (std.c.environ[i]) |entry| : (i += 1) {
                const key_value = std.mem.span(entry);
                const equal_index = std.mem.indexOfScalar(u8, key_value, '=') orelse continue;
                env_map.put(key_value[0..equal_index], key_value[equal_index + 1 ..]) catch return error.Fatal;
            }
            return env_map;
        }

        return std.process.Environ.createMap(self.environ, self.allocator) catch return error.Fatal;
    }

    pub fn allocCStringZ(self: *VM, bytes: []const u8) VMError![:0]u8 {
        const out = self.allocator.allocSentinel(u8, bytes.len, 0) catch return error.Fatal;
        @memcpy(out[0..bytes.len], bytes);
        return out;
    }

    pub fn dupeCStringZAsSlice(self: *VM, bytes_z: [:0]const u8) VMError![]u8 {
        return self.allocator.dupe(u8, bytes_z[0..bytes_z.len]) catch return error.Fatal;
    }

    pub fn envGet(self: *VM, key: []const u8) VMError!Value {
        var env_map = try self.currentEnvMap();
        defer env_map.deinit();
        const value_str = env_map.get(key) orelse return Value.nil();
        return self.newString(value_str, false);
    }

    pub fn syncHostEnvSet(self: *VM, key: []const u8, value_str: []const u8) VMError!void {
        if (builtin.os.tag == .windows) {
            return self.raiseExceptionFmt(self.runtime_error_class, "ENV host sync is not implemented on Windows", .{});
        }

        const key_z = try self.allocCStringZ(key);
        defer self.allocator.free(key_z);
        const value_z = try self.allocCStringZ(value_str);
        defer self.allocator.free(value_z);

        if (setenv(key_z.ptr, value_z.ptr, 1) != 0) {
            return self.raiseExceptionFmt(self.runtime_error_class, "failed to set environment variable: {s}", .{key});
        }
    }

    pub fn syncHostEnvUnset(self: *VM, key: []const u8) VMError!void {
        if (builtin.os.tag == .windows) {
            return self.raiseExceptionFmt(self.runtime_error_class, "ENV host sync is not implemented on Windows", .{});
        }

        const key_z = try self.allocCStringZ(key);
        defer self.allocator.free(key_z);

        if (unsetenv(key_z.ptr) != 0) {
            return self.raiseExceptionFmt(self.runtime_error_class, "failed to unset environment variable: {s}", .{key});
        }
    }

    pub fn envSetString(self: *VM, key: []const u8, value_str: []const u8, sync_host: bool) VMError!Value {
        if (sync_host) {
            try self.syncHostEnvSet(key, value_str);
        }
        return try self.newString(value_str, false);
    }

    pub fn envUnset(self: *VM, key: []const u8, sync_host: bool) VMError!Value {
        if (sync_host) {
            try self.syncHostEnvUnset(key);
        }
        return Value.nil();
    }

    pub fn envToHash(self: *VM) VMError!Value {
        const hash_obj = try self.createHash();
        var env_map = try self.currentEnvMap();
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const key_val = try self.newString(entry.key_ptr.*, false);
            const value_val = try self.newString(entry.value_ptr.*, false);
            try self.hashSetEntry(hash_obj, key_val, value_val);
        }

        return Value.fromObject(&hash_obj.object);
    }

    pub fn envToArray(self: *VM) VMError!Value {
        const array_obj = try self.createArray();
        var env_map = try self.currentEnvMap();
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const pair = try self.createArray();
            const key_val = try self.newString(entry.key_ptr.*, false);
            const value_val = try self.newString(entry.value_ptr.*, false);
            pair.elements.append(self.gc_allocator, key_val) catch return error.Fatal;
            pair.elements.append(self.gc_allocator, value_val) catch return error.Fatal;
            array_obj.elements.append(self.gc_allocator, Value.fromObject(&pair.object)) catch return error.Fatal;
        }

        return Value.fromObject(&array_obj.object);
    }

    pub fn envSize(self: *VM) VMError!Value {
        var env_map = try self.currentEnvMap();
        defer env_map.deinit();

        var count: usize = 0;
        var iter = env_map.iterator();
        while (iter.next()) |_| {
            count += 1;
        }

        return Value.integer(@intCast(count));
    }

    pub fn deinit(self: *VM) void {
        if (self.gc_vm_root_registered) {
            self.unregisterVmRootForGc();
        }
        var key_iter = self.loaded_files.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.loaded_files.deinit();
        var require_iter = self.require_in_progress.keyIterator();
        while (require_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.require_in_progress.deinit();
        self.loaded_paths.deinit(self.allocator);
        if (self.ruby_executable_path) |path| {
            self.allocator.free(path);
        }

        self.stack.deinit(self.gc_allocator);
        self.frames.deinit(self.gc_allocator);
        for (self.zio_coroutines.items) |c| {
            self.unregisterCoroutineStackForGc(c);
            zio.coro.stackFree(c.context.stack_info);
            self.allocator.destroy(c);
        }
        self.zio_coroutines.deinit(self.allocator);
        self.gc_registered_coro_stacks.deinit();
        if (self.zio_stack_growth_ready) {
            zio.coro.cleanupStackGrowth();
            self.zio_stack_growth_ready = false;
        }
        self.symbols.deinit();
        var global_key_iter = self.globals.keyIterator();
        while (global_key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.globals.deinit();
        var fstring_key_iter = self.fstring_cache.keyIterator();
        while (fstring_key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.fstring_cache.deinit();
        self.canonical_fstrings.deinit(self.gc_allocator);
        var packed_targets_iter = self.packed_pointer_targets.valueIterator();
        while (packed_targets_iter.next()) |targets| {
            targets.deinit();
        }
        self.packed_pointer_targets.deinit();
        self.errno_classes.deinit();
        self.pending_async_exceptions.deinit(self.allocator);
        self.pending_signal_traps.deinit(self.allocator);
        self.rescued_exceptions.deinit(self.allocator);
        self.ensure_saved_unwinds.deinit(self.allocator);
        var fiber_catches_iter = self.fiber_active_catches.valueIterator();
        while (fiber_catches_iter.next()) |active_catches| {
            active_catches.deinit(self.allocator);
        }
        self.fiber_active_catches.deinit();
        var thread_catches_iter = self.thread_active_catches.valueIterator();
        while (thread_catches_iter.next()) |active_catches| {
            active_catches.deinit(self.allocator);
        }
        self.thread_active_catches.deinit();
        self.at_exit_handlers.deinit(self.gc_allocator);
        self.recursion_guard.deinit(self.allocator);
        var jit_iter = self.jit_chunk_states.valueIterator();
        while (jit_iter.next()) |state| {
            state.deinit(self.allocator);
        }
        self.jit_chunk_states.deinit();
        for (self.io_objects.items) |io_obj| {
            if (io_obj.owns_fd and !io_obj.closed and io_obj.fd >= 0) {
                _ = std.c.close(@intCast(io_obj.fd));
                io_obj.closed = true;
            }
        }
        self.io_objects.deinit(self.gc_allocator);
        for (self.lexical_scopes.items) |scope| {
            self.allocator.destroy(scope);
        }
        self.lexical_scopes.deinit(self.allocator);
        for (self.frame_scope_contexts.items) |ctx| {
            self.allocator.destroy(ctx);
        }
        self.frame_scope_contexts.deinit(self.allocator);
        var owned_mutexes_iter = self.thread_owned_mutexes.valueIterator();
        while (owned_mutexes_iter.next()) |owned_mutexes| {
            owned_mutexes.deinit(self.allocator);
        }
        self.thread_owned_mutexes.deinit();
        var mutex_waiters_iter = self.mutex_waiters.valueIterator();
        while (mutex_waiters_iter.next()) |waiters| {
            waiters.deinit(self.allocator);
        }
        self.mutex_waiters.deinit();
        self.runnable_queue.deinit(self.gc_allocator);
        self.thread_list.deinit(self.gc_allocator);
    }

    pub fn run(self: *VM) VMError!Value {
        self.setupOutput();
        try self.pushFrame(&self.program.main_chunk, self.main_self, null);
        try self.executeFastLoop(1, false, 0);
        return self.pop();
    }

    pub fn setBacktraceLimit(self: *VM, limit: ?usize) void {
        self.backtrace_limit = limit;
    }

    pub fn setTccJitEnabled(self: *VM, enabled: bool) void {
        self.tcc_jit_enabled = enabled;
    }

    pub fn setDisableGems(self: *VM, disabled: bool) void {
        self.disable_gems = disabled;
    }

    pub fn setDumpJitSource(self: *VM, enabled: bool) void {
        self.dump_jit_source = enabled;
    }

    pub fn runAtExitHandlers(self: *VM) VMError!void {
        if (self.skip_at_exit_handlers) {
            return;
        }

        const original_exception = self.pendingException();
        var last_exception: ?*value.ExceptionObject = null;

        if (self.exit_signal_trap_mode == .callable and !self.exit_signal_trap_callable.isNil()) {
            _ = self.callMethodByName(self.exit_signal_trap_callable, "call", &[_]Value{}, null) catch |err| {
                switch (err) {
                    error.Unwind => {
                        if (self.pendingException()) |exc| {
                            last_exception = exc;
                            self.setPendingException(null);
                        }
                    },
                    else => return err,
                }
            };
        }

        while (self.at_exit_handlers.items.len > 0) {
            const handler = self.at_exit_handlers.pop().?;
            _ = self.callMethodByName(handler, "call", &[_]Value{}, null) catch |err| {
                switch (err) {
                    error.Unwind => {
                        if (self.pendingException()) |exc| {
                            last_exception = exc;
                            self.setPendingException(null);
                        }
                    },
                    else => return err,
                }
            };
        }

        if (last_exception) |exc| {
            self.setPendingException(exc);
            return error.UnhandledException;
        }

        self.setPendingException(original_exception);
    }

    fn createSignalException(self: *VM, signo: c_int) VMError!*value.ExceptionObject {
        const class = if (signo == @as(c_int, @intCast(@intFromEnum(std.posix.SIG.INT))))
            self.interrupt_class
        else
            self.signal_exception_class;
        const exc = try self.createException(class, signal_support.fullName(signo) orelse "SIG");
        try self.setInstanceVariable(Value.fromObject(&exc.object), "@signo", Value.integer(signo));
        return exc;
    }

    fn enqueueAsyncException(self: *VM, exc: *value.ExceptionObject) VMError!void {
        self.pending_async_exceptions.append(self.allocator, exc) catch return error.Fatal;
    }

    fn enqueuePendingSignalTrap(self: *VM, signo: c_int) VMError!void {
        self.pending_signal_traps.append(self.allocator, signo) catch return error.Fatal;
    }

    pub fn signalTrapMode(self: *VM, signo: c_int) SignalTrapMode {
        if (signo == 0) return self.exit_signal_trap_mode;
        if (signo < 0) return .system_default;
        const idx: usize = @intCast(signo);
        if (idx >= MAX_QUEUED_SIGNALS) return .system_default;
        return self.signal_trap_modes[idx];
    }

    pub fn signalTrapCallable(self: *VM, signo: c_int) Value {
        if (signo == 0) return self.exit_signal_trap_callable;
        if (signo < 0) return Value.nil();
        const idx: usize = @intCast(signo);
        if (idx >= MAX_QUEUED_SIGNALS) return Value.nil();
        return self.signal_trap_callables[idx];
    }

    pub fn setSignalTrap(self: *VM, signo: c_int, mode: SignalTrapMode, callable: Value) VMError!void {
        if (signo == 0) {
            self.exit_signal_trap_mode = mode;
            self.exit_signal_trap_callable = if (mode == .callable) callable else Value.nil();
            return;
        }
        if (signo < 0) {
            return self.raiseExceptionFmt(self.argument_error_class, "invalid signal number ({d})", .{signo});
        }
        const idx: usize = @intCast(signo);
        if (idx >= MAX_QUEUED_SIGNALS) {
            return self.raiseExceptionFmt(self.argument_error_class, "invalid signal number ({d})", .{signo});
        }

        const signal_info = signal_support.infoByNumber(signo) orelse {
            return self.raiseExceptionFmt(self.argument_error_class, "invalid signal number ({d})", .{signo});
        };
        if (signal_info.ruby_reserved) {
            return self.raiseExceptionFmt(self.argument_error_class, "can't trap reserved signal: {s}", .{signal_info.full_name});
        }
        if (!signal_info.can_trap) {
            return self.raiseExceptionFmt(self.argument_error_class, "Signal already used by VM or OS", .{});
        }

        self.signal_trap_modes[idx] = mode;
        self.signal_trap_callables[idx] = if (mode == .callable) callable else Value.nil();
        setOsSignalMode(signo, mode);
    }

    inline fn hasPendingUnwind(self: *VM) bool {
        return self.pending_unwind != null;
    }

    pub inline fn pendingException(self: *VM) ?*value.ExceptionObject {
        if (self.pending_unwind) |pending| {
            if (pending == .exception) return pending.exception;
        }
        return null;
    }

    pub inline fn setPendingException(self: *VM, exc: ?*value.ExceptionObject) void {
        self.pending_unwind = if (exc) |e| .{ .exception = e } else null;
    }

    pub inline fn pendingThrow(self: *VM) ?PendingThrow {
        if (self.pending_unwind) |pending| {
            if (pending == .throw_) return pending.throw_;
        }
        return null;
    }

    pub inline fn setPendingThrow(self: *VM, pending_throw: ?PendingThrow) void {
        self.pending_unwind = if (pending_throw) |t| .{ .throw_ = t } else null;
    }

    inline fn pendingControlFlow(self: *VM) ?PendingControlFlow {
        if (self.pending_unwind) |pending| {
            if (pending == .control_flow) return pending.control_flow;
        }
        return null;
    }

    inline fn pendingControlFlowPtr(self: *VM) ?*PendingControlFlow {
        if (self.pending_unwind) |*pending| {
            if (pending.* == .control_flow) return &pending.control_flow;
        }
        return null;
    }

    inline fn setPendingControlFlow(self: *VM, control_flow: ?PendingControlFlow) void {
        self.pending_unwind = if (control_flow) |cf| .{ .control_flow = cf } else null;
    }

    pub inline fn clearPendingThrow(self: *VM) void {
        if (self.pending_unwind != null and self.pending_unwind.? == .throw_)
            self.pending_unwind = null;
    }

    pub fn throwTagsMatch(_: *VM, left: Value, right: Value) bool {
        return left.raw == right.raw;
    }

    pub fn hasActiveCatch(self: *VM, tag: Value) bool {
        var i = self.active_catches.items.len;
        while (i > 0) {
            i -= 1;
            if (self.throwTagsMatch(self.active_catches.items[i], tag)) return true;
        }
        return false;
    }

    pub fn pushActiveCatch(self: *VM, tag: Value) VMError!void {
        self.active_catches.append(self.allocator, tag) catch return error.Fatal;
    }

    pub fn popActiveCatch(self: *VM) void {
        _ = self.active_catches.pop();
    }

    pub fn startThrow(self: *VM, tag: Value, thrown_value: Value) VMError!void {
        self.setPendingThrow(.{
            .tag = tag,
            .value = thrown_value,
        });
        return error.Unwind;
    }

    pub fn createUncaughtThrowError(self: *VM, tag: Value, thrown_value: Value) VMError!*value.ExceptionObject {
        const tag_inspect = try tag.inspect(self);
        const message = std.fmt.allocPrint(
            self.gc_allocator,
            "uncaught throw {s}",
            .{tag_inspect.toStringObject().str},
        ) catch return error.Fatal;
        const exc = try self.createException(self.uncaught_throw_error_class, message);
        try self.setInstanceVariable(Value.fromObject(&exc.object), "@tag", tag);
        try self.setInstanceVariable(Value.fromObject(&exc.object), "@value", thrown_value);
        return exc;
    }

    fn drainQueuedSignalsToAsyncExceptions(self: *VM) VMError!void {
        var signo: usize = 1;
        while (signo < MAX_QUEUED_SIGNALS) : (signo += 1) {
            const count = @atomicRmw(u32, &queued_signal_counts[signo], .Xchg, 0, .seq_cst);
            if (count == 0) continue;

            var i: u32 = 0;
            while (i < count) : (i += 1) {
                const signum: c_int = @intCast(signo);
                switch (self.signalTrapMode(signum)) {
                    .system_default, .ignore, .ignore_nil => {},
                    .callable => try self.enqueuePendingSignalTrap(signum),
                    .default => {
                        const exc = try self.createSignalException(signum);
                        try self.enqueueAsyncException(exc);
                    },
                }
            }
        }
    }

    pub fn checkAsyncEvents(self: *VM) VMError!void {
        try self.drainQueuedSignalsToAsyncExceptions();
        if (self.hasPendingUnwind()) return;
        if (self.pending_signal_traps.items.len != 0) {
            const signo = self.pending_signal_traps.orderedRemove(0);
            const callable = self.signalTrapCallable(signo);
            if (!callable.isNil()) {
                var args = [_]Value{Value.integer(signo)};
                _ = try self.callMethodByName(callable, "call", args[0..], null);
            }
            return;
        }
        if (self.pending_async_exceptions.items.len == 0) return;

        self.setPendingException(self.pending_async_exceptions.orderedRemove(0));
        return error.Unwind;
    }

    inline fn checkAsyncEventsWithUnwind(self: *VM, comptime bounded: bool, min_unwind_depth: usize) VMError!void {
        self.checkAsyncEvents() catch |err| switch (err) {
            error.Unwind => {
                if (bounded) {
                    if (!try self.unwindStackUntilFrameDepth(min_unwind_depth))
                        return error.Unwind;
                } else {
                    try self.unwindStack();
                }
            },
            else => return err,
        };
    }

    pub fn enterRecursionGuard(self: *VM, kind: RecursionGuardKind, lhs: Value, rhs: Value) VMError!bool {
        return self.recursion_guard.enter(self.allocator, kind, lhs, rhs) catch return error.Fatal;
    }

    pub fn leaveRecursionGuard(self: *VM, kind: RecursionGuardKind, lhs: Value, rhs: Value) void {
        self.recursion_guard.leave(kind, lhs, rhs);
    }

    pub fn currentFrame(self: *VM) *CallFrame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn nearestRubyFrame(self: *VM, start_exclusive: usize) ?*CallFrame {
        var i = @min(start_exclusive, self.frames.items.len);
        while (i > 0) {
            i -= 1;
            const frame = &self.frames.items[i];
            if (frame.frame_type != .builtin) return frame;
        }
        return null;
    }

    pub fn currentRubyFrame(self: *VM) ?*CallFrame {
        return self.nearestRubyFrame(self.frames.items.len);
    }

    fn currentChunk(self: *VM) *Chunk {
        return self.currentFrame().chunk;
    }

    fn callMethodSymbolFromConstant(self: *VM, ch: *Chunk, method_idx: u16) VMError!*SymbolObject {
        if (method_idx >= ch.constants.items.len) return error.Fatal;
        return switch (ch.constants.items[method_idx]) {
            .symbol => |sym| sym,
            .string => |method_name| blk: {
                const sym = try self.intern(method_name);
                ch.allocator.free(method_name);
                ch.constants.items[method_idx] = .{ .symbol = sym };
                break :blk sym;
            },
            else => error.Fatal,
        };
    }

    /// Ensure that callsite_caches and callsite_descriptors are large enough to hold
    /// an entry at the given byte offset (used as callsite key).
    fn ensureCallsiteArraysForOffset(ch: *Chunk, byte_offset: usize) VMError!void {
        const needed = byte_offset + 1;
        if (ch.callsite_caches.items.len < needed) {
            const old_len = ch.callsite_caches.items.len;
            ch.callsite_caches.ensureTotalCapacity(ch.allocator, needed) catch return error.Fatal;
            ch.callsite_caches.items.len = needed;
            for (old_len..ch.callsite_caches.items.len) |idx| {
                ch.callsite_caches.items[idx] = null;
            }
        }

        if (ch.callsite_descriptors.items.len < needed) {
            const old_len = ch.callsite_descriptors.items.len;
            ch.callsite_descriptors.ensureTotalCapacity(ch.allocator, needed) catch return error.Fatal;
            ch.callsite_descriptors.items.len = needed;
            for (old_len..ch.callsite_descriptors.items.len) |idx| {
                ch.callsite_descriptors.items[idx] = null;
            }
        }
    }

    /// Decode a CallSiteDescriptor from the operand bytes immediately following a CALL/CALL_KW opcode.
    fn decodeCallSiteDescriptorFromOperands(op: bytecode.OpCode, operands: []const u8) VMError!chunk.CallSiteDescriptor {
        return switch (op) {
            .CALL => .{
                .method_idx = readU16At(operands, 0),
                .argc = readU8At(operands, 2),
                .call_flags = readU8At(operands, 3),
                .block_chunk_id = readU16At(operands, 4),
            },
            .CALL_KW => .{
                .method_idx = readU16At(operands, 0),
                .argc = readU8At(operands, 2),
                .kwargc = readU8At(operands, 3),
                .call_flags = readU8At(operands, 4),
                .kw_metadata_idx = readU16At(operands, 5),
                .block_chunk_id = readU16At(operands, 7),
            },
            else => error.Fatal,
        };
    }

    fn buildChunkCallsiteDescriptors(self: *VM, ch: *Chunk) VMError!void {
        if (ch.code.items.len == 0) return;

        var ip: usize = 0;
        while (ip < ch.code.items.len) {
            const op: bytecode.OpCode = @enumFromInt(ch.code.items[ip]);
            const operands = ch.code.items[ip + 1 ..];
            switch (op) {
                .CALL => {
                    try ensureCallsiteArraysForOffset(ch, ip);
                    var desc = try decodeCallSiteDescriptorFromOperands(op, operands);
                    desc.method_sym = try self.callMethodSymbolFromConstant(ch, desc.method_idx);
                    ch.callsite_descriptors.items[ip] = desc;
                    ip += 1 + 6; // opcode + method_idx(2) + argc(1) + call_flags(1) + block_chunk_id(2)
                },
                .CALL_KW => {
                    try ensureCallsiteArraysForOffset(ch, ip);
                    var desc = try decodeCallSiteDescriptorFromOperands(op, operands);
                    desc.method_sym = try self.callMethodSymbolFromConstant(ch, desc.method_idx);
                    ch.callsite_descriptors.items[ip] = desc;
                    ip += 1 + 9; // opcode + method_idx(2) + argc(1) + kwargc(1) + call_flags(1) + kw_metadata_idx(2) + block_chunk_id(2)
                },
                else => {
                    ip += 1 + bytecode.opcodeOperandSize(op);
                },
            }
        }
    }

    fn buildProgramCallsiteDescriptors(self: *VM) VMError!void {
        try self.buildChunkCallsiteDescriptors(&self.program.main_chunk);

        var chunk_iter = self.program.child_chunks.valueIterator();
        while (chunk_iter.next()) |chunk_ptr| {
            try self.buildChunkCallsiteDescriptors(chunk_ptr.*);
        }
    }

    fn internLiteralSymbolsInChunk(self: *VM, ch: *Chunk) VMError!void {
        if (ch.code.items.len == 0) return;

        var ip: usize = 0;
        while (ip < ch.code.items.len) {
            const op: bytecode.OpCode = @enumFromInt(ch.code.items[ip]);
            const operands = ch.code.items[ip + 1 ..];
            if (op == .PUSH_SYMBOL) {
                const idx = readU16At(operands, 0);
                if (idx >= ch.constants.items.len) return error.Fatal;
                switch (ch.constants.items[idx]) {
                    .string => |name| {
                        const symbol_encoding = literalSymbolEncodingForChunk(ch.source_encoding, name);
                        _ = try self.internWithEncoding(name, symbol_encoding);
                    },
                    .encoded_string => |name| {
                        _ = try self.internWithEncoding(name.bytes, name.encoding);
                    },
                    .symbol => {},
                    else => return error.Fatal,
                }
            }
            ip += 1 + bytecode.opcodeOperandSize(op);
        }
    }

    fn internProgramLiteralSymbols(self: *VM) VMError!void {
        try self.internLiteralSymbolsInChunk(&self.program.main_chunk);

        var chunk_iter = self.program.child_chunks.valueIterator();
        while (chunk_iter.next()) |chunk_ptr| {
            try self.internLiteralSymbolsInChunk(chunk_ptr.*);
        }
    }

    pub fn bumpMethodStateVersion(self: *VM) void {
        self.method_state_version +%= 1;
        if (self.method_state_version == 0) {
            self.method_state_version = 1;
            var chunk_iter = self.program.child_chunks.valueIterator();
            while (chunk_iter.next()) |chunk_ptr| {
                for (chunk_ptr.*.callsite_caches.items) |*entry| {
                    entry.* = null;
                }
            }
            for (self.program.main_chunk.callsite_caches.items) |*entry| {
                entry.* = null;
            }
        }
    }

    inline fn getDispatchClass(self: *VM, receiver: Value) *ClassObject {
        if (receiver.isInteger()) return self.integer_class;
        if (receiver.isObject()) {
            const obj: *value.Object = @ptrFromInt(receiver.raw);
            return obj.singleton_class orelse obj.class.?;
        }
        if (receiver.isNil()) return self.nil_class;
        return if (receiver.toBool()) self.true_class else self.false_class;
    }

    fn resolveMethodForCallSite(
        self: *VM,
        frame: *CallFrame,
        callsite_byte_offset: usize,
        receiver: Value,
        method_name_sym: *SymbolObject,
    ) VMError!?ResolvedMethod {
        // Fast path: check if cache arrays are already large enough
        const caches = frame.chunk.callsite_caches.items;
        if (callsite_byte_offset >= caches.len) {
            try ensureCallsiteArraysForOffset(frame.chunk, callsite_byte_offset);
        }

        const dispatch_class = self.getDispatchClass(receiver);
        const cache_slot = &frame.chunk.callsite_caches.items[callsite_byte_offset];
        if (cache_slot.*) |cached| {
            if (cached.receiver_class == dispatch_class and
                cached.method_name == method_name_sym and
                cached.method_state_version == self.method_state_version)
            {
                return .{
                    .name = method_name_sym,
                    .owner_class = cached.owner_class,
                    .entry = cached.entry,
                };
            }
        }

        const resolved = try self.findMethod(receiver, method_name_sym);
        if (resolved) |r| {
            cache_slot.* = CallSiteCache{
                .receiver_class = dispatch_class,
                .method_name = method_name_sym,
                .method_state_version = self.method_state_version,
                .owner_class = r.owner_class,
                .entry = r.entry,
            };
        }
        return resolved;
    }

    fn getOrDecodeCallSiteDescriptor(
        self: *VM,
        ch: *Chunk,
        callsite_byte_offset: usize,
    ) VMError!*chunk.CallSiteDescriptor {
        if (callsite_byte_offset >= ch.code.items.len) return error.Fatal;
        try ensureCallsiteArraysForOffset(ch, callsite_byte_offset);

        if (ch.callsite_descriptors.items[callsite_byte_offset]) |*desc| {
            return desc;
        }

        const op: bytecode.OpCode = @enumFromInt(ch.code.items[callsite_byte_offset]);
        const operands = ch.code.items[callsite_byte_offset + 1 ..];
        var desc = try decodeCallSiteDescriptorFromOperands(op, operands);
        desc.method_sym = try self.callMethodSymbolFromConstant(ch, desc.method_idx);

        ch.callsite_descriptors.items[callsite_byte_offset] = desc;
        return &ch.callsite_descriptors.items[callsite_byte_offset].?;
    }

    fn getOrCreateJitState(self: *VM, ch: *Chunk) VMError!*jit.State {
        const entry = self.jit_chunk_states.getOrPut(ch) catch return error.Fatal;
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        return entry.value_ptr;
    }

    fn maybeCallJittedChunk(
        self: *VM,
        method_chunk: *Chunk,
        receiver: Value,
        args: []const Value,
    ) VMError!?Value {
        if (!self.tcc_jit_enabled or !jit.available) return null;
        if (self.integer_changed or args.len != 1 or !args[0].isInteger()) return null;

        const state = try self.getOrCreateJitState(method_chunk);
        if (state.compiled_method_state_version != self.method_state_version or state.entry == null) {
            if (state.failed_method_state_version == self.method_state_version) return null;
            const dump_writer = blk: {
                if (!self.dump_jit_source) break :blk null;
                self.setupOutput();
                break :blk self.stderr;
            };
            jit.compileState(self.allocator, state, method_chunk, self.method_state_version, dump_writer) catch return null;
        }

        const entry = state.entry orelse return null;
        var ok: u8 = 1;
        const raw = entry(receiver.raw, args[0].raw, &ok);
        if (ok == 0) return null;
        return Value{ .raw = raw };
    }

    fn resolveCallMethodSymbolFromDescriptor(
        self: *VM,
        ch: *Chunk,
        desc: *chunk.CallSiteDescriptor,
    ) VMError!*SymbolObject {
        if (desc.method_sym) |sym| {
            return sym;
        }
        const sym = try self.callMethodSymbolFromConstant(ch, desc.method_idx);
        desc.method_sym = sym;
        return sym;
    }

    fn addIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        if (lhs.isInteger() and rhs.isInteger()) {
            if (std.math.add(i64, lhs.toInteger(), rhs.toInteger())) |sum| {
                return Value.integer(sum);
            } else |_| {}
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        var out = BigInt.init(self.allocator) catch return error.Fatal;
        defer out.deinit();
        out.add(&a, &b) catch return error.Fatal;
        return self.valueFromManagedInteger(&out);
    }

    fn subIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        if (lhs.isInteger() and rhs.isInteger()) {
            if (std.math.sub(i64, lhs.toInteger(), rhs.toInteger())) |diff| {
                return Value.integer(diff);
            } else |_| {}
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        var out = BigInt.init(self.allocator) catch return error.Fatal;
        defer out.deinit();
        out.sub(&a, &b) catch return error.Fatal;
        return self.valueFromManagedInteger(&out);
    }

    pub fn mulIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        if (lhs.isInteger() and rhs.isInteger()) {
            if (std.math.mul(i64, lhs.toInteger(), rhs.toInteger())) |product| {
                return Value.integer(product);
            } else |_| {}
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        var out = BigInt.init(self.allocator) catch return error.Fatal;
        defer out.deinit();
        out.mul(&a, &b) catch return error.Fatal;
        return self.valueFromManagedInteger(&out);
    }

    pub fn compareIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!std.math.Order {
        if (lhs.isInteger() and rhs.isInteger()) {
            return std.math.order(lhs.toInteger(), rhs.toInteger());
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        return BigInt.order(a, b);
    }

    pub fn divTruncIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        if (lhs.isInteger() and rhs.isInteger()) {
            const li: i63 = @intCast(lhs.toInteger());
            const ri: i63 = @intCast(rhs.toInteger());
            if (std.math.divTrunc(i63, li, ri)) |quot| {
                return Value.integer(@as(i64, quot));
            } else |_| {}
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();

        var quot = BigInt.init(self.allocator) catch return error.Fatal;
        defer quot.deinit();
        var rem = BigInt.init(self.allocator) catch return error.Fatal;
        defer rem.deinit();

        quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
        return self.valueFromManagedInteger(&quot);
    }

    fn divFloorIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        const divisor_is_zero = if (rhs.isInteger())
            rhs.toInteger() == 0
        else if (rhs.isBigInteger())
            rhs.toBigIntegerObject().value.eqlZero()
        else
            false;
        if (divisor_is_zero) {
            return self.raiseExceptionFmt(self.zero_division_error_class, "divided by 0", .{});
        }

        if (lhs.isInteger() and rhs.isInteger()) {
            if (std.math.divFloor(i64, lhs.toInteger(), rhs.toInteger())) |quot| {
                return Value.integer(quot);
            } else |_| {}
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        var quot = BigInt.init(self.allocator) catch return error.Fatal;
        defer quot.deinit();
        var rem = BigInt.init(self.allocator) catch return error.Fatal;
        defer rem.deinit();
        quot.divFloor(&rem, &a, &b) catch return error.Fatal;
        return self.valueFromManagedInteger(&quot);
    }

    inline fn push(self: *VM, val: Value) VMError!void {
        const len = self.stack.items.len;
        if (len >= self.stack.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        self.stack.storage[len] = val;
        self.stack.items = self.stack.storage[0 .. len + 1];
    }

    pub inline fn pop(self: *VM) Value {
        const len = self.stack.items.len;
        if (len == 0) return Value.nil();

        const idx = len - 1;
        const val = self.stack.storage[idx];
        self.stack.items = self.stack.storage[0..idx];
        return val;
    }

    inline fn peek(self: *VM, distance: usize) Value {
        return self.stack.items[self.stack.items.len - 1 - distance];
    }

    fn readByteFrom(frame: *CallFrame, operands: []const u8, operand_cursor: *usize) u8 {
        const byte = operands[operand_cursor.*];
        operand_cursor.* += 1;
        frame.ip += 1;
        return byte;
    }

    fn readU16From(frame: *CallFrame, operands: []const u8, operand_cursor: *usize) u16 {
        const lo: u16 = operands[operand_cursor.*];
        const hi: u16 = operands[operand_cursor.* + 1];
        operand_cursor.* += 2;
        frame.ip += 2;
        return lo | (hi << 8);
    }

    fn readI16From(frame: *CallFrame, operands: []const u8, operand_cursor: *usize) i16 {
        return @bitCast(readU16From(frame, operands, operand_cursor));
    }

    inline fn readU8At(operands: []const u8, index: usize) u8 {
        return operands[index];
    }

    inline fn readU16At(operands: []const u8, index: usize) u16 {
        return @as(u16, operands[index]) | (@as(u16, operands[index + 1]) << 8);
    }

    fn setFrameIp(frame: *CallFrame, ip: usize) VMError!void {
        if (ip > frame.chunk.code.items.len) return error.Fatal;
        frame.ip = ip;
    }

    /// Resolve a block from its chunk ID. Handles three cases:
    /// - BLOCK_ARG_ON_STACK: pops Proc-like value and resolves to callable Block
    /// - Literal block (1..MAX_CHUNK_ID): looks up chunk, creates Block
    /// - No block (0): returns null
    fn resolveBlock(self: *VM, block_chunk_id: chunk.ChunkId, frame: *CallFrame) VMError!?Block {
        if (block_chunk_id == chunk.BLOCK_ARG_ON_STACK) {
            // Block argument: value is on top of stack and may need to_proc coercion.
            var proc_val = self.pop();
            const original_val = proc_val;

            if (proc_val.isNil()) {
                return null;
            }

            if (!proc_val.isProc()) {
                const maybe_proc = try self.checkCallMethodByName(proc_val, "to_proc", false, &[_]Value{}, null);
                proc_val = maybe_proc orelse {
                    return self.raiseExceptionFmt(
                        self.type_error_class,
                        "wrong argument type {s} (expected Proc)",
                        .{self.className(proc_val)},
                    );
                };
                if (!proc_val.isProc() and try self.respondsToMethodByName(proc_val, "call", false)) {
                    return .{ .kind = .{ .callable = proc_val } };
                }
                if (!proc_val.isProc()) {
                    return self.raiseExceptionFmt(
                        self.type_error_class,
                        "can't convert {s} to Proc ({s}#to_proc gives {s})",
                        .{
                            self.className(original_val),
                            self.className(original_val),
                            self.className(proc_val),
                        },
                    );
                }
            }

            const proc_obj = proc_val.toProcObject();
            var resolved = proc_obj.block;
            resolved.source_proc = proc_obj;
            return resolved;
        } else if (block_chunk_id != 0) {
            // Literal block: look up chunk
            if (self.program.child_chunks.get(block_chunk_id)) |bc| {
                bc.lexical_scope = self.current_lexical_scope;
                const defining_ep = try self.promoteFrameToHeap(frame.ep);
                return Block{
                    .kind = .{ .chunk = .{
                        .chunk = bc,
                        .defining_ep = defining_ep,
                        .defining_self = frame.self_value,
                        .return_target_ep = self.currentNonLocalReturnTarget(),
                        .enclosing_block_proc = if (frame.block) |blk| try self.ensureBlockProc(blk) else null,
                    } },
                };
            } else {
                return error.Fatal;
            }
        }
        return null;
    }

    /// Push a frame for a block/proc/lambda invocation.
    /// Uses `defining_ep` (the ep of the scope where the block was defined) as the
    /// lexical parent (ep[0]), matching MRI's SPECVAL prev-ep convention.
    pub const BlockFrameOptions = struct {
        block: ?Block = null,
        return_target_ep: ?[*]Value = null,
        break_target_frame_idx: ?usize = null,
        next_target_frame_idx: ?usize = null,
        method_definition_target: ?Value = null,
    };

    fn pushBlockFrame(
        self: *VM,
        ch: *Chunk,
        defining_ep: [*]Value,
        self_value: Value,
        frame_type: CallFrame.FrameType,
        opts: BlockFrameOptions,
    ) VMError!void {
        if (self.frames.items.len >= self.frames.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber call stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        const locals_count = ch.locals_count;
        const locals_base = self.stack.items.len;
        const needed = locals_base + locals_count + ENV_DATA_SIZE;

        if (needed > MAX_FIBER_STACK_SIZE) {
            const exc = try self.createException(self.fiber_error_class, "fiber stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        self.stack.items.len = needed;
        @memset(self.stack.items[locals_base .. locals_base + locals_count], Value.nil());

        const ep: [*]Value = self.stack.items[locals_base + locals_count ..].ptr;
        ep[0] = encodeEp(defining_ep);
        const lexical_scope = ch.lexical_scope orelse self.current_lexical_scope;
        ep[1] = try self.frameScopeValue(lexical_scope, null, opts.method_definition_target);
        ep[2] = Value.integer(locals_count);

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = ch,
            .ip = 0,
            .locals_base = locals_base,
            .ep = ep,
            .stack_base = needed,
            .self_value = self_value,
            .block = opts.block,
            .frame_type = frame_type,
            .return_target_ep = opts.return_target_ep,
            .break_target_frame_idx = opts.break_target_frame_idx,
            .next_target_frame_idx = opts.next_target_frame_idx,
        }) catch return error.Fatal;

        if (ch.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }
    }

    fn ensureBlockProc(self: *VM, block: Block) VMError!*value.ProcObject {
        if (block.source_proc) |proc_obj| return proc_obj;
        return (try self.newProc(block)).toProcObject();
    }

    fn pushFrame(self: *VM, ch: *Chunk, self_value: Value, block: ?Block) VMError!void {
        if (self.frames.items.len >= self.frames.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber call stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        const locals_count = ch.locals_count;
        const locals_base = self.stack.items.len;
        const needed = locals_base + locals_count + ENV_DATA_SIZE;

        if (needed > MAX_FIBER_STACK_SIZE) {
            const exc = try self.createException(self.fiber_error_class, "fiber stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        // Extend the value stack: locals (nil-initialised) + env_data slots.
        self.stack.items.len = needed;
        // Nil-initialise locals.
        @memset(self.stack.items[locals_base .. locals_base + locals_count], Value.nil());

        // Write env_data:
        //   ep[0] = parent ep (current top frame's ep, or 0 if none)
        //   ep[1] = lexical scope pointer or eval frame-scope context
        //   ep[2] = locals_count (as Ruby integer for GC safety)
        const ep: [*]Value = self.stack.items[locals_base + locals_count ..].ptr;
        const parent_val: Value = if (self.frames.items.len > 0)
            encodeEp(self.frames.items[self.frames.items.len - 1].ep)
        else
            .{ .raw = 0 };
        ep[0] = parent_val;
        ep[1] = try self.frameScopeValue(ch.lexical_scope orelse self.current_lexical_scope, null, null);
        ep[2] = Value.integer(locals_count);

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = ch,
            .ip = 0,
            .locals_base = locals_base,
            .ep = ep,
            .stack_base = needed,
            .self_value = self_value,
            .block = block,
        }) catch return error.Fatal;

        // Update current_lexical_scope to the frame's scope
        if (ch.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }
    }

    fn popFrame(self: *VM) VMError!void {
        if (self.frames.items.len > 0) {
            const frame = self.frames.pop().?;
            if (frame.active_rescue_exceptions > self.rescued_exceptions.items.len) return error.Fatal;
            self.rescued_exceptions.shrinkRetainingCapacity(self.rescued_exceptions.items.len - frame.active_rescue_exceptions);

            // Restore current_lexical_scope from the previous frame
            if (self.frames.items.len > 0) {
                self.current_lexical_scope = epLexScope(self.frames.items[self.frames.items.len - 1].ep);
            }
        }
    }

    inline fn initFiberValueStackInPlace(stack: *FiberValueStack) void {
        stack.storage = undefined;
        stack.items = stack.storage[0..0];
        stack.capacity = MAX_FIBER_STACK_SIZE;
    }

    inline fn initFiberFrameStackInPlace(frames: *FiberFrameStack) void {
        frames.storage = undefined;
        frames.items = frames.storage[0..0];
        frames.capacity = MAX_FIBER_FRAMES;
    }

    fn ensureFiberCatchStack(self: *VM, fiber: *FiberObject) VMError!void {
        const gop = self.fiber_active_catches.getOrPut(fiber) catch return error.Fatal;
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }
    }

    fn ensureThreadCatchStack(self: *VM, thread: *ThreadObject) VMError!void {
        const gop = self.thread_active_catches.getOrPut(thread) catch return error.Fatal;
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }
    }

    fn fiberCatchStack(self: *VM, fiber: *FiberObject) *std.ArrayList(Value) {
        return self.fiber_active_catches.getPtr(fiber).?;
    }

    fn threadCatchStack(self: *VM, thread: *ThreadObject) *std.ArrayList(Value) {
        return self.thread_active_catches.getPtr(thread).?;
    }

    pub fn saveFiberState(self: *VM, fiber: *FiberObject) void {
        if (fiber.owner_thread) |owner_thread| {
            if (owner_thread.main_fiber != null and owner_thread.main_fiber.? == fiber) {
                if (self.main_thread == null or owner_thread != self.main_thread.?) {
                    owner_thread.current_lexical_scope = self.current_lexical_scope;
                    return;
                }
            }
        }
        fiber.current_lexical_scope = self.current_lexical_scope;
    }

    pub fn restoreFiberState(self: *VM, fiber: *FiberObject) void {
        if (fiber.owner_thread) |owner_thread| {
            if (owner_thread.main_fiber != null and owner_thread.main_fiber.? == fiber) {
                if (self.main_thread == null or owner_thread != self.main_thread.?) {
                    self.stack = &owner_thread.stack;
                    self.frames = &owner_thread.frames;
                    self.current_lexical_scope = owner_thread.current_lexical_scope;
                    self.active_catches = self.threadCatchStack(owner_thread);
                    return;
                }
            }
        }
        self.stack = &fiber.stack;
        self.frames = &fiber.frames;
        self.current_lexical_scope = fiber.current_lexical_scope;
        self.active_catches = self.fiberCatchStack(fiber);
    }

    inline fn rootFiberForCurrentThread(self: *VM) *FiberObject {
        if (self.current_thread) |thread| {
            if (thread.main_fiber) |main_fiber| return main_fiber;
        }
        return self.main_fiber;
    }

    inline fn setCurrentFiber(self: *VM, fiber: *FiberObject) void {
        self.current_fiber = fiber;
    }

    fn captureMainGcStackBase(self: *VM) VMError!void {
        var boehm_stack_base: bdwgc.c.GC_stack_base = undefined;
        const handle = bdwgc.c.GC_get_my_stackbottom(&boehm_stack_base);
        if (handle == null) return error.Fatal;
        if (boehm_stack_base.mem_base == null) return error.Fatal;
        self.gc_thread_handle = handle;
        self.main_stack_base = boehm_stack_base.mem_base;
    }

    fn registerVmRootForGc(self: *VM) void {
        if (self.gc_vm_root_registered) return;
        const vm_start: *anyopaque = @ptrCast(self);
        const vm_end: *anyopaque = @ptrFromInt(@intFromPtr(self) + @sizeOf(VM));
        bdwgc.c.GC_add_roots(vm_start, vm_end);
        self.gc_vm_root_registered = true;
    }

    fn unregisterVmRootForGc(self: *VM) void {
        if (!self.gc_vm_root_registered) return;
        const vm_start: *anyopaque = @ptrCast(self);
        const vm_end: *anyopaque = @ptrFromInt(@intFromPtr(self) + @sizeOf(VM));
        bdwgc.c.GC_remove_roots(vm_start, vm_end);
        self.gc_vm_root_registered = false;
    }

    fn stackBaseForFiber(self: *VM, fiber: *FiberObject) VMError!*anyopaque {
        if (fiber.coro) |coro| {
            return @ptrFromInt(coro.context.stack_info.base);
        }
        if (fiber.owner_thread) |owner_thread| {
            return self.stackBaseForThread(owner_thread);
        }
        if (fiber == self.main_fiber) {
            return self.main_stack_base orelse error.Fatal;
        }
        return error.Fatal;
    }

    fn setCurrentStackBaseForGc(self: *VM, stack_base: *anyopaque) VMError!void {
        const gc_thread_handle = self.gc_thread_handle orelse return error.Fatal;
        var boehm_stack_base: bdwgc.c.GC_stack_base = undefined;
        boehm_stack_base.mem_base = stack_base;
        if (@hasField(bdwgc.c.GC_stack_base, "reg_base")) {
            boehm_stack_base.reg_base = null;
        }
        bdwgc.c.GC_set_stackbottom(gc_thread_handle, &boehm_stack_base);
    }

    fn registerCoroutineStackForGc(self: *VM, coro_obj: *FiberCoro) VMError!void {
        if (self.gc_registered_coro_stacks.contains(coro_obj)) return;

        const stack_info = coro_obj.context.stack_info;
        if (stack_info.base <= stack_info.limit) return error.Fatal;

        const stack_start: *anyopaque = @ptrFromInt(stack_info.limit);
        const stack_end: *anyopaque = @ptrFromInt(stack_info.base);
        bdwgc.c.GC_add_roots(stack_start, stack_end);
        self.gc_registered_coro_stacks.put(coro_obj, {}) catch return error.Fatal;
    }

    fn unregisterCoroutineStackForGc(self: *VM, coro_obj: *FiberCoro) void {
        if (!self.gc_registered_coro_stacks.contains(coro_obj)) return;

        const stack_info = coro_obj.context.stack_info;
        if (stack_info.base > stack_info.limit) {
            const stack_start: *anyopaque = @ptrFromInt(stack_info.limit);
            const stack_end: *anyopaque = @ptrFromInt(stack_info.base);
            bdwgc.c.GC_remove_roots(stack_start, stack_end);
        }
        _ = self.gc_registered_coro_stacks.remove(coro_obj);
    }

    fn fiberEntrypoint(coro_obj: *FiberCoro, userdata: ?*anyopaque) void {
        _ = coro_obj;
        const fiber: *FiberObject = @ptrCast(@alignCast(userdata.?));
        runFiberCoroutine(fiber) catch |err| {
            const self = fiber.owner_vm;
            fiber.state = .terminated;
            switch (err) {
                error.UnhandledException => {
                    fiber.coro_event = .raised;
                    fiber.coro_exception = self.pendingException();
                },
                else => {
                    fiber.coro_event = .none;
                    fiber.coro_exception = null;
                },
            }
            if (fiber.coro) |c| c.yield();
            return;
        };
    }

    /// Fiber execution loop. Uses its own inline loop rather than executeFastLoop because
    /// fibers need mid-instruction hooks: checking for yield events and fiber termination
    /// between each instruction. These checks would pollute the hot path in executeFastLoop.
    fn runFiberCoroutine(fiber: *FiberObject) VMError!void {
        const self = fiber.owner_vm;
        const blk = fiber.block orelse return error.Fatal;
        switch (blk.kind) {
            .chunk => |chunk_blk| {
                self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, .fiber, .{}) catch return error.Fatal;

                const current_frame = self.currentFrame();
                self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, fiber.first_resume_args[0..fiber.first_resume_argc], .lenient) catch return error.Fatal;
            },
            .symbol => |sym| {
                const result = try self.invokeSymbolProc(sym, fiber.first_resume_args[0..fiber.first_resume_argc], null);
                fiber.state = .terminated;
                fiber.coro_result = result;
                fiber.coro_event = .returned;
                if (fiber.coro) |c| c.yield();
                return;
            },
            .receiver_builtin => |builtin_data| {
                const result = try builtin_data.func(self, builtin_data.receiver, fiber.first_resume_args[0..fiber.first_resume_argc]);
                fiber.state = .terminated;
                fiber.coro_result = result;
                fiber.coro_event = .returned;
                if (fiber.coro) |c| c.yield();
                return;
            },
            .builtin => |func| {
                const result = func(self, fiber.first_resume_args[0..fiber.first_resume_argc]) catch |err| {
                    if (err == error.Unwind) {
                        fiber.state = .terminated;
                        if (self.pendingException() == null and self.pendingThrow() != null) {
                            const pending_throw = self.pendingThrow().?;
                            self.setPendingException(try self.createUncaughtThrowError(pending_throw.tag, pending_throw.value));
                        }
                        fiber.coro_exception = self.pendingException();
                        fiber.coro_event = .raised;
                        if (fiber.coro) |c| c.yield();
                        return;
                    }
                    return err;
                };
                fiber.state = .terminated;
                fiber.coro_result = result;
                fiber.coro_event = .returned;
                if (fiber.coro) |c| c.yield();
                return;
            },
            .callable => |callable| {
                const result = try self.callMethodByName(callable, "call", fiber.first_resume_args[0..fiber.first_resume_argc], null);
                fiber.state = .terminated;
                fiber.coro_result = result;
                fiber.coro_event = .returned;
                if (fiber.coro) |c| c.yield();
                return;
            },
        }
        fiber.state = .running;

        while (true) {
            self.executeInstruction() catch |err| switch (err) {
                error.Unwind => {
                    self.unwindStack() catch |unwind_err| switch (unwind_err) {
                        error.UnhandledException => return error.UnhandledException,
                        else => return error.Fatal,
                    };
                },
                else => return error.Fatal,
            };

            if (fiber.coro_event == .yielded) {
                if (fiber.coro) |c| c.yield();
            }

            if (self.frames.items.len == 0) {
                fiber.state = .terminated;
                fiber.coro_result = self.pop();
                fiber.coro_event = .returned;
                if (fiber.coro) |c| c.yield();
                return;
            }
        }
    }

    fn ensureFiberCoroutine(self: *VM, fiber: *FiberObject) VMError!void {
        if (fiber.coro != null) return;

        const coro_obj = self.allocator.create(FiberCoro) catch return error.Fatal;
        coro_obj.* = .{
            .context = undefined,
            .parent_context_ptr = .init(&self.zio_main_context),
        };
        errdefer self.allocator.destroy(coro_obj);
        zio.coro.stackAlloc(&coro_obj.context.stack_info, 8 * 1024 * 1024, 256 * 1024) catch return error.Fatal;
        errdefer zio.coro.stackFree(coro_obj.context.stack_info);
        try self.registerCoroutineStackForGc(coro_obj);
        errdefer self.unregisterCoroutineStackForGc(coro_obj);
        coro_obj.setup(&fiberEntrypoint, fiber);
        self.zio_coroutines.append(self.allocator, coro_obj) catch return error.Fatal;
        fiber.coro = coro_obj;
    }

    pub fn fiberYield(self: *VM, yield_value: Value) VMError!Value {
        const fiber = self.current_fiber;
        if (fiber == self.rootFiberForCurrentThread()) {
            const exc = try self.createException(self.fiber_error_class, "can't yield from root fiber");
            self.setPendingException(exc);
            return error.Unwind;
        }

        fiber.coro_result = yield_value;
        fiber.coro_event = .yielded;
        fiber.state = .suspended;

        const coro_obj = fiber.coro orelse return error.Fatal;
        coro_obj.yield();

        fiber.state = .running;
        return fiber.coro_result;
    }

    pub fn resumeFiber(self: *VM, fiber: *FiberObject, args: []Value, resume_value: Value) VMError!Value {
        fiber.coro_result = resume_value;
        fiber.coro_event = .none;

        if (fiber.state == .created) {
            if (args.len > fiber.first_resume_args.len) return error.Fatal;
            for (args, 0..) |arg, i| {
                fiber.first_resume_args[i] = arg;
            }
            fiber.first_resume_argc = args.len;
            try self.ensureFiberCoroutine(fiber);
        }

        if (fiber.state == .suspended) {
            fiber.state = .running;
        }

        const caller = self.current_fiber;
        self.saveFiberState(caller);
        fiber.caller = caller;

        const parent_context: *FiberCoroContext = if (caller.coro) |caller_coro|
            &caller_coro.context
        else if (self.current_thread) |thread|
            if (thread.coro) |thread_coro|
                &thread_coro.context
            else
                &self.zio_main_context
        else
            &self.zio_main_context;

        const target_coro = fiber.coro orelse return error.Fatal;
        target_coro.parent_context_ptr.store(parent_context, .release);

        const caller_stack_base = try self.stackBaseForFiber(caller);
        const target_stack_base = try self.stackBaseForFiber(fiber);
        try self.setCurrentStackBaseForGc(target_stack_base);

        self.setCurrentFiber(fiber);
        self.restoreFiberState(fiber);

        errdefer {
            self.saveFiberState(fiber);
            self.setCurrentFiber(caller);
            self.restoreFiberState(caller);
            fiber.caller = null;
            self.setCurrentStackBaseForGc(caller_stack_base) catch {};
        }

        target_coro.step();

        self.saveFiberState(fiber);
        self.setCurrentFiber(caller);
        self.restoreFiberState(caller);
        fiber.caller = null;
        try self.setCurrentStackBaseForGc(caller_stack_base);
        if (fiber.state == .terminated) {
            if (fiber.coro) |terminated_coro| {
                self.unregisterCoroutineStackForGc(terminated_coro);
            }
        }

        return switch (fiber.coro_event) {
            .yielded => fiber.coro_result,
            .returned => fiber.coro_result,
            .raised => {
                self.setPendingException(fiber.coro_exception orelse return error.Fatal);
                return error.Unwind;
            },
            .none => error.Fatal,
        };
    }

    // =========================================================================
    // Thread infrastructure
    // =========================================================================

    pub fn ensureMainThread(self: *VM) VMError!*value.ThreadObject {
        if (self.main_thread) |mt| return mt;
        const main_thread_obj = self.gc_allocator.create(value.ThreadObject) catch return error.Fatal;
        main_thread_obj.object = .{ .type_tag = .thread, .flags = 0, .class = self.thread_class, .singleton_class = null, .instance_variables = null };
        main_thread_obj.state = .running;
        main_thread_obj.block = null;
        initFiberValueStackInPlace(&main_thread_obj.stack);
        initFiberFrameStackInPlace(&main_thread_obj.frames);
        main_thread_obj.current_lexical_scope = null;
        main_thread_obj.coro = null;
        main_thread_obj.result = Value.nil();
        main_thread_obj.exception = null;
        main_thread_obj.terminated_normally = false;
        main_thread_obj.fiber_locals = null;
        main_thread_obj.thread_variables = null;
        main_thread_obj.name = null;
        main_thread_obj.priority = 0;
        main_thread_obj.report_on_exception = true;
        main_thread_obj.abort_on_exception = false;
        main_thread_obj.kill_requested = false;
        main_thread_obj.waiting_on_queue = false;
        main_thread_obj.preempt_requested = false;
        main_thread_obj.ops_until_preempt = self.thread_preempt_quantum_ops;
        main_thread_obj.io_wait = null;
        main_thread_obj.args = null;
        main_thread_obj.main_fiber = self.main_fiber;
        main_thread_obj.current_fiber = self.main_fiber;
        main_thread_obj.owner_vm = self;
        self.main_fiber.owner_thread = main_thread_obj;
        try self.ensureThreadCatchStack(main_thread_obj);
        self.main_thread = main_thread_obj;
        self.current_thread = main_thread_obj;
        self.setCurrentFiber(self.main_fiber);
        self.thread_list.append(self.gc_allocator, main_thread_obj) catch return error.Fatal;
        return main_thread_obj;
    }

    pub fn newMutex(self: *VM, class_val: Value) VMError!*value.MutexObject {
        _ = class_val;
        const mutex_obj = self.gc_allocator.create(value.MutexObject) catch return error.Fatal;
        mutex_obj.object = .{ .type_tag = .mutex, .flags = 0, .class = self.mutex_class, .singleton_class = null, .instance_variables = null };
        mutex_obj.state = .unlocked;
        mutex_obj.owner_thread = null;
        mutex_obj.owner_fiber = null;
        return mutex_obj;
    }

    pub fn newConditionVariable(self: *VM, class_val: Value) VMError!*value.ConditionVariableObject {
        const cv_obj = self.gc_allocator.create(value.ConditionVariableObject) catch return error.Fatal;
        cv_obj.object = .{ .type_tag = .condition_variable, .flags = 0, .class = class_val.toClassObject(), .singleton_class = null, .instance_variables = null };
        cv_obj.waiters = .empty;
        return cv_obj;
    }

    pub fn newQueue(self: *VM, class_val: Value) VMError!*value.QueueObject {
        const queue_obj = self.gc_allocator.create(value.QueueObject) catch return error.Fatal;
        queue_obj.object = .{ .type_tag = .queue, .flags = 0, .class = class_val.toClassObject(), .singleton_class = null, .instance_variables = null };
        queue_obj.items = .empty;
        queue_obj.read_index = 0;
        queue_obj.dequeue_waiters = .empty;
        queue_obj.enqueue_waiters = .empty;
        queue_obj.closed = false;
        queue_obj.max_size = null;
        return queue_obj;
    }

    pub fn newThreadUnstarted(self: *VM, class_obj: *value.ClassObject) VMError!*value.ThreadObject {
        _ = try self.ensureMainThread();
        const thread_obj = self.gc_allocator.create(value.ThreadObject) catch return error.Fatal;
        thread_obj.object = .{ .type_tag = .thread, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null };
        thread_obj.state = .created;
        thread_obj.block = null;
        initFiberValueStackInPlace(&thread_obj.stack);
        initFiberFrameStackInPlace(&thread_obj.frames);
        thread_obj.current_lexical_scope = self.current_lexical_scope;
        thread_obj.coro = null;
        thread_obj.result = Value.nil();
        thread_obj.exception = null;
        thread_obj.terminated_normally = false;
        thread_obj.fiber_locals = null;
        thread_obj.thread_variables = null;
        thread_obj.name = null;
        thread_obj.priority = 0;
        thread_obj.report_on_exception = true;
        thread_obj.abort_on_exception = false;
        thread_obj.kill_requested = false;
        thread_obj.waiting_on_queue = false;
        thread_obj.waiting_on_require = false;
        thread_obj.preempt_requested = false;
        thread_obj.ops_until_preempt = self.thread_preempt_quantum_ops;
        thread_obj.io_wait = null;
        thread_obj.args = null;
        const root_fiber = self.gc_allocator.create(value.FiberObject) catch return error.Fatal;
        root_fiber.object = .{ .type_tag = .fiber, .flags = 0, .class = self.fiber_class, .singleton_class = null, .instance_variables = null };
        root_fiber.state = .running;
        root_fiber.block = null;
        initFiberValueStackInPlace(&root_fiber.stack);
        initFiberFrameStackInPlace(&root_fiber.frames);
        root_fiber.current_lexical_scope = thread_obj.current_lexical_scope;
        root_fiber.caller = null;
        root_fiber.coro = null;
        root_fiber.coro_event = .none;
        root_fiber.coro_result = Value.nil();
        root_fiber.coro_exception = null;
        root_fiber.first_resume_args = undefined;
        root_fiber.first_resume_argc = 0;
        root_fiber.fiber_locals = null;
        root_fiber.owner_thread = thread_obj;
        root_fiber.owner_vm = self;
        thread_obj.main_fiber = root_fiber;
        thread_obj.current_fiber = root_fiber;
        thread_obj.owner_vm = self;
        try self.ensureThreadCatchStack(thread_obj);
        try self.ensureFiberCatchStack(root_fiber);
        return thread_obj;
    }

    pub fn configureThread(self: *VM, thread_obj: *value.ThreadObject, block: Block, args: []Value) VMError!void {
        // Copy args to GC-allocated memory so they survive across coroutine switches.
        const args_copy = if (args.len > 0) blk: {
            const copy = self.gc_allocator.alloc(Value, args.len) catch return error.Fatal;
            @memcpy(copy, args);
            break :blk copy;
        } else null;

        thread_obj.block = block;
        thread_obj.args = args_copy;
    }

    pub fn startThread(self: *VM, thread_obj: *value.ThreadObject) VMError!void {
        self.thread_list.append(self.gc_allocator, thread_obj) catch return error.Fatal;
        self.runnable_queue.append(self.gc_allocator, thread_obj) catch return error.Fatal;
    }

    pub fn releaseThreadOwnedMutexes(self: *VM, thread: *value.ThreadObject) void {
        if (self.thread_owned_mutexes.getPtr(thread)) |owned_mutexes| {
            while (owned_mutexes.items.len > 0) {
                const mutex = owned_mutexes.pop() orelse break;
                mutex.state = .unlocked;
                mutex.owner_thread = null;
                mutex.owner_fiber = null;
                self.wakeNextMutexWaiter(mutex);
            }
        }
    }

    pub fn wakeNextMutexWaiter(self: *VM, mutex: *value.MutexObject) void {
        if (self.mutex_waiters.getPtr(mutex)) |waiters| {
            while (waiters.items.len > 0) {
                const waiter = waiters.orderedRemove(0);
                if (!self.isKnownThread(waiter)) continue;
                if (waiter.state == .terminated) continue;
                waiter.state = .running;
                for (self.runnable_queue.items) |thread| {
                    if (thread == waiter) return;
                }
                self.runnable_queue.append(self.gc_allocator, waiter) catch {};
                return;
            }
        }
    }

    pub fn newThread(self: *VM, class_obj: *value.ClassObject, block: Block, args: []Value) VMError!*value.ThreadObject {
        const thread_obj = try self.newThreadUnstarted(class_obj);
        try self.configureThread(thread_obj, block, args);
        try self.startThread(thread_obj);
        return thread_obj;
    }

    fn saveThreadState(self: *VM, thread: *value.ThreadObject) void {
        thread.current_lexical_scope = self.current_lexical_scope;
        thread.current_fiber = self.current_fiber;
    }

    fn restoreThreadState(self: *VM, thread: *value.ThreadObject) void {
        self.stack = &thread.stack;
        self.frames = &thread.frames;
        self.current_lexical_scope = thread.current_lexical_scope;
        self.active_catches = self.threadCatchStack(thread);
    }

    fn ensureThreadCoroutine(self: *VM, thread: *value.ThreadObject) VMError!void {
        if (thread.coro != null) return;

        const coro_obj = self.allocator.create(FiberCoro) catch return error.Fatal;
        coro_obj.* = .{
            .context = undefined,
            .parent_context_ptr = .init(&self.zio_main_context),
        };
        errdefer self.allocator.destroy(coro_obj);
        zio.coro.stackAlloc(&coro_obj.context.stack_info, 8 * 1024 * 1024, 256 * 1024) catch return error.Fatal;
        errdefer zio.coro.stackFree(coro_obj.context.stack_info);
        try self.registerCoroutineStackForGc(coro_obj);
        errdefer self.unregisterCoroutineStackForGc(coro_obj);
        coro_obj.setup(&threadEntrypoint, thread);
        self.zio_coroutines.append(self.allocator, coro_obj) catch return error.Fatal;
        thread.coro = coro_obj;
    }

    fn threadEntrypoint(coro_obj: *FiberCoro, userdata: ?*anyopaque) void {
        _ = coro_obj;
        const thread: *value.ThreadObject = @ptrCast(@alignCast(userdata.?));
        runThreadCoroutine(thread) catch |err| {
            const self = thread.owner_vm;
            thread.state = .terminated;
            self.releaseThreadOwnedMutexes(thread);
            switch (err) {
                error.UnhandledException => {
                    if (self.pendingException()) |exc| {
                        if (exc.object.class == self.thread_kill_exception_class) {
                            thread.terminated_normally = true;
                            thread.exception = null;
                            thread.result = Value.nil();
                            self.setPendingException(null);
                        } else {
                            thread.terminated_normally = false;
                            thread.exception = exc;
                        }
                    } else {
                        thread.terminated_normally = false;
                        thread.exception = null;
                    }
                },
                else => {
                    thread.terminated_normally = true;
                },
            }
            if (thread.coro) |c| c.yield();
            return;
        };
    }

    fn runThreadCoroutine(thread: *value.ThreadObject) VMError!void {
        const self = thread.owner_vm;
        const blk = thread.block orelse return error.Fatal;
        switch (blk.kind) {
            .chunk => |chunk_blk| {
                self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, .fiber, .{}) catch return error.Fatal;

                const current_frame = self.currentFrame();
                const thread_args = thread.args orelse &[_]Value{};
                self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, thread_args, .lenient) catch return error.Fatal;
            },
            .symbol => |sym| {
                const thread_args = thread.args orelse &[_]Value{};
                const result = try self.invokeSymbolProc(sym, thread_args, null);
                thread.state = .terminated;
                thread.result = result;
                thread.terminated_normally = true;
                self.releaseThreadOwnedMutexes(thread);
                if (thread.coro) |c| c.yield();
                return;
            },
            .receiver_builtin => |builtin_data| {
                var empty_args = [_]Value{};
                const thread_args = thread.args orelse &empty_args;
                const result = try builtin_data.func(self, builtin_data.receiver, thread_args);
                thread.state = .terminated;
                thread.result = result;
                thread.terminated_normally = true;
                self.releaseThreadOwnedMutexes(thread);
                if (thread.coro) |c| c.yield();
                return;
            },
            .builtin => |func| {
                var empty_args = [_]Value{};
                const thread_args = thread.args orelse &empty_args;
                const result = func(self, thread_args) catch |err| {
                    if (err == error.Unwind) {
                        if (self.pendingException() == null and self.pendingThrow() != null) {
                            const pending_throw = self.pendingThrow().?;
                            self.setPendingException(try self.createUncaughtThrowError(pending_throw.tag, pending_throw.value));
                        }
                        thread.state = .terminated;
                        thread.exception = self.pendingException();
                        thread.terminated_normally = false;
                        self.releaseThreadOwnedMutexes(thread);
                        if (thread.coro) |c| c.yield();
                        return;
                    }
                    return err;
                };
                thread.state = .terminated;
                thread.result = result;
                thread.terminated_normally = true;
                self.releaseThreadOwnedMutexes(thread);
                if (thread.coro) |c| c.yield();
                return;
            },
            .callable => |callable| {
                var empty_args = [_]Value{};
                const thread_args = thread.args orelse &empty_args;
                const result = try self.callMethodByName(callable, "call", thread_args, null);
                thread.state = .terminated;
                thread.result = result;
                thread.terminated_normally = true;
                self.releaseThreadOwnedMutexes(thread);
                if (thread.coro) |c| c.yield();
                return;
            },
        }
        thread.state = .running;
        self.resetThreadPreemptBudget(thread);

        while (true) {
            // Check kill request before each instruction
            if (thread.kill_requested) {
                thread.kill_requested = false;
                thread.state = .aborting;
                self.setPendingException(try self.createException(self.thread_kill_exception_class, ""));
                self.unwindStack() catch |unwind_err| switch (unwind_err) {
                    error.UnhandledException => return error.UnhandledException,
                    else => return error.Fatal,
                };
                continue;
            }

            var executed_op: ?bytecode.OpCode = null;
            if (self.frames.items.len > 0) {
                const frame = &self.frames.storage[self.frames.items.len - 1];
                if (frame.ip < frame.chunk.code.items.len) {
                    executed_op = @enumFromInt(frame.chunk.code.items[frame.ip]);
                }
            }

            self.executeInstruction() catch |err| switch (err) {
                error.Unwind => {
                    self.unwindStack() catch |unwind_err| switch (unwind_err) {
                        error.UnhandledException => return error.UnhandledException,
                        else => return error.Fatal,
                    };
                },
                else => return error.Fatal,
            };

            if (self.frames.items.len == 0) {
                thread.state = .terminated;
                thread.result = self.pop();
                thread.terminated_normally = true;
                self.releaseThreadOwnedMutexes(thread);
                if (thread.coro) |c| c.yield();
                return;
            }

            const safe_point = if (executed_op) |op| isThreadPreemptSafePoint(op) else false;
            if (self.shouldPreemptThread(thread, safe_point)) {
                try self.threadYield();
            }
        }
    }

    inline fn hasOtherRunnableThread(self: *VM, current_thread: *value.ThreadObject) bool {
        for (self.runnable_queue.items) |thread| {
            if (!self.isKnownThread(thread)) continue;
            if (thread == current_thread) continue;
            if (thread.state == .created or thread.state == .running) return true;
        }
        return false;
    }

    inline fn isKnownThread(self: *VM, candidate: *value.ThreadObject) bool {
        for (self.thread_list.items) |thread| {
            if (thread == candidate) return true;
        }
        return false;
    }

    fn addRunnableThreadIfAbsent(self: *VM, thread: *value.ThreadObject) void {
        for (self.runnable_queue.items) |queued| {
            if (queued == thread) return;
        }
        self.runnable_queue.append(self.gc_allocator, thread) catch {};
    }

    fn wakeSleepingIoWaiters(self: *VM) void {
        const now_ms = monotonicMilliseconds();
        for (self.thread_list.items) |thread| {
            if (thread.state != .sleeping) continue;
            const io_wait = thread.io_wait orelse continue;

            if (thread.kill_requested) {
                thread.io_wait = null;
                thread.state = .running;
                self.addRunnableThreadIfAbsent(thread);
                continue;
            }

            if (io_wait.deadline_ms) |deadline_ms| {
                if (now_ms >= deadline_ms) {
                    thread.io_wait = null;
                    thread.state = .running;
                    self.addRunnableThreadIfAbsent(thread);
                    continue;
                }
            }

            var fds = [_]std.posix.pollfd{.{
                .fd = @intCast(io_wait.fd),
                .events = io_wait.events,
                .revents = 0,
            }};
            const ready_count = std.posix.poll(fds[0..], 0) catch continue;
            if (ready_count == 0) continue;

            var ready_mask = io_wait.events | std.posix.POLL.ERR;
            if (io_wait.include_hup) ready_mask |= std.posix.POLL.HUP;
            if ((fds[0].revents & ready_mask) == 0) continue;

            thread.io_wait = null;
            thread.state = .running;
            self.addRunnableThreadIfAbsent(thread);
        }
    }

    inline fn resetThreadPreemptBudget(self: *VM, thread: *value.ThreadObject) void {
        thread.preempt_requested = false;
        thread.ops_until_preempt = self.thread_preempt_quantum_ops;
    }

    inline fn isThreadPreemptSafePoint(op: bytecode.OpCode) bool {
        return switch (op) {
            .JUMP, .JUMP_IF_FALSE, .JUMP_IF_NIL, .RETURN => true,
            else => false,
        };
    }

    inline fn shouldPreemptThread(self: *VM, thread: *value.ThreadObject, safe_point: bool) bool {
        if (self.thread_preempt_quantum_ops == 0) return false;
        if (thread.ops_until_preempt > 1) {
            thread.ops_until_preempt -= 1;
        } else {
            thread.ops_until_preempt = self.thread_preempt_quantum_ops;
            thread.preempt_requested = true;
        }

        if (!thread.preempt_requested or !safe_point) return false;

        if (!self.hasOtherRunnableThread(thread)) {
            thread.preempt_requested = false;
            return false;
        }
        thread.preempt_requested = false;
        return true;
    }

    fn stackBaseForThread(self: *VM, thread: *value.ThreadObject) VMError!*anyopaque {
        if (self.main_thread != null and thread == self.main_thread.?) {
            return self.main_stack_base orelse error.Fatal;
        }
        const coro = thread.coro orelse return error.Fatal;
        return @ptrFromInt(coro.context.stack_info.base);
    }

    /// Yield to the thread scheduler. Runs all other runnable threads one step each,
    /// then returns control to the caller.
    pub fn schedulerYield(self: *VM) VMError!void {
        self.wakeSleepingIoWaiters();
        if (self.runnable_queue.items.len == 0) return;

        const caller_thread = self.current_thread orelse return;

        // Save current fiber state so we can restore it after
        const caller_fiber = self.current_fiber;
        self.saveFiberState(caller_fiber);
        self.saveThreadState(caller_thread);

        const caller_stack_base = try self.stackBaseForFiber(caller_fiber);

        // Run each runnable thread one step
        var i: usize = 0;
        while (i < self.runnable_queue.items.len) {
            const thread = self.runnable_queue.items[i];
            if (!self.isKnownThread(thread)) {
                _ = self.runnable_queue.orderedRemove(i);
                continue;
            }
            if (thread == caller_thread) {
                i += 1;
                continue;
            }
            if (thread.state == .terminated) {
                _ = self.runnable_queue.orderedRemove(i);
                continue;
            }

            // Set up thread's coroutine if needed
            if (thread.state == .created) {
                try self.ensureThreadCoroutine(thread);
                thread.state = .running;
            }

            if (thread.state == .sleeping) {
                i += 1;
                continue;
            }

            // Switch to thread
            self.current_thread = thread;
            self.restoreThreadState(thread);
            self.current_fiber = thread.current_fiber orelse thread.main_fiber orelse self.main_fiber;

            const target_stack_base = try self.stackBaseForThread(thread);
            try self.setCurrentStackBaseForGc(target_stack_base);
            self.resetThreadPreemptBudget(thread);

            const target_coro = thread.coro orelse return error.Fatal;
            const parent_context: *FiberCoroContext = if (caller_fiber.coro) |caller_coro|
                &caller_coro.context
            else if (caller_thread.coro) |caller_thread_coro|
                &caller_thread_coro.context
            else
                &self.zio_main_context;
            target_coro.parent_context_ptr.store(parent_context, .release);
            target_coro.step();

            self.saveThreadState(thread);

            if (thread.state == .terminated) {
                if (thread.coro) |terminated_coro| {
                    self.unregisterCoroutineStackForGc(terminated_coro);
                }
                // Thread may have already removed itself from the queue
                if (i < self.runnable_queue.items.len and self.runnable_queue.items[i] == thread) {
                    _ = self.runnable_queue.orderedRemove(i);
                }
                continue;
            }

            i += 1;
        }

        // Restore caller state
        self.current_thread = caller_thread;
        self.restoreThreadState(caller_thread);
        self.current_fiber = caller_fiber;
        self.restoreFiberState(caller_fiber);
        try self.setCurrentStackBaseForGc(caller_stack_base);
    }

    /// Yield to scheduler, used by Thread.pass and join loops
    pub fn threadYield(self: *VM) VMError!void {
        try self.checkAsyncEvents();

        const thread = self.current_thread orelse return self.schedulerYield();
        const main = self.main_thread orelse return self.schedulerYield();
        if (thread == main) {
            // Main thread: run scheduler directly
            return self.schedulerYield();
        }
        // Non-main thread: yield the coroutine
        if (thread.coro) |c| c.yield();

        // After resuming, check if we've been killed
        if (thread.kill_requested) {
            thread.kill_requested = false;
            thread.state = .aborting;
            self.setPendingException(try self.createException(self.thread_kill_exception_class, ""));
            return error.Unwind;
        }
    }

    pub fn maybePreemptCurrentThread(self: *VM, safe_point: bool) VMError!void {
        try self.checkAsyncEvents();
        const thread = self.current_thread orelse return;
        const main = self.main_thread orelse return;
        if (thread == main) return;
        if (self.shouldPreemptThread(thread, safe_point)) {
            try self.threadYield();
        }
    }

    const OptIntegerBinaryOp = enum {
        plus,
        minus,
        mult,
        div,
        eq,
        lt,
        gt,
        le,
        ge,
    };

    inline fn executeOptIntegerBinary(self: *VM, op: OptIntegerBinaryOp) VMError!void {
        if (self.stack.items.len < 2) return error.Fatal;
        const receiver = self.peek(1);
        const arg = self.peek(0);

        if (!self.integer_changed and receiver.isInteger() and arg.isInteger()) {
            _ = self.pop();
            _ = self.pop();
            const fast_result = switch (op) {
                .plus => try self.addIntegerValues(receiver, arg),
                .minus => try self.subIntegerValues(receiver, arg),
                .mult => try self.mulIntegerValues(receiver, arg),
                .div => try self.divFloorIntegerValues(receiver, arg),
                .eq => Value.boolean(receiver.toInteger() == arg.toInteger()),
                .lt => Value.boolean(receiver.toInteger() < arg.toInteger()),
                .gt => Value.boolean(receiver.toInteger() > arg.toInteger()),
                .le => Value.boolean(receiver.toInteger() <= arg.toInteger()),
                .ge => Value.boolean(receiver.toInteger() >= arg.toInteger()),
            };
            try self.push(fast_result);
            return;
        }

        var args = [_]Value{arg};
        const method_name = switch (op) {
            .plus => "+",
            .minus => "-",
            .mult => "*",
            .div => "/",
            .eq => "==",
            .lt => "<",
            .gt => ">",
            .le => "<=",
            .ge => ">=",
        };
        const result = try self.callMethodByName(receiver, method_name, args[0..], null);
        _ = self.pop();
        _ = self.pop();
        try self.push(result);
    }

    pub fn executeInstruction(self: *VM) VMError!void {
        const frame = self.currentFrame();
        if (frame.ip >= frame.chunk.code.items.len) return error.Fatal;

        const instr_idx = frame.ip;
        const op: bytecode.OpCode = @enumFromInt(frame.chunk.code.items[instr_idx]);
        // ip now points just past the opcode byte; operands start here
        frame.ip = instr_idx + 1;
        const operands = frame.chunk.code.items[frame.ip..];
        var operand_cursor: usize = 0;
        const constants = frame.chunk.constants.items;

        switch (op) {
            .PUSH_NIL => {
                try self.push(Value.nil());
            },

            .PUSH_TRUE => {
                try self.push(Value.boolean(true));
            },

            .PUSH_FALSE => {
                try self.push(Value.boolean(false));
            },

            .PUSH_CONST => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                const val = switch (constant) {
                    .integer => |i| if (std.math.cast(i63, i) != null) Value.integer(i) else try self.newBigIntegerFromI64(i),
                    .big_integer_decimal => |digits| try self.newBigIntegerFromDecimalString(digits),
                    .float => |f| try self.newFloat(f),
                    .rational => |r| try self.newRational(r.numerator, r.denominator),
                    .string => |s| try self.newStringWithEncoding(s, false, literalStringEncodingForChunk(frame.chunk.source_encoding, s)),
                    .encoded_string => |s| try self.newStringWithEncoding(s.bytes, false, s.encoding),
                    .symbol => |s| Value.fromObject(&s.object),
                };
                try self.push(val);
            },

            .PUSH_CSTRING => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                switch (constant) {
                    .string => |s| {
                        const val = try self.newStringWithEncoding(s, false, literalStringEncodingForChunk(frame.chunk.source_encoding, s));
                        val.toStringObject().chilled_literal = true;
                        try self.push(val);
                    },
                    .encoded_string => |s| {
                        const val = try self.newStringWithEncoding(s.bytes, false, s.encoding);
                        val.toStringObject().chilled_literal = true;
                        try self.push(val);
                    },
                    else => return error.Fatal,
                }
            },

            .PUSH_FSTRING => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                switch (constant) {
                    .string => |s| {
                        const literal_encoding = literalStringEncodingForChunk(frame.chunk.source_encoding, s);
                        const encoding_tag: u8 = @intFromEnum(std.meta.activeTag(literal_encoding));
                        const source_marker = frame.chunk.source_file orelse frame.chunk.name;
                        var source_hasher = std.hash.Wyhash.init(0);
                        source_hasher.update(source_marker);
                        const source_hash = source_hasher.final();
                        var hasher = std.hash.Wyhash.init(0);
                        hasher.update(s);
                        const content_hash = hasher.final();
                        var key_buf: [64]u8 = undefined;
                        const key = std.fmt.bufPrint(
                            &key_buf,
                            "{x}:{x}:{d}",
                            .{ source_hash, content_hash, encoding_tag },
                        ) catch return error.Fatal;
                        if (self.fstring_cache.get(key)) |cached| {
                            const canonical = try self.getOrCreateCanonicalFStringValue(cached);
                            try self.push(canonical);
                        } else {
                            const frozen = try self.newStringWithEncoding(
                                s,
                                true,
                                literal_encoding,
                            );
                            const canonical = try self.getOrCreateCanonicalFStringValue(frozen);
                            const owned_key = self.allocator.dupe(u8, key) catch return error.Fatal;
                            self.fstring_cache.put(owned_key, canonical) catch return error.Fatal;
                            try self.push(canonical);
                        }
                    },
                    .encoded_string => |s| {
                        const encoding_tag: u8 = @intFromEnum(std.meta.activeTag(s.encoding));
                        const source_marker = frame.chunk.source_file orelse frame.chunk.name;
                        var source_hasher = std.hash.Wyhash.init(0);
                        source_hasher.update(source_marker);
                        const source_hash = source_hasher.final();
                        var hasher = std.hash.Wyhash.init(0);
                        hasher.update(s.bytes);
                        const content_hash = hasher.final();
                        var key_buf: [64]u8 = undefined;
                        const key = std.fmt.bufPrint(
                            &key_buf,
                            "{x}:{x}:{d}",
                            .{ source_hash, content_hash, encoding_tag },
                        ) catch return error.Fatal;
                        if (self.fstring_cache.get(key)) |cached| {
                            const canonical = try self.getOrCreateCanonicalFStringValue(cached);
                            try self.push(canonical);
                        } else {
                            const frozen = try self.newStringWithEncoding(
                                s.bytes,
                                true,
                                s.encoding,
                            );
                            const canonical = try self.getOrCreateCanonicalFStringValue(frozen);
                            const owned_key = self.allocator.dupe(u8, key) catch return error.Fatal;
                            self.fstring_cache.put(owned_key, canonical) catch return error.Fatal;
                            try self.push(canonical);
                        }
                    },
                    else => return error.Fatal,
                }
            },

            .PUSH_I8 => {
                const val: i8 = @bitCast(readByteFrom(frame, operands, &operand_cursor));
                try self.push(Value.integer(@intCast(val)));
            },

            .PUSH_SYMBOL => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                switch (constant) {
                    .string => |name| {
                        const symbol_encoding = literalSymbolEncodingForChunk(frame.chunk.source_encoding, name);
                        const sym = try self.internWithEncoding(name, symbol_encoding);
                        try self.push(Value.fromObject(&sym.object));
                    },
                    .encoded_string => |name| {
                        const sym = try self.internWithEncoding(name.bytes, name.encoding);
                        try self.push(Value.fromObject(&sym.object));
                    },
                    .symbol => |sym| try self.push(Value.fromObject(&sym.object)),
                    else => return error.Fatal,
                }
            },

            .GET_LOCAL => {
                // Operand is ep_offset (patched at compile time from local_idx).
                // ep - ep_offset gives the local's Value slot.
                const ep_offset = readU16From(frame, operands, &operand_cursor);
                try self.push((frame.ep - ep_offset)[0]);
            },

            .SET_LOCAL => {
                const ep_offset = readU16From(frame, operands, &operand_cursor);
                const val = self.pop();
                (frame.ep - ep_offset)[0] = val;
                try self.push(val);
            },

            .GET_LOCAL_DEEP => {
                // Operand is local_idx (0-based in the outer scope).
                // Walk the ep chain `depth` times, then use ep[2] (stored locals_count)
                // to compute the ep_offset at runtime.
                const local_idx = readU16From(frame, operands, &operand_cursor);
                const depth = readByteFrom(frame, operands, &operand_cursor);
                var ep: [*]Value = frame.ep;
                for (0..depth) |_| ep = decodeEp(ep[0]) orelse break;
                const outer_lc = epLocalsCount(ep);
                const ep_offset = outer_lc - local_idx;
                try self.push((ep - ep_offset)[0]);
            },

            .SET_LOCAL_DEEP => {
                const local_idx = readU16From(frame, operands, &operand_cursor);
                const depth = readByteFrom(frame, operands, &operand_cursor);
                const val = self.pop();
                var ep: [*]Value = frame.ep;
                for (0..depth) |_| ep = decodeEp(ep[0]) orelse break;
                const outer_lc = epLocalsCount(ep);
                const ep_offset = outer_lc - local_idx;
                (ep - ep_offset)[0] = val;
                try self.push(val);
            },

            .GET_GLOBAL => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;

                const global_val = self.globals.get(var_name) orelse Value.nil();
                try self.push(global_val);
            },

            .GET_BACKREF => {
                const capture_index = readU16From(frame, operands, &operand_cursor);
                try self.push(self.getBackrefCapture(capture_index));
            },

            .SET_GLOBAL => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const global_val = self.peek(0);
                try self.setGlobal(var_name, global_val);
            },

            .GET_CVAR => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const name_sym = try self.intern(var_name);

                const ctx = self.resolveClassVariableContext(frame);
                if (self.lookupClassVariable(ctx.module, ctx.start_class, name_sym)) |val| {
                    try self.push(val);
                } else {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized class variable {s} in {s}",
                        .{ var_name, ctx.module.name.name },
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.setPendingException(exc);
                    return error.Unwind;
                }
            },

            .GET_CVAR_OR_NIL => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const name_sym = try self.intern(var_name);

                const ctx = self.resolveClassVariableContext(frame);
                if (self.lookupClassVariable(ctx.module, ctx.start_class, name_sym)) |val| {
                    try self.push(val);
                } else {
                    try self.push(Value.nil());
                }
            },

            .SET_CVAR => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const name_sym = try self.intern(var_name);
                const class_var_val = self.peek(0);

                const ctx = self.resolveClassVariableContext(frame);
                ctx.module.class_variables.put(name_sym, class_var_val) catch return error.Fatal;
            },

            .GET_IVAR => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const self_val = frame.self_value;

                const ivar_val = try self.getInstanceVariable(self_val, var_name);
                try self.push(ivar_val);
            },

            .SET_IVAR => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const name_val = constants[name_idx];
                const var_name = name_val.string;
                const ivar_val = self.peek(0);
                const self_val = frame.self_value;

                try self.setInstanceVariable(self_val, var_name, ivar_val);
            },

            .GET_CONST => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);
                var lexical_lookup = LexicalConstantLookupResult{};

                // Walk lexical scope chain first
                if (epLexScope(frame.ep)) |scope| {
                    lexical_lookup = try self.findConstantInLexicalScope(scope, name_sym);
                    if (lexical_lookup.value) |val| {
                        try self.push(val);
                        return;
                    }
                }

                // Fallback: top-level Object constants
                if (self.object_class.module.constants.get(name_sym)) |entry| {
                    try self.warnDeprecatedConstant(&self.object_class.module, name_sym);
                    try self.push(entry.value);
                } else {
                    if (!lexical_lookup.object_autoload_attempted) {
                        switch (try self.triggerAutoload(&self.object_class.module, name_sym)) {
                            .missing, .attempted => {},
                            .loaded => |const_val| {
                                try self.push(const_val);
                                return;
                            },
                        }
                    }
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized constant {s}",
                        .{constant.string},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.setPendingException(exc);
                    return error.Unwind;
                }
            },

            .GET_CONST_OR_NIL => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);
                var lexical_lookup = LexicalConstantLookupResult{};

                if (epLexScope(frame.ep)) |scope| {
                    lexical_lookup = try self.findConstantInLexicalScope(scope, name_sym);
                    if (lexical_lookup.value) |val| {
                        try self.push(val);
                        return;
                    }
                }

                if (self.object_class.module.constants.get(name_sym)) |entry| {
                    try self.warnDeprecatedConstant(&self.object_class.module, name_sym);
                    try self.push(entry.value);
                } else {
                    if (!lexical_lookup.object_autoload_attempted) {
                        switch (try self.triggerAutoload(&self.object_class.module, name_sym)) {
                            .missing, .attempted => {},
                            .loaded => |const_val| {
                                try self.push(const_val);
                                return;
                            },
                        }
                    }
                    try self.push(Value.nil());
                }
            },

            .SET_CONST => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const val = self.pop();
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);

                // Set in current lexical scope's module (or Object if no scope)
                if (epLexScope(frame.ep)) |scope| {
                    const module = scope.getModule();
                    if (module.constants.getPtr(name_sym)) |entry| {
                        entry.value = val;
                    } else {
                        module.constants.put(name_sym, .{ .value = val }) catch return error.Fatal;
                    }
                } else {
                    if (self.object_class.module.constants.getPtr(name_sym)) |entry| {
                        entry.value = val;
                    } else {
                        self.object_class.module.constants.put(name_sym, .{ .value = val }) catch return error.Fatal;
                    }
                }
                try self.push(val);
            },

            .SET_CONST_PATH => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const val = self.pop();
                const parent_val = self.pop();
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);

                const module = if (parent_val.isClass())
                    &parent_val.toClassObject().module
                else if (parent_val.isModule())
                    parent_val.toModuleObject()
                else {
                    const exc = try self.createException(self.type_error_class, "receiver is not a Module");
                    self.setPendingException(exc);
                    return error.Unwind;
                };

                if (module.constants.getPtr(name_sym)) |entry| {
                    entry.value = val;
                } else {
                    module.constants.put(name_sym, .{ .value = val }) catch return error.Fatal;
                }
                _ = module.autoloads.remove(name_sym);
                try self.push(val);
            },

            .GET_CONST_PATH => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                const parent_val = self.pop();
                const name_sym = try self.intern(constant.string);

                const module = if (parent_val.isClass())
                    &parent_val.toClassObject().module
                else if (parent_val.isModule())
                    parent_val.toModuleObject()
                else
                    unreachable;
                if (module.constants.get(name_sym)) |entry| {
                    if (entry.flags.visibility == .private) {
                        try self.raisePrivateConstantReference(module, name_sym);
                    }
                    try self.warnDeprecatedConstant(module, name_sym);
                    try self.push(entry.value);
                    return;
                }

                // Check included modules of the class/module itself.
                var ii = module.included_modules.items.len;
                while (ii > 0) {
                    ii -= 1;
                    const included = module.included_modules.items[ii];
                    if (included.constants.get(name_sym)) |entry| {
                        try self.warnDeprecatedConstant(included, name_sym);
                        try self.push(entry.value);
                        return;
                    }
                }

                if (parent_val.isClass()) {
                    var superclass = parent_val.toClassObject().superclass;
                    while (superclass) |cls| : (superclass = cls.superclass) {
                        if (cls.module.constants.get(name_sym)) |entry| {
                            if (entry.flags.visibility == .private) {
                                try self.raisePrivateConstantReference(&cls.module, name_sym);
                            }
                            try self.warnDeprecatedConstant(&cls.module, name_sym);
                            try self.push(entry.value);
                            return;
                        }
                        // Check included modules of each superclass.
                        var si = cls.module.included_modules.items.len;
                        while (si > 0) {
                            si -= 1;
                            const included = cls.module.included_modules.items[si];
                            if (included.constants.get(name_sym)) |entry| {
                                try self.warnDeprecatedConstant(included, name_sym);
                                try self.push(entry.value);
                                return;
                            }
                        }
                    }
                }

                switch (try self.triggerAutoload(module, name_sym)) {
                    .missing, .attempted => {},
                    .loaded => |const_val| {
                        try self.push(const_val);
                        return;
                    },
                }
                const msg = std.fmt.allocPrint(
                    self.gc_allocator,
                    "uninitialized constant {s}::{s}",
                    .{ module.name.name, constant.string },
                ) catch return error.Fatal;
                const exc = try self.createException(self.name_error_class, msg);
                self.setPendingException(exc);
                return error.Unwind;
            },

            .PUSH_SELF => {
                try self.push(frame.self_value);
            },

            .JUMP => {
                const offset = readI16From(frame, operands, &operand_cursor);
                try setFrameIp(frame, @intCast(@as(i32, @intCast(frame.ip)) + offset));
            },

            .JUMP_IF_FALSE => {
                const offset = readI16From(frame, operands, &operand_cursor);
                const cond = self.pop();

                if (!cond.is_truthy()) {
                    try setFrameIp(frame, @intCast(@as(i32, @intCast(frame.ip)) + offset));
                }
            },

            .JUMP_IF_TRUE => {
                const offset = readI16From(frame, operands, &operand_cursor);
                const cond = self.pop();

                if (cond.is_truthy()) {
                    try setFrameIp(frame, @intCast(@as(i32, @intCast(frame.ip)) + offset));
                }
            },

            .JUMP_IF_NIL => {
                const offset = readI16From(frame, operands, &operand_cursor);
                const cond = self.pop();

                if (cond.isNil()) {
                    try setFrameIp(frame, @intCast(@as(i32, @intCast(frame.ip)) + offset));
                }
            },

            .POP => {
                _ = self.pop();
            },

            .DUP => {
                const top = self.peek(0);
                try self.push(top);
            },

            .DUP_N => {
                const count = readByteFrom(frame, operands, &operand_cursor);
                if (count > 0) {
                    if (self.stack.items.len < count) {
                        return error.Fatal;
                    }

                    const base = self.stack.items.len - count;
                    var i: usize = 0;
                    while (i < count) : (i += 1) {
                        const v = self.stack.items[base + i];
                        try self.push(v);
                    }
                }
            },

            .SETN => {
                const depth = readByteFrom(frame, operands, &operand_cursor);
                const len = self.stack.items.len;
                if (len <= depth) {
                    return error.Fatal;
                }

                self.stack.storage[len - 1 - depth] = self.peek(0);
            },

            .SWAP => {
                // Swap top two stack items
                const a = self.pop();
                const b = self.pop();
                try self.push(a);
                try self.push(b);
            },

            .CASE_MATCH => {
                const condition = self.pop();
                const predicate = self.peek(0);
                var args = [_]Value{predicate};
                const result = try self.callMethodByName(condition, "===", args[0..], null);
                try self.push(result);
            },

            .WHEN_SPLAT => {
                const mode = readByteFrom(frame, operands, &operand_cursor);

                const expanded = try self.expandSplatValue(self.pop());
                const elements = expanded.toArrayObject().elements.items;

                var matched = false;
                if (mode == 1) {
                    const predicate = self.peek(0);
                    for (elements) |condition| {
                        var args = [_]Value{predicate};
                        const result = try self.callMethodByName(condition, "===", args[0..], null);
                        if (result.is_truthy()) {
                            matched = true;
                            break;
                        }
                    }
                } else {
                    for (elements) |condition| {
                        if (condition.is_truthy()) {
                            matched = true;
                            break;
                        }
                    }
                }

                try self.push(Value.boolean(matched));
            },

            .OPT_PLUS => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        // Tag-bit add: (a<<1|1) + (b<<1|1) - 1 = ((a+b)<<1|1)
                        // Use signed overflow detection
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        const result, const overflow = @addWithOverflow(a_signed, b_signed);
                        if (overflow == 0) {
                            self.stack.storage[len - 2] = .{ .raw = @bitCast(result -% 1) };
                            self.stack.items = self.stack.storage[0 .. len - 1];
                        } else {
                            try self.executeOptIntegerBinary(.plus);
                        }
                    } else {
                        try self.executeOptIntegerBinary(.plus);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_MINUS => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        // Tag-bit sub: (a<<1|1) - (b<<1|1) + 1 = ((a-b)<<1|1)
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        const result, const overflow = @subWithOverflow(a_signed, b_signed);
                        if (overflow == 0) {
                            self.stack.storage[len - 2] = .{ .raw = @bitCast(result +% 1) };
                            self.stack.items = self.stack.storage[0 .. len - 1];
                        } else {
                            try self.executeOptIntegerBinary(.minus);
                        }
                    } else {
                        try self.executeOptIntegerBinary(.minus);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_MULT => {
                try self.executeOptIntegerBinary(.mult);
            },

            .OPT_DIV => {
                try self.executeOptIntegerBinary(.div);
            },

            .OPT_EQ => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        // Both tagged ints: compare raw values directly
                        self.stack.storage[len - 2] = if (a_raw == b_raw) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        try self.executeOptIntegerBinary(.eq);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_LT => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        // Both tagged ints: signed comparison on raw values works because
                        // tag bit is the same for both, so relative order is preserved
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        self.stack.storage[len - 2] = if (a_signed < b_signed) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        try self.executeOptIntegerBinary(.lt);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_GT => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        self.stack.storage[len - 2] = if (a_signed > b_signed) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        try self.executeOptIntegerBinary(.gt);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_LE => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        self.stack.storage[len - 2] = if (a_signed <= b_signed) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        try self.executeOptIntegerBinary(.le);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .OPT_GE => {
                const stack_items = self.stack.items;
                const len = stack_items.len;
                if (len >= 2) {
                    const a_raw = stack_items[len - 2].raw;
                    const b_raw = stack_items[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        self.stack.storage[len - 2] = if (a_signed >= b_signed) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        try self.executeOptIntegerBinary(.ge);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .CALL => {
                const callsite_byte_offset = instr_idx; // byte offset of the CALL opcode
                // Advance frame.ip past the 6 CALL operand bytes
                frame.ip += 6;
                operand_cursor += 6;
                const call_desc = if (callsite_byte_offset < frame.chunk.callsite_descriptors.items.len and frame.chunk.callsite_descriptors.items[callsite_byte_offset] != null)
                    &frame.chunk.callsite_descriptors.items[callsite_byte_offset].?
                else
                    try self.getOrDecodeCallSiteDescriptor(frame.chunk, callsite_byte_offset);
                const argc = call_desc.argc;
                const call_style: ReceiverCallStyle = bytecode.decodeReceiverCallStyle(call_desc.call_flags);
                const args_array_mode = bytecode.argsArrayMode(call_desc.call_flags);
                const block_chunk_id = call_desc.block_chunk_id;
                const method_name_sym = call_desc.method_sym orelse try self.resolveCallMethodSymbolFromDescriptor(frame.chunk, call_desc);

                const block = if (block_chunk_id == 0)
                    null
                else
                    try self.resolveBlock(block_chunk_id, frame);

                var args_temp: TempValueSlice = .{};
                defer args_temp.deinit(self.allocator);
                var args: []Value = &.{};
                var receiver: Value = undefined;
                if (args_array_mode) {
                    const positional = try self.expandSplatValue(self.pop());
                    const elems = positional.toArrayObject().elements.items;
                    args = try args_temp.copyFrom(self, elems);
                    receiver = self.pop();
                } else {
                    if (self.stack.items.len < argc + 1) {
                        return error.Fatal;
                    }
                    const receiver_index = self.stack.items.len - (argc + 1);
                    receiver = self.stack.items[receiver_index];

                    // Stack-window fast path for chunk methods:
                    // bind arguments directly from caller stack and avoid temporary arg buffers.
                    if (call_style == .implicit_self) {
                        // Inline cache check: avoid calling resolveMethodForCallSite on cache hit
                        const caches = frame.chunk.callsite_caches.items;
                        if (callsite_byte_offset < caches.len) {
                            if (caches[callsite_byte_offset]) |cached| {
                                const dispatch_class = self.getDispatchClass(receiver);
                                if (cached.receiver_class == dispatch_class and
                                    cached.method_name == method_name_sym and
                                    cached.method_state_version == self.method_state_version)
                                {
                                    // Cache hit - use cached method directly
                                    switch (cached.entry.method) {
                                        .chunk => |method_chunk| {
                                            if (try self.maybeCallJittedChunk(method_chunk, receiver, self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)])) |jit_result| {
                                                self.stack.storage[receiver_index] = jit_result;
                                                self.stack.items = self.stack.storage[0 .. receiver_index + 1];
                                                return;
                                            }
                                            if (block == null and method_chunk.is_simple_positional and
                                                argc == method_chunk.arity and
                                                self.frames.items.len < self.frames.capacity)
                                            {
                                                // Ultra-fast path: inline frame + env setup on unified stack.
                                                // Save args BEFORE nil-init (nil-init clobbers the arg slots).
                                                const lc = method_chunk.locals_count;
                                                var saved_args: [32]Value = undefined;
                                                if (argc > 0 and argc <= 32) {
                                                    @memcpy(saved_args[0..argc], self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                                }
                                                const new_locals_base = receiver_index;
                                                const needed = new_locals_base + lc + ENV_DATA_SIZE;
                                                self.stack.items.len = needed;
                                                if (lc > 0) @memset(self.stack.items[new_locals_base .. new_locals_base + lc], Value.nil());
                                                if (argc > 0 and argc <= 32) @memcpy(self.stack.items[new_locals_base .. new_locals_base + argc], saved_args[0..argc]);
                                                // Write env_data
                                                const new_ep: [*]Value = self.stack.items[new_locals_base + lc ..].ptr;
                                                new_ep[0] = encodeEp(frame.ep);
                                                new_ep[1] = try self.frameScopeValue(method_chunk.lexical_scope orelse self.current_lexical_scope, null, null);
                                                new_ep[2] = Value.integer(lc);

                                                self.frames.storage[self.frames.items.len] = CallFrame{
                                                    .chunk = method_chunk,
                                                    .ip = 0,
                                                    .locals_base = new_locals_base,
                                                    .ep = new_ep,
                                                    .stack_base = needed,
                                                    .self_value = receiver,
                                                    .block = null,
                                                    .method_name = cached.method_name.name,
                                                    .super_defining_class = cached.owner_class,
                                                };
                                                self.frames.items = self.frames.storage[0 .. self.frames.items.len + 1];

                                                if (method_chunk.lexical_scope) |scope| {
                                                    self.current_lexical_scope = scope;
                                                }
                                                return;
                                            }
                                            // Non-ultra-fast chunk call with cache hit
                                            {
                                                var call_args_tmp: TempValueSlice = .{};
                                                defer call_args_tmp.deinit(self.allocator);
                                                const call_args = try call_args_tmp.copyFrom(self, self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                                self.stack.shrinkRetainingCapacity(receiver_index);
                                             try self.setupChunkCallFrame(method_chunk, receiver, call_args, .{
                                                 .method_name = cached.method_name.name,
                                                 .super_defining_class = cached.owner_class,
                                                 .block = block,
                                             });
                                            }
                                            return;
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                        // Cache miss: full resolution
                        const resolved = try self.resolveMethodForCallSite(frame, callsite_byte_offset, receiver, method_name_sym);
                        if (resolved) |method| {
                            if (self.isMethodCallable(receiver, method, call_style)) {
                                switch (method.entry.method) {
                                    .chunk => |method_chunk| {
                                        if (try self.maybeCallJittedChunk(method_chunk, receiver, self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)])) |jit_result| {
                                            self.stack.storage[receiver_index] = jit_result;
                                            self.stack.items = self.stack.storage[0 .. receiver_index + 1];
                                            return;
                                        }
                                        {
                                            var call_args_tmp: TempValueSlice = .{};
                                            defer call_args_tmp.deinit(self.allocator);
                                            const call_args = try call_args_tmp.copyFrom(self, self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                            self.stack.shrinkRetainingCapacity(receiver_index);
                                             try self.setupChunkCallFrame(method_chunk, receiver, call_args, .{
                                                 .method_name = method.name.name,
                                                 .super_defining_class = method.owner_class,
                                                 .block = block,
                                             });
                                        }
                                        return;
                                    },
                                    else => {},
                                }
                            }
                        }
                    }

                    args = try args_temp.copyFrom(
                        self,
                        self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)],
                    );
                    self.stack.shrinkRetainingCapacity(receiver_index);
                }

                try self.callMethodHelperForExecuteInstruction(frame, callsite_byte_offset, method_name_sym, call_style, receiver, args, .{ .args_array_mode = args_array_mode, .block = block });
            },

            .CALL_KW => {
                const callsite_byte_offset = instr_idx; // byte offset of the CALL_KW opcode
                // Advance frame.ip past the 9 CALL_KW operand bytes
                frame.ip += 9;
                operand_cursor += 9;
                const call_desc = if (callsite_byte_offset < frame.chunk.callsite_descriptors.items.len and frame.chunk.callsite_descriptors.items[callsite_byte_offset] != null)
                    &frame.chunk.callsite_descriptors.items[callsite_byte_offset].?
                else
                    try self.getOrDecodeCallSiteDescriptor(frame.chunk, callsite_byte_offset);
                const argc = call_desc.argc;
                const kwargc = call_desc.kwargc;
                const call_style: ReceiverCallStyle = bytecode.decodeReceiverCallStyle(call_desc.call_flags);
                const args_array_mode = bytecode.argsArrayMode(call_desc.call_flags);
                const kw_hash_mode = bytecode.kwHashMode(call_desc.call_flags);
                const kw_metadata_idx = call_desc.kw_metadata_idx;
                const block_chunk_id = call_desc.block_chunk_id;
                const method_name_sym = call_desc.method_sym orelse try self.resolveCallMethodSymbolFromDescriptor(frame.chunk, call_desc);

                const block = if (block_chunk_id == 0)
                    null
                else
                    try self.resolveBlock(block_chunk_id, frame);

                // Pop keyword values
                var kw_pairs_temp: TempKeywordPairs = .{};
                defer kw_pairs_temp.deinit(self.allocator);
                var i: usize = 0;
                var kw_key_slice: ?[]Value = null;
                var kw_value_slice: ?[]Value = null;

                var args_temp: TempValueSlice = .{};
                defer args_temp.deinit(self.allocator);
                var args: []Value = &.{};
                var receiver: Value = undefined;
                if (args_array_mode) {
                    if (kw_hash_mode) {
                        const kw_hash = self.pop();
                        try kw_pairs_temp.initFromHash(self, kw_hash);
                        kw_key_slice = kw_pairs_temp.keys.slice;
                        kw_value_slice = kw_pairs_temp.values.slice;
                    } else {
                        try kw_pairs_temp.initUninitialized(self, kwargc);
                        kw_key_slice = kw_pairs_temp.keys.slice;
                        kw_value_slice = kw_pairs_temp.values.slice;
                        i = kwargc;
                        while (i > 0) {
                            i -= 1;
                            kw_value_slice.?[i] = self.pop();
                        }
                        if (kwargc > 0) {
                            const kw_metadata = frame.chunk.keyword_metadata.items[kw_metadata_idx];
                            for (0..kwargc) |idx| {
                                const name_idx = kw_metadata.names.items[idx];
                                const key_name = switch (frame.chunk.constants.items[name_idx]) {
                                    .string => |s| s,
                                    .symbol => |sym| sym.name,
                                    else => return error.Fatal,
                                };
                                const key_sym = try self.intern(key_name);
                                kw_key_slice.?[idx] = Value.fromObject(&key_sym.object);
                            }
                        }
                    }
                    const positional = self.pop();
                    const elems = (try self.expandSplatValue(positional)).toArrayObject().elements.items;
                    args = try args_temp.copyFrom(self, elems);
                    receiver = self.pop();
                } else {
                    const stack_kw_items: usize = if (kw_hash_mode) 1 else kwargc;
                    if (self.stack.items.len < argc + stack_kw_items + 1) {
                        return error.Fatal;
                    }
                    const receiver_index = self.stack.items.len - (argc + stack_kw_items + 1);
                    receiver = self.stack.items[receiver_index];

                    args = try args_temp.copyFrom(
                        self,
                        self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)],
                    );
                    if (kw_hash_mode) {
                        const kw_hash = self.stack.items[receiver_index + 1 + argc];
                        try kw_pairs_temp.initFromHash(self, kw_hash);
                        kw_key_slice = kw_pairs_temp.keys.slice;
                        kw_value_slice = kw_pairs_temp.values.slice;
                    } else if (kwargc > 0) {
                        try kw_pairs_temp.initUninitialized(self, kwargc);
                        kw_key_slice = kw_pairs_temp.keys.slice;
                        kw_value_slice = kw_pairs_temp.values.slice;
                        @memcpy(
                            kw_value_slice.?,
                            self.stack.items[(receiver_index + 1 + argc)..(receiver_index + 1 + argc + kwargc)],
                        );
                        const kw_metadata = frame.chunk.keyword_metadata.items[kw_metadata_idx];
                        for (0..kwargc) |idx| {
                            const name_idx = kw_metadata.names.items[idx];
                            const key_name = switch (frame.chunk.constants.items[name_idx]) {
                                .string => |s| s,
                                .symbol => |sym| sym.name,
                                else => return error.Fatal,
                            };
                            const key_sym = try self.intern(key_name);
                            kw_key_slice.?[idx] = Value.fromObject(&key_sym.object);
                        }
                    }
                    self.stack.shrinkRetainingCapacity(receiver_index);
                }

                // Call method with keywords
                try self.callMethodHelperForExecuteInstruction(frame, callsite_byte_offset, method_name_sym, call_style, receiver, args, .{ .args_array_mode = args_array_mode, .kw_keys = kw_key_slice, .kw_values = kw_value_slice, .block = block });
            },

            .FORWARD_ARGS_CALL => {
                const method_idx = readU16From(frame, operands, &operand_cursor);
                const call_flags = readByteFrom(frame, operands, &operand_cursor);
                const block_chunk_id = readU16From(frame, operands, &operand_cursor);
                const call_style: ReceiverCallStyle = bytecode.decodeReceiverCallStyle(call_flags);

                var block = try self.resolveBlock(block_chunk_id, frame);
                if (block == null) {
                    block = frame.block;
                }

                var fwd_buf: [256]Value = undefined;
                const fwd_args = self.getForwardingArguments(frame, &fwd_buf);
                const fwd_kw_ctx = try self.buildForwardingKeywordContext(frame);
                const kw_keys: ?[]Value = if (fwd_kw_ctx) |ctx|
                    if (ctx.kw_values.len > 0) @constCast(ctx.kw_keys) else null
                else
                    null;
                const kw_values: ?[]Value = if (fwd_kw_ctx) |ctx|
                    if (ctx.kw_values.len > 0) @constCast(ctx.kw_values) else null
                else
                    null;

                const method_name = switch (frame.chunk.constants.items[method_idx]) {
                    .string => |s| s,
                    .symbol => |sym| sym.name,
                    else => return error.Fatal,
                };
                const method_name_sym = try self.intern(method_name);

                const receiver = self.pop();
                try self.callMethodHelperForExecuteInstruction(frame, instr_idx, method_name_sym, call_style, receiver, fwd_args, .{ .args_array_mode = true, .kw_keys = kw_keys, .kw_values = kw_values, .block = block });
            },

            .FORWARD_ARGS_CALL_WITH_PREFIX => {
                const method_idx = readU16From(frame, operands, &operand_cursor);
                const call_flags = readByteFrom(frame, operands, &operand_cursor);
                const block_chunk_id = readU16From(frame, operands, &operand_cursor);
                const prefix_argc = readByteFrom(frame, operands, &operand_cursor);
                const call_style: ReceiverCallStyle = bytecode.decodeReceiverCallStyle(call_flags);

                var block = try self.resolveBlock(block_chunk_id, frame);
                if (block == null) {
                    block = frame.block;
                }

                var fwd_buf: [256]Value = undefined;
                const fwd_args = self.getForwardingArguments(frame, &fwd_buf);
                const fwd_kw_ctx = try self.buildForwardingKeywordContext(frame);
                const kw_keys: ?[]Value = if (fwd_kw_ctx) |ctx|
                    if (ctx.kw_values.len > 0) @constCast(ctx.kw_keys) else null
                else
                    null;
                const kw_values: ?[]Value = if (fwd_kw_ctx) |ctx|
                    if (ctx.kw_values.len > 0) @constCast(ctx.kw_values) else null
                else
                    null;

                // Read prefix args from stack (above the receiver).
                // Stack layout: [..., receiver, prefix_arg_0, ..., prefix_arg_N-1] (top)
                var combined_buf: [256]Value = undefined;
                const stack_top = self.stack.items.len;
                const receiver_idx = stack_top - prefix_argc - 1;
                for (0..prefix_argc) |i| {
                    combined_buf[i] = self.stack.items[receiver_idx + 1 + i];
                }
                @memcpy(combined_buf[prefix_argc .. prefix_argc + fwd_args.len], fwd_args);
                const combined_args = combined_buf[0 .. prefix_argc + fwd_args.len];

                // Pop prefix args and receiver off the stack.
                self.stack.items = self.stack.storage[0..receiver_idx];

                const method_name = switch (frame.chunk.constants.items[method_idx]) {
                    .string => |s| s,
                    .symbol => |sym| sym.name,
                    else => return error.Fatal,
                };
                const method_name_sym = try self.intern(method_name);

                const receiver = self.stack.storage[receiver_idx];
                try self.callMethodHelperForExecuteInstruction(frame, instr_idx, method_name_sym, call_style, receiver, combined_args, .{ .args_array_mode = true, .kw_keys = kw_keys, .kw_values = kw_values, .block = block });
            },

            .RETURN => {
                const return_mode = readByteFrom(frame, operands, &operand_cursor);
                const current_frame = self.currentFrame();
                const frame_locals_base = current_frame.locals_base;
                const frame_type = current_frame.frame_type;
                const return_target_ep = current_frame.return_target_ep;
                const result = self.pop();
                const frame_idx = self.frames.items.len - 1;
                const top_level_return_with_arg = return_mode == 2;
                const top_level_return_without_arg = return_mode == 3;

                if ((top_level_return_with_arg or top_level_return_without_arg) and frame_idx == 0) {
                    if (top_level_return_with_arg) {
                        try warning_builtin.writeWarning(self, "warning: argument of top-level return is ignored\n");
                    }
                    self.stack.shrinkRetainingCapacity(frame_locals_base);
                    self.frames.items = self.frames.storage[0..0];
                    try self.push(Value.nil());
                    return;
                }

                // Fast path: implicit return or explicit return from method/lambda
                if (return_mode == 0 or (frame_type != .fiber and frame_type != .proc)) {
                    self.stack.shrinkRetainingCapacity(frame_locals_base);
                    // Inline fast popFrame: just decrement frame length
                    const new_frame_len = self.frames.items.len - 1;
                    self.frames.items = self.frames.storage[0..new_frame_len];
                    // Restore lexical scope from previous frame
                    if (new_frame_len > 0) {
                        self.current_lexical_scope = epLexScope(self.frames.storage[new_frame_len - 1].ep);
                    }
                    try self.push(result);
                } else {
                    try self.startNonLocalReturn(frame_type, return_target_ep, result);
                }
            },

            .DEF_MODULE => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const body_chunk_id = readU16From(frame, operands, &operand_cursor);

                const constant = constants[name_idx];
                if (constant == .string) {
                    const target = try self.resolveDefinitionTarget(epLexScope(frame.ep), constant.string);

                    const module_val = blk: {
                        if (target.existing_value) |em| {
                            if (em.isModule()) break :blk em;
                            const exc = try self.createException(self.type_error_class, "constant is not a module");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }

                        const fresh_module = try self.newModule(target.name_sym);
                        target.owner_module.constants.put(target.name_sym, .{ .value = fresh_module }) catch return error.Fatal;
                        break :blk fresh_module;
                    };

                    // Execute module body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.child_chunks.get(body_chunk_id)) |body_chunk_ptr| {
                            // Create new lexical scope for this module
                            body_chunk_ptr.lexical_scope = try self.createLexicalScope(module_val, self.current_lexical_scope);

                            // Call the body chunk with the module as self
                            // pushFrame will update current_lexical_scope
                            try self.pushFrame(body_chunk_ptr, module_val, null);
                        } else {
                            return error.Fatal;
                        }
                    } else {
                        try self.push(module_val);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .DEF_CLASS => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const body_chunk_id = readU16From(frame, operands, &operand_cursor);

                // Pop superclass (or nil)
                const superclass_val = self.pop();

                var superclass: *value.ClassObject = self.object_class;
                if (superclass_val.isClass()) {
                    superclass = superclass_val.toClassObject();
                } else if (!superclass_val.isNil()) {
                    const exc = try self.createException(self.type_error_class, "superclass must be a Class");
                    self.setPendingException(exc);
                    return error.Unwind;
                }

                const constant = constants[name_idx];
                if (constant == .string) {
                    const target = try self.resolveDefinitionTarget(epLexScope(frame.ep), constant.string);

                    var class_val: Value = undefined;
                    if (target.existing_value) |ec| {
                        if (ec.isClass()) {
                            // Reopen existing class
                            class_val = ec;
                        } else {
                            // Name exists but isn't a class - error
                            const exc = try self.createException(self.type_error_class, "constant is not a class");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                    } else {
                        // Create new class
                        class_val = try self.newClass(target.name_sym, superclass);
                        target.owner_module.constants.put(target.name_sym, .{ .value = class_val }) catch return error.Fatal;
                    }

                    // Execute class body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.child_chunks.get(body_chunk_id)) |body_chunk_ptr| {
                            // Create new lexical scope for this class
                            body_chunk_ptr.lexical_scope = try self.createLexicalScope(class_val, self.current_lexical_scope);

                            // Call the body chunk with the class as self
                            // pushFrame will update current_lexical_scope
                            try self.pushFrame(body_chunk_ptr, class_val, null);
                        } else {
                            return error.Fatal;
                        }
                    } else {
                        try self.push(class_val);
                    }
                } else {
                    return error.Fatal;
                }
            },

            .DEF_SINGLETON_CLASS => {
                const body_chunk_id = readU16From(frame, operands, &operand_cursor);
                const receiver = self.pop();

                const singleton_val = if (receiver.isNil())
                    Value.fromObject(&self.nil_class.module.object)
                else if (receiver.isBool())
                    Value.fromObject(&(if (receiver.toBool()) self.true_class else self.false_class).module.object)
                else if (receiver.isInteger() or receiver.isFloat() or receiver.isSymbol())
                    return self.raiseExceptionFmt(self.type_error_class, "can't define singleton", .{})
                else blk: {
                    const singleton_class = try self.getOrCreateSingletonClass(receiver);
                    break :blk Value.fromObject(&singleton_class.module.object);
                };

                if (body_chunk_id != 0) {
                    if (self.program.child_chunks.get(body_chunk_id)) |body_chunk_ptr| {
                        body_chunk_ptr.lexical_scope = try self.createLexicalScope(singleton_val, self.current_lexical_scope);
                        try self.pushFrame(body_chunk_ptr, singleton_val, null);
                    } else {
                        return error.Fatal;
                    }
                } else {
                    try self.push(Value.nil());
                }
            },

            .DEF_METHOD => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const chunk_idx = readU16From(frame, operands, &operand_cursor);

                const constant = constants[name_idx];
                if (constant != .string) {
                    return error.Fatal;
                }

                const method_name = constant.string;
                const method_name_sym = try self.intern(method_name);

                // Look up the chunk by ID
                if (self.program.child_chunks.get(chunk_idx)) |chunk_ptr| {
                    // Capture the current lexical scope for this method
                    chunk_ptr.lexical_scope = self.current_lexical_scope;
                    const module_function_mode = if (self.current_lexical_scope) |scope| scope.module_function_mode else false;
                    const visibility: MethodVisibility = if (module_function_mode) .private else self.currentDefaultMethodVisibility();

                    // Get current self from the frame
                    const method_owner = if (epMethodDefinitionTarget(frame.ep)) |target|
                        if (target.getModuleMethods()) |_|
                            target
                        else if (target.isInteger() or target.isBigInteger() or target.isFloat() or target.isSymbol())
                            return self.raiseExceptionFmt(self.type_error_class, "can't define singleton method for literals", .{})
                        else
                            Value.fromObject(&(try self.getOrCreateSingletonClass(target)).module.object)
                    else if (self.current_lexical_scope) |scope|
                        switch (scope.scope_module) {
                            .module => |module_obj| Value.fromObject(&module_obj.object),
                            .class => |class_obj| Value.fromObject(&class_obj.module.object),
                        }
                    else
                        frame.self_value;
                    const methods = method_owner.getModuleMethods() orelse unreachable;
                    const entry: MethodEntry = .{
                        .method = .{ .chunk = chunk_ptr },
                        .visibility = visibility,
                    };
                    methods.put(method_name_sym, entry) catch return error.Fatal;
                    self.markIntegerChangedForReceiver(method_owner);
                    self.bumpMethodStateVersion();

                    // module_function mode (set by Module#module_function with no args)
                    // also creates a public singleton method copy on the defining module.
                    if (module_function_mode and method_owner.isModule()) {
                        const singleton_class = try self.getOrCreateSingletonClass(method_owner);
                        var singleton_entry = entry;
                        singleton_entry.visibility = .public;
                        singleton_class.module.methods.put(method_name_sym, singleton_entry) catch return error.Fatal;
                        self.markIntegerChangedForReceiver(Value.fromObject(&singleton_class.module.object));
                        self.bumpMethodStateVersion();
                    }
                } else {
                    std.debug.print("Error: undefined chunk {d}\n", .{chunk_idx});
                    return error.Fatal;
                }
            },

            .DEF_SINGLETON_METHOD => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const chunk_idx = readU16From(frame, operands, &operand_cursor);

                const constant = constants[name_idx];
                if (constant != .string) {
                    return error.Fatal;
                }

                const method_name = constant.string;
                const method_name_sym = try self.intern(method_name);

                if (self.program.child_chunks.get(chunk_idx)) |chunk_ptr| {
                    chunk_ptr.lexical_scope = self.current_lexical_scope;

                    // Pop the receiver from stack (compiled by compileMethod)
                    const receiver = self.pop();

                    // Get or create singleton class for the receiver
                    const singleton_class = try self.getOrCreateSingletonClass(receiver);

                    // Store method on singleton class
                    singleton_class.module.methods.put(method_name_sym, .{
                        .method = .{ .chunk = chunk_ptr },
                        .visibility = .public,
                    }) catch return error.Fatal;
                    self.markIntegerChangedForReceiver(receiver);
                    self.bumpMethodStateVersion();
                } else {
                    return error.Fatal;
                }
            },

            .PUSH_ARRAY => {
                const element_count = readU16From(frame, operands, &operand_cursor);

                const array_obj = try self.createArray();
                if (self.stack.items.len < element_count) return error.Fatal;
                array_obj.elements.ensureTotalCapacity(self.gc_allocator, element_count) catch return error.Fatal;
                array_obj.elements.items.len = element_count;

                var dst = element_count;
                while (dst > 0) {
                    dst -= 1;
                    array_obj.elements.items[dst] = self.pop();
                }

                try self.push(Value.fromObject(&array_obj.object));
            },

            .ARRAY_APPEND => {
                const value_to_append = self.pop();
                const array_val = self.pop();
                if (!array_val.isArray()) {
                    const exc = try self.createException(self.type_error_class, "internal error: ARRAY_APPEND target is not an Array");
                    self.setPendingException(exc);
                    return error.Unwind;
                }
                array_val.toArrayObject().elements.append(self.gc_allocator, value_to_append) catch return error.Fatal;
                try self.push(array_val);
            },

            .ARRAY_CONCAT_ARRAY => {
                const other = self.pop();
                const array_val = self.pop();
                if (!array_val.isArray()) {
                    const exc = try self.createException(self.type_error_class, "internal error: ARRAY_CONCAT_ARRAY target is not an Array");
                    self.setPendingException(exc);
                    return error.Unwind;
                }
                const other_array = try self.expandSplatValue(other);
                for (other_array.toArrayObject().elements.items) |elem| {
                    array_val.toArrayObject().elements.append(self.gc_allocator, elem) catch return error.Fatal;
                }
                try self.push(array_val);
            },

            .PUSH_HASH => {
                const pair_count = readU16From(frame, operands, &operand_cursor);

                const hash_obj = try self.createHash();
                const needed: usize = pair_count * 2;
                if (self.stack.items.len < needed) return error.Fatal;
                const start = self.stack.items.len - needed;
                const pairs = self.stack.items[start..];

                var i: usize = 0;
                while (i < pair_count) : (i += 1) {
                    const key = pairs[i * 2];
                    const val = pairs[i * 2 + 1];
                    try self.hashSetEntry(hash_obj, key, val);
                }
                self.stack.items.len = start;

                try self.push(Value.fromObject(&hash_obj.object));
            },

            .HASH_SET_CONST_KEY => {
                const key_name_idx = readU16From(frame, operands, &operand_cursor);
                if (self.stack.items.len < 2) return error.Fatal;

                const value_to_set = self.pop();
                const target_hash_val = self.peek(0);
                if (!target_hash_val.isHash()) {
                    const exc = try self.createException(self.type_error_class, "internal error: HASH_SET_CONST_KEY target is not a Hash");
                    self.setPendingException(exc);
                    return error.Unwind;
                }

                if (key_name_idx >= frame.chunk.constants.items.len) return error.Fatal;
                const key_name = switch (frame.chunk.constants.items[key_name_idx]) {
                    .string => |s| s,
                    .symbol => |sym| sym.name,
                    else => return error.Fatal,
                };
                const key_sym = try self.intern(key_name);
                try self.hashSetEntry(target_hash_val.toHashObject(), Value.fromObject(&key_sym.object), value_to_set);
            },

            .HASH_MERGE_KW => {
                if (self.stack.items.len < 2) return error.Fatal;
                const source_val = self.pop();
                const target_hash_val = self.peek(0);
                if (!target_hash_val.isHash()) {
                    const exc = try self.createException(self.type_error_class, "internal error: HASH_MERGE_KW target is not a Hash");
                    self.setPendingException(exc);
                    return error.Unwind;
                }

                try self.mergeKwSplatInto(target_hash_val.toHashObject(), source_val);
            },

            .PUSH_RANGE => {
                const exclude_end_flag = readByteFrom(frame, operands, &operand_cursor);
                const end_val = self.pop();
                const begin_val = self.pop();

                if (!begin_val.isNil() and !end_val.isNil()) {
                    var cmp_args = [_]Value{end_val};
                    const comparable = try self.callMethodByName(begin_val, "<=>", cmp_args[0..], null);
                    if (comparable.isNil()) {
                        const exc = try self.createException(self.argument_error_class, "bad value for range");
                        self.setPendingException(exc);
                        return error.Unwind;
                    }
                }

                const range_val = try self.newRange(self.range_class);
                const range_obj = range_val.toRangeObject();
                range_obj.begin = begin_val;
                range_obj.end = end_val;
                range_obj.exclude_end = exclude_end_flag != 0;

                try self.push(range_val);
            },

            .INTERPOLATE_STRING => {
                const part_count = readByteFrom(frame, operands, &operand_cursor);

                if (self.stack.items.len < part_count) return error.Fatal;
                const start = self.stack.items.len - part_count;
                var out: std.ArrayList(u8) = .empty;
                defer out.deinit(self.allocator);
                var result_encoding: enc.Encoding = .{ .ascii_8bit = .{} };
                var i: usize = 0;
                while (i < part_count) : (i += 1) {
                    const val = self.stack.items[start + i];
                    const str_val = self.callMethodByName(val, "to_s", &[_]Value{}, null) catch |err| {
                        if (err == error.Unwind and self.pendingException() != null) {
                            return error.Unwind;
                        }
                        return err;
                    };
                    if (!str_val.isString()) {
                        const exc = try self.createException(self.type_error_class, "to_s did not return String");
                        self.setPendingException(exc);
                        return error.Unwind;
                    }
                    const str_obj = str_val.toStringObject();
                    result_encoding = resolveInterpolatedStringEncoding(result_encoding, out.items, str_obj.encoding, str_obj.str) orelse {
                        return self.raiseEncodingCompatibilityError(result_encoding, str_obj.encoding);
                    };
                    out.appendSlice(self.allocator, str_obj.str) catch return error.Fatal;
                }
                self.stack.items.len = start;

                const final_str = out.toOwnedSlice(self.allocator) catch return error.Fatal;
                defer self.allocator.free(final_str);
                try self.push(try self.newStringWithEncoding(final_str, false, result_encoding));
            },

            .HALT => {
                // HALT behaves like an implicit RETURN: shrink stack to
                // locals_base, push the last expression value (or nil),
                // and pop the frame.
                const halt_frame = self.currentFrame();
                const halt_locals_base = halt_frame.locals_base;
                const halt_result = if (self.stack.items.len > halt_frame.stack_base)
                    self.pop()
                else
                    Value.nil();
                self.stack.shrinkRetainingCapacity(halt_locals_base);
                const new_frame_len = self.frames.items.len - 1;
                self.frames.items = self.frames.storage[0..new_frame_len];
                if (new_frame_len > 0) {
                    self.current_lexical_scope = epLexScope(self.frames.storage[new_frame_len - 1].ep);
                }
                try self.push(halt_result);
            },

            .YIELD => {
                const argc = readByteFrom(frame, operands, &operand_cursor);

                // Pop arguments
                var yield_args: [256]Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    yield_args[argc - 1 - i] = self.pop();
                }

                // Check for block
                const block = frame.block orelse {
                    const exc = try self.createException(
                        self.argument_error_class,
                        "no block given",
                    );
                    self.setPendingException(exc);
                    return error.Unwind;
                };
                switch (block.kind) {
                    .chunk => |chunk_blk| {
                        // De-recursed: push block frame inline, return to dispatch loop
                        const ft: CallFrame.FrameType = if (chunk_blk.chunk.is_lambda) .lambda else .proc;
                        const break_target_frame_idx = if (self.frames.items.len > 0) self.frames.items.len - 1 else null;
                        const next_target_frame_idx = self.frames.items.len;
                        try self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, ft, .{
                            .block = if (chunk_blk.enclosing_block_proc) |proc_obj| proc_obj.block else null,
                            .return_target_ep = chunk_blk.return_target_ep,
                            .break_target_frame_idx = break_target_frame_idx,
                            .next_target_frame_idx = next_target_frame_idx,
                        });

                        const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                        const block_frame = self.currentFrame();
                        try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, yield_args[0..argc], arity_mode);
                    },
                    .receiver_builtin => |builtin_data| {
                        const result = try builtin_data.func(self, builtin_data.receiver, yield_args[0..argc]);
                        try self.push(result);
                    },
                    .symbol => |sym| {
                        const result = try self.invokeSymbolProc(sym, yield_args[0..argc], null);
                        try self.push(result);
                    },
                    .builtin => |func| {
                        const result = try func(self, yield_args[0..argc]);
                        try self.push(result);
                    },
                    .callable => |callable| {
                        const result = try self.callMethodByName(callable, "call", yield_args[0..argc], null);
                        try self.push(result);
                    },
                }
            },

            .YIELD_SPLAT => {
                const args_array_val = try self.expandSplatValue(self.pop());

                const block = frame.block orelse {
                    const exc = try self.createException(
                        self.argument_error_class,
                        "no block given",
                    );
                    self.setPendingException(exc);
                    return error.Unwind;
                };

                const splat_args = args_array_val.toArrayObject().elements.items;
                switch (block.kind) {
                    .chunk => |chunk_blk| {
                        // De-recursed: push block frame inline, return to dispatch loop
                        const ft: CallFrame.FrameType = if (chunk_blk.chunk.is_lambda) .lambda else .proc;
                        const break_target_frame_idx = if (self.frames.items.len > 0) self.frames.items.len - 1 else null;
                        const next_target_frame_idx = self.frames.items.len;
                        try self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, ft, .{
                            .block = if (chunk_blk.enclosing_block_proc) |proc_obj| proc_obj.block else null,
                            .return_target_ep = chunk_blk.return_target_ep,
                            .break_target_frame_idx = break_target_frame_idx,
                            .next_target_frame_idx = next_target_frame_idx,
                        });

                        const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                        const block_frame = self.currentFrame();
                        try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, splat_args, arity_mode);
                    },
                    .receiver_builtin => |builtin_data| {
                        const result = try builtin_data.func(self, builtin_data.receiver, @constCast(splat_args));
                        try self.push(result);
                    },
                    .symbol => |sym| {
                        const result = try self.invokeSymbolProc(sym, splat_args, null);
                        try self.push(result);
                    },
                    .builtin => |func| {
                        const result = try func(self, @constCast(splat_args));
                        try self.push(result);
                    },
                    .callable => |callable| {
                        const result = try self.callMethodByName(callable, "call", @constCast(splat_args), null);
                        try self.push(result);
                    },
                }
            },

            .PUSH_LAMBDA => {
                const chunk_id = readU16From(frame, operands, &operand_cursor);
                const lambda_chunk = self.program.child_chunks.get(chunk_id) orelse unreachable;

                // Create a block with the lambda chunk and current environment
                const block = Block{
                    .kind = .{ .chunk = .{
                        .chunk = lambda_chunk,
                        .defining_ep = frame.ep,
                        .defining_self = frame.self_value,
                        .return_target_ep = self.currentNonLocalReturnTarget(),
                        .enclosing_block_proc = if (frame.block) |blk| try self.ensureBlockProc(blk) else null,
                    } },
                };

                // Create a Proc value from the block
                const proc_val = try self.newProc(block);
                try self.push(proc_val);
            },

            .PUSH_REGEXP => {
                const pattern_idx = readU16From(frame, operands, &operand_cursor);
                const options = readU16From(frame, operands, &operand_cursor);
                const pattern_constant = constants[pattern_idx];
                const pattern: []const u8 = switch (pattern_constant) {
                    .string => |bytes| bytes,
                    .encoded_string => |encoded| encoded.bytes,
                    else => return error.Fatal,
                };
                const source_encoding: enc.Encoding = switch (pattern_constant) {
                    .string => frame.chunk.source_encoding,
                    .encoded_string => |encoded| encoded.encoding,
                    else => return error.Fatal,
                };
                const normalized = self.normalizeRegexpEncoding(pattern, source_encoding, options);
                const result = try self.newRegexpWithEncoding(pattern, normalized.options, normalized.encoding);
                try self.push(result);
            },

            .ALIAS_METHOD => {
                const new_name_idx = readU16From(frame, operands, &operand_cursor);
                const old_name_idx = readU16From(frame, operands, &operand_cursor);

                const new_name = constants[new_name_idx].string;
                const old_name = constants[old_name_idx].string;

                const new_name_sym = try self.intern(new_name);
                const old_name_sym = try self.intern(old_name);

                const current_self = frame.self_value;
                const methods = current_self.getModuleMethods() orelse &self.object_class.module.methods;

                const entry = if (current_self.isClass()) blk: {
                    const resolved = self.lookupMethodDetailed(current_self.toClassObject(), old_name_sym);
                    break :blk switch (resolved) {
                        .found => |found| found.entry,
                        else => null,
                    };
                } else if (current_self.isModule()) blk: {
                    const resolved = self.lookupModuleMethodDetailed(self.object_class, current_self.toModuleObject(), old_name_sym);
                    break :blk switch (resolved) {
                        .found => |found| found.entry,
                        else => null,
                    };
                } else methods.get(old_name_sym);

                if (entry) |resolved_entry| {
                    methods.put(new_name_sym, resolved_entry) catch return error.Fatal;
                    self.markIntegerChangedForReceiver(current_self);
                    self.bumpMethodStateVersion();
                } else {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "undefined method '{s}'",
                        .{old_name},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.setPendingException(exc);
                    return error.Unwind;
                }

                // alias returns nil in Ruby
                try self.push(Value.NIL);
            },

            .UNDEF_METHOD => {
                const argc = operands[operand_cursor];
                operand_cursor += 1;

                var args: [256]Value = undefined;
                var i: usize = argc;
                while (i > 0) {
                    i -= 1;
                    args[i] = self.pop();
                }

                const current_self = frame.self_value;
                const methods = current_self.getModuleMethods() orelse &self.object_class.module.methods;
                const target_is_class = current_self.isClass();
                const target_is_module = current_self.isModule();

                for (args[0..argc]) |arg| {
                    const name_sym = try self.coerceToMethodNameSymbol(arg);
                    const exists = if (target_is_class)
                        self.lookupMethod(current_self.toClassObject(), name_sym) != null
                    else if (target_is_module) blk: {
                        const entry = methods.get(name_sym) orelse break :blk false;
                        break :blk entry.method != .undefined;
                    } else self.lookupMethod(self.object_class, name_sym) != null;

                    if (!exists) {
                        const msg = std.fmt.allocPrint(
                            self.gc_allocator,
                            "undefined method '{s}'",
                            .{name_sym.name},
                        ) catch return error.Fatal;
                        const exc = try self.createException(self.name_error_class, msg);
                        self.setPendingException(exc);
                        return error.Unwind;
                    }

                    methods.put(name_sym, .{ .method = .{ .undefined = {} } }) catch return error.Fatal;
                }

                self.markIntegerChangedForReceiver(current_self);
                self.bumpMethodStateVersion();
                try self.push(Value.NIL);
            },

            .MULTI_ASSIGN_PREPARE => {
                const receiver = self.pop();

                switch (try self.probeToAry(receiver)) {
                    .array => |array| {
                        try self.push(array);
                    },
                    .missing, .nil_result => {
                        const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
                        array_obj.* = .{
                            .object = .{ .type_tag = .array, .flags = 0, .class = self.array_class, .singleton_class = null, .instance_variables = null },
                            .elements = .empty,
                        };
                        array_obj.elements.append(self.gc_allocator, receiver) catch return error.Fatal;
                        try self.push(Value.fromObject(&array_obj.object));
                    },
                }
            },

            .BREAK => {
                const result = self.pop();
                const current_frame = self.currentFrame();
                if (current_frame.frame_type == .lambda) {
                    self.stack.shrinkRetainingCapacity(current_frame.locals_base);
                    const new_frame_len = self.frames.items.len - 1;
                    self.frames.items = self.frames.storage[0..new_frame_len];
                    if (new_frame_len > 0) {
                        self.current_lexical_scope = epLexScope(self.frames.storage[new_frame_len - 1].ep);
                    }
                    try self.push(result);
                    return;
                }

                const target_frame_idx = current_frame.break_target_frame_idx orelse {
                    const exc = try self.createException(self.local_jump_error_class, "unexpected break");
                    self.setPendingException(exc);
                    return error.Unwind;
                };
                self.setPendingControlFlow(.{
                    .kind = .break_,
                    .value = result,
                    .target_frame_idx = target_frame_idx,
                });
                return error.Unwind;
            },

            .NEXT => {
                const result = self.pop();
                const current_frame = self.currentFrame();
                const target_frame_idx = current_frame.next_target_frame_idx orelse self.frames.items.len - 1;
                self.setPendingControlFlow(.{
                    .kind = .next_,
                    .value = result,
                    .target_frame_idx = target_frame_idx,
                });
                return error.Unwind;
            },

            .REDO => {
                const target_ip = readU16From(frame, operands, &operand_cursor);
                self.setPendingControlFlow(.{
                    .kind = .redo_,
                    .value = Value.nil(),
                    .target_frame_idx = self.frames.items.len - 1,
                    .target_ip = target_ip,
                });
                return error.Unwind;
            },

            .RAISE => {
                const argc = readByteFrom(frame, operands, &operand_cursor);
                if (argc > 2) {
                    var discard_count: u8 = 0;
                    while (discard_count < argc) : (discard_count += 1) {
                        _ = self.pop();
                    }
                    return self.raiseArgumentErrorWrongArgCountGeneric();
                }
                var raise_args: [2]Value = undefined;
                var i: usize = argc;
                while (i > 0) {
                    i -= 1;
                    raise_args[i] = self.pop();
                }
                return self.raiseFromArgs(raise_args[0..argc], "no current exception");
            },

            .TRY_BEGIN => {
                // Skip the handler index operand
                _ = readU16From(frame, operands, &operand_cursor);
            },

            .TRY_END => {},

            .CATCH_END => {
                if (frame.active_rescue_exceptions == 0 or self.rescued_exceptions.items.len == 0) return error.Fatal;
                frame.active_rescue_exceptions -= 1;
                _ = self.rescued_exceptions.pop();
            },

            .ENSURE_START => {
                self.ensure_saved_unwinds.append(self.allocator, .{
                    .pending_unwind = self.pending_unwind,
                }) catch return error.Fatal;
            },

            .RETRY => {
                const target_ip = readU16From(frame, operands, &operand_cursor);
                self.setPendingControlFlow(.{
                    .kind = .retry_,
                    .value = Value.nil(),
                    .target_frame_idx = self.frames.items.len - 1,
                    .target_ip = target_ip,
                });
                return error.Unwind;
            },

            .ENSURE_END => {
                // Pop the ensure block's return value (it's ignored)
                _ = self.pop();

                const saved = if (self.ensure_saved_unwinds.items.len > 0)
                    self.ensure_saved_unwinds.pop().?
                else
                    SavedUnwind{};

                if (self.hasPendingUnwind()) {
                    return error.Unwind;
                }

                self.pending_unwind = saved.pending_unwind;
                if (self.hasPendingUnwind()) {
                    return error.Unwind;
                }
            },

            .CATCH_START => {
                // Read variable index (local_idx, not ep_offset; we compute at runtime)
                const var_idx = readByteFrom(frame, operands, &operand_cursor);

                if (self.pendingException()) |exc| {
                    self.rescued_exceptions.append(self.allocator, exc) catch return error.Fatal;
                    frame.active_rescue_exceptions += 1;
                }

                // Store exception in local variable if binding exists (var_idx != 255)
                if (var_idx != 255) {
                    if (self.pendingException()) |exc| {
                        // Compute ep_offset from the chunk's locals_count at runtime
                        const ep_offset = frame.chunk.locals_count - @as(u16, var_idx);
                        (frame.ep - ep_offset)[0] = Value.fromObject(&exc.object);
                    }
                }

                // Clear pending exception - it's now caught
                self.setPendingException(null);
            },

            .SUPER => {
                const argc = readByteFrom(frame, operands, &operand_cursor);
                const flags = readByteFrom(frame, operands, &operand_cursor);
                const args_array_mode = (flags & bytecode.SUPER_FLAG_ARGS_ARRAY) != 0;
                const block_chunk_id = readU16From(frame, operands, &operand_cursor);

                // Resolve block first (may pop from stack for &variable syntax)
                const block = try self.resolveBlock(block_chunk_id, frame);

                var args: [256]Value = undefined;
                var positional_argc: usize = 0;
                if (args_array_mode) {
                    const positional = try self.expandSplatValue(self.pop());
                    const elems = positional.toArrayObject().elements.items;
                    if (elems.len > args.len) {
                        const exc = try self.createException(self.argument_error_class, "too many arguments");
                        self.setPendingException(exc);
                        return error.Unwind;
                    }
                    for (elems, 0..) |elem, idx| {
                        args[idx] = elem;
                    }
                    positional_argc = elems.len;
                } else {
                    var i: usize = 0;
                    while (i < argc) : (i += 1) {
                        args[argc - 1 - i] = self.pop();
                    }
                    positional_argc = argc;
                }

                try self.callSuper(args[0..positional_argc], block);
            },

            .FORWARDING_SUPER => {
                const block_chunk_id = readU16From(frame, operands, &operand_cursor);

                // Resolve block, falling back to frame's block for forwarding
                var block = try self.resolveBlock(block_chunk_id, frame);
                if (block == null) {
                    block = frame.block;
                }

                // Get forwarding positional arguments from current method's environment
                var fwd_buf: [256]Value = undefined;
                const fwd_args = self.getForwardingArguments(frame, &fwd_buf);

                // Build forwarding keyword context from actual param slot values
                // (includes defaults that were applied, not just what was explicitly passed).
                const fwd_kw_ctx = try self.buildForwardingKeywordContext(frame);
                if (fwd_kw_ctx) |ctx| {
                    frame.forwarded_keyword_ctx = ctx;
                }

                try self.callSuper(fwd_args, block);
            },
        }
    }

    /// Execute one instruction via the slow path, handling unwind errors.
    /// When bounded is true, uses bounded unwinding that stops at min_unwind_depth
    /// (returns error.Unwind if no handler found above that depth).
    /// When bounded is false, uses full unwinding.
    inline fn executeInstructionWithUnwind(self: *VM, comptime bounded: bool, min_unwind_depth: usize) VMError!void {
        self.executeInstruction() catch |err| switch (err) {
            error.Unwind => {
                if (bounded) {
                    if (!try self.unwindStackUntilFrameDepth(min_unwind_depth))
                        return error.Unwind;
                } else {
                    try self.unwindStack();
                }
            },
            else => return err,
        };
    }

    /// Top-level fast dispatch loop. Uses inline opcodes for hot paths (locals, arithmetic,
    /// jumps, simple calls/returns) and falls back to executeInstruction() for complex opcodes.
    ///
    /// When bounded is false, unwinds fully on exception (used by run() for top-level).
    /// When bounded is true, uses bounded unwinding that stops at min_unwind_depth and
    /// returns error.Unwind if no handler is found (used by executeChunk/require to avoid
    /// unwinding past the caller's frames).
    ///
    /// The comptime parameter generates two specialized versions so the run() hot path
    /// has zero overhead from the bounded unwinding logic.
    pub fn executeFastLoop(self: *VM, target_len: usize, comptime bounded: bool, min_unwind_depth: usize) VMError!void {
        while (self.frames.items.len >= target_len) {
            if (self.pendingControlFlow()) |cf| {
                if ((cf.kind == .return_ or cf.kind == .next_) and cf.value_placed) {
                    self.setPendingControlFlow(null);
                }
            }
            const frame_len = self.frames.items.len;
            const f = &self.frames.storage[frame_len - 1];
            const code = f.chunk.code.items;
            if (f.ip >= code.len) {
                try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                continue;
            }

            const op: bytecode.OpCode = @enumFromInt(code[f.ip]);
            switch (op) {
                .GET_LOCAL => {
                    // ep_offset is 2 bytes (u16) after the opcode
                    const ep_offset: u16 = @as(u16, code[f.ip + 1]) | (@as(u16, code[f.ip + 2]) << 8);
                    f.ip += 3;
                    const val = (f.ep - ep_offset)[0];
                    const len = self.stack.items.len;
                    self.stack.storage[len] = val;
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .PUSH_I8 => {
                    const val: i8 = @bitCast(code[f.ip + 1]);
                    f.ip += 2;
                    const len = self.stack.items.len;
                    self.stack.storage[len] = Value.integer(@intCast(val));
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .PUSH_SELF => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    self.stack.storage[len] = f.self_value;
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .OPT_PLUS => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    const a_raw = self.stack.storage[len - 2].raw;
                    const b_raw = self.stack.storage[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        const result, const overflow = @addWithOverflow(a_signed, b_signed);
                        if (overflow == 0) {
                            self.stack.storage[len - 2] = .{ .raw = @bitCast(result -% 1) };
                            self.stack.items = self.stack.storage[0 .. len - 1];
                        } else {
                            f.ip -= 1; // back up to re-execute in full handler
                            self.executeInstruction() catch |err| switch (err) {
                                error.Unwind => try self.unwindStack(),
                                else => return err,
                            };
                        }
                    } else {
                        f.ip -= 1;
                        try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                    }
                },
                .OPT_MINUS => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    const a_raw = self.stack.storage[len - 2].raw;
                    const b_raw = self.stack.storage[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        const result, const overflow = @subWithOverflow(a_signed, b_signed);
                        if (overflow == 0) {
                            self.stack.storage[len - 2] = .{ .raw = @bitCast(result +% 1) };
                            self.stack.items = self.stack.storage[0 .. len - 1];
                        } else {
                            f.ip -= 1;
                            self.executeInstruction() catch |err| switch (err) {
                                error.Unwind => try self.unwindStack(),
                                else => return err,
                            };
                        }
                    } else {
                        f.ip -= 1;
                        try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                    }
                },
                .OPT_EQ => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    const a_raw = self.stack.storage[len - 2].raw;
                    const b_raw = self.stack.storage[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        self.stack.storage[len - 2] = if (a_raw == b_raw) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        f.ip -= 1;
                        try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                    }
                },
                .OPT_LT, .OPT_GT, .OPT_LE, .OPT_GE => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    const a_raw = self.stack.storage[len - 2].raw;
                    const b_raw = self.stack.storage[len - 1].raw;
                    if (!self.integer_changed and (a_raw & b_raw & 1) == 1) {
                        const a_signed = @as(i64, @bitCast(a_raw));
                        const b_signed = @as(i64, @bitCast(b_raw));
                        const cmp_result = switch (op) {
                            .OPT_LT => a_signed < b_signed,
                            .OPT_GT => a_signed > b_signed,
                            .OPT_LE => a_signed <= b_signed,
                            .OPT_GE => a_signed >= b_signed,
                            else => unreachable,
                        };
                        self.stack.storage[len - 2] = if (cmp_result) Value.TRUE else Value.FALSE;
                        self.stack.items = self.stack.storage[0 .. len - 1];
                    } else {
                        f.ip -= 1;
                        try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                    }
                },
                .JUMP_IF_FALSE => {
                    const lo: u16 = code[f.ip + 1];
                    const hi: u16 = code[f.ip + 2];
                    const offset: i16 = @bitCast(lo | (hi << 8));
                    f.ip += 3;
                    const len = self.stack.items.len;
                    const cond = self.stack.storage[len - 1];
                    self.stack.items = self.stack.storage[0 .. len - 1];
                    if (!cond.is_truthy()) {
                        f.ip = @intCast(@as(i32, @intCast(f.ip)) + offset);
                    }
                },
                .JUMP_IF_NIL => {
                    const lo: u16 = code[f.ip + 1];
                    const hi: u16 = code[f.ip + 2];
                    const offset: i16 = @bitCast(lo | (hi << 8));
                    f.ip += 3;
                    const len = self.stack.items.len;
                    const cond = self.stack.storage[len - 1];
                    self.stack.items = self.stack.storage[0 .. len - 1];
                    if (cond.isNil()) {
                        f.ip = @intCast(@as(i32, @intCast(f.ip)) + offset);
                    }
                },
                .JUMP => {
                    const lo: u16 = code[f.ip + 1];
                    const hi: u16 = code[f.ip + 2];
                    const offset: i16 = @bitCast(lo | (hi << 8));
                    f.ip += 3;
                    f.ip = @intCast(@as(i32, @intCast(f.ip)) + offset);
                },
                .POP => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    self.stack.items = self.stack.storage[0 .. len - 1];
                },
                .PUSH_NIL => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    self.stack.storage[len] = Value.NIL;
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .PUSH_TRUE => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    self.stack.storage[len] = Value.TRUE;
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .PUSH_FALSE => {
                    f.ip += 1;
                    const len = self.stack.items.len;
                    self.stack.storage[len] = Value.FALSE;
                    self.stack.items = self.stack.storage[0 .. len + 1];
                },
                .RETURN => {
                    const return_mode = code[f.ip + 1];
                    const frame_idx = self.frames.items.len - 1;
                    const top_level_return_with_arg = return_mode == 2;
                    const top_level_return_without_arg = return_mode == 3;
                    if ((top_level_return_with_arg or top_level_return_without_arg) and frame_idx == 0) {
                        _ = self.pop();
                        if (top_level_return_with_arg) {
                            try warning_builtin.writeWarning(self, "warning: argument of top-level return is ignored\n");
                        }
                        self.stack.items = self.stack.storage[0..f.locals_base];
                        self.frames.items = self.frames.storage[0..0];
                        const len = self.stack.items.len;
                        self.stack.storage[len] = Value.NIL;
                        self.stack.items = self.stack.storage[0 .. len + 1];
                    } else if (return_mode == 0 or f.frame_type == .method or f.frame_type == .lambda) {
                        const s_len = self.stack.items.len;
                        const result = self.stack.storage[s_len - 1];
                        self.stack.items = self.stack.storage[0..f.locals_base];
                        // Pop frame
                        const new_frame_len = self.frames.items.len - 1;
                        self.frames.items = self.frames.storage[0..new_frame_len];
                        if (new_frame_len > 0) {
                            self.current_lexical_scope = epLexScope(self.frames.storage[new_frame_len - 1].ep);
                        }
                        const len = self.stack.items.len;
                        self.stack.storage[len] = result;
                        self.stack.items = self.stack.storage[0 .. len + 1];
                    } else {
                        // Complex return (proc, fiber) - fall back
                        try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                    }
                },
                .CALL => {
                    // Fast path for simple chunk method calls (implicit_self, cache hit, simple sig)
                    const callsite_byte_offset = f.ip;
                    f.ip += 7; // opcode(1) + method_idx(2) + argc(1) + flags(1) + block_chunk_id(2)
                    const call_flags = code[callsite_byte_offset + 4];
                    const call_style: ReceiverCallStyle = bytecode.decodeReceiverCallStyle(call_flags);
                    if (call_style == .implicit_self and !bytecode.argsArrayMode(call_flags)) {
                        // Read block_chunk_id
                        const blk_lo: u16 = code[callsite_byte_offset + 5];
                        const blk_hi: u16 = code[callsite_byte_offset + 6];
                        const block_chunk_id: chunk.ChunkId = @intCast(blk_lo | (blk_hi << 8));
                        if (block_chunk_id == 0) {
                            const argc: usize = code[callsite_byte_offset + 3];
                            const caches = f.chunk.callsite_caches.items;
                            if (callsite_byte_offset < caches.len) {
                                if (caches[callsite_byte_offset]) |cached| {
                                    // Get receiver from stack
                                    const s_len = self.stack.items.len;
                                    const receiver_index = s_len - (argc + 1);
                                    const call_receiver = self.stack.items[receiver_index];
                                    const dispatch_class = self.getDispatchClass(call_receiver);
                                    if (cached.receiver_class == dispatch_class and
                                        cached.method_state_version == self.method_state_version)
                                    {
                                        switch (cached.entry.method) {
                                            .chunk => |method_chunk| {
                                                if (try self.maybeCallJittedChunk(method_chunk, call_receiver, self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)])) |jit_result| {
                                                    self.stack.storage[receiver_index] = jit_result;
                                                    self.stack.items = self.stack.storage[0 .. receiver_index + 1];
                                                    try self.checkAsyncEventsWithUnwind(bounded, min_unwind_depth);
                                                    continue;
                                                }
                                                if (method_chunk.is_simple_positional and
                                                    argc == method_chunk.arity and
                                                    self.frames.items.len < self.frames.capacity)
                                                {
                                                    // Ultra-fast inline call on unified stack.
                                                    // Save args BEFORE nil-init (nil-init clobbers the arg slots).
                                                    const lc = method_chunk.locals_count;
                                                    var saved_args: [32]Value = undefined;
                                                    if (argc > 0 and argc <= 32) {
                                                        @memcpy(saved_args[0..argc], self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                                    }
                                                    const new_locals_base = receiver_index;
                                                    const needed = new_locals_base + lc + ENV_DATA_SIZE;
                                                    self.stack.items.len = needed;
                                                    if (lc > 0) @memset(self.stack.items[new_locals_base .. new_locals_base + lc], Value.nil());
                                                    if (argc > 0 and argc <= 32) @memcpy(self.stack.items[new_locals_base .. new_locals_base + argc], saved_args[0..argc]);
                                                    const new_ep: [*]Value = self.stack.items[new_locals_base + lc ..].ptr;
                                                    new_ep[0] = encodeEp(f.ep);
                                                    new_ep[1] = try self.frameScopeValue(method_chunk.lexical_scope orelse self.current_lexical_scope, null, null);
                                                    new_ep[2] = Value.integer(lc);

                                                    const new_fl = self.frames.items.len;
                                                    self.frames.storage[new_fl] = CallFrame{
                                                        .chunk = method_chunk,
                                                        .ip = 0,
                                                        .locals_base = new_locals_base,
                                                        .ep = new_ep,
                                                        .stack_base = needed,
                                                        .self_value = call_receiver,
                                                        .block = null,
                                                    };
                                                    self.frames.items = self.frames.storage[0 .. new_fl + 1];

                                                    if (method_chunk.lexical_scope) |scope| {
                                                        self.current_lexical_scope = scope;
                                                    }
                                                    try self.checkAsyncEventsWithUnwind(bounded, min_unwind_depth);
                                                    continue;
                                                }
                                            },
                                            else => {},
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Fall back to full CALL handler
                    f.ip = callsite_byte_offset; // reset ip
                    try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                },
                else => {
                    // Fall back to full instruction handler for complex opcodes
                    try self.executeInstructionWithUnwind(bounded, min_unwind_depth);
                },
            }

            try self.checkAsyncEventsWithUnwind(bounded, min_unwind_depth);
        }
    }

    fn currentDefaultMethodVisibility(self: *VM) MethodVisibility {
        if (self.current_lexical_scope) |scope| {
            return scope.default_method_visibility;
        }
        return .public;
    }

    pub fn isClassOrSubclassOf(_: *VM, class: *ClassObject, candidate_ancestor: *ClassObject) bool {
        var current: ?*ClassObject = class;
        while (current) |c| {
            if (c == candidate_ancestor) return true;
            current = c.superclass;
        }
        return false;
    }

    fn isMethodCallable(self: *VM, receiver: Value, resolved: ResolvedMethod, call_style: ReceiverCallStyle) bool {
        switch (resolved.entry.visibility) {
            .public => return true,
            .private => return call_style == .implicit_self or
                (self.frames.items.len > 0 and receiver.eql(self.currentFrame().self_value)),
            .protected => {
                if (self.frames.items.len == 0) return false;
                const caller_self = self.currentFrame().self_value;
                const caller_class = self.getClass(caller_self);
                const receiver_class = self.getClass(receiver);
                return self.isClassOrSubclassOf(caller_class, resolved.owner_class) and
                    self.isClassOrSubclassOf(receiver_class, resolved.owner_class);
            },
        }
    }

    /// Find a method on a receiver, checking singleton class first, then regular class
    pub fn findMethod(self: *VM, receiver: Value, method_name_sym: *SymbolObject) VMError!?ResolvedMethod {
        // Ordinary object lookup should not materialize singleton classes just to check for
        // singleton methods. Class/module receivers are the exception because class methods
        // inherit through the eigenclass chain.
        const singleton_class = if (receiver.getSingletonClass()) |existing|
            existing
        else if (receiver.isClass() or receiver.isModule())
            self.getOrCreateSingletonClass(receiver) catch return error.Fatal
        else
            null;

        if (singleton_class) |sc| {
            switch (self.lookupMethodDetailed(sc, method_name_sym)) {
                .found => |resolved| return resolved,
                .undefined => return null,
                .not_found => {},
            }
        }

        // If not found in singleton class, check regular class.
        const class = self.getClass(receiver);
        return switch (self.lookupMethodDetailed(class, method_name_sym)) {
            .found => |resolved| resolved,
            .undefined, .not_found => null,
        };
    }

    fn resolveLookupEntry(
        _: *VM,
        method_name: *SymbolObject,
        owner_class: *ClassObject,
        entry: MethodEntry,
    ) LookupMethodResult {
        return switch (entry.method) {
            .undefined => .undefined,
            else => .{ .found = .{
                .name = method_name,
                .owner_class = owner_class,
                .entry = entry,
            } },
        };
    }

    fn lookupModuleMethodDetailed(
        self: *VM,
        owner_class: *ClassObject,
        module_obj: *value.ModuleObject,
        method_name: *value.SymbolObject,
    ) LookupMethodResult {
        var i = module_obj.prepended_modules.items.len;
        while (i > 0) {
            i -= 1;
            switch (self.lookupModuleMethodDetailed(owner_class, module_obj.prepended_modules.items[i], method_name)) {
                .found => |resolved| return .{ .found = resolved },
                .undefined => return .undefined,
                .not_found => {},
            }
        }

        if (module_obj.methods.get(method_name)) |entry| {
            return self.resolveLookupEntry(method_name, owner_class, entry);
        }

        i = module_obj.included_modules.items.len;
        while (i > 0) {
            i -= 1;
            switch (self.lookupModuleMethodDetailed(owner_class, module_obj.included_modules.items[i], method_name)) {
                .found => |resolved| return .{ .found = resolved },
                .undefined => return .undefined,
                .not_found => {},
            }
        }

        return .not_found;
    }

    pub fn lookupMethodDetailed(self: *VM, class: *ClassObject, method_name: *value.SymbolObject) LookupMethodResult {
        var current_class: ?*ClassObject = class;
        while (current_class) |c| {
            // 1. Check prepended modules first (in reverse order - most recently prepended at highest index is checked first)
            var i = c.module.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.module.prepended_modules.items[i];
                switch (self.lookupModuleMethodDetailed(c, module, method_name)) {
                    .found => |resolved| return .{ .found = resolved },
                    .undefined => return .undefined,
                    .not_found => {},
                }
            }

            // 2. Check class's own methods
            if (c.module.methods.get(method_name)) |entry| {
                return self.resolveLookupEntry(method_name, c, entry);
            }

            // 3. Check included modules (in reverse order - most recently included at highest index is checked first)
            i = c.module.included_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.module.included_modules.items[i];
                switch (self.lookupModuleMethodDetailed(c, module, method_name)) {
                    .found => |resolved| return .{ .found = resolved },
                    .undefined => return .undefined,
                    .not_found => {},
                }
            }

            current_class = c.superclass;
        }

        return .not_found;
    }

    fn noMethodReceiverDescription(self: *VM, receiver: Value) VMError![]const u8 {
        if (receiver.isNil()) return "nil";
        if (receiver.isBool()) return if (receiver.toBool()) "true" else "false";
        if (receiver.isClass()) {
            return std.fmt.allocPrint(
                self.gc_allocator,
                "class {s}",
                .{receiver.toClassObject().module.name.name},
            ) catch return error.Fatal;
        }
        if (receiver.isModule()) {
            return std.fmt.allocPrint(
                self.gc_allocator,
                "module {s}",
                .{receiver.toModuleObject().name.name},
            ) catch return error.Fatal;
        }
        return std.fmt.allocPrint(
            self.gc_allocator,
            "an instance of {s}",
            .{self.className(receiver)},
        ) catch return error.Fatal;
    }

    pub fn raiseNoMethod(self: *VM, receiver: Value, method_name: []const u8) VMError {
        const receiver_desc = self.noMethodReceiverDescription(receiver) catch return error.Fatal;
        const exc = try self.createException(self.no_method_error_class, std.fmt.allocPrint(self.gc_allocator, "undefined method '{s}' for {s}", .{ method_name, receiver_desc }) catch return error.Fatal);
        exc.receiver = receiver;
        self.setPendingException(exc);
        return error.Unwind;
    }

    fn raiseMethodVisibilityError(self: *VM, method_name: []const u8, visibility: MethodVisibility) VMError {
        const message = std.fmt.allocPrint(self.gc_allocator, "{s} method `{s}' called", .{
            if (visibility == .private) "private" else "protected",
            method_name,
        }) catch return error.Fatal;
        const exc = self.createException(self.no_method_error_class, message) catch return error.Fatal;
        self.setPendingException(exc);
        return error.Unwind;
    }

    pub const ChunkCallOptions = struct {
        kw_keys: ?[]const Value = null,
        kw_values: ?[]const Value = null,
        method_name: ?[]const u8 = null,
        super_defining_class: ?*ClassObject = null,
        block: ?Block = null,
    };

    inline fn setupChunkCallFrame(
        self: *VM,
        method_chunk: *Chunk,
        receiver: Value,
        args: []const Value,
        opts: ChunkCallOptions,
    ) VMError!void {
        var args_temp: TempValueSlice = .{};
        defer args_temp.deinit(self.allocator);

        // Always copy args immediately: pushFrame will nil-init the locals region
        // which overlaps with the on-stack arg slots when locals_base = receiver_index.
        var effective_args: []const Value = if (args.len > 0)
            try args_temp.copyFrom(self, args)
        else
            args;
        var effective_kw_keys = opts.kw_keys;
        var effective_kw_values = opts.kw_values;
        var has_keywords = effective_kw_values != null and effective_kw_values.?.len > 0;

        if (has_keywords and
            method_chunk.required_keywords.items.len == 0 and
            method_chunk.optional_keywords.items.len == 0 and
            method_chunk.keyword_rest_index == null and
            !method_chunk.no_keywords)
        {
            const kw_hash = try self.createHashFromKeywordPairs(effective_kw_keys.?, effective_kw_values.?);
            const expanded_args = try args_temp.initUninitialized(self, effective_args.len + 1);
            if (effective_args.len > 0) {
                std.mem.copyForwards(Value, expanded_args[0..effective_args.len], effective_args);
            }
            expanded_args[effective_args.len] = kw_hash;
            effective_args = expanded_args;
            effective_kw_keys = null;
            effective_kw_values = null;
            has_keywords = false;
        }

        if (method_chunk.no_keywords and has_keywords) {
            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
            self.setPendingException(exc);
            return error.Unwind;
        }

        if (!has_keywords and method_chunk.required_keywords.items.len > 0) {
            const msg = "missing required keyword arguments";
            const exc = try self.createException(self.argument_error_class, msg);
            self.setPendingException(exc);
            return error.Unwind;
        }

        try self.pushFrame(method_chunk, receiver, opts.block);
        const callee_frame = self.currentFrame();
        callee_frame.method_name = opts.method_name;
        callee_frame.super_defining_class = opts.super_defining_class;
        callee_frame.forwarded_keyword_ctx = if (has_keywords)
            try self.copyKeywordContext(effective_kw_keys.?, effective_kw_values.?)
        else
            null;
        if (method_chunk.is_simple_positional) {
            if (effective_args.len != method_chunk.arity) {
                return self.raiseArgumentErrorWrongArgCount(effective_args.len, method_chunk.arity);
            }

            if (effective_args.len > 0) {
                // Copy args into the first `effective_args.len` local slots
                const lc = method_chunk.locals_count;
                for (effective_args, 0..) |arg, i|
                    (callee_frame.ep - lc + @as(u16, @intCast(i)))[0] = arg;
            }
        } else {
            try self.copyArgumentsWithRestParam(method_chunk, callee_frame.ep, effective_args, .strict);
        }

        if (has_keywords) {
            const keys = effective_kw_keys orelse return error.Fatal;
            const kw_vals = effective_kw_values.?;
            try self.bindKeywordArguments(method_chunk, callee_frame.ep, keys, kw_vals);
        } else {
            if (method_chunk.optional_keywords.items.len > 0 or method_chunk.keyword_rest_index != null) {
                for (method_chunk.optional_keywords.items) |opt_kw| {
                    const default_chunk = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                    const current_ep = self.currentFrame().ep;
                    const default_value = try self.executeDefaultExpression(default_chunk, current_ep);
                    const f = &self.frames.items[self.frames.items.len - 1];
                    const lc = f.chunk.locals_count;
                    (f.ep - lc + opt_kw.param_slot)[0] = default_value;
                }

                if (method_chunk.keyword_rest_index) |rest_idx| {
                    const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                    kw_hash.* = .{
                        .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                        .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                        .entries = .empty,
                        .default_value = null,
                        .default_proc = null,
                        .compare_by_identity = false,
                    };
                    const f = &self.frames.items[self.frames.items.len - 1];
                    const lc = f.chunk.locals_count;
                    (f.ep - lc + rest_idx)[0] = Value.fromObject(&kw_hash.object);
                }
            }
        }

        if (method_chunk.block_param_index) |block_idx| {
            const current_frame = &self.frames.items[self.frames.items.len - 1];
            const lc = current_frame.chunk.locals_count;

            if (current_frame.block) |blk| {
                const proc_val = try self.newProc(blk);
                const f = &self.frames.items[self.frames.items.len - 1];
                (f.ep - lc + block_idx)[0] = proc_val;
            } else {
                (current_frame.ep - lc + block_idx)[0] = Value.nil();
            }
        }
    }

    fn chunkSupportsRuby2Keywords(self: *VM, ch: *const Chunk) bool {
        _ = self;
        return ch.rest_param_index != null and
            ch.post_required_count == 0 and
            !ch.no_keywords and
            ch.required_keywords.items.len == 0 and
            ch.optional_keywords.items.len == 0 and
            ch.keyword_rest_index == null;
    }

    fn methodAcceptsKeywords(self: *VM, entry: MethodEntry) bool {
        _ = self;
        return switch (entry.method) {
            .chunk => |ch| chunkAcceptsKeywords(ch),
            .proc => |proc_obj| switch (proc_obj.block.kind) {
                .chunk => |chunk_blk| chunkAcceptsKeywords(chunk_blk.chunk),
                else => false,
            },
            .builtin, .undefined => false,
        };
    }

    fn methodSupportsRuby2Keywords(self: *VM, entry: MethodEntry) bool {
        if (!entry.ruby2_keywords) return false;
        return switch (entry.method) {
            .chunk => |ch| self.chunkSupportsRuby2Keywords(ch),
            .proc => |proc_obj| switch (proc_obj.block.kind) {
                .chunk => |chunk_blk| self.chunkSupportsRuby2Keywords(chunk_blk.chunk),
                else => false,
            },
            .builtin, .undefined => false,
        };
    }

    pub fn copyHashInto(self: *VM, target: *value.HashObject, source: *const value.HashObject, copy_ivars: bool) VMError!void {
        target.entries.clearRetainingCapacity();
        target.map.clearRetainingCapacity();
        target.default_value = null;
        target.default_proc = null;
        target.compare_by_identity = source.compare_by_identity;
        target.default_value = source.default_value;
        target.default_proc = source.default_proc;
        target.object.flags &= ~@as(u32, value.HASH_RUBY2_KEYWORDS_FLAG);
        target.object.flags |= source.object.flags & value.HASH_RUBY2_KEYWORDS_FLAG;
        for (source.entries.items) |entry| {
            try self.hashSetEntry(target, entry.key, entry.value);
        }
        if (copy_ivars) {
            target.object.instance_variables = null;
            try self.copyObjectInstanceVariables(&source.object, &target.object);
        }
    }

    pub fn copyHashObject(self: *VM, source: *const value.HashObject) VMError!*value.HashObject {
        const copied_value = try self.newObjectForClass(source.object.class orelse self.hash_class);
        const copied = copied_value.toHashObject();
        try self.copyHashInto(copied, source, true);
        return copied;
    }

    fn normalizeRuby2KeywordsDispatch(
        self: *VM,
        entry: MethodEntry,
        args: []const Value,
        kw_keys: ?[]const Value,
        kw_values: ?[]const Value,
        args_array_mode: bool,
        args_temp: *TempValueSlice,
        kw_temp: *TempKeywordPairs,
    ) VMError!Ruby2KeywordsDispatch {
        if (kw_values) |vals| {
            if (vals.len > 0 and self.methodSupportsRuby2Keywords(entry)) {
                const marked_hash = try self.createHashFromKeywordPairs(kw_keys.?, vals);
                marked_hash.toHashObject().object.flags |= value.HASH_RUBY2_KEYWORDS_FLAG;
                const expanded = try args_temp.initUninitialized(self, args.len + 1);
                if (args.len > 0) {
                    std.mem.copyForwards(Value, expanded[0..args.len], args);
                }
                expanded[args.len] = marked_hash;
                return .{ .args = expanded };
            }
        }

        if (kw_values != null or args.len == 0) {
            return .{ .args = args, .kw_keys = kw_keys, .kw_values = kw_values };
        }

        if (!args_array_mode) {
            return .{ .args = args, .kw_keys = kw_keys, .kw_values = kw_values };
        }

        const last = args[args.len - 1];
        if (!last.isHash() or (last.toHashObject().object.flags & value.HASH_RUBY2_KEYWORDS_FLAG) == 0) {
            return .{ .args = args, .kw_keys = kw_keys, .kw_values = kw_values };
        }

        if (self.methodAcceptsKeywords(entry)) {
            try kw_temp.initFromHash(self, last);
            return .{
                .args = args[0 .. args.len - 1],
                .kw_keys = kw_temp.keys.slice,
                .kw_values = kw_temp.values.slice,
            };
        }

        if (self.methodSupportsRuby2Keywords(entry)) {
            return .{ .args = args, .kw_keys = kw_keys, .kw_values = kw_values };
        }

        const expanded = try args_temp.copyFrom(self, args);
        const copied_hash = try self.copyHashObject(last.toHashObject());
        copied_hash.object.flags &= ~@as(u32, value.HASH_RUBY2_KEYWORDS_FLAG);
        expanded[expanded.len - 1] = Value.fromObject(&copied_hash.object);
        return .{ .args = expanded, .kw_keys = kw_keys, .kw_values = kw_values };
    }

    fn keywordNameForContextIndex(self: *VM, ctx: *const BuiltinKeywordContext, idx: usize) VMError![]const u8 {
        _ = self;
        if (idx >= ctx.kw_keys.len) return error.Fatal;
        const key = ctx.kw_keys[idx];
        if (key.isSymbol()) return key.toSymbolObject().name;
        if (key.isString()) return key.toStringObject().str;
        return "unknown";
    }

    fn findKeywordInContext(self: *VM, ctx: *const BuiltinKeywordContext, name: []const u8) VMError!?usize {
        _ = self;
        var i: usize = 0;
        while (i < ctx.kw_values.len) : (i += 1) {
            const key = ctx.kw_keys[i];
            if (key.isSymbol() and std.mem.eql(u8, key.toSymbolObject().name, name)) {
                return i;
            }
            if (key.isString() and std.mem.eql(u8, key.toStringObject().str, name)) {
                return i;
            }
        }
        return null;
    }

    fn invokeBuiltinMethod(
        self: *VM,
        builtin_method: BuiltinMethod,
        receiver: Value,
        method_name: []const u8,
        args: []Value,
        block: ?Block,
        keyword_ctx: ?*BuiltinKeywordContext,
    ) VMError!Value {
        const saved_frame_len = self.frames.items.len;
        try self.pushBuiltinFrame(receiver, method_name, block);
        defer if (self.frames.items.len > saved_frame_len and self.frames.items[self.frames.items.len - 1].frame_type == .builtin) {
            self.popBuiltinFrame();
        };

        const previous_ctx = self.builtin_keyword_ctx;
        self.builtin_keyword_ctx = keyword_ctx;
        defer self.builtin_keyword_ctx = previous_ctx;

        const result = builtin_method.function(self, receiver, args, block) catch |err| {
            if (self.pendingException() != null) {
                return error.Unwind;
            }
            return err;
        };
        return result;
    }

    pub fn invokeBuiltinMethodForwardingKeywords(
        self: *VM,
        builtin_method: BuiltinMethod,
        receiver: Value,
        method_name: []const u8,
        args: []Value,
        block: ?Block,
    ) VMError!Value {
        return self.invokeBuiltinMethod(builtin_method, receiver, method_name, args, block, self.builtin_keyword_ctx);
    }

    pub fn popCurrentBuiltinFrame(self: *VM) void {
        std.debug.assert(self.frames.items.len > 0);
        std.debug.assert(self.frames.items[self.frames.items.len - 1].frame_type == .builtin);
        self.popBuiltinFrame();
    }

    pub fn currentRubyCallerFrame(self: *VM) ?*CallFrame {
        if (self.frames.items.len == 0) return null;
        return self.nearestRubyFrame(self.frames.items.len - 1);
    }

    fn copyKeywordContext(
        self: *VM,
        kw_keys: []const Value,
        kw_values: []const Value,
    ) VMError!?*BuiltinKeywordContext {
        if (kw_keys.len != kw_values.len) return error.Fatal;
        if (kw_keys.len == 0) return null;

        const keyword_ctx = self.gc_allocator.create(BuiltinKeywordContext) catch return error.Fatal;
        keyword_ctx.* = .{
            .kw_keys_storage = undefined,
            .kw_values_storage = undefined,
        };
        @memcpy(keyword_ctx.kw_keys_storage[0..kw_keys.len], kw_keys);
        @memcpy(keyword_ctx.kw_values_storage[0..kw_values.len], kw_values);
        keyword_ctx.kw_keys = keyword_ctx.kw_keys_storage[0..kw_keys.len];
        keyword_ctx.kw_values = keyword_ctx.kw_values_storage[0..kw_values.len];
        return keyword_ctx;
    }

    pub fn keywordArgsGiven(self: *VM) bool {
        return self.builtin_keyword_ctx != null and self.builtin_keyword_ctx.?.kw_values.len > 0;
    }

    pub fn consumeCloneFreezeOpt(self: *VM) VMError!Value {
        const freeze_value = try self.consumeKeywordArg("freeze");
        try self.validateKeywordArgsConsumed();

        const value_opt = freeze_value orelse return Value.nil();
        if (value_opt.isNil() or value_opt.isTrue() or value_opt.isFalse()) return value_opt;

        return self.raiseExceptionFmt(
            self.argument_error_class,
            "unexpected value for freeze: {s}",
            .{self.className(value_opt)},
        );
    }

    pub fn callInitializeClone(self: *VM, clone: Value, original: Value, kwfreeze: Value) VMError!void {
        var initialize_clone_args = [_]Value{original};
        if (kwfreeze.isNil()) {
            _ = try self.callMethodByName(clone, "initialize_clone", initialize_clone_args[0..], null);
            return;
        }

        const freeze_sym = try self.intern("freeze");
        const kw_keys = [_]Value{Value.fromObject(&freeze_sym.object)};
        const kw_values = [_]Value{kwfreeze};
        _ = try self.callMethodByNameWithKeywords(
            clone,
            "initialize_clone",
            initialize_clone_args[0..],
            kw_keys[0..],
            kw_values[0..],
            null,
        );
    }

    pub fn applyCloneFreeze(self: *VM, original: Value, clone: Value, kwfreeze: Value) void {
        _ = self;
        if (kwfreeze.isFalse()) return;

        if (kwfreeze.isTrue() or original.isFrozen()) {
            var mutable_clone = clone;
            mutable_clone.freeze();
        }
    }

    pub fn consumeKeywordArg(self: *VM, name: []const u8) VMError!?Value {
        const ctx = self.builtin_keyword_ctx orelse return null;

        const idx = try self.findKeywordInContext(ctx, name) orelse return null;
        ctx.consumed[idx] = true;
        return ctx.kw_values[idx];
    }

    pub fn consumeKeywordArgs(self: *VM, comptime names: anytype, out_ptrs: anytype) VMError!void {
        comptime {
            const names_info = @typeInfo(@TypeOf(names));
            if (names_info != .@"struct" or !names_info.@"struct".is_tuple) {
                @compileError("consumeKeywordArgs names must be a tuple literal, e.g. .{\"foo\", \"bar\"}");
            }

            const outs_info = @typeInfo(@TypeOf(out_ptrs));
            if (outs_info != .@"struct" or !outs_info.@"struct".is_tuple) {
                @compileError("consumeKeywordArgs out_ptrs must be a tuple of pointers");
            }

            if (names_info.@"struct".fields.len != outs_info.@"struct".fields.len) {
                @compileError("consumeKeywordArgs requires equal counts for names and output pointers");
            }
        }

        inline for (names, out_ptrs) |name, out_ptr| {
            const ptr_type = @TypeOf(out_ptr);
            comptime {
                const info = @typeInfo(ptr_type);
                if (info != .pointer) {
                    @compileError("consumeKeywordArgs outputs must be pointers");
                }
                const child = info.pointer.child;
                if (child != Value and child != ?Value) {
                    @compileError("consumeKeywordArgs output pointers must be *Value or *?Value");
                }
            }

            const val = try self.consumeKeywordArg(name);
            if (@typeInfo(ptr_type).pointer.child == Value) {
                out_ptr.* = val orelse Value.nil();
            } else {
                out_ptr.* = val;
            }
        }
    }

    fn materializeKeywordHashForContext(self: *VM, ctx: *BuiltinKeywordContext) VMError!Value {
        if (!ctx.hash_materialized) {
            ctx.cached_hash = try self.createHashFromKeywordPairs(ctx.kw_keys, ctx.kw_values);
            ctx.hash_materialized = true;
        }

        @memset(ctx.consumed[0..ctx.kw_values.len], true);
        return ctx.cached_hash.?;
    }

    pub fn consumeKeywordArgHash(self: *VM) VMError!?Value {
        const ctx = self.builtin_keyword_ctx orelse return null;
        return try self.materializeKeywordHashForContext(ctx);
    }

    pub fn validateKeywordArgsConsumed(self: *VM) VMError!void {
        const ctx = self.builtin_keyword_ctx orelse return;
        if (ctx.kw_values.len == 0) return;

        var i: usize = 0;
        while (i < ctx.kw_values.len) : (i += 1) {
            if (!ctx.consumed[i]) {
                const key = ctx.kw_keys[i];
                if (key.isSymbol()) {
                    return self.raiseExceptionFmt(self.argument_error_class, "unknown keyword: {s}", .{key.toSymbolObject().name});
                }
                if (key.isString()) {
                    return self.raiseExceptionFmt(self.argument_error_class, "unknown keyword: {s}", .{key.toStringObject().str});
                }
                return self.raiseExceptionFmt(self.argument_error_class, "unknown keyword", .{});
            }
        }
    }

    fn invokeResolvedMethodWithKeywords(
        self: *VM,
        resolved: ResolvedMethod,
        receiver: Value,
        args: []Value,
        block: ?Block,
        keyword_ctx: ?*BuiltinKeywordContext,
    ) VMError!Value {
        var dispatch_args_temp: TempValueSlice = .{};
        defer dispatch_args_temp.deinit(self.allocator);
        var dispatch_kw_temp: TempKeywordPairs = .{};
        defer dispatch_kw_temp.deinit(self.allocator);
        const raw_kw_keys: ?[]const Value = if (keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_keys else null else null;
        const raw_kw_values: ?[]const Value = if (keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_values else null else null;
        const dispatch: Ruby2KeywordsDispatch = if (raw_kw_values != null)
            try self.normalizeRuby2KeywordsDispatch(
                resolved.entry,
                args,
                raw_kw_keys,
                raw_kw_values,
                false,
                &dispatch_args_temp,
                &dispatch_kw_temp,
            )
        else
            .{
                .args = args,
                .kw_keys = null,
                .kw_values = null,
            };

        switch (resolved.entry.method) {
            .chunk => |method_chunk| {
                const saved_frame_count = self.frames.items.len;
                const saved_stack_len = self.stack.items.len;
                try self.setupChunkCallFrame(method_chunk, receiver, dispatch.args, .{
                    .kw_keys = dispatch.kw_keys,
                    .kw_values = dispatch.kw_values,
                    .method_name = resolved.name.name,
                    .super_defining_class = resolved.owner_class,
                    .block = block,
                });

                try self.executeUntilReturn(saved_frame_count);
                return (try self.finishSubcallFromStack(saved_frame_count, saved_stack_len)).value();
            },
            .builtin => |fun_ptr| {
                const dispatch_keyword_ctx = if (dispatch.kw_values) |vals|
                    if (vals.len > 0) (try self.copyKeywordContext(dispatch.kw_keys.?, vals)).? else null
                else
                    null;
                return self.invokeBuiltinMethod(fun_ptr, receiver, resolved.name.name, @constCast(dispatch.args), block, dispatch_keyword_ctx);
            },
            .proc => |proc_obj| {
                return self.callProcAsMethod(proc_obj, receiver, dispatch.args, .{
                    .kw_keys = dispatch.kw_keys,
                    .kw_values = dispatch.kw_values,
                    .block = block,
                    .method_name = resolved.name.name,
                    .defining_class = resolved.owner_class,
                });
            },
            .undefined => unreachable,
        }
    }

    pub fn invokeResolvedMethod(self: *VM, resolved: ResolvedMethod, receiver: Value, args: []Value, block: ?Block) VMError!Value {
        return self.invokeResolvedMethodWithKeywords(resolved, receiver, args, block, null);
    }

    fn bindMethodBlockParam(self: *VM, method_chunk: *Chunk, frame: *CallFrame, block: ?Block) VMError!void {
        if (method_chunk.block_param_index) |block_idx| {
            const lc = method_chunk.locals_count;
            if (block) |blk| {
                const proc_val = try self.newProc(blk);
                (frame.ep - lc + block_idx)[0] = proc_val;
            } else {
                (frame.ep - lc + block_idx)[0] = Value.nil();
            }
        }
    }

    fn invokeMethodMissing(
        self: *VM,
        receiver: Value,
        missing_method_sym: *SymbolObject,
        args: []Value,
        kw_hash: ?Value,
        block: ?Block,
    ) VMError!Value {
        if (std.mem.eql(u8, missing_method_sym.name, "method_missing")) {
            return self.raiseNoMethod(receiver, missing_method_sym.name);
        }

        const method_missing_sym = try self.intern("method_missing");
        const resolved = try self.findMethod(receiver, method_missing_sym);
        if (resolved == null) {
            return self.raiseNoMethod(receiver, missing_method_sym.name);
        }

        var missing_args: [258]Value = undefined;
        missing_args[0] = Value.fromObject(&missing_method_sym.object);
        for (args, 0..) |arg, i| {
            missing_args[i + 1] = arg;
        }

        var missing_argc: usize = 1 + args.len;
        if (kw_hash) |hash| {
            missing_args[missing_argc] = hash;
            missing_argc += 1;
        }

        return self.invokeResolvedMethod(resolved.?, receiver, missing_args[0..missing_argc], block);
    }

    fn callMethodByNameInternal(
        self: *VM,
        receiver: Value,
        method_name: []const u8,
        args: []Value,
        block: ?Block,
        keyword_ctx: ?*BuiltinKeywordContext,
    ) VMError!Value {
        const method_name_sym = try self.intern(method_name);
        const resolved = try self.findMethod(receiver, method_name_sym);

        if (resolved == null) {
            const kw_hash = if (keyword_ctx) |ctx|
                if (ctx.kw_values.len > 0) try self.materializeKeywordHashForContext(ctx) else null
            else
                null;
            return self.invokeMethodMissing(receiver, method_name_sym, args, kw_hash, block);
        }

        return self.invokeResolvedMethodWithKeywords(resolved.?, receiver, args, block, keyword_ctx);
    }

    fn callPublicMethodByNameInternal(
        self: *VM,
        receiver: Value,
        method_name: []const u8,
        args: []Value,
        block: ?Block,
        keyword_ctx: ?*BuiltinKeywordContext,
    ) VMError!Value {
        const method_name_sym = try self.intern(method_name);
        const resolved = try self.findMethod(receiver, method_name_sym);

        if (resolved) |r| {
            if (r.entry.visibility != .public) {
                return self.raiseMethodVisibilityError(method_name_sym.name, r.entry.visibility);
            }
            return self.invokeResolvedMethodWithKeywords(r, receiver, args, block, keyword_ctx);
        }

        const kw_hash = if (keyword_ctx) |ctx|
            if (ctx.kw_values.len > 0) try self.materializeKeywordHashForContext(ctx) else null
        else
            null;
        return self.invokeMethodMissing(receiver, method_name_sym, args, kw_hash, block);
    }

    /// Call a method by name string (not from bytecode constant pool)
    pub fn callMethodByName(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callMethodByNameInternal(receiver, method_name, args, block, null);
    }

    pub fn callPublicMethodByName(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callPublicMethodByNameInternal(receiver, method_name, args, block, null);
    }

    /// MRI records C methods as real control frames so backtraces preserve the
    /// true call order. Reuse the nearest Ruby frame's location metadata so
    /// lightweight builtin frames compose correctly with Ruby frames.
    pub fn pushBuiltinFrame(self: *VM, receiver: Value, method_name: []const u8, block: ?Block) VMError!void {
        if (self.frames.items.len >= self.frames.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber call stack overflow");
            self.setPendingException(exc);
            return error.Unwind;
        }

        const caller_frame = self.currentRubyFrame() orelse return;
        self.frames.append(self.gc_allocator, .{
            .chunk = caller_frame.chunk,
            .ip = caller_frame.ip,
            .locals_base = self.stack.items.len,
            .ep = caller_frame.ep,
            .stack_base = self.stack.items.len,
            .self_value = receiver,
            .block = block,
            .frame_type = .builtin,
            .method_name = method_name,
            .dir_returns_nil = caller_frame.dir_returns_nil,
        }) catch return error.Fatal;
    }

    pub fn popBuiltinFrame(self: *VM) void {
        const frame = self.frames.pop().?;
        std.debug.assert(frame.frame_type == .builtin);
        if (self.frames.items.len > 0) {
            self.current_lexical_scope = epLexScope(self.frames.items[self.frames.items.len - 1].ep);
        }
    }

    pub fn callMethodByNameWithKeywords(
        self: *VM,
        receiver: Value,
        method_name: []const u8,
        args: []Value,
        kw_keys: []const Value,
        kw_values: []const Value,
        block: ?Block,
    ) VMError!Value {
        if (kw_keys.len != kw_values.len) return error.Fatal;
        if (kw_keys.len == 0) return self.callMethodByNameInternal(receiver, method_name, args, block, null);

        const keyword_ctx = (try self.copyKeywordContext(kw_keys, kw_values)).?;
        return self.callMethodByNameInternal(receiver, method_name, args, block, keyword_ctx);
    }

    /// Call a method by name while forwarding the current builtin keyword context.
    pub fn callMethodByNameForwardingKeywords(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callMethodByNameInternal(receiver, method_name, args, block, self.builtin_keyword_ctx);
    }

    /// Call a public method by name while forwarding the current builtin keyword context.
    pub fn callPublicMethodByNameForwardingKeywords(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callPublicMethodByNameInternal(receiver, method_name, args, block, self.builtin_keyword_ctx);
    }

    pub fn respondsToMethodByName(self: *VM, receiver: Value, method_name: []const u8, include_private: bool) VMError!bool {
        const method_name_sym = try self.intern(method_name);
        var respond_args: [2]Value = .{
            Value.fromObject(&method_name_sym.object),
            Value.boolean(include_private),
        };
        const responds = try self.callMethodByName(receiver, "respond_to?", respond_args[0..], null);
        return responds.is_truthy();
    }

    /// MRI-like check-call helper for optional conversion/probe calls.
    /// Returns null when receiver does not respond to the method.
    /// If receiver responds, performs a normal call (including method_missing behavior).
    pub fn checkCallMethodByName(self: *VM, receiver: Value, method_name: []const u8, include_private: bool, args: []Value, block: ?Block) VMError!?Value {
        const respond_to_sym = try self.intern("respond_to?");
        const method_name_sym = try self.intern(method_name);
        const direct_method = try self.findMethod(receiver, method_name_sym);
        const respond_to_method = try self.findMethod(receiver, respond_to_sym);
        const has_respond_to = respond_to_method != null;

        if (direct_method != null) {
            return try self.callMethodByName(receiver, method_name, args, block);
        }

        if (has_respond_to) {
            if (try self.respondsToMethodByName(receiver, method_name, include_private)) {
                return try self.callMethodByName(receiver, method_name, args, block);
            }

            if (respond_to_method.?.owner_class != self.object_class) {
                return null;
            }
        }

        const original_exception = self.pendingException();
        const call_result = self.callMethodByName(receiver, method_name, args, block) catch |err| {
            if (err == error.Unwind) {
                if (self.pendingException()) |exc| {
                    if (exc.object.class == self.no_method_error_class and direct_method == null) {
                        self.setPendingException(original_exception);
                        return null;
                    }
                }
            }

            return err;
        };
        return call_result;
    }

    const SubcallOutcome = union(enum) {
        returned: Value,
        non_local_return: Value,
        broke: Value,

        inline fn value(self: SubcallOutcome) Value {
            return switch (self) {
                .returned => |v| v,
                .non_local_return => |v| v,
                .broke => |v| v,
            };
        }

        inline fn isBreak(self: SubcallOutcome) bool {
            return switch (self) {
                .broke => true,
                else => false,
            };
        }

        inline fn isNonLocalReturn(self: SubcallOutcome) bool {
            return switch (self) {
                .non_local_return => true,
                else => false,
            };
        }
    };

    /// Result from yielding to a block
    pub const YieldResult = struct {
        value: Value,
        break_occurred: bool,
        non_local_return_occurred: bool,

        pub inline fn controlFlowValue(self: YieldResult) ?Value {
            if (self.non_local_return_occurred or self.break_occurred) return self.value;
            return null;
        }
    };

    /// Yield to a block with arguments, handling break and exceptions
    /// Returns the block's result value and whether a break occurred
    pub fn yieldToBlock(self: *VM, block: Block, yield_args: []const Value) VMError!YieldResult {
        return switch (block.kind) {
            .receiver_builtin => |builtin_data| .{
                .value = try builtin_data.func(self, builtin_data.receiver, @constCast(yield_args)),
                .break_occurred = false,
                .non_local_return_occurred = false,
            },
            .symbol => |sym| .{
                .value = try self.invokeSymbolProc(sym, yield_args, null),
                .break_occurred = false,
                .non_local_return_occurred = false,
            },
            .builtin => |func| .{
                .value = try func(self, @constCast(yield_args)),
                .break_occurred = false,
                .non_local_return_occurred = false,
            },
            .callable => |callable| blk: {
                const saved_last_match = self.globals.get("$~") orelse Value.nil();
                try self.clearLastMatch();
                const call_result = self.callMethodByName(callable, "call", @constCast(yield_args), null) catch |err| {
                    if (saved_last_match.isMatchData()) {
                        try self.setLastMatch(saved_last_match.toMatchDataObject());
                    } else {
                        try self.clearLastMatch();
                    }
                    return err;
                };
                if (saved_last_match.isMatchData()) {
                    try self.setLastMatch(saved_last_match.toMatchDataObject());
                } else {
                    try self.clearLastMatch();
                }
                break :blk .{
                    .value = call_result,
                    .break_occurred = false,
                    .non_local_return_occurred = false,
                };
            },
            .chunk => |chunk_blk| blk: {
                const saved_stack_len = self.stack.items.len;
                const ft: CallFrame.FrameType = if (chunk_blk.chunk.is_lambda) .lambda else .proc;
                const break_target_frame_idx = self.frames.items.len;
                const next_target_frame_idx = self.frames.items.len;
                 try self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, ft, .{
                     .block = if (chunk_blk.enclosing_block_proc) |proc_obj| proc_obj.block else null,
                     .return_target_ep = chunk_blk.return_target_ep,
                     .break_target_frame_idx = break_target_frame_idx,
                     .next_target_frame_idx = next_target_frame_idx,
                 });

                const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                const block_frame = self.currentFrame();
                try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, yield_args, arity_mode);

                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);
                const outcome = try self.finishSubcallFromStack(saved_frame_count, saved_stack_len);
                break :blk YieldResult{
                    .value = outcome.value(),
                    .break_occurred = outcome.isBreak(),
                    .non_local_return_occurred = outcome.isNonLocalReturn(),
                };
            },
        };
    }

    /// Execute a ProcObject as a method body
    fn procCallBlock(explicit_block: ?Block, enclosing_block_proc: ?*value.ProcObject) ?Block {
        return explicit_block orelse if (enclosing_block_proc) |proc_obj| proc_obj.block else null;
    }

    pub const ProcCallOptions = struct {
        kw_keys: ?[]const Value = null,
        kw_values: ?[]const Value = null,
        block: ?Block = null,
        method_name: ?[]const u8 = null,
        defining_class: ?*ClassObject = null,
    };

    fn callProcAsMethod(
        self: *VM,
        proc_obj: *value.ProcObject,
        receiver: Value,
        args: []const Value,
        opts: ProcCallOptions,
    ) VMError!Value {
        const kw_keys = opts.kw_keys;
        const kw_values = opts.kw_values;
        const block = opts.block;
        const method_name = opts.method_name;
        const defining_class = opts.defining_class;
        return switch (proc_obj.block.kind) {
            .receiver_builtin => |builtin_data| builtin_data.func(self, builtin_data.receiver, @constCast(args)),
            .symbol => |sym| self.invokeSymbolProc(sym, args, block),
            .builtin => |func| func(self, @constCast(args)),
            .callable => |callable| self.callMethodByName(callable, "call", @constCast(args), block),
            .chunk => |chunk_blk| blk: {
                const proc_chunk = chunk_blk.chunk;
                const has_kw = kw_keys != null and kw_values != null and kw_values.?.len > 0;

                // Reject kwargs if the chunk explicitly forbids them or has no keyword params.
                if (has_kw and !chunkAcceptsKeywords(proc_chunk)) {
                    const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                    self.setPendingException(exc);
                    return error.Unwind;
                }

                const saved_stack_len = self.stack.items.len;
                try self.pushBlockFrame(proc_chunk, chunk_blk.defining_ep, receiver, .method, .{
                    .block = procCallBlock(block, chunk_blk.enclosing_block_proc),
                });

                const current_frame = self.currentFrame();
                current_frame.method_name = method_name;
                current_frame.super_defining_class = defining_class;
                try self.copyArgumentsWithRestParam(proc_chunk, current_frame.ep, args, .strict);
                try self.bindMethodBlockParam(proc_chunk, current_frame, block);

                if (has_kw) {
                    try self.bindKeywordArguments(proc_chunk, current_frame.ep, kw_keys.?, kw_values.?);
                } else if (proc_chunk.optional_keywords.items.len > 0 or proc_chunk.keyword_rest_index != null) {
                    for (proc_chunk.optional_keywords.items) |opt_kw| {
                        const default_chunk = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                        const default_value = try self.executeDefaultExpression(default_chunk, current_frame.ep);
                        const f = &self.frames.items[self.frames.items.len - 1];
                        const lc = f.chunk.locals_count;
                        (f.ep - lc + opt_kw.param_slot)[0] = default_value;
                    }
                    if (proc_chunk.keyword_rest_index) |rest_idx| {
                        const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                        kw_hash.* = .{
                            .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                            .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                            .entries = .empty,
                            .default_value = null,
                            .default_proc = null,
                            .compare_by_identity = false,
                        };
                        const f = &self.frames.items[self.frames.items.len - 1];
                        const lc = f.chunk.locals_count;
                        (f.ep - lc + rest_idx)[0] = Value.fromObject(&kw_hash.object);
                    }
                }

                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);

                break :blk (try self.finishSubcallFromStack(saved_frame_count, saved_stack_len)).value();
            },
        };
    }

    /// Returns true if a chunk's parameter signature accepts keyword arguments.
    inline fn chunkAcceptsKeywords(proc_chunk: *const Chunk) bool {
        if (proc_chunk.no_keywords) return false;
        return proc_chunk.keyword_rest_index != null or
            proc_chunk.required_keywords.items.len > 0 or
            proc_chunk.optional_keywords.items.len > 0;
    }

    fn invokeSymbolProc(self: *VM, symbol: *SymbolObject, args: []const Value, block: ?Block) VMError!Value {
        try self.requireMinArgCount(args, 1);
        const receiver = args[0];
        const method_name_sym = symbol;
        const resolved = try self.findMethod(receiver, method_name_sym);

        const r = resolved orelse {
            var missing_args: [256]Value = undefined;
            const remaining = args[1..];
            for (remaining, 0..) |arg, i| {
                missing_args[i] = arg;
            }
            return self.invokeMethodMissing(receiver, method_name_sym, missing_args[0..remaining.len], null, block);
        };

        if (r.entry.visibility != .public) {
            const is_private = r.entry.visibility == .private;
            const message = std.fmt.allocPrint(self.gc_allocator, "{s} method `{s}' called", .{
                if (is_private) "private" else "protected",
                symbol.name,
            }) catch return error.Fatal;
            const exc = try self.createException(self.no_method_error_class, message);
            self.setPendingException(exc);
            return error.Unwind;
        }

        var forwarded_args: [256]Value = undefined;
        if (args.len > 1) {
            @memcpy(forwarded_args[0 .. args.len - 1], args[1..]);
        }
        return self.invokeResolvedMethod(r, receiver, forwarded_args[0 .. args.len - 1], block);
    }

    pub fn callProcObject(
        self: *VM,
        proc_obj: *value.ProcObject,
        args: []const Value,
        block: ?Block,
        self_override: ?Value,
        method_definition_target: ?Value,
    ) VMError!Value {
        return switch (proc_obj.block.kind) {
            .receiver_builtin => |builtin_data| builtin_data.func(self, builtin_data.receiver, @constCast(args)),
            .symbol => |sym| self.invokeSymbolProc(sym, args, block),
            .builtin => |func| func(self, @constCast(args)),
            .callable => |callable| self.callMethodByName(callable, "call", @constCast(args), block),
            .chunk => |chunk_blk| blk: {
                const saved_stack_len = self.stack.items.len;
                const ft: CallFrame.FrameType = if (chunk_blk.chunk.is_lambda) .lambda else .proc;
                const next_target_frame_idx = self.frames.items.len;
                try self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, self_override orelse chunk_blk.defining_self, ft, .{
                    .block = procCallBlock(block, chunk_blk.enclosing_block_proc),
                    .return_target_ep = chunk_blk.return_target_ep,
                    .next_target_frame_idx = next_target_frame_idx,
                    .method_definition_target = method_definition_target,
                });

                const current_frame = self.currentFrame();
                const mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                try self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, args, mode);

                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);
                break :blk (try self.finishSubcallFromStack(saved_frame_count, saved_stack_len)).value();
            },
        };
    }

    /// Ensure a block was given, or raise an error
    pub fn requireBlock(self: *VM, block: ?Block) VMError!Block {
        return block orelse {
            const exc = try self.createException(self.argument_error_class, "no block given");
            self.setPendingException(exc);
            return error.Unwind;
        };
    }

    /// Ruby-level equality helper using `==`.
    /// Treats non-boolean/nil return values with Ruby truthiness.
    pub fn valueEquals(self: *VM, left: Value, right: Value) VMError!bool {
        var eq_args = [_]Value{right};
        const result = try self.callMethodByName(left, "==", eq_args[0..], null);
        return result.is_truthy();
    }

    /// Used by executeInstruction to implement both CALL and CALL_KW
    /// For a Chunk, it sets up the frame and returns.
    /// For a builtin function pointer, it calls it and pushes the return value onto the stack.
    /// Don't call this from anywhere else because stack unwinding won't work right.
    pub const CallMethodOptions = struct {
        args_array_mode: bool = false,
        kw_keys: ?[]Value = null,
        kw_values: ?[]Value = null,
        block: ?Block = null,
    };

    fn callMethodHelperForExecuteInstruction(
        self: *VM,
        frame: *CallFrame,
        callsite_byte_offset: usize,
        method_name_sym: *SymbolObject,
        call_style: ReceiverCallStyle,
        receiver: Value,
        args: []const Value,
        opts: CallMethodOptions,
    ) VMError!void {
        const args_array_mode = opts.args_array_mode;
        const kw_keys = opts.kw_keys;
        const kw_values = opts.kw_values;
        const block = opts.block;
        const resolved = try self.resolveMethodForCallSite(frame, callsite_byte_offset, receiver, method_name_sym);
        const should_fallback = resolved == null or !self.isMethodCallable(receiver, resolved.?, call_style);
        const kwargc: usize = if (kw_values) |vals| vals.len else 0;
        if (should_fallback) {
            const kw_hash = if (kwargc > 0) try self.createHashFromKeywordPairs(kw_keys.?, kw_values.?) else null;
            const result = try self.invokeMethodMissing(receiver, method_name_sym, @constCast(args), kw_hash, block);
            try self.push(result);
            return;
        }

        const method = resolved.?;
        var dispatch_args_temp: TempValueSlice = .{};
        defer dispatch_args_temp.deinit(self.allocator);
        var dispatch_kw_temp: TempKeywordPairs = .{};
        defer dispatch_kw_temp.deinit(self.allocator);
        const dispatch = if (args_array_mode or kwargc > 0)
            try self.normalizeRuby2KeywordsDispatch(
                method.entry,
                args,
                if (kw_keys) |keys| keys else null,
                if (kw_values) |vals| vals else null,
                args_array_mode,
                &dispatch_args_temp,
                &dispatch_kw_temp,
            )
        else
            Ruby2KeywordsDispatch{ .args = args };
        const dispatch_kwargc: usize = if (dispatch.kw_values) |vals| vals.len else 0;
        const dispatch_kw_keys: ?[]Value = if (dispatch.kw_keys) |keys| @constCast(keys) else null;
        const dispatch_kw_values: ?[]Value = if (dispatch.kw_values) |vals| @constCast(vals) else null;

        switch (method.entry.method) {
            .chunk => |method_chunk| {
                try self.setupChunkCallFrame(method_chunk, receiver, dispatch.args, .{
                    .kw_keys = dispatch.kw_keys,
                    .kw_values = dispatch.kw_values,
                    .method_name = method.name.name,
                    .super_defining_class = method.owner_class,
                    .block = block,
                });
            },
            .builtin => |fun_ptr| {
                // Special case: Proc#call on chunk proc — push frame inline to avoid recursion
                if (dispatch_kwargc == 0 and receiver.isProc()) {
                    const proc_obj = receiver.toProcObject();
                    switch (proc_obj.block.kind) {
                        .chunk => |chunk_blk| {
                            const mn = method.name.name;
                            if (std.mem.eql(u8, mn, "call") or std.mem.eql(u8, mn, "[]") or std.mem.eql(u8, mn, "yield")) {
                                const ft: CallFrame.FrameType = if (chunk_blk.chunk.is_lambda) .lambda else .proc;
                                const next_target_frame_idx = self.frames.items.len;
                                try self.pushBlockFrame(chunk_blk.chunk, chunk_blk.defining_ep, chunk_blk.defining_self, ft, .{
                                    .block = procCallBlock(block, chunk_blk.enclosing_block_proc),
                                    .return_target_ep = chunk_blk.return_target_ep,
                                    .next_target_frame_idx = next_target_frame_idx,
                                });

                                const current_frame = self.currentFrame();
                                const mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                                try self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, dispatch.args, mode);
                                return;
                            }
                        },
                        else => {},
                    }
                }

                const maybe_keyword_ctx = if (dispatch_kwargc > 0)
                    try self.copyKeywordContext(dispatch.kw_keys.?, dispatch.kw_values.?)
                else
                    null;

                const saved_frame_len = self.frames.items.len;
                const result = try self.invokeBuiltinMethod(fun_ptr, receiver, method.name.name, @constCast(dispatch.args), block, maybe_keyword_ctx);
                if (self.frames.items.len < saved_frame_len) {
                    // Builtins can trigger block returns that unwind past this call helper. In
                    // that case the surviving frame already has the right stack state/result.
                    return;
                }
                try self.push(result);
            },
            .proc => |proc_obj| {
                switch (proc_obj.block.kind) {
                    .chunk => |chunk_blk| {
                        const proc_chunk = chunk_blk.chunk;
                        // Reject kwargs if chunk has no keyword params.
                        if (dispatch_kwargc > 0 and !chunkAcceptsKeywords(proc_chunk)) {
                            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                        // De-recursed: push frame inline, return to dispatch loop
                        try self.pushBlockFrame(proc_chunk, chunk_blk.defining_ep, receiver, .method, .{
                            .block = procCallBlock(block, chunk_blk.enclosing_block_proc),
                        });

                        const current_frame = self.currentFrame();
                        current_frame.method_name = method.name.name;
                        current_frame.super_defining_class = method.owner_class;
                        try self.copyArgumentsWithRestParam(proc_chunk, current_frame.ep, dispatch.args, .strict);
                        try self.bindMethodBlockParam(proc_chunk, current_frame, block);

                        if (dispatch_kwargc > 0) {
                            try self.bindKeywordArguments(proc_chunk, current_frame.ep, dispatch_kw_keys.?[0..dispatch_kwargc], dispatch_kw_values.?[0..dispatch_kwargc]);
                        } else if (proc_chunk.optional_keywords.items.len > 0 or proc_chunk.keyword_rest_index != null) {
                            for (proc_chunk.optional_keywords.items) |opt_kw| {
                                const default_chunk_inline = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                                const default_value = try self.executeDefaultExpression(default_chunk_inline, current_frame.ep);
                                const f = &self.frames.items[self.frames.items.len - 1];
                                const lc = f.chunk.locals_count;
                                (f.ep - lc + opt_kw.param_slot)[0] = default_value;
                            }
                            if (proc_chunk.keyword_rest_index) |rest_idx| {
                                const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                                kw_hash.* = .{
                                    .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                                    .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                                    .entries = .empty,
                                    .default_value = null,
                                    .default_proc = null,
                                    .compare_by_identity = false,
                                };
                                const f = &self.frames.items[self.frames.items.len - 1];
                                const lc = f.chunk.locals_count;
                                (f.ep - lc + rest_idx)[0] = Value.fromObject(&kw_hash.object);
                            }
                        }
                    },
                    .receiver_builtin => |builtin_data| {
                        if (dispatch_kwargc > 0) {
                            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                        const result = try builtin_data.func(self, builtin_data.receiver, @constCast(dispatch.args));
                        try self.push(result);
                    },
                    .symbol => |sym| {
                        if (dispatch_kwargc > 0) {
                            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                        const result = try self.invokeSymbolProc(sym, dispatch.args, block);
                        try self.push(result);
                    },
                    .builtin => |func| {
                        if (dispatch_kwargc > 0) {
                            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                        const result = try func(self, @constCast(dispatch.args));
                        try self.push(result);
                    },
                    .callable => |callable| {
                        if (dispatch_kwargc > 0) {
                            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                            self.setPendingException(exc);
                            return error.Unwind;
                        }
                        const result = try self.callMethodByName(callable, "call", @constCast(dispatch.args), block);
                        try self.push(result);
                    },
                }
            },
            .undefined => unreachable,
        }
    }

    pub fn getClass(self: *VM, val: Value) *ClassObject {
        if (val.isInteger()) return self.integer_class;
        if (val.isNil()) return self.nil_class;
        if (val.isBool()) return if (val.toBool()) self.true_class else self.false_class;
        if (val.isObject()) {
            // Types with Object headers - use the class field from the header
            const obj: *value.Object = @ptrFromInt(val.raw);
            return obj.class.?;
        }
        // float (special case not yet implemented)
        return self.float_class;
    }

    pub inline fn className(self: *VM, val: Value) []const u8 {
        return self.getClass(val).module.name.name;
    }

    pub fn resolveConstantPath(self: *VM, path: []const u8) VMError!?Value {
        return self.resolveConstantPathFrom(null, path, false);
    }

    fn getObjectPointer(_: *VM, obj_val: value.Value) ?*value.Object {
        return obj_val.getObjectPointer();
    }

    pub fn lookupMethod(self: *VM, class: *ClassObject, method_name: *value.SymbolObject) ?ResolvedMethod {
        return switch (self.lookupMethodDetailed(class, method_name)) {
            .found => |resolved| resolved,
            .undefined, .not_found => null,
        };
    }

    fn resolveConstantPathFrom(
        self: *VM,
        start_scope: ?*LexicalScope,
        path: []const u8,
        prefer_lexical_for_first_segment: bool,
    ) VMError!?Value {
        var segments = std.mem.splitSequence(u8, path, "::");
        const first = segments.next() orelse return null;
        if (first.len == 0) return null;

        const first_sym = try self.intern(first);
        var current = blk: {
            if (prefer_lexical_for_first_segment) {
                if (start_scope) |scope| {
                    const lexical_lookup = try self.findConstantInLexicalScope(scope, first_sym);
                    if (lexical_lookup.value) |val| break :blk val;
                }
            }
            break :blk (self.object_class.module.constants.get(first_sym) orelse return null).value;
        };

        while (segments.next()) |segment| {
            if (segment.len == 0) continue;
            if (!current.isClass() and !current.isModule()) return null;

            const segment_sym = try self.intern(segment);
            if (current.isClass()) {
                var klass: ?*ClassObject = current.toClassObject();
                current = blk: while (klass) |cls| : (klass = cls.superclass) {
                    if (cls.module.constants.get(segment_sym)) |entry| break :blk entry.value;
                } else return null;
            } else {
                const module_obj = current.toModuleObject();
                current = (module_obj.constants.get(segment_sym) orelse return null).value;
            }
        }

        return current;
    }

    fn resolveDefinitionTarget(
        self: *VM,
        lexical_scope: ?*LexicalScope,
        raw_name: []const u8,
    ) VMError!struct {
        owner_module: *value.ModuleObject,
        existing_value: ?Value,
        name_sym: *value.SymbolObject,
    } {
        if (std.mem.lastIndexOf(u8, raw_name, "::")) |sep| {
            const owner_path = raw_name[0..sep];
            const child_name = raw_name[sep + 2 ..];
            const prefer_lexical = owner_path.len == 0 or owner_path[0] != ':';
            const normalized_owner_path = if (std.mem.startsWith(u8, owner_path, "::")) owner_path[2..] else owner_path;

            const owner_val = if (normalized_owner_path.len == 0)
                Value.fromObject(&self.object_class.module.object)
            else
                (try self.resolveConstantPathFrom(lexical_scope, normalized_owner_path, prefer_lexical)) orelse {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized constant {s}",
                        .{normalized_owner_path},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.setPendingException(exc);
                    return error.Unwind;
                };

            if (!owner_val.isClass() and !owner_val.isModule()) {
                const exc = try self.createException(self.type_error_class, "constant path does not refer to class/module");
                self.setPendingException(exc);
                return error.Unwind;
            }

            const owner_module = if (owner_val.isClass())
                &owner_val.toClassObject().module
            else
                owner_val.toModuleObject();
            const name_sym = try self.intern(child_name);
            return .{
                .owner_module = owner_module,
                .existing_value = if (owner_module.constants.get(name_sym)) |entry| entry.value else null,
                .name_sym = name_sym,
            };
        }

        const name_sym = try self.intern(raw_name);
        const owner_module = if (lexical_scope) |scope| scope.getModule() else &self.object_class.module;

        return .{
            .owner_module = owner_module,
            .existing_value = if (owner_module.constants.get(name_sym)) |entry| entry.value else null,
            .name_sym = name_sym,
        };
    }

    /// Get the defining class for super lookup from the current frame's lexical scope
    fn getDefiningClassForSuper(_: *VM, frame_chunk: *Chunk) ?*ClassObject {
        const lexical_scope = frame_chunk.lexical_scope orelse return null;

        switch (lexical_scope.scope_module) {
            .class => |cls| return cls,
            .module => return null,
        }

        unreachable;
    }

    const SuperLookupScope = union(enum) {
        class: *ClassObject,
        module: *value.ModuleObject,
    };

    fn lookupMethodForSuperInModuleChain(
        self: *VM,
        owner_class: *ClassObject,
        module_obj: *value.ModuleObject,
        is_class_module: bool,
        defining_scope: SuperLookupScope,
        method_name: *value.SymbolObject,
        found_owner: *bool,
    ) LookupMethodResult {
        var i = module_obj.prepended_modules.items.len;
        while (i > 0) {
            i -= 1;
            switch (self.lookupMethodForSuperInModuleChain(
                owner_class,
                module_obj.prepended_modules.items[i],
                false,
                defining_scope,
                method_name,
                found_owner,
            )) {
                .found => |resolved| return .{ .found = resolved },
                .undefined => return .undefined,
                .not_found => {},
            }
        }

        const matches_owner = switch (defining_scope) {
            .class => |defining_class| is_class_module and owner_class == defining_class,
            .module => |defining_module| module_obj == defining_module,
        };

        if (found_owner.*) {
            if (module_obj.methods.get(method_name)) |entry| {
                return self.resolveLookupEntry(method_name, owner_class, entry);
            }
        } else if (matches_owner) {
            found_owner.* = true;
        }

        i = module_obj.included_modules.items.len;
        while (i > 0) {
            i -= 1;
            switch (self.lookupMethodForSuperInModuleChain(
                owner_class,
                module_obj.included_modules.items[i],
                false,
                defining_scope,
                method_name,
                found_owner,
            )) {
                .found => |resolved| return .{ .found = resolved },
                .undefined => return .undefined,
                .not_found => {},
            }
        }

        return .not_found;
    }

    fn lookupMethodForSuperFromScope(
        self: *VM,
        start_class: *ClassObject,
        defining_scope: SuperLookupScope,
        method_name: *value.SymbolObject,
    ) ?ResolvedMethod {
        var current_class: ?*ClassObject = start_class;
        var found_owner = false;

        while (current_class) |klass| {
            switch (self.lookupMethodForSuperInModuleChain(
                klass,
                &klass.module,
                true,
                defining_scope,
                method_name,
                &found_owner,
            )) {
                .found => |resolved| return resolved,
                .undefined => return null,
                .not_found => {},
            }
            current_class = klass.superclass;
        }

        return null;
    }

    pub fn methodArityValue(_: *VM, resolved: ResolvedMethod) VMError!Value {
        return switch (resolved.entry.method) {
            .chunk => |method_chunk| blk: {
                const required = method_chunk.arity + method_chunk.post_required_count;
                if (method_chunk.rest_param_index != null or method_chunk.optional_params.items.len > 0) {
                    break :blk Value.integer(-@as(i64, @intCast(required)) - 1);
                }
                break :blk Value.integer(@intCast(required));
            },
            .proc => |proc_obj| switch (proc_obj.block.kind) {
                .chunk => |chunk_blk| blk: {
                    const required = chunk_blk.chunk.arity + chunk_blk.chunk.post_required_count;
                    if (chunk_blk.chunk.rest_param_index != null or chunk_blk.chunk.optional_params.items.len > 0) {
                        break :blk Value.integer(-@as(i64, @intCast(required)) - 1);
                    }
                    break :blk Value.integer(@intCast(required));
                },
                .receiver_builtin => |builtin_data| Value.integer(builtin_data.arity),
                .symbol, .builtin, .callable => Value.integer(-2),
            },
            .builtin => |builtin_method| Value.integer(builtin_method.arity.asRubyArity()),
            .undefined => unreachable,
        };
    }

    pub fn getChunkParameters(self: *VM, ch: *Chunk) VMError!Value {
        const result = try self.createArray();

        var i: u8 = 0;
        while (i < ch.arity) : (i += 1) {
            const param_array = try self.createArray();
            const req_sym = try self.intern("req");
            param_array.elements.append(self.gc_allocator, Value.fromObject(&req_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&param_array.object)) catch return error.Fatal;
        }

        if (ch.rest_param_index) |_| {
            const rest_array = try self.createArray();
            const rest_sym = try self.intern("rest");
            rest_array.elements.append(self.gc_allocator, Value.fromObject(&rest_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&rest_array.object)) catch return error.Fatal;
        }

        i = 0;
        while (i < ch.optional_params.items.len) : (i += 1) {
            const opt_array = try self.createArray();
            const opt_sym = try self.intern("opt");
            opt_array.elements.append(self.gc_allocator, Value.fromObject(&opt_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&opt_array.object)) catch return error.Fatal;
        }

        i = 0;
        while (i < ch.post_required_count) : (i += 1) {
            const post_array = try self.createArray();
            const req_sym = try self.intern("req");
            post_array.elements.append(self.gc_allocator, Value.fromObject(&req_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&post_array.object)) catch return error.Fatal;
        }

        if (ch.keyword_rest_index) |_| {
            const kwrest_array = try self.createArray();
            const keyrest_sym = try self.intern("keyrest");
            kwrest_array.elements.append(self.gc_allocator, Value.fromObject(&keyrest_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&kwrest_array.object)) catch return error.Fatal;
        }

        i = 0;
        while (i < ch.required_keywords.items.len) : (i += 1) {
            const key_array = try self.createArray();
            const key_sym = try self.intern("key");
            key_array.elements.append(self.gc_allocator, Value.fromObject(&key_sym.object)) catch return error.Fatal;
            result.elements.append(self.gc_allocator, Value.fromObject(&key_array.object)) catch return error.Fatal;
        }

        return Value.fromObject(&result.object);
    }

    /// Copy forwarding arguments into the provided buffer.
    /// Without rest params, this copies param slots directly from the environment.
    /// With rest params, the rest array is expanded inline.
    /// Returns the slice of buf that was filled.
    fn getForwardingArguments(_: *VM, frame: *CallFrame, buf: *[256]Value) []Value {
        const ch = frame.chunk;
        const ep = frame.ep;
        const lc = ch.locals_count;

        if (ch.has_forwarding_parameter) {
            const rest_idx = ch.rest_param_index orelse return buf[0..0];
            const rest_val = (ep - lc + rest_idx)[0];
            if (!rest_val.isArray()) return buf[0..0];

            const elems = rest_val.toArrayObject().elements.items;
            @memcpy(buf[0..elems.len], elems);
            return buf[0..elems.len];
        }

        const param_count = ch.arity + ch.optional_params.items.len + ch.post_required_count;

        if (ch.rest_param_index == null) {
            // Common case: copy param slots into buffer
            for (0..param_count) |i| buf[i] = (ep - lc + @as(u16, @intCast(i)))[0];
            return buf[0..param_count];
        }

        // Rest param case: copy slots, expanding the rest array inline
        const rest_idx: usize = ch.rest_param_index.?;
        const total_slots = param_count + 1; // +1 for the rest slot itself
        var out: usize = 0;
        for (0..total_slots) |slot| {
            const slot_val = (ep - lc + @as(u16, @intCast(slot)))[0];
            if (slot == rest_idx) {
                if (slot_val.isArray()) {
                    for (slot_val.toArrayObject().elements.items) |elem| {
                        buf[out] = elem;
                        out += 1;
                    }
                }
            } else {
                buf[out] = slot_val;
                out += 1;
            }
        }

        return buf[0..out];
    }

    /// Build a BuiltinKeywordContext from the current frame's keyword parameter
    /// slots. Used by FORWARDING_SUPER to forward actual keyword values (including
    /// applied defaults) rather than just what was explicitly passed at the call site.
    fn buildForwardingKeywordContext(self: *VM, frame: *CallFrame) VMError!?*BuiltinKeywordContext {
        const ch = frame.chunk;
        if (ch.has_forwarding_parameter) {
            const rest_idx = ch.keyword_rest_index orelse return null;
            const kw_hash_val = (frame.ep - ch.locals_count + rest_idx)[0];
            if (!kw_hash_val.isHash()) return null;

            const len = kw_hash_val.toHashObject().entries.items.len;
            if (len == 0) return null;

            const ctx = self.gc_allocator.create(BuiltinKeywordContext) catch return error.Fatal;
            ctx.* = .{};
            _ = try self.extractKeywordPairsFromHash(kw_hash_val, ctx.kw_keys_storage[0..len], ctx.kw_values_storage[0..len]);
            ctx.kw_keys = ctx.kw_keys_storage[0..len];
            ctx.kw_values = ctx.kw_values_storage[0..len];
            return ctx;
        }

        const total = ch.required_keywords.items.len + ch.optional_keywords.items.len;
        if (total == 0) return null;

        const ctx = self.gc_allocator.create(BuiltinKeywordContext) catch return error.Fatal;
        ctx.* = .{};

        const ep = frame.ep;
        const lc = ch.locals_count;
        var i: usize = 0;

        for (ch.required_keywords.items) |kw| {
            const name_str = switch (ch.constants.items[kw.name_idx]) {
                .string => |s| s,
                .symbol => |sym| sym.name,
                else => return error.Fatal,
            };
            ctx.kw_keys_storage[i] = Value.fromObject(&(try self.intern(name_str)).object);
            ctx.kw_values_storage[i] = (ep - lc + kw.param_slot)[0];
            i += 1;
        }
        for (ch.optional_keywords.items) |kw| {
            const name_str = switch (ch.constants.items[kw.name_idx]) {
                .string => |s| s,
                .symbol => |sym| sym.name,
                else => return error.Fatal,
            };
            ctx.kw_keys_storage[i] = Value.fromObject(&(try self.intern(name_str)).object);
            ctx.kw_values_storage[i] = (ep - lc + kw.param_slot)[0];
            i += 1;
        }

        ctx.kw_keys = ctx.kw_keys_storage[0..total];
        ctx.kw_values = ctx.kw_values_storage[0..total];
        return ctx;
    }

    /// Call the superclass method with the given arguments
    fn callSuper(self: *VM, args: []const Value, block: ?Block) VMError!void {
        const frame = self.currentFrame();

        // Use explicit frame metadata when a method body comes from a Proc (define_method/define_singleton_method).
        const method_name = frame.method_name orelse frame.chunk.name;
        const method_name_sym = try self.intern(method_name);

        const lexical_scope = frame.chunk.lexical_scope;
        const maybe_resolved = if (lexical_scope) |scope|
            switch (scope.scope_module) {
                .module => |defining_module| if (frame.super_defining_class) |explicit_defining_class|
                    if (explicit_defining_class.attached_object != null and
                        explicit_defining_class.attached_object.?.eql(frame.self_value))
                        self.lookupMethodForSuperFromScope(
                            explicit_defining_class,
                            if (defining_module == &explicit_defining_class.module)
                                .{ .class = explicit_defining_class }
                            else
                                .{ .module = defining_module },
                            method_name_sym,
                        ) orelse self.lookupMethodForSuperFromScope(
                            explicit_defining_class,
                            .{ .class = explicit_defining_class },
                            method_name_sym,
                        )
                    else
                        self.lookupMethodForSuperFromScope(
                            self.getClass(frame.self_value),
                            .{ .module = defining_module },
                            method_name_sym,
                        )
                else
                    self.lookupMethodForSuperFromScope(
                        self.getClass(frame.self_value),
                        .{ .module = defining_module },
                        method_name_sym,
                    ),
                .class => |defining_class| if (frame.super_defining_class) |explicit_defining_class|
                    self.lookupMethodForSuperFromScope(
                        explicit_defining_class,
                        .{ .class = explicit_defining_class },
                        method_name_sym,
                    )
                else
                    self.lookupMethodForSuperFromScope(
                        defining_class,
                        .{ .class = defining_class },
                        method_name_sym,
                    ),
            }
        else if (frame.super_defining_class) |defining_class|
            self.lookupMethodForSuperFromScope(
                defining_class,
                .{ .class = defining_class },
                method_name_sym,
            )
        else
            null;

        const resolved = maybe_resolved orelse {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "super: no superclass method '{s}' for {s}",
                .{ method_name, self.getClass(frame.self_value).module.name.name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.no_method_error_class, msg);
            self.setPendingException(exc);
            return error.Unwind;
        };

        // Call with the same receiver (self)
        const receiver = frame.self_value;

        switch (resolved.entry.method) {
            .chunk => |method_chunk| {
                const kw_keys = if (frame.forwarded_keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_keys else null else null;
                const kw_values = if (frame.forwarded_keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_values else null else null;
                try self.setupChunkCallFrame(method_chunk, receiver, args, .{
                    .kw_keys = kw_keys,
                    .kw_values = kw_values,
                    .method_name = resolved.name.name,
                    .super_defining_class = resolved.owner_class,
                    .block = block,
                });
            },
            .builtin => |fun_ptr| {
                // For builtin methods, we need a mutable copy
                var args_copy: [256]Value = undefined;
                @memcpy(args_copy[0..args.len], args);
                const result = try self.invokeBuiltinMethod(fun_ptr, receiver, resolved.name.name, args_copy[0..args.len], block, frame.forwarded_keyword_ctx);
                try self.push(result);
            },
            .proc => |proc_obj| {
                const kw_keys: ?[]const Value = if (frame.forwarded_keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_keys else null else null;
                const kw_values: ?[]const Value = if (frame.forwarded_keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_values else null else null;
                const result = try self.callProcAsMethod(proc_obj, receiver, args, .{
                    .kw_keys = kw_keys,
                    .kw_values = kw_values,
                    .block = block,
                    .method_name = resolved.name.name,
                    .defining_class = resolved.owner_class,
                });
                try self.push(result);
            },
            .undefined => unreachable,
        }
    }

    pub fn getOrCreateSingletonClass(self: *VM, obj_val: value.Value) VMError!*ClassObject {
        if (obj_val.isNil()) return self.nil_class;
        if (obj_val.isBool()) return if (obj_val.toBool()) self.true_class else self.false_class;

        // Return existing singleton class if already created
        if (obj_val.getSingletonClass()) |singleton| {
            if (obj_val.isFrozen()) {
                singleton.module.object.flags |= value.Object.FROZEN_FLAG;
            }
            return singleton;
        }

        // Get the object pointer (returns null for primitives)
        const obj_ptr = obj_val.getObjectPointer() orelse {
            const exc = try self.createException(self.type_error_class, "can't define singleton method for literals");
            self.setPendingException(exc);
            return error.Unwind;
        };

        // Create singleton class name: "#<Class:#<hex_address>>"
        const singleton_name = std.fmt.allocPrint(
            self.gc_allocator,
            "#<Class:#{x}>",
            .{@intFromPtr(obj_ptr)},
        ) catch return error.Fatal;
        const singleton_name_sym = try self.intern(singleton_name);

        // Determine singleton's superclass
        const singleton_superclass: *ClassObject = blk: {
            if (!obj_val.isObject()) unreachable; // Primitives can't have singleton classes
            switch (obj_val.objectTypeTag()) {
                .class => {
                    const c = obj_val.toClassObject();
                    if (c.superclass) |super| {
                        break :blk try self.getOrCreateSingletonClass(Value.fromObject(&super.module.object));
                    } else {
                        break :blk self.class_class;
                    }
                },
                else => break :blk obj_ptr.class.?,
            }
        };

        // Create the singleton ClassObject
        const singleton_class = self.gc_allocator.create(ClassObject) catch return error.Fatal;
        singleton_class.* = .{
            .superclass = singleton_superclass,
            .attached_object = obj_val,
            .object_type = singleton_superclass.object_type,
            .module = .{
                .object = .{
                    .type_tag = .class,
                    .flags = 0,
                    .class = self.class_class,
                    .singleton_class = null,
                    .instance_variables = null,
                },
                .name = singleton_name_sym,
                .methods = std.AutoHashMap(*value.SymbolObject, MethodEntry).init(self.gc_allocator),
                .constants = std.AutoHashMap(*value.SymbolObject, value.ConstEntry).init(self.gc_allocator),
                .autoloads = std.AutoHashMap(*value.SymbolObject, []const u8).init(self.gc_allocator),
                .class_variables = std.AutoHashMap(*value.SymbolObject, value.Value).init(self.gc_allocator),
            },
        };

        // Link back to object
        obj_ptr.singleton_class = singleton_class;

        if (obj_val.isFrozen()) {
            singleton_class.module.object.flags |= value.Object.FROZEN_FLAG;
        }

        return singleton_class;
    }

    pub fn copySingletonClassMetadata(self: *VM, source_val: Value, target_val: Value) VMError!void {
        try self.copySingletonClassMetadataWithFreeze(source_val, target_val, true);
    }

    pub fn copySingletonClassMetadataWithFreeze(self: *VM, source_val: Value, target_val: Value, preserve_frozen: bool) VMError!void {
        const source_singleton = source_val.getSingletonClass() orelse return;
        const target_singleton = try self.getOrCreateSingletonClass(target_val);

        var methods_iter = source_singleton.module.methods.iterator();
        while (methods_iter.next()) |entry| {
            target_singleton.module.methods.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        var constants_iter = source_singleton.module.constants.iterator();
        while (constants_iter.next()) |entry| {
            target_singleton.module.constants.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        var class_vars_iter = source_singleton.module.class_variables.iterator();
        while (class_vars_iter.next()) |entry| {
            target_singleton.module.class_variables.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        try self.copyObjectInstanceVariables(&source_singleton.module.object, &target_singleton.module.object);

        for (source_singleton.module.prepended_modules.items) |module_obj| {
            target_singleton.module.prepended_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        for (source_singleton.module.included_modules.items) |module_obj| {
            target_singleton.module.included_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        if (preserve_frozen) {
            target_singleton.module.object.flags |= source_singleton.module.object.flags & value.Object.FROZEN_FLAG;
        }
        self.bumpMethodStateVersion();
    }

    pub fn copyModuleMetadata(self: *VM, source: *const value.ModuleObject, target: *value.ModuleObject, preserve_frozen: bool) VMError!void {
        var methods_iter = source.methods.iterator();
        while (methods_iter.next()) |entry| {
            target.methods.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        var constants_iter = source.constants.iterator();
        while (constants_iter.next()) |entry| {
            target.constants.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        var autoloads_iter = source.autoloads.iterator();
        while (autoloads_iter.next()) |entry| {
            target.autoloads.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        var class_vars_iter = source.class_variables.iterator();
        while (class_vars_iter.next()) |entry| {
            target.class_variables.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        try self.copyObjectInstanceVariables(&source.object, &target.object);

        for (source.prepended_modules.items) |module_obj| {
            target.prepended_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        for (source.included_modules.items) |module_obj| {
            target.included_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        if (preserve_frozen) {
            target.object.flags |= source.object.flags & value.Object.FROZEN_FLAG;
        }
        self.bumpMethodStateVersion();
    }

    pub fn copyObjectInstanceVariables(self: *VM, source_obj: *const Object, target_obj: *Object) VMError!void {
        const src_ivars = source_obj.instance_variables orelse return;

        var copied_ivars: std.array_hash_map.Auto(*value.SymbolObject, Value) = .{};
        var iter = src_ivars.iterator();
        while (iter.next()) |entry| {
            copied_ivars.put(self.gc_allocator, entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }
        target_obj.instance_variables = copied_ivars;
    }

    pub fn objectIdValue(self: *VM, receiver: Value) VMError!Value {
        if (receiver.isInteger()) {
            var managed = std.math.big.int.Managed.initSet(self.allocator, receiver.toInteger()) catch return error.Fatal;
            defer managed.deinit();
            managed.shiftLeft(&managed, 1) catch return error.Fatal;
            managed.addScalar(&managed, 1) catch return error.Fatal;
            return self.valueFromManagedInteger(&managed);
        }

        return Value.integer(receiver.objectId());
    }

    pub fn intern(self: *VM, str: []const u8) VMError!*SymbolObject {
        return self.internWithEncoding(str, .{ .us_ascii = .{} });
    }

    pub fn internWithEncoding(self: *VM, str: []const u8, symbol_encoding: enc.Encoding) VMError!*SymbolObject {
        const canonical_encoding: enc.Encoding = if (enc.isAsciiOnly(str) and !symbol_encoding.isDummy() and symbol_encoding.isAsciiCompatible())
            .{ .us_ascii = .{} }
        else
            symbol_encoding;
        const probe_key = SymbolKey{
            .bytes = str,
            .encoding_tag = @as(SymbolEncodingTag, canonical_encoding),
        };
        if (self.symbols.get(probe_key)) |symbol_obj| {
            return symbol_obj;
        }

        const key_bytes = self.gc_allocator_atomic.dupe(u8, str) catch return error.Fatal;
        const map_key = SymbolKey{
            .bytes = key_bytes,
            .encoding_tag = @as(SymbolEncodingTag, canonical_encoding),
        };

        const symbol_obj = self.gc_allocator.create(SymbolObject) catch return error.Fatal;
        symbol_obj.* = .{
            .object = .{ .type_tag = .symbol, .flags = Object.FROZEN_FLAG, .class = self.symbol_class, .singleton_class = null, .instance_variables = null },
            .name = key_bytes,
            .encoding = canonical_encoding,
        };
        self.symbols.put(map_key, symbol_obj) catch return error.Fatal;
        return symbol_obj;
    }

    // ==== Object creation ====

    fn registerErrnoClass(self: *VM, errno_code: std.posix.E, class_obj: *ClassObject) VMError!void {
        self.errno_classes.put(@intCast(@intFromEnum(errno_code)), class_obj) catch return error.Fatal;
    }

    pub fn newModule(self: *VM, name: *SymbolObject) VMError!Value {
        const module_obj = self.gc_allocator.create(value.ModuleObject) catch return error.Fatal;
        module_obj.* = .{
            .object = .{ .type_tag = .module, .flags = 0, .class = self.module_class, .singleton_class = null, .instance_variables = null },
            .name = name,
            .methods = std.AutoHashMap(*SymbolObject, MethodEntry).init(self.gc_allocator),
            .constants = std.AutoHashMap(*value.SymbolObject, value.ConstEntry).init(self.gc_allocator),
            .autoloads = std.AutoHashMap(*SymbolObject, []const u8).init(self.gc_allocator),
            .class_variables = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
        };
        return Value.fromObject(&module_obj.object);
    }

    pub fn newClass(self: *VM, name: *SymbolObject, superclass: ?*ClassObject) VMError!Value {
        const object_type = if (superclass) |super| super.object_type else .instance;
        return self.newClassWithType(name, superclass, object_type);
    }

    pub fn newClassWithType(self: *VM, name: *SymbolObject, superclass: ?*ClassObject, object_type: value.ObjectType) VMError!Value {
        const class_obj = self.gc_allocator.create(ClassObject) catch return error.Fatal;
        class_obj.* = .{
            .superclass = superclass,
            .attached_object = null,
            .object_type = object_type,
            .module = .{
                .object = .{ .type_tag = .class, .flags = 0, .class = self.class_class, .singleton_class = null, .instance_variables = null },
                .name = name,
                .methods = std.AutoHashMap(*SymbolObject, MethodEntry).init(self.gc_allocator),
                .constants = std.AutoHashMap(*value.SymbolObject, value.ConstEntry).init(self.gc_allocator),
                .autoloads = std.AutoHashMap(*SymbolObject, []const u8).init(self.gc_allocator),
                .class_variables = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
            },
        };
        return Value.fromObject(&class_obj.module.object);
    }

    pub fn newInstance(self: *VM, class_obj: *ClassObject) VMError!Value {
        const obj = self.gc_allocator.create(Object) catch return error.Fatal;
        obj.* = .{
            .type_tag = .instance,
            .flags = 0,
            .class = class_obj,
            .singleton_class = null,
            .instance_variables = null,
        };
        return Value.fromObject(obj);
    }

    pub fn newExceptionInstance(self: *VM, class_obj: *ClassObject, args: []const Value, block: ?Block) VMError!Value {
        const exc = try self.createException(class_obj, "");
        const exc_val = Value.fromObject(&exc.object);
        _ = try self.callMethodByNameForwardingKeywords(exc_val, "initialize", @constCast(args), block);
        return exc_val;
    }

    pub fn newFiber(self: *VM, class_obj: *ClassObject, block: ?Block) VMError!Value {
        if (self.current_thread == null) {
            _ = try self.ensureMainThread();
        }
        const fiber_obj = self.gc_allocator.create(value.FiberObject) catch return error.Fatal;
        fiber_obj.object = .{ .type_tag = .fiber, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null };
        fiber_obj.state = .created;
        fiber_obj.block = block;
        initFiberValueStackInPlace(&fiber_obj.stack);
        initFiberFrameStackInPlace(&fiber_obj.frames);
        fiber_obj.current_lexical_scope = null;
        fiber_obj.caller = null;
        fiber_obj.coro = null;
        fiber_obj.coro_event = .none;
        fiber_obj.coro_result = Value.nil();
        fiber_obj.coro_exception = null;
        fiber_obj.first_resume_args = undefined;
        fiber_obj.first_resume_argc = 0;
        fiber_obj.fiber_locals = null;
        fiber_obj.owner_thread = self.current_thread;
        fiber_obj.owner_vm = self;
        try self.ensureFiberCatchStack(fiber_obj);
        return Value.fromObject(&fiber_obj.object);
    }

    pub const IoInit = struct {
        owns_fd: bool,
        readable: bool,
        writable: bool,
        append: bool = false,
        path: ?[]const u8 = null,
        path_encoding: ?enc.Encoding = null,
        sync: bool = false,
    };

    pub fn newIo(self: *VM, class_obj: *ClassObject, fd: i32, init: IoInit) VMError!Value {
        const io_obj = self.gc_allocator.create(value.IoObject) catch return error.Fatal;
        io_obj.* = .{
            .object = .{ .type_tag = .io, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .fd = fd,
            .owns_fd = init.owns_fd,
            .closed = false,
            .readable = init.readable,
            .writable = init.writable,
            .append = init.append,
            .path = init.path,
            .path_encoding = init.path_encoding,
            .sync = init.sync,
        };
        self.io_objects.append(self.gc_allocator, io_obj) catch return error.Fatal;
        return Value.fromObject(&io_obj.object);
    }

    pub fn newRange(self: *VM, class_obj: *ClassObject) VMError!Value {
        const range_obj = self.gc_allocator.create(value.RangeObject) catch return error.Fatal;
        range_obj.* = .{
            .object = .{
                .type_tag = .range,
                .flags = 0,
                .class = class_obj,
                .singleton_class = null,
                .instance_variables = null,
            },
            .begin = Value.nil(),
            .end = Value.nil(),
            .exclude_end = false,
        };
        return Value.fromObject(&range_obj.object);
    }

    pub const NormalizedRegexp = struct {
        encoding: enc.Encoding,
        options: u16,
    };

    fn regexpPatternNoEncodingAsciiOnly(pattern: []const u8) bool {
        var i: usize = 0;
        while (i < pattern.len) {
            const b = pattern[i];
            if (b > 0x7F) return false;
            if (b != '\\') {
                i += 1;
                continue;
            }

            i += 1;
            if (i >= pattern.len) break;
            const escaped = pattern[i];

            if (escaped == 'x' and i + 2 < pattern.len) {
                const hi = std.fmt.charToDigit(pattern[i + 1], 16) catch {
                    i += 1;
                    continue;
                };
                const lo = std.fmt.charToDigit(pattern[i + 2], 16) catch {
                    i += 1;
                    continue;
                };
                if (((hi << 4) | lo) > 0x7F) return false;
                i += 3;
                continue;
            }

            if (escaped >= '0' and escaped <= '7') {
                var octal_value: u16 = @intCast(escaped - '0');
                var digits: usize = 1;
                while (digits < 3 and i + digits < pattern.len) : (digits += 1) {
                    const oct = pattern[i + digits];
                    if (oct < '0' or oct > '7') break;
                    octal_value = (octal_value << 3) | @as(u16, oct - '0');
                }
                if (octal_value > 0x7F) return false;
                i += digits;
                continue;
            }

            i += 1;
        }

        return true;
    }

    pub fn normalizeRegexpEncoding(_: *VM, pattern: []const u8, source_encoding: enc.Encoding, options: u16) NormalizedRegexp {
        const ascii_only = if ((options & 32) != 0)
            regexpPatternNoEncodingAsciiOnly(pattern)
        else
            source_encoding.isAsciiOnlyString(pattern);

        if ((options & 32) != 0) {
            return .{
                .encoding = if (ascii_only) .{ .us_ascii = .{} } else .{ .ascii_8bit = .{} },
                .options = if (ascii_only) options & ~@as(u16, 16) else options | 16,
            };
        }

        if ((options & 16) != 0) {
            return .{ .encoding = source_encoding, .options = options | 16 };
        }

        if (!source_encoding.isAsciiCompatible()) {
            return .{ .encoding = source_encoding, .options = options | 16 };
        }

        if (ascii_only) {
            return .{ .encoding = .{ .us_ascii = .{} }, .options = options & ~@as(u16, 16) };
        }

        return .{ .encoding = source_encoding, .options = options | 16 };
    }

    pub fn newRegexpWithEncoding(self: *VM, pattern: []const u8, options: u16, encoding: enc.Encoding) VMError!Value {
        // Map our option bits to Onigmo options
        var onig_options: u32 = 0;
        if ((options & 1) != 0) onig_options |= onigmo.OPTION_IGNORECASE;
        if ((options & 2) != 0) onig_options |= onigmo.OPTION_EXTEND;
        if ((options & 4) != 0) onig_options |= onigmo.OPTION_MULTILINE;

        const onig_encoding = switch (encoding) {
            .utf8 => onigmo.ENCODING_UTF_8,
            .ascii_8bit => onigmo.ENCODING_ASCII,
            .us_ascii => onigmo.ENCODING_ASCII,
            .shift_jis => onigmo.ENCODING_SHIFT_JIS,
            .windows_31j => onigmo.ENCODING_WINDOWS_31J,
            .euc_jp => onigmo.ENCODING_EUC_JP,
            .iso_8859_1 => onigmo.ENCODING_ISO_8859_1,
            .iso_8859_9 => onigmo.ENCODING_ISO_8859_9,
            .iso_8859_15 => onigmo.ENCODING_ISO_8859_15,
            .utf16le => onigmo.ENCODING_UTF_16LE,
            .utf16be => onigmo.ENCODING_UTF_16BE,
            .utf32le => onigmo.ENCODING_UTF_32LE,
            .utf32be => onigmo.ENCODING_UTF_32BE,
            else => onigmo.ENCODING_UTF_8,
        };

        const result = onigmo.compileWithEncoding(pattern.ptr, pattern.ptr + pattern.len, onig_options, onig_encoding);

        if (result.err) |err| {
            return self.raiseExceptionFmt(
                self.regexp_error_class,
                "{s}",
                .{err.message[0..err.len]},
            );
        }

        // Duplicate the pattern string so it's owned by GC
        const pattern_copy = self.gc_allocator_atomic.dupe(u8, pattern) catch return error.Fatal;

        const regexp_obj = self.gc_allocator.create(value.RegexpObject) catch return error.Fatal;
        regexp_obj.* = .{
            .object = .{
                .type_tag = .regexp,
                .flags = value.Object.FROZEN_FLAG,
                .class = self.regexp_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .pattern = pattern_copy,
            .encoding = encoding,
            .options = options,
            .regex = result.regex.?,
        };
        return Value.fromObject(&regexp_obj.object);
    }

    pub fn newRegexp(self: *VM, pattern: []const u8, options: u16) VMError!Value {
        const normalized = self.normalizeRegexpEncoding(pattern, .{ .utf8 = .{} }, options);
        return self.newRegexpWithEncoding(pattern, normalized.options, normalized.encoding);
    }

    pub fn newMatchData(
        self: *VM,
        regexp_obj: *value.RegexpObject,
        source: *StringObject,
        captures: []const Value,
        begin_byte_offsets: []const i64,
        end_byte_offsets: []const i64,
    ) VMError!Value {
        if (captures.len != begin_byte_offsets.len or captures.len != end_byte_offsets.len) {
            return error.Fatal;
        }

        const md = self.gc_allocator.create(MatchDataObject) catch return error.Fatal;
        md.* = .{
            .object = .{
                .type_tag = .match_data,
                .flags = 0,
                .class = self.match_data_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .regexp = regexp_obj,
            .source = source,
            .captures = .empty,
            .begin_byte_offsets = .empty,
            .end_byte_offsets = .empty,
        };

        for (captures) |capture| {
            md.captures.append(self.gc_allocator, capture) catch return error.Fatal;
        }
        for (begin_byte_offsets) |pos| {
            md.begin_byte_offsets.append(self.gc_allocator, pos) catch return error.Fatal;
        }
        for (end_byte_offsets) |pos| {
            md.end_byte_offsets.append(self.gc_allocator, pos) catch return error.Fatal;
        }

        return Value.fromObject(&md.object);
    }

    pub fn setLastMatch(self: *VM, md: ?*MatchDataObject) VMError!void {
        if (md == null) {
            try self.setGlobal("$~", Value.nil());
            try self.setGlobal("$&", Value.nil());
            try self.setGlobal("$`", Value.nil());
            try self.setGlobal("$'", Value.nil());
            return;
        }

        const match_data = md.?;
        const match_val = Value.fromObject(&match_data.object);
        try self.setGlobal("$~", match_val);

        const full_capture = if (match_data.captures.items.len > 0)
            match_data.captures.items[0]
        else
            Value.nil();
        try self.setGlobal("$&", full_capture);

        const source_bytes = match_data.source.str;
        const source_encoding = match_data.source.encoding;
        const begin_idx = if (match_data.begin_byte_offsets.items.len > 0)
            match_data.begin_byte_offsets.items[0]
        else
            -1;
        const end_idx = if (match_data.end_byte_offsets.items.len > 0)
            match_data.end_byte_offsets.items[0]
        else
            -1;

        if (begin_idx < 0 or end_idx < 0) {
            try self.setGlobal("$`", Value.nil());
            try self.setGlobal("$'", Value.nil());
            return;
        }

        const begin_usize: usize = @intCast(begin_idx);
        const end_usize: usize = @intCast(end_idx);
        if (begin_usize > source_bytes.len or end_usize > source_bytes.len or begin_usize > end_usize) {
            return error.Fatal;
        }

        const pre = try self.newStringWithEncoding(source_bytes[0..begin_usize], false, source_encoding);
        const post = try self.newStringWithEncoding(source_bytes[end_usize..], false, source_encoding);
        try self.setGlobal("$`", pre);
        try self.setGlobal("$'", post);
    }

    pub fn clearLastMatch(self: *VM) VMError!void {
        try self.setLastMatch(null);
    }

    pub fn newObjectForClass(self: *VM, class_obj: *ClassObject) VMError!Value {
        if (self.isClassOrSubclassOf(class_obj, self.exception_class)) {
            const exc = try self.createException(class_obj, "");
            return Value.fromObject(&exc.object);
        }

        return switch (class_obj.object_type) {
            .string => self.newStringForClassWithEncoding(class_obj, "", false, .{ .ascii_8bit = .{} }),
            .array => blk: {
                const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
                array_obj.* = .{
                    .object = .{
                        .type_tag = .array,
                        .flags = 0,
                        .class = class_obj,
                        .singleton_class = null,
                        .instance_variables = null,
                    },
                    .elements = .empty,
                };
                break :blk Value.fromObject(&array_obj.object);
            },
            .hash => blk: {
                const hash_obj = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                hash_obj.* = .{
                    .object = .{
                        .type_tag = .hash,
                        .flags = 0,
                        .class = class_obj,
                        .singleton_class = null,
                        .instance_variables = null,
                    },
                    .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                    .entries = .empty,
                    .default_value = null,
                    .default_proc = null,
                    .compare_by_identity = false,
                };
                break :blk Value.fromObject(&hash_obj.object);
            },
            .range => self.newRange(class_obj),
            .fiber => try self.newFiber(class_obj, null),
            .io => try self.newIo(class_obj, -1, .{ .owns_fd = false, .readable = false, .writable = false }),
            .time => self.newTime(class_obj, 0),
            .instance => self.newInstance(class_obj),
        };
    }

    pub fn newBacktraceLocation(
        self: *VM,
        path: []const u8,
        lineno: u32,
        label: []const u8,
    ) VMError!Value {
        const location = try self.newObjectForClass(self.thread_backtrace_location_class);
        const path_value = try self.newString(path, false);
        const label_value = try self.newString(label, false);
        const rendered = std.fmt.allocPrint(
            self.gc_allocator,
            "{s}:{d}:in '{s}'",
            .{ path, lineno, label },
        ) catch return error.Fatal;
        const rendered_value = try self.newString(rendered, false);
        try self.setInstanceVariable(location, "@path", path_value);
        try self.setInstanceVariable(location, "@absolute_path", path_value);
        try self.setInstanceVariable(location, "@label", label_value);
        try self.setInstanceVariable(location, "@lineno", Value.integer(@intCast(lineno)));
        try self.setInstanceVariable(location, "@to_s", rendered_value);
        return location;
    }

    pub fn allocateDupShell(self: *VM, receiver: Value) VMError!Value {
        if (receiver.isClass()) {
            if (receiver.toClassObject() == self.basic_object_class) {
                return self.raiseExceptionFmt(self.type_error_class, "can't copy the root class", .{});
            }

            const anonymous = try self.intern("<anonymous>");
            const source = receiver.toClassObject();
            return self.newClassWithType(anonymous, source.superclass, source.object_type);
        }

        if (receiver.isModule()) {
            const anonymous = try self.intern("<anonymous>");
            return self.newModule(anonymous);
        }

        if (receiver.isBinding()) {
            const src = receiver.toBindingObject();
            const dup_ptr = self.gc_allocator.create(value.BindingObject) catch return error.Fatal;
            var names_copy: std.ArrayListUnmanaged([]const u8) = .empty;
            for (src.local_names.items) |name| {
                const duped = self.gc_allocator.dupe(u8, name) catch return error.Fatal;
                names_copy.append(self.gc_allocator, duped) catch return error.Fatal;
            }
            dup_ptr.* = value.BindingObject{
                .object = .{
                    .type_tag = .binding,
                    .flags = 0,
                    .class = self.binding_class,
                    .singleton_class = null,
                    .instance_variables = null,
                },
                .self_value = src.self_value,
                .ep = src.ep,
                .lexical_scope = src.lexical_scope,
                .local_names = names_copy,
                .real_local_count = src.real_local_count,
                .method_name = src.method_name,
            };
            return Value.fromObject(&dup_ptr.object);
        }

        return self.newObjectForClass(self.getClass(receiver));
    }

    pub fn getInstanceVariable(self: *VM, receiver: Value, name: []const u8) VMError!Value {
        const obj_ptr = receiver.getObjectPointer() orelse {
            return Value.nil();
        };

        if (obj_ptr.instance_variables) |*ivars| {
            const name_sym = try self.intern(name);
            if (ivars.get(name_sym)) |val| {
                return val;
            }
        }

        return Value.nil();
    }

    pub fn hasInstanceVariable(self: *VM, receiver: Value, name: []const u8) VMError!bool {
        const obj_ptr = receiver.getObjectPointer() orelse {
            return false;
        };

        if (obj_ptr.instance_variables) |*ivars| {
            const name_sym = try self.intern(name);
            return ivars.contains(name_sym);
        }

        return false;
    }

    pub fn getInstanceVariableNames(self: *VM, receiver: Value) VMError!*value.ArrayObject {
        const array = try self.createArray();
        const obj_ptr = receiver.getObjectPointer() orelse return array;
        const ivars = obj_ptr.instance_variables orelse return array;

        for (ivars.keys()) |name_sym| {
            array.elements.append(self.gc_allocator, Value.fromObject(&name_sym.object)) catch return error.Fatal;
        }
        return array;
    }

    pub fn setInstanceVariable(self: *VM, receiver: Value, name: []const u8, val: Value) VMError!void {
        const obj_ptr = receiver.getObjectPointer() orelse {
            return self.raiseExceptionFmt(self.frozen_error_class, "can't modify frozen {s}", .{self.className(receiver)});
        };

        if (receiver.isFrozen()) {
            return self.raiseExceptionFmt(self.frozen_error_class, "can't modify frozen {s}", .{self.className(receiver)});
        }

        if (obj_ptr.instance_variables == null) {
            obj_ptr.instance_variables = .{};
        }

        const name_sym = try self.intern(name);
        obj_ptr.instance_variables.?.put(self.gc_allocator, name_sym, val) catch return error.Fatal;
    }

    pub fn setGlobal(self: *VM, name: []const u8, val: Value) VMError!void {
        if (self.globals.getPtr(name)) |existing| {
            existing.* = val;
            return;
        }
        const owned_name = self.allocator.dupe(u8, name) catch return error.Fatal;
        self.globals.put(owned_name, val) catch return error.Fatal;
    }

    fn getBackrefCapture(self: *VM, capture_index: u16) Value {
        if (capture_index == 0) return Value.nil();
        const match_val = self.globals.get("$~") orelse return Value.nil();
        if (!match_val.isMatchData()) return Value.nil();
        const captures = match_val.toMatchDataObject().captures.items;
        const idx: usize = capture_index;
        if (idx >= captures.len) return Value.nil();
        return captures[idx];
    }

    fn processExited(wait_status: c_int) bool {
        return (wait_status & 0x7f) == 0;
    }

    fn processSignaled(wait_status: c_int) bool {
        const signal_bits = wait_status & 0x7f;
        return signal_bits != 0 and signal_bits != 0x7f;
    }

    pub fn setLastProcessStatus(self: *VM, exitstatus: i64) VMError!void {
        return self.setLastProcessStatusFromWaitStatus(@intCast((exitstatus & 0xff) << 8));
    }

    pub fn setLastProcessStatusFromWaitStatus(self: *VM, wait_status: c_int) VMError!void {
        const status_obj = try self.newInstance(self.process_status_class);
        try self.setInstanceVariable(status_obj, "@raw_status", Value.integer(wait_status));
        if (processExited(wait_status)) {
            try self.setInstanceVariable(status_obj, "@exitstatus", Value.integer((wait_status >> 8) & 0xff));
        }
        if (processSignaled(wait_status)) {
            try self.setInstanceVariable(status_obj, "@termsig", Value.integer(wait_status & 0x7f));
        }
        try self.setGlobal("$?", status_obj);
    }

    pub fn getOrCreateCanonicalFString(self: *VM, str: []const u8, encoding: enc.Encoding) VMError!Value {
        for (self.canonical_fstrings.items) |existing| {
            const existing_obj = existing.toStringObject();
            if (encodingKey(existing_obj.encoding) == encodingKey(encoding) and std.mem.eql(u8, existing_obj.str, str)) {
                return existing;
            }
        }

        const frozen = try self.newStringWithEncoding(str, true, encoding);
        self.canonical_fstrings.append(self.gc_allocator, frozen) catch return error.Fatal;
        return frozen;
    }

    pub fn getOrCreateCanonicalFStringValue(self: *VM, string_value: Value) VMError!Value {
        const string_obj = string_value.toStringObject();
        for (self.canonical_fstrings.items) |existing| {
            const existing_obj = existing.toStringObject();
            if (encodingKey(existing_obj.encoding) == encodingKey(string_obj.encoding) and std.mem.eql(u8, existing_obj.str, string_obj.str)) {
                return existing;
            }
        }

        self.canonical_fstrings.append(self.gc_allocator, string_value) catch return error.Fatal;
        return string_value;
    }

    pub fn isCanonicalFStringValue(self: *VM, string_value: Value) bool {
        if (!string_value.isString()) return false;
        for (self.canonical_fstrings.items) |existing| {
            if (existing.raw == string_value.raw) return true;
        }
        return false;
    }

    fn getOrCreateFrozenStringLiteral(self: *VM, str: []const u8) VMError!Value {
        if (self.fstring_cache.get(str)) |cached| {
            return cached;
        }

        const frozen = try self.newString(str, true);
        const key = self.allocator.dupe(u8, str) catch return error.Fatal;
        self.fstring_cache.put(key, frozen) catch return error.Fatal;
        return frozen;
    }

    pub fn newString(self: *VM, str: []const u8, frozen: bool) VMError!Value {
        return self.newStringWithEncoding(str, frozen, .{ .utf8 = .{} });
    }

    fn literalStringEncodingForChunk(source_encoding: enc.Encoding, bytes: []const u8) enc.Encoding {
        if (enc.isAsciiOnly(bytes)) {
            return source_encoding;
        }
        if (source_encoding == .ascii_8bit) {
            return .{ .ascii_8bit = .{} };
        }
        if (source_encoding == .us_ascii) {
            const utf8_encoding = enc.Encoding{ .utf8 = .{} };
            if (utf8_encoding.isValid(bytes)) {
                return .{ .utf8 = .{} };
            }
            return .{ .ascii_8bit = .{} };
        }
        return source_encoding;
    }

    fn resolveInterpolatedStringEncoding(
        lhs_encoding: enc.Encoding,
        lhs_bytes: []const u8,
        rhs_encoding: enc.Encoding,
        rhs_bytes: []const u8,
    ) ?enc.Encoding {
        if (lhs_encoding.eql(rhs_encoding)) return lhs_encoding;

        if (rhs_bytes.len == 0) return lhs_encoding;
        if (lhs_bytes.len == 0) return rhs_encoding;

        if (!lhs_encoding.isAsciiCompatible() or !rhs_encoding.isAsciiCompatible()) return null;

        const lhs_ascii_only = enc.isAsciiOnly(lhs_bytes);
        const rhs_ascii_only = enc.isAsciiOnly(rhs_bytes);

        if (lhs_ascii_only and !rhs_ascii_only) return rhs_encoding;
        if (!lhs_ascii_only and rhs_ascii_only) return lhs_encoding;
        if (lhs_ascii_only and rhs_ascii_only) return lhs_encoding;

        return null;
    }

    fn literalSymbolEncodingForChunk(source_encoding: enc.Encoding, bytes: []const u8) enc.Encoding {
        if (enc.isAsciiOnly(bytes)) {
            return .{ .us_ascii = .{} };
        }
        return literalStringEncodingForChunk(source_encoding, bytes);
    }

    pub fn newFloat(self: *VM, f: f64) VMError!Value {
        const float_obj = self.gc_allocator.create(value.FloatObject) catch return error.Fatal;
        float_obj.* = .{
            .object = .{ .type_tag = .float, .flags = 0, .class = self.float_class, .singleton_class = null, .instance_variables = null },
            .val = f,
        };
        return Value.fromObject(&float_obj.object);
    }

    fn gcdIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
        if (lhs.isInteger() and rhs.isInteger()) {
            var a = lhs.toInteger();
            var b = rhs.toInteger();
            if (a < 0) a = -a;
            if (b < 0) b = -b;
            while (b != 0) {
                const temp = b;
                b = @mod(a, b);
                a = temp;
            }
            return Value.integer(a);
        }

        var a = try lhs.integerToManaged(self);
        defer a.deinit();
        if (!a.isPositive()) a.negate();
        var b = try rhs.integerToManaged(self);
        defer b.deinit();
        if (!b.isPositive()) b.negate();

        var quot = BigInt.init(self.allocator) catch return error.Fatal;
        defer quot.deinit();
        var rem = BigInt.init(self.allocator) catch return error.Fatal;
        defer rem.deinit();
        while (!b.eqlZero()) {
            quot.divTrunc(&rem, &a, &b) catch return error.Fatal;
            a.swap(&b);
            b.swap(&rem);
        }

        return self.valueFromManagedInteger(&a);
    }
    pub fn newRationalValues(self: *VM, numerator: Value, denominator: Value) VMError!Value {
        try numerator.ensureInteger(self);
        try denominator.ensureInteger(self);

        const zero = Value.integer(0);
        const one = Value.integer(1);
        const negative_one = Value.integer(-1);

        if ((try self.compareIntegerValues(denominator, zero)) == .eq) {
            return self.raiseExceptionFmt(self.zero_division_error_class, "divided by 0", .{});
        }

        var num = numerator;
        var den = denominator;

        if ((try self.compareIntegerValues(den, zero)) == .lt) {
            num = try self.mulIntegerValues(negative_one, num);
            den = try self.mulIntegerValues(negative_one, den);
        }

        if ((try self.compareIntegerValues(num, zero)) == .eq) {
            den = one;
        } else {
            const abs_num = if ((try self.compareIntegerValues(num, zero)) == .lt)
                try self.mulIntegerValues(negative_one, num)
            else
                num;
            const gcd = try gcdIntegerValues(self, abs_num, den);
            if ((try self.compareIntegerValues(gcd, one)) != .eq) {
                num = try self.divTruncIntegerValues(num, gcd);
                den = try self.divTruncIntegerValues(den, gcd);
            }
        }

        const rational_obj = self.gc_allocator.create(value.RationalObject) catch return error.Fatal;
        rational_obj.* = .{
            .object = .{ .type_tag = .rational, .flags = value.Object.FROZEN_FLAG, .class = self.rational_class, .singleton_class = null, .instance_variables = null },
            .numerator = num,
            .denominator = den,
        };
        return Value.fromObject(&rational_obj.object);
    }

    pub fn newRational(self: *VM, numerator: i64, denominator: i64) VMError!Value {
        return self.newRationalValues(Value.integer(numerator), Value.integer(denominator));
    }

    pub fn newTime(self: *VM, class_obj: *ClassObject, epoch_nanoseconds: i64) VMError!Value {
        const time_obj = self.gc_allocator.create(value.TimeObject) catch return error.Fatal;
        time_obj.* = .{
            .object = .{ .type_tag = .time, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .epoch_nanoseconds = epoch_nanoseconds,
            .utc_offset_nanos = 0,
            .is_utc = true,
            .is_local = false,
        };
        return Value.fromObject(&time_obj.object);
    }

    pub fn newTimeWithOffset(self: *VM, class_obj: *ClassObject, epoch_nanoseconds: i64, utc_offset_nanos: i64) VMError!Value {
        const time_obj = self.gc_allocator.create(value.TimeObject) catch return error.Fatal;
        time_obj.* = .{
            .object = .{ .type_tag = .time, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .epoch_nanoseconds = epoch_nanoseconds,
            .utc_offset_nanos = utc_offset_nanos,
            .is_utc = false,
            .is_local = false,
        };
        return Value.fromObject(&time_obj.object);
    }

    pub fn newTimeLocal(self: *VM, class_obj: *ClassObject, epoch_nanoseconds: i64, utc_offset_nanos: i64) VMError!Value {
        const time_obj = self.gc_allocator.create(value.TimeObject) catch return error.Fatal;
        time_obj.* = .{
            .object = .{ .type_tag = .time, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .epoch_nanoseconds = epoch_nanoseconds,
            .utc_offset_nanos = utc_offset_nanos,
            .is_utc = false,
            .is_local = true,
        };
        return Value.fromObject(&time_obj.object);
    }

    pub fn newBigIntegerFromI64(self: *VM, n: i64) VMError!Value {
        const managed = std.math.big.int.Managed.initSet(self.gc_allocator, n) catch return error.Fatal;
        const big_obj = self.gc_allocator.create(BigIntegerObject) catch return error.Fatal;
        big_obj.* = .{
            .object = .{ .type_tag = .big_integer, .flags = 0, .class = self.integer_class, .singleton_class = null, .instance_variables = null },
            .value = managed,
        };
        return Value.fromObject(&big_obj.object);
    }

    pub fn newBigIntegerFromDecimalString(self: *VM, digits: []const u8) VMError!Value {
        var managed = std.math.big.int.Managed.init(self.gc_allocator) catch return error.Fatal;
        managed.setString(10, digits) catch return error.Fatal;

        if (managed.toInt(i64)) |small| {
            return Value.integer(small);
        } else |_| {}

        const big_obj = self.gc_allocator.create(BigIntegerObject) catch return error.Fatal;
        big_obj.* = .{
            .object = .{ .type_tag = .big_integer, .flags = 0, .class = self.integer_class, .singleton_class = null, .instance_variables = null },
            .value = managed,
        };
        return Value.fromObject(&big_obj.object);
    }

    pub fn valueFromManagedInteger(self: *VM, managed: *const std.math.big.int.Managed) VMError!Value {
        if (managed.toInt(i63)) |small| {
            return Value.integer(@as(i64, small));
        } else |_| {}

        const stored = managed.cloneWithDifferentAllocator(self.gc_allocator) catch return error.Fatal;
        const big_obj = self.gc_allocator.create(BigIntegerObject) catch return error.Fatal;
        big_obj.* = .{
            .object = .{ .type_tag = .big_integer, .flags = 0, .class = self.integer_class, .singleton_class = null, .instance_variables = null },
            .value = stored,
        };
        return Value.fromObject(&big_obj.object);
    }

    pub fn registerPackedPointerTarget(self: *VM, packed_str: *StringObject, offset: usize, target: *StringObject) VMError!void {
        if (self.packed_pointer_targets.getPtr(packed_str)) |targets| {
            targets.put(offset, target) catch return error.Fatal;
            return;
        }

        var targets = PackedPointerTargets.init(self.gc_allocator);
        errdefer targets.deinit();
        targets.put(offset, target) catch return error.Fatal;
        self.packed_pointer_targets.put(packed_str, targets) catch return error.Fatal;
    }

    pub fn packedPointerTargetAt(self: *VM, packed_str: *StringObject, offset: usize) ?*StringObject {
        const targets = self.packed_pointer_targets.get(packed_str) orelse return null;
        return targets.get(offset);
    }

    pub fn copyPackedPointerTargets(self: *VM, from: *StringObject, to: *StringObject) VMError!void {
        const src_targets = self.packed_pointer_targets.get(from) orelse return;
        var copied = PackedPointerTargets.init(self.gc_allocator);
        errdefer copied.deinit();

        var it = src_targets.iterator();
        while (it.next()) |entry| {
            copied.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }
        self.packed_pointer_targets.put(to, copied) catch return error.Fatal;
    }

    pub fn newStringWithEncoding(self: *VM, str: []const u8, frozen: bool, encoding: enc.Encoding) VMError!Value {
        return self.newStringForClassWithEncoding(self.string_class, str, frozen, encoding);
    }

    pub fn newStringForClass(self: *VM, class_obj: *ClassObject, str: []const u8, frozen: bool) VMError!Value {
        return self.newStringForClassWithEncoding(class_obj, str, frozen, .{ .utf8 = .{} });
    }

    pub fn newStringForClassWithEncoding(self: *VM, class_obj: *ClassObject, str: []const u8, frozen: bool, encoding: enc.Encoding) VMError!Value {
        const copy = self.gc_allocator_atomic.dupe(u8, str) catch return error.Fatal;
        const flags: u32 = if (frozen) Object.FROZEN_FLAG else 0;

        const string_obj = self.gc_allocator.create(StringObject) catch return error.Fatal;
        string_obj.* = .{
            .object = .{ .type_tag = .string, .flags = flags, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .str = copy,
            .encoding = encoding,
        };
        return Value.fromObject(&string_obj.object);
    }

    pub fn inspectTargetEncoding(self: *VM) enc.Encoding {
        return inspect_util.targetEncoding(
            if (self.default_internal_encoding) |encoding_obj| encoding_obj.encoding else null,
            self.default_external_encoding.encoding,
        );
    }

    pub fn encodingToValue(self: *VM, encoding_value: enc.Encoding) Value {
        return switch (encoding_value) {
            .utf8 => Value.fromObject(&self.encoding_utf8.object),
            .cesu8 => Value.fromObject(&self.encoding_cesu8.object),
            .ascii_8bit => Value.fromObject(&self.encoding_ascii_8bit.object),
            .us_ascii => Value.fromObject(&self.encoding_us_ascii.object),
            .shift_jis => Value.fromObject(&self.encoding_shift_jis.object),
            .windows_31j => Value.fromObject(&self.encoding_windows_31j.object),
            .euc_jp => Value.fromObject(&self.encoding_euc_jp.object),
            .cp437 => Value.fromObject(&self.encoding_cp437.object),
            .iso_2022_jp => Value.fromObject(&self.encoding_iso_2022_jp.object),
            .iso_8859_1 => Value.fromObject(&self.encoding_iso_8859_1.object),
            .iso_8859_9 => Value.fromObject(&self.encoding_iso_8859_9.object),
            .iso_8859_15 => Value.fromObject(&self.encoding_iso_8859_15.object),
            .utf7 => Value.fromObject(&self.encoding_utf7.object),
            .utf16 => Value.fromObject(&self.encoding_utf16.object),
            .utf32 => Value.fromObject(&self.encoding_utf32.object),
            .utf16le => Value.fromObject(&self.encoding_utf16le.object),
            .utf16be => Value.fromObject(&self.encoding_utf16be.object),
            .utf32le => Value.fromObject(&self.encoding_utf32le.object),
            .utf32be => Value.fromObject(&self.encoding_utf32be.object),
        };
    }

    fn createEncodingObject(self: *VM, encoding: enc.Encoding) VMError!*value.EncodingObject {
        const encoding_obj = self.gc_allocator.create(value.EncodingObject) catch return error.Fatal;
        encoding_obj.* = .{
            .object = .{
                .type_tag = .encoding_obj,
                .flags = Object.FROZEN_FLAG, // Encoding objects are frozen singletons
                .class = self.encoding_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .encoding = encoding,
        };
        return encoding_obj;
    }

    pub fn newProc(self: *VM, block: Block) VMError!Value {
        const proc_obj = self.gc_allocator.create(value.ProcObject) catch return error.Fatal;
        proc_obj.* = .{
            .object = .{ .type_tag = .proc, .flags = 0, .class = self.proc_class, .singleton_class = null, .instance_variables = null },
            .block = switch (block.kind) {
                .receiver_builtin => block,
                .symbol => block,
                .builtin => block,
                .callable => block,
                .chunk => |chunk_blk| .{ .kind = .{ .chunk = .{
                    .chunk = chunk_blk.chunk,
                    .defining_ep = self.promoteFrameToHeap(chunk_blk.defining_ep) catch return error.Fatal,
                    .defining_self = chunk_blk.defining_self,
                    .return_target_ep = if (chunk_blk.return_target_ep) |target_ep|
                        self.promoteFrameToHeap(target_ep) catch return error.Fatal
                    else
                        null,
                    .enclosing_block_proc = chunk_blk.enclosing_block_proc,
                } } },
            },
        };
        return Value.fromObject(&proc_obj.object);
    }

    pub fn procValueForBlock(self: *VM, block: Block) VMError!Value {
        if (block.source_proc) |proc_obj| {
            return Value.fromObject(&proc_obj.object);
        }
        return self.newProc(block);
    }

    pub fn newEnumerator(
        self: *VM,
        kind: value.EnumeratorObject.Kind,
        method_args: ?*value.ArrayObject,
        size: ?Value,
        size_fn: ?value.EnumeratorObject.SizeFn,
    ) VMError!Value {
        const enum_obj = self.gc_allocator.create(value.EnumeratorObject) catch return error.Fatal;
        enum_obj.* = .{
            .object = .{ .type_tag = .enumerator, .flags = 0, .class = self.enumerator_class, .singleton_class = null, .instance_variables = null },
            .kind = kind,
            .method_args = method_args,
            .size = size,
            .size_fn = size_fn,
            .fiber = null,
            .lookahead_values = null,
            .has_lookahead_values = false,
        };
        return Value.fromObject(&enum_obj.object);
    }

    pub fn newYielder(self: *VM, block: Block) VMError!Value {
        const yielder_obj = self.gc_allocator.create(value.YielderObject) catch return error.Fatal;
        yielder_obj.* = .{
            .object = .{ .type_tag = .yielder, .flags = 0, .class = self.yielder_class, .singleton_class = null, .instance_variables = null },
            .block = block,
        };
        return Value.fromObject(&yielder_obj.object);
    }

    pub fn createMethodEnumerator(self: *VM, receiver: Value, method_name: *SymbolObject, args: []const Value) VMError!Value {
        return self.createMethodEnumeratorWithSizeAndCallback(receiver, method_name, args, null, null);
    }

    pub fn createMethodEnumeratorWithSize(
        self: *VM,
        receiver: Value,
        method_name: *SymbolObject,
        args: []const Value,
        size: ?Value,
    ) VMError!Value {
        return self.createMethodEnumeratorWithSizeAndCallback(receiver, method_name, args, size, null);
    }

    pub fn createMethodEnumeratorWithSizeFn(
        self: *VM,
        receiver: Value,
        method_name: *SymbolObject,
        args: []const Value,
        size_fn: ?value.EnumeratorObject.SizeFn,
    ) VMError!Value {
        return self.createMethodEnumeratorWithSizeAndCallback(receiver, method_name, args, null, size_fn);
    }

    fn createMethodEnumeratorWithSizeAndCallback(
        self: *VM,
        receiver: Value,
        method_name: *SymbolObject,
        args: []const Value,
        size: ?Value,
        size_fn: ?value.EnumeratorObject.SizeFn,
    ) VMError!Value {
        var method_args: ?*value.ArrayObject = null;
        if (args.len > 0) {
            const arr = try self.createArray();
            for (args) |arg| {
                arr.elements.append(self.gc_allocator, arg) catch return error.Fatal;
            }
            method_args = arr;
        }
        return self.newEnumerator(.{ .method = .{ .receiver = receiver, .method_name = method_name } }, method_args, size, size_fn);
    }

    fn moduleAffectsInteger(self: *VM, module: *value.ModuleObject) bool {
        if (module == &self.integer_class.module) return true;
        for (self.integer_class.module.prepended_modules.items) |prepended| {
            if (prepended == module) return true;
        }
        for (self.integer_class.module.included_modules.items) |included| {
            if (included == module) return true;
        }
        return false;
    }

    pub fn markIntegerChangedForReceiver(self: *VM, receiver: Value) void {
        if (receiver.isClass()) {
            const klass = receiver.toClassObject();
            if (klass == self.integer_class or self.moduleAffectsInteger(&klass.module)) {
                self.integer_changed = true;
            }
        } else if (receiver.isModule()) {
            const module = receiver.toModuleObject();
            if (self.moduleAffectsInteger(module)) {
                self.integer_changed = true;
            }
        }
    }

    pub fn includeModule(self: *VM, target: *value.ModuleObject, module: *value.ModuleObject) VMError!void {
        target.included_modules.append(self.gc_allocator, module) catch return error.Fatal;
        if (target == &self.integer_class.module) {
            self.integer_changed = true;
        }
        self.bumpMethodStateVersion();
    }

    pub fn prependModule(self: *VM, target: *value.ModuleObject, module: *value.ModuleObject) VMError!void {
        target.prepended_modules.append(self.gc_allocator, module) catch return error.Fatal;
        if (target == &self.integer_class.module) {
            self.integer_changed = true;
        }
        self.bumpMethodStateVersion();
    }

    pub fn requireArgCount(self: *VM, args: []Value, expected: usize) VMError!void {
        if (args.len != expected) {
            return self.raiseArgumentErrorWrongArgCount(args.len, expected);
        }
    }

    pub fn requireArgCountRange(self: *VM, args: []Value, min: usize, max: usize) VMError!void {
        if (args.len < min or args.len > max) {
            return self.raiseArgumentErrorWrongArgCountRange(args.len, min, max);
        }
    }

    pub fn requireMinArgCount(self: *VM, args: []const Value, min: usize) VMError!void {
        if (args.len < min) {
            return self.raiseArgumentErrorWrongArgCountAtLeast(args.len, min);
        }
    }

    const AccessorKind = enum { reader, writer };

    pub fn createAccessorChunk(self: *VM, base_name: []const u8, kind: AccessorKind) VMError!*Chunk {
        if (self.next_chunk_id > chunk.MAX_CHUNK_ID) {
            std.debug.print("Too many chunks\n", .{});
            return error.Fatal;
        }

        const allocator = self.program.allocator;
        const method_name = if (kind == .reader)
            self.gc_allocator_atomic.dupe(u8, base_name) catch return error.Fatal
        else
            std.fmt.allocPrint(self.gc_allocator_atomic, "{s}=", .{base_name}) catch return error.Fatal;
        const ivar_name = std.fmt.allocPrint(self.gc_allocator_atomic, "@{s}", .{base_name}) catch return error.Fatal;

        const chunk_ptr = allocator.create(Chunk) catch return error.Fatal;
        chunk_ptr.* = Chunk.init(allocator, method_name);
        chunk_ptr.chunk_id = self.next_chunk_id;
        self.next_chunk_id += 1;
        const source_file = blk: {
            if (self.currentRubyCallerFrame()) |frame| {
                if (frame.chunk.source_file) |path| break :blk path;
            }
            break :blk self.current_loading_file orelse self.program.main_chunk.source_file;
        };
        chunk_ptr.setSourceFile(source_file) catch return error.Fatal;
        chunk_ptr.lexical_scope = self.current_lexical_scope;
        chunk_ptr.arity = if (kind == .reader) 0 else 1;
        chunk_ptr.locals_count = if (kind == .reader) 0 else 1;

        const name_idx = chunk_ptr.addConstant(.{ .string = ivar_name }) catch return error.Fatal;

        switch (kind) {
            .reader => {
                chunk_ptr.emitOpU16(.GET_IVAR, @intCast(name_idx), 0) catch return error.Fatal;
                chunk_ptr.emitOpU8(.RETURN, 0, 0) catch return error.Fatal;
            },
            .writer => {
                // Emit GET_LOCAL with local_idx=0 (will be patched to ep_offset by patchEpOffsets)
                chunk_ptr.emitOpU16(.GET_LOCAL, 0, 0) catch return error.Fatal;
                chunk_ptr.emitOpU16(.SET_IVAR, @intCast(name_idx), 0) catch return error.Fatal;
                chunk_ptr.emitOpU8(.RETURN, 0, 0) catch return error.Fatal;
                chunk_ptr.patchEpOffsets(null);
            },
        }

        try self.buildChunkCallsiteDescriptors(chunk_ptr);
        self.program.child_chunks.put(chunk_ptr.chunk_id.?, chunk_ptr) catch return error.Fatal;
        return chunk_ptr;
    }

    pub fn requireArgType(
        self: *VM,
        args: []Value,
        index: usize,
        comptime expected_tag: value.ObjectTypeTag,
        comptime type_name: []const u8,
    ) VMError!void {
        const arg = args[index];
        const matches = switch (expected_tag) {
            .instance => arg.isInstance(),
            .binding => arg.isBinding(),
            .string => arg.isString(),
            .symbol => arg.isSymbol(),
            .array => arg.isArray(),
            .hash => arg.isHash(),
            .range => arg.isRange(),
            .exception => arg.isException(),
            .proc => arg.isProc(),
            .fiber => arg.isFiber(),
            .io => arg.isIo(),
            .regexp => arg.isRegexp(),
            .match_data => arg.isMatchData(),
            .big_integer => arg.isBigInteger(),
            .encoding_obj => arg.isEncoding(),
            .enumerator => arg.isEnumerator(),
            .yielder => arg.isYielder(),
            .module => arg.isModule(),
            .class => arg.isClass(),
            .float => arg.isFloat(),
            .rational => arg.isRational(),
            .thread => arg.isThread(),
            .mutex => arg.isMutex(),
            .condition_variable => arg.isConditionVariable(),
            .queue => arg.isQueue(),
            .time => arg.isTime(),
            .method => arg.isMethodObject(),
            .unbound_method => arg.isUnboundMethodObject(),
        };
        if (!matches) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "argument is not {s} {s}",
                .{ if (type_name[0] == 'A' or type_name[0] == 'I' or type_name[0] == 'O') "an" else "a", type_name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.type_error_class, msg);
            self.setPendingException(exc);
            return error.Unwind;
        }
    }

    pub fn requireIntegerArg(
        self: *VM,
        args: []Value,
        index: usize,
        comptime type_name: []const u8,
    ) VMError!void {
        if (!args[index].isInteger()) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "argument is not {s} {s}",
                .{ if (type_name[0] == 'A' or type_name[0] == 'I' or type_name[0] == 'O') "an" else "a", type_name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.type_error_class, msg);
            self.setPendingException(exc);
            return error.Unwind;
        }
    }

    pub fn requireSingleArg(
        self: *VM,
        args: []Value,
        comptime arg_tag: value.ObjectTypeTag,
        comptime type_name: []const u8,
    ) VMError!void {
        try self.requireArgCount(args, 1);
        try self.requireArgType(args, 0, arg_tag, type_name);
    }

    pub const ToAryResult = union(enum) {
        array: Value,
        missing,
        nil_result,
    };

    pub const ToHashResult = union(enum) {
        hash: Value,
        missing,
        nil_result,
        non_hash: Value,
    };

    pub const ToStringResult = union(enum) {
        string: Value,
        missing,
        nil_result,
    };

    pub fn probeToStringValue(self: *VM, arg: Value) VMError!ToStringResult {
        if (arg.isString()) return .{ .string = arg };

        const maybe_string = try self.checkCallMethodByName(arg, "to_str", false, &[_]Value{}, null);
        const coerced = maybe_string orelse return .missing;
        if (coerced.isNil()) return .nil_result;
        if (coerced.isString()) return .{ .string = coerced };

        return self.raiseExceptionFmt(
            self.type_error_class,
            "can't convert {s} to String ({s}#to_str gives {s})",
            .{ self.className(arg), self.className(arg), self.className(coerced) },
        );
    }

    pub fn probeToAryWithVisibility(self: *VM, arg: Value, include_private: bool) VMError!ToAryResult {
        if (arg.isArray()) return .{ .array = arg };

        const maybe_array = try self.checkCallMethodByName(arg, "to_ary", include_private, &[_]Value{}, null);
        const coerced = maybe_array orelse return .missing;
        if (coerced.isNil()) return .nil_result;
        if (coerced.isArray()) return .{ .array = coerced };

        return self.raiseExceptionFmt(
            self.type_error_class,
            "can't convert {s} to Array ({s}#to_ary gives {s})",
            .{ self.className(arg), self.className(arg), self.className(coerced) },
        );
    }

    pub fn probeToAry(self: *VM, arg: Value) VMError!ToAryResult {
        return self.probeToAryWithVisibility(arg, true);
    }

    pub fn probeToHash(self: *VM, arg: Value) VMError!ToHashResult {
        if (arg.isHash()) return .{ .hash = arg };

        const maybe_hash = try self.checkCallMethodByName(arg, "to_hash", false, &[_]Value{}, null);
        const coerced = maybe_hash orelse return .missing;
        if (coerced.isNil()) return .nil_result;
        if (coerced.isHash()) return .{ .hash = coerced };
        return .{ .non_hash = coerced };
    }

    pub fn coerceToHashValue(self: *VM, arg: Value) VMError!Value {
        return switch (try self.probeToHash(arg)) {
            .hash => |hash| hash,
            .missing => self.raiseExceptionFmt(
                self.type_error_class,
                "can't convert {s} into Hash",
                .{self.className(arg)},
            ),
            .nil_result => self.raiseExceptionFmt(
                self.type_error_class,
                "can't convert {s} to Hash ({s}#to_hash gives NilClass)",
                .{ self.className(arg), self.className(arg) },
            ),
            .non_hash => |coerced| self.raiseExceptionFmt(
                self.type_error_class,
                "can't convert {s} to Hash ({s}#to_hash gives {s})",
                .{ self.className(arg), self.className(arg), self.className(coerced) },
            ),
        };
    }

    pub fn coerceToArrayValue(self: *VM, arg: Value) VMError!Value {
        return switch (try self.probeToAry(arg)) {
            .array => |array| array,
            .missing => self.raiseExceptionFmt(
                self.type_error_class,
                "no implicit conversion of {s} into Array",
                .{self.className(arg)},
            ),
            .nil_result => self.raiseExceptionFmt(
                self.type_error_class,
                "can't convert {s} to Array ({s}#to_ary gives NilClass)",
                .{ self.className(arg), self.className(arg) },
            ),
        };
    }

    pub fn expandSplatValue(self: *VM, arg: Value) VMError!Value {
        if (arg.isArray()) return arg;
        if (arg.isNil()) {
            const empty = try self.createArray();
            return Value.fromObject(&empty.object);
        }

        if (try self.checkCallMethodByName(arg, "to_a", false, &[_]Value{}, null)) |coerced| {
            if (coerced.isNil()) {
                const wrapped = try self.createArray();
                wrapped.elements.append(self.gc_allocator, arg) catch return error.Fatal;
                return Value.fromObject(&wrapped.object);
            }
            if (coerced.isArray()) return coerced;

            return self.raiseExceptionFmt(
                self.type_error_class,
                "can't convert {s} to Array ({s}#to_a gives {s})",
                .{ self.className(arg), self.className(arg), self.className(coerced) },
            );
        }

        const wrapped = try self.createArray();
        wrapped.elements.append(self.gc_allocator, arg) catch return error.Fatal;
        return Value.fromObject(&wrapped.object);
    }

    pub fn coerceToPath(self: *VM, arg: Value, type_error_message: []const u8) VMError![]const u8 {
        const path_value = try self.coerceToPathValue(arg, type_error_message);
        return path_value.toStringObject().str;
    }

    pub fn coerceToPathValue(self: *VM, arg: Value, type_error_message: []const u8) VMError!Value {
        const maybe_candidate = try self.checkCallMethodByName(arg, "to_path", false, &[_]Value{}, null);
        const candidate = maybe_candidate orelse arg;

        const path_value = try candidate.coerceToStringValue(self, type_error_message);
        const path_string = path_value.toStringObject();
        if (!path_string.encoding.isAsciiCompatible()) {
            return self.raiseEncodingCompatibilityError(.{ .utf8 = .{} }, path_string.encoding);
        }
        if (std.mem.indexOfScalar(u8, path_string.str, 0) != null) {
            return self.raiseExceptionFmt(self.argument_error_class, "path name contains null byte", .{});
        }
        return path_value;
    }

    pub fn coerceToMethodNameString(self: *VM, arg: Value) VMError![]const u8 {
        if (arg.isSymbol()) return arg.toSymbolObject().name;
        return arg.coerceToStr(self, "is not a symbol nor a string");
    }

    pub fn coerceToMethodNameSymbol(self: *VM, arg: Value) VMError!*SymbolObject {
        const name_str = try self.coerceToMethodNameString(arg);
        return self.intern(name_str);
    }

    fn isValidIvarName(name: []const u8) bool {
        if (name.len < 2) return false;
        if (name[0] != '@') return false;
        if (name[1] == '@') return false;
        if (std.ascii.isDigit(name[1])) return false;
        return true;
    }

    pub fn coerceToIvarName(self: *VM, arg: Value) VMError![]const u8 {
        const name_str = if (arg.isSymbol())
            arg.toSymbolObject().name
        else
            try arg.coerceToStr(self, "is not a symbol nor a string");

        if (!isValidIvarName(name_str)) {
            return self.raiseExceptionFmt(
                self.name_error_class,
                "'{s}' is not allowed as an instance variable name",
                .{name_str},
            );
        }

        return name_str;
    }

    pub fn raiseExceptionFmt(
        self: *VM,
        exception_class: *value.ClassObject,
        comptime fmt: []const u8,
        args: anytype,
    ) VMError {
        const msg = std.fmt.allocPrint(self.gc_allocator, fmt, args) catch return error.Fatal;
        const exc = self.createException(exception_class, msg) catch return error.Fatal;
        self.setPendingException(exc);
        return error.Unwind;
    }

    pub fn errnoClass(self: *VM, errno_number: c_int) *value.ClassObject {
        return self.errno_classes.get(errno_number) orelse self.system_call_error_class;
    }

    pub fn errnoNumberForClass(self: *VM, class_obj: *value.ClassObject) ?c_int {
        var it = self.errno_classes.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == class_obj) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn defaultExceptionMessageForClass(self: *VM, class_obj: *value.ClassObject) []const u8 {
        if (self.isClassOrSubclassOf(class_obj, self.system_call_error_class)) {
            if (self.errnoNumberForClass(class_obj)) |errno_number| {
                return std.mem.span(strerror(errno_number));
            }
        }
        return class_obj.module.name.name;
    }

    pub fn raiseErrnoFmt(self: *VM, errno_code: std.posix.E, comptime fmt: []const u8, args: anytype) VMError {
        return self.raiseExceptionFmt(self.errnoClass(@intCast(@intFromEnum(errno_code))), fmt, args);
    }

    pub fn raiseLastErrnoFmt(self: *VM, comptime fmt: []const u8, args: anytype) VMError {
        return self.raiseExceptionFmt(self.errnoClass(std.c._errno().*), fmt, args);
    }

    pub fn raiseArgumentErrorWrongArgCount(self: *VM, given: usize, expected: usize) VMError {
        return self.raiseExceptionFmt(
            self.argument_error_class,
            "wrong number of arguments (given {d}, expected {d})",
            .{ given, expected },
        );
    }

    pub fn raiseArgumentErrorWrongArgCountRange(self: *VM, given: usize, min: usize, max: usize) VMError {
        return self.raiseExceptionFmt(
            self.argument_error_class,
            "wrong number of arguments (given {d}, expected {d}..{d})",
            .{ given, min, max },
        );
    }

    pub fn raiseArgumentErrorWrongArgCountAtLeast(self: *VM, given: usize, min: usize) VMError {
        return self.raiseExceptionFmt(
            self.argument_error_class,
            "wrong number of arguments (given {d}, expected {d}+)",
            .{ given, min },
        );
    }

    pub fn requireArgCountAtLeast(self: *VM, args: []const Value, min: usize) VMError!void {
        if (args.len < min) {
            return self.raiseArgumentErrorWrongArgCountAtLeast(args.len, min);
        }
    }

    pub fn raiseArgumentErrorWrongArgCountGeneric(self: *VM) VMError {
        return self.raiseExceptionFmt(self.argument_error_class, "wrong number of arguments", .{});
    }

    pub fn raiseEncodingCompatibilityError(self: *VM, lhs: enc.Encoding, rhs: enc.Encoding) VMError {
        return self.raiseExceptionFmt(
            self.encoding_compatibility_error_class,
            "incompatible character encodings: {s} and {s}",
            .{ lhs.name(), rhs.name() },
        );
    }

    pub fn raiseFromArgs(self: *VM, args: []const Value, no_current_exception_message: []const u8) VMError {
        if (args.len == 0) {
            if (self.rescued_exceptions.items.len > 0) {
                self.setPendingException(self.rescued_exceptions.items[self.rescued_exceptions.items.len - 1]);
                return error.Unwind;
            }
            if (self.pendingException()) |exc| {
                self.setPendingException(exc);
                return error.Unwind;
            }
            return self.raiseExceptionFmt(self.runtime_error_class, "{s}", .{no_current_exception_message});
        }

        if (args.len == 1) {
            if (args[0].isException()) {
                self.setPendingException(args[0].toExceptionObject());
                return error.Unwind;
            } else if (args[0].isClass()) {
                const class_obj = args[0].toClassObject();
                if (self.isClassOrSubclassOf(class_obj, self.exception_class)) {
                    const exc_val = try self.newExceptionInstance(class_obj, &[_]Value{}, null);
                    self.setPendingException(exc_val.toExceptionObject());
                    return error.Unwind;
                }
                const exc = self.createException(class_obj, "") catch return error.Fatal;
                self.setPendingException(exc);
                return error.Unwind;
            } else if (args[0].isString()) {
                const exc = self.createException(self.runtime_error_class, args[0].toStringObject().str) catch return error.Fatal;
                self.setPendingException(exc);
                return error.Unwind;
            } else {
                return self.raiseExceptionFmt(self.type_error_class, "exception class/object expected", .{});
            }
        }

        if (args.len == 2) {
            if (args[0].isException()) {
                const class_obj = args[0].toExceptionObject().object.class orelse return error.Fatal;
                const exc_val = try self.newExceptionInstance(class_obj, args[1..], null);
                self.setPendingException(exc_val.toExceptionObject());
                return error.Unwind;
            }
            if (!args[0].isClass()) {
                return self.raiseExceptionFmt(self.type_error_class, "exception class/object expected", .{});
            }
            const class_obj = args[0].toClassObject();
            if (self.isClassOrSubclassOf(class_obj, self.exception_class)) {
                const exc_val = try self.newExceptionInstance(class_obj, args[1..], null);
                self.setPendingException(exc_val.toExceptionObject());
                return error.Unwind;
            }
            const msg_str = if (args[1].isString()) args[1].toStringObject().str else "";
            const exc = self.createException(class_obj, msg_str) catch return error.Fatal;
            self.setPendingException(exc);
            return error.Unwind;
        }

        return self.raiseArgumentErrorWrongArgCountGeneric();
    }

    pub fn resetLoadedFilesFromGlobal(self: *VM) VMError!void {
        const loaded_val = self.globals.get("$LOADED_FEATURES") orelse return;
        if (!loaded_val.isArray()) return;

        var key_iter = self.loaded_files.keyIterator();
        while (key_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.loaded_files.deinit();
        self.loaded_files = std.StringHashMap(void).init(self.allocator);
        self.loaded_paths.clearRetainingCapacity();

        for (loaded_val.toArrayObject().elements.items) |entry| {
            if (!entry.isString()) continue;
            const duped = self.allocator.dupe(u8, entry.toStringObject().str) catch return error.Fatal;
            self.loaded_files.put(duped, {}) catch return error.Fatal;
            self.loaded_paths.append(self.allocator, duped) catch return error.Fatal;
        }
    }

    pub fn insertLoadedFile(self: *VM, path: []const u8) VMError!void {
        if (self.loaded_files.contains(path)) return;
        const duped = self.allocator.dupe(u8, path) catch return error.Fatal;
        errdefer self.allocator.free(duped);
        self.loaded_files.put(duped, {}) catch return error.Fatal;
        self.loaded_paths.append(self.allocator, duped) catch return error.Fatal;
    }

    pub fn removeLoadedFile(self: *VM, path: []const u8) void {
        if (self.loaded_files.fetchRemove(path)) |entry| {
            var i: usize = 0;
            while (i < self.loaded_paths.items.len) : (i += 1) {
                if (std.mem.eql(u8, self.loaded_paths.items[i], entry.key)) {
                    _ = self.loaded_paths.orderedRemove(i);
                    break;
                }
            }
            self.allocator.free(entry.key);
        }
    }

    pub fn syncLoadedFeaturesGlobals(self: *VM) VMError!void {
        const loaded = try self.createArray();
        for (self.loaded_paths.items) |path| {
            loaded.elements.append(self.gc_allocator, try self.newString(path, false)) catch return error.Fatal;
        }
        const loaded_val = Value.fromObject(&loaded.object);
        try self.setGlobal("$LOADED_FEATURES", loaded_val);
        try self.setGlobal("$\"", loaded_val);
    }

    pub fn syncLoadPathGlobals(self: *VM) VMError!void {
        const load_path_obj = self.load_path orelse return error.Fatal;
        const load_path_val = Value.fromObject(&load_path_obj.object);
        try self.setGlobal("$LOAD_PATH", load_path_val);
        try self.setGlobal("$:", load_path_val);
    }

    pub fn appendLoadPath(self: *VM, path: []const u8) VMError!void {
        const load_path = self.load_path orelse return error.Fatal;
        for (load_path.elements.items) |entry| {
            if (!entry.isString()) continue;
            if (std.mem.eql(u8, entry.toStringObject().str, path)) return;
        }
        load_path.elements.append(self.gc_allocator, try self.newString(path, false)) catch return error.Fatal;
    }

    // File loading helper methods

    pub fn resolveAbsolutePath(self: *VM, path: []const u8) VMError![]const u8 {
        var path_buffer: [4096]u8 = undefined;
        const absolute_len = std.Io.Dir.cwd().realPathFile(self.io, path, &path_buffer) catch {
            if (std.fs.path.isAbsolute(path)) {
                return self.allocator.dupe(u8, path) catch return error.Fatal;
            }
            return error.Fatal;
        };
        return self.allocator.dupe(u8, path_buffer[0..absolute_len]) catch return error.Fatal;
    }

    pub fn fileExists(self: *VM, path: []const u8) bool {
        const file = std.Io.Dir.cwd().openFile(self.io, path, .{ .allow_directory = false }) catch return false;
        file.close(self.io);
        return true;
    }

    fn hasExplicitRelativePrefix(path: []const u8) bool {
        return std.mem.eql(u8, path, ".") or
            std.mem.eql(u8, path, "..") or
            std.mem.startsWith(u8, path, "./") or
            std.mem.startsWith(u8, path, "../");
    }

    fn currentWorkingDir(self: *VM) VMError![]u8 {
        const cwd_z = std.process.currentPathAlloc(self.io, self.allocator) catch return error.Fatal;
        defer self.allocator.free(cwd_z);
        return self.dupeCStringZAsSlice(cwd_z);
    }

    fn joinPathPartsAlloc(self: *VM, base: []const u8, tail: []const u8) VMError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);

        if (base.len == 0) {
            out.appendSlice(self.allocator, tail) catch return error.Fatal;
        } else if (tail.len == 0) {
            out.appendSlice(self.allocator, base) catch return error.Fatal;
        } else {
            out.appendSlice(self.allocator, base) catch return error.Fatal;
            if (out.items[out.items.len - 1] != '/') {
                out.append(self.allocator, '/') catch return error.Fatal;
            }
            var start: usize = 0;
            while (start < tail.len and tail[start] == '/') : (start += 1) {}
            out.appendSlice(self.allocator, tail[start..]) catch return error.Fatal;
        }

        return self.allocator.dupe(u8, out.items) catch return error.Fatal;
    }

    fn normalizeAbsolutePathAlloc(self: *VM, path: []const u8) VMError![]u8 {
        var leading_slashes: usize = 0;
        while (leading_slashes < path.len and path[leading_slashes] == '/') : (leading_slashes += 1) {}
        if (leading_slashes == 0) return error.Fatal;

        var segments: std.ArrayList([]const u8) = .empty;
        defer segments.deinit(self.allocator);

        var i: usize = leading_slashes;
        while (i <= path.len) {
            const start = i;
            while (i < path.len and path[i] != '/') : (i += 1) {}
            const segment = path[start..i];
            if (segment.len > 0 and !std.mem.eql(u8, segment, ".")) {
                if (std.mem.eql(u8, segment, "..")) {
                    if (segments.items.len > 0) _ = segments.pop();
                } else {
                    segments.append(self.allocator, segment) catch return error.Fatal;
                }
            }
            i += 1;
        }

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);
        for (0..leading_slashes) |_| {
            out.append(self.allocator, '/') catch return error.Fatal;
        }

        for (segments.items, 0..) |segment, idx| {
            if (idx > 0) out.append(self.allocator, '/') catch return error.Fatal;
            out.appendSlice(self.allocator, segment) catch return error.Fatal;
        }

        return self.allocator.dupe(u8, out.items) catch return error.Fatal;
    }

    pub fn expandPathLexical(self: *VM, path: []const u8) VMError![]const u8 {
        if (path.len > 0 and path[0] == '/') {
            return self.normalizeAbsolutePathAlloc(path);
        }

        const cwd = try self.currentWorkingDir();
        defer self.allocator.free(cwd);
        const joined = try self.joinPathPartsAlloc(cwd, path);
        defer self.allocator.free(joined);
        return self.normalizeAbsolutePathAlloc(joined);
    }

    pub fn isBareFeatureWithoutExt(path: []const u8) bool {
        if (path.len == 0) return false;
        if (std.fs.path.isAbsolute(path)) return false;
        if (hasExplicitRelativePrefix(path)) return false;
        if (std.mem.indexOfScalar(u8, path, '/')) |_| return false;
        return std.mem.indexOfScalar(u8, path, '.') == null;
    }

    fn resolveFeaturePath(self: *VM, path: []const u8) VMError!?[]const u8 {
        if (self.fileExists(path)) {
            return try self.resolveAbsolutePath(path);
        }

        const with_rb = std.fmt.allocPrint(self.allocator, "{s}.rb", .{path}) catch return error.Fatal;
        defer self.allocator.free(with_rb);
        if (self.fileExists(with_rb)) {
            return try self.resolveAbsolutePath(with_rb);
        }

        return null;
    }

    const ResolvedFeature = struct {
        load_path: []const u8,
        identity_path: []const u8,
    };

    fn resolveExplicitFeature(self: *VM, path: []const u8) VMError!?ResolvedFeature {
        const load_path = try self.expandPathLexical(path);
        errdefer self.allocator.free(load_path);

        if (self.fileExists(load_path)) {
            const identity_path = try self.resolveAbsolutePath(load_path);
            return .{ .load_path = load_path, .identity_path = identity_path };
        }

        const with_rb = std.fmt.allocPrint(self.allocator, "{s}.rb", .{load_path}) catch return error.Fatal;
        defer self.allocator.free(with_rb);
        if (self.fileExists(with_rb)) {
            self.allocator.free(load_path);
            const stored = self.allocator.dupe(u8, with_rb) catch return error.Fatal;
            errdefer self.allocator.free(stored);
            const identity_path = try self.resolveAbsolutePath(stored);
            return .{ .load_path = stored, .identity_path = identity_path };
        }

        self.allocator.free(load_path);
        return null;
    }

    fn canonicalizeLoadPathEntry(self: *VM, entry: []const u8) VMError![]const u8 {
        var path_buffer: [4096]u8 = undefined;
        const len = std.Io.Dir.cwd().realPathFile(self.io, entry, &path_buffer) catch {
            return try self.expandPathLexical(entry);
        };
        return self.allocator.dupe(u8, path_buffer[0..len]) catch return error.Fatal;
    }

    pub fn resolveRequireFeature(self: *VM, feature: []const u8) VMError!?ResolvedFeature {
        if (std.fs.path.isAbsolute(feature) or hasExplicitRelativePrefix(feature)) {
            return try self.resolveExplicitFeature(feature);
        }

        const load_path = self.load_path orelse return error.Fatal;
        for (load_path.elements.items) |entry| {
            if (!entry.isString()) continue;
            const dir = entry.toStringObject().str;
            const canonical_dir = try self.canonicalizeLoadPathEntry(dir);
            defer self.allocator.free(canonical_dir);

            const joined = try self.joinPathPartsAlloc(canonical_dir, feature);
            defer self.allocator.free(joined);

            const load_candidate = try self.normalizeAbsolutePathAlloc(joined);
            errdefer self.allocator.free(load_candidate);
            if (self.fileExists(load_candidate)) {
                const identity_path = try self.resolveAbsolutePath(load_candidate);
                return .{ .load_path = load_candidate, .identity_path = identity_path };
            }

            const with_rb = std.fmt.allocPrint(self.allocator, "{s}.rb", .{load_candidate}) catch return error.Fatal;
            defer self.allocator.free(with_rb);
            if (self.fileExists(with_rb)) {
                self.allocator.free(load_candidate);
                const stored = self.allocator.dupe(u8, with_rb) catch return error.Fatal;
                errdefer self.allocator.free(stored);
                const identity_path = try self.resolveAbsolutePath(stored);
                return .{ .load_path = stored, .identity_path = identity_path };
            }

            self.allocator.free(load_candidate);
        }

        return null;
    }

    fn normalizeLoadedFeatureEntry(self: *VM, entry: []const u8) VMError!?[]const u8 {
        if (isBareFeatureWithoutExt(entry)) return null;

        if (try self.resolveRequireFeature(entry)) |resolved| {
            defer self.allocator.free(resolved.load_path);
            return resolved.identity_path;
        }
        return null;
    }

    pub fn loadedFeatureMatches(self: *VM, feature: []const u8, resolved_path: ?[]const u8) VMError!bool {
        if (resolved_path == null) {
            return self.loaded_files.contains(feature);
        }

        if (!isBareFeatureWithoutExt(feature) and self.loaded_files.contains(feature)) {
            return true;
        }

        var key_iter = self.loaded_files.keyIterator();
        while (key_iter.next()) |key| {
            const normalized = try self.normalizeLoadedFeatureEntry(key.*) orelse continue;
            defer self.allocator.free(normalized);
            if (std.mem.eql(u8, normalized, resolved_path.?)) {
                return true;
            }
        }

        return false;
    }

    pub fn loadedFeatureMatchesCurrentLoadPath(self: *VM, feature: []const u8) VMError!bool {
        const load_path = self.load_path orelse return false;
        for (load_path.elements.items) |entry| {
            if (!entry.isString()) continue;
            const dir = entry.toStringObject().str;
            const canonical_dir = try self.canonicalizeLoadPathEntry(dir);
            defer self.allocator.free(canonical_dir);

            const joined = try self.joinPathPartsAlloc(canonical_dir, feature);
            defer self.allocator.free(joined);

            const candidate = try self.normalizeAbsolutePathAlloc(joined);
            defer self.allocator.free(candidate);
            if (self.loaded_files.contains(candidate)) return true;

            const with_rb = std.fmt.allocPrint(self.allocator, "{s}.rb", .{candidate}) catch return error.Fatal;
            defer self.allocator.free(with_rb);
            if (self.loaded_files.contains(with_rb)) return true;
        }
        return false;
    }

    pub fn searchLoadPath(self: *VM, feature: []const u8) VMError!?[]const u8 {
        if (try self.resolveRequireFeature(feature)) |resolved| {
            defer self.allocator.free(resolved.identity_path);
            return resolved.load_path;
        }
        return null;
    }

    pub fn requireInProgressOwner(self: *VM, identity_path: []const u8) ?*value.ThreadObject {
        return self.require_in_progress.get(identity_path);
    }

    pub fn beginRequireInProgress(self: *VM, identity_path: []const u8, owner: *value.ThreadObject) VMError!void {
        const duped = self.allocator.dupe(u8, identity_path) catch return error.Fatal;
        errdefer self.allocator.free(duped);
        self.require_in_progress.put(duped, owner) catch return error.Fatal;
    }

    pub fn endRequireInProgress(self: *VM, identity_path: []const u8) void {
        if (self.require_in_progress.fetchRemove(identity_path)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    fn allocateOwnedMainChunk(self: *VM, program: *compiler.CompiledProgram) VMError!*Chunk {
        const main_chunk = self.allocator.create(Chunk) catch return error.Fatal;
        main_chunk.* = program.main_chunk;
        return main_chunk;
    }

    pub fn loadFile(self: *VM, absolute_path: []const u8) VMError!void {
        const code_buffer = std.Io.Dir.cwd().readFileAlloc(self.io, absolute_path, self.gc_allocator_atomic, .limited(std.math.maxInt(usize))) catch return error.Fatal;

        var parser = prism.Parser.init(self.allocator, code_buffer, absolute_path) catch return error.Fatal;
        defer parser.deinit();

        var program = compiler.Compiler.compile(self.allocator, &parser, self.next_chunk_id) catch return error.Fatal;
        defer program.child_chunks.deinit();
        const main_chunk = try self.allocateOwnedMainChunk(&program);
        defer {
            main_chunk.deinit();
            self.allocator.destroy(main_chunk);
        }

        self.next_chunk_id = program.next_chunk_id;
        try self.buildChunkCallsiteDescriptors(main_chunk);
        var loaded_iter = program.child_chunks.valueIterator();
        while (loaded_iter.next()) |chunk_ptr| {
            try self.buildChunkCallsiteDescriptors(chunk_ptr.*);
        }

        // Transfer ownership of chunks to main program
        var iter = program.child_chunks.iterator();
        while (iter.next()) |entry| {
            self.program.child_chunks.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        const prev_file = self.current_loading_file;
        self.current_loading_file = main_chunk.source_file orelse absolute_path;
        defer self.current_loading_file = prev_file;

        try self.executeChunk(main_chunk);
    }

    pub fn evalSource(self: *VM, source: []const u8, source_file: ?[]const u8) VMError!Value {
        return self.evalSourceWithEncoding(source, source_file, null);
    }

    pub fn evalSourceWithEncoding(self: *VM, source: []const u8, source_file: ?[]const u8, source_encoding: ?enc.Encoding) VMError!Value {
        return self.evalSourceWithEncodingAndContext(source, source_file, source_encoding, null);
    }

    pub const EvalContext = struct {
        self_value: Value,
        parent_ep: ?[*]Value,
        lexical_scope: ?*LexicalScope,
        class_variable_scope: ?*LexicalScope = null,
        method_definition_target: ?Value = null,
        parent_local_names: ?[]const []const u8 = null,
        dir_returns_nil: bool = false,
        line_offset: u32 = 0,
        // Optional binding to update with eval-created local variable names.
        binding_to_update: ?*value.BindingObject = null,
        // Method name to stamp on the eval frame (for __method__ in binding evals).
        method_name: ?[]const u8 = null,
    };

    pub fn evalSourceWithEncodingAndContext(
        self: *VM,
        source: []const u8,
        source_file: ?[]const u8,
        source_encoding: ?enc.Encoding,
        context: ?EvalContext,
    ) VMError!Value {
        var parse_source = source;
        var owned_parse_source: ?[]u8 = null;
        defer if (owned_parse_source) |buf| self.allocator.free(buf);

        if (context) |ctx| {
            if (ctx.line_offset > 0) {
                const buf = self.allocator.alloc(u8, ctx.line_offset + source.len) catch return error.Fatal;
                @memset(buf[0..ctx.line_offset], '\n');
                @memcpy(buf[ctx.line_offset..], source);
                parse_source = buf;
                owned_parse_source = buf;
            }
        }

        const outer_names = if (context) |ctx| ctx.parent_local_names else null;
        var parser = prism.Parser.initWithEncodingAndLocals(self.allocator, parse_source, source_file, source_encoding, outer_names) catch {
            return self.raiseExceptionFmt(self.syntax_error_class, "{s}: syntax error", .{source_file orelse "(eval)"});
        };
        defer parser.deinit();

        var eval_program = compiler.Compiler.compileWithContext(
            self.allocator,
            &parser,
            self.next_chunk_id,
            .{ .outer_local_names = if (context) |ctx| ctx.parent_local_names else null },
        ) catch |err| {
            if (compiler.syntaxErrorMessage(err)) |message| {
                return self.raiseExceptionFmt(self.syntax_error_class, "{s}: {s}", .{ source_file orelse "(eval)", message });
            }
            return self.raiseExceptionFmt(self.syntax_error_class, "{s}: syntax error", .{source_file orelse "(eval)"});
        };
        defer eval_program.child_chunks.deinit();
        const eval_main_chunk = try self.allocateOwnedMainChunk(&eval_program);
        defer {
            eval_main_chunk.deinit();
            self.allocator.destroy(eval_main_chunk);
        }

        self.next_chunk_id = eval_program.next_chunk_id;

        try self.buildChunkCallsiteDescriptors(eval_main_chunk);
        var iter = eval_program.child_chunks.valueIterator();
        while (iter.next()) |chunk_ptr| {
            try self.buildChunkCallsiteDescriptors(chunk_ptr.*);
        }

        var ownership_iter = eval_program.child_chunks.iterator();
        while (ownership_iter.next()) |entry| {
            self.program.child_chunks.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        if (context) |ctx| {
            const result = try self.executeChunkInContext(eval_main_chunk, ctx.self_value, ctx.parent_ep, ctx.lexical_scope, .{
                .class_variable_scope = ctx.class_variable_scope,
                .method_definition_target = ctx.method_definition_target,
                .dir_returns_nil = ctx.dir_returns_nil,
                .method_name = ctx.method_name,
            });
            // Update binding's local variable names with any new names from the eval.
            // eval_main_chunk is still alive here (deferred deinit fires after return).
            if (ctx.binding_to_update) |binding| {
                for (eval_main_chunk.local_names.items) |name| {
                    var found = false;
                    for (binding.local_names.items) |existing| {
                        if (std.mem.eql(u8, existing, name)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        const duped = self.gc_allocator.dupe(u8, name) catch return error.Fatal;
                        binding.local_names.append(self.gc_allocator, duped) catch return error.Fatal;
                    }
                }
            }
            return result;
        }

        if (self.frames.items.len > 0) {
            const current_frame = self.currentFrame();
            return self.executeChunkInContext(eval_main_chunk, current_frame.self_value, current_frame.ep, self.current_lexical_scope, .{});
        }

        return self.executeChunkInContext(eval_main_chunk, self.main_self, null, self.current_lexical_scope, .{});
    }

    fn executeChunk(self: *VM, target_chunk: *Chunk) VMError!void {
        _ = try self.executeChunkInContext(
            target_chunk,
            self.main_self,
            null,
            target_chunk.lexical_scope orelse self.toplevel_lexical_scope orelse self.current_lexical_scope,
            .{},
        );
    }

    pub const ChunkContextOptions = struct {
        class_variable_scope: ?*LexicalScope = null,
        method_definition_target: ?Value = null,
        dir_returns_nil: bool = false,
        method_name: ?[]const u8 = null,
    };

    fn executeChunkInContext(
        self: *VM,
        target_chunk: *Chunk,
        self_value: Value,
        parent_ep: ?[*]Value,
        lexical_scope: ?*LexicalScope,
        opts: ChunkContextOptions,
    ) VMError!Value {
        const saved_stack_len = self.stack.items.len;
        const lc = target_chunk.locals_count;
        const locals_base = saved_stack_len;
        const needed = locals_base + lc + ENV_DATA_SIZE;
        if (needed > MAX_FIBER_STACK_SIZE) return error.Fatal;
        self.stack.items.len = needed;
        @memset(self.stack.storage[locals_base .. locals_base + lc], Value.nil());

        const ep: [*]Value = self.stack.storage[locals_base + lc .. locals_base + lc + ENV_DATA_SIZE].ptr;
        ep[0] = if (parent_ep) |p| encodeEp(p) else .{ .raw = 0 };
        ep[1] = try self.frameScopeValue(lexical_scope orelse self.current_lexical_scope, opts.class_variable_scope, opts.method_definition_target);
        ep[2] = Value.integer(lc);

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = target_chunk,
            .ip = 0,
            .locals_base = locals_base,
            .ep = ep,
            .stack_base = needed,
            .self_value = self_value,
            .block = null,
            .frame_type = .method,
            .dir_returns_nil = opts.dir_returns_nil,
            .method_name = opts.method_name,
        }) catch return error.Fatal;

        if (lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }

        const saved = self.frames.items.len - 1;
        try self.executeUntilReturn(saved);
        return (try self.finishSubcallFromStack(saved, saved_stack_len)).value();
    }

    // ===== Exception Handling Methods =====

    /// Create a new exception object
    pub fn createArray(self: *VM) VMError!*value.ArrayObject {
        const array_ptr = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_ptr.* = value.ArrayObject{
            .object = .{
                .type_tag = .array,
                .flags = 0,
                .class = self.array_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .elements = .empty,
        };
        return array_ptr;
    }

    pub fn createHash(self: *VM) VMError!*value.HashObject {
        const hash_ptr = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
        hash_ptr.* = value.HashObject{
            .object = .{
                .type_tag = .hash,
                .flags = 0,
                .class = self.hash_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
            .entries = .empty,
            .default_value = null,
            .default_proc = null,
            .compare_by_identity = false,
        };
        return hash_ptr;
    }

    pub fn createBinding(self: *VM, self_value: Value, ep: ?[*]Value, lexical_scope: ?*LexicalScope) VMError!*value.BindingObject {
        // Bindings always outlive the frame; promote the ep to the heap.
        const heap_ep: ?[*]Value = if (ep) |e| try self.promoteFrameToHeap(e) else null;
        const binding_ptr = self.gc_allocator.create(value.BindingObject) catch return error.Fatal;
        binding_ptr.* = value.BindingObject{
            .object = .{
                .type_tag = .binding,
                .flags = 0,
                .class = self.binding_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .self_value = self_value,
            .ep = heap_ep,
            .lexical_scope = lexical_scope,
        };
        return binding_ptr;
    }

    pub const ArityMode = enum { strict, lenient };

    /// Execute a default parameter expression chunk and return its value.
    /// The default chunk shares the calling frame's ep so it can read already-bound
    /// parameters.  We push a frame with no locals of its own (locals_base = stack top,
    /// stack_base = same) and reuse the parent ep.
    fn executeDefaultExpression(
        self: *VM,
        default_chunk: *const Chunk,
        parent_ep: [*]Value,
    ) VMError!Value {
        const saved_stack_len = self.stack.items.len;

        // Push a minimal frame that shares the parent's ep.
        // locals_base = stack_base = current top (no locals, no env_data pushed).
        const default_frame = CallFrame{
            .chunk = @constCast(default_chunk),
            .ip = 0,
            .locals_base = self.stack.items.len,
            .ep = parent_ep,
            .stack_base = self.stack.items.len,
            .self_value = self.currentFrame().self_value,
            .frame_type = .method,
            .block = null,
        };

        self.frames.append(self.gc_allocator, default_frame) catch return error.Fatal;

        // Execute instructions until this frame completes
        const saved = self.frames.items.len - 1;
        try self.executeUntilReturn(saved);
        return (try self.finishSubcallFromStack(saved, saved_stack_len)).value();
    }

    pub fn copyArgumentsWithRestParam(
        self: *VM,
        target_chunk: *const Chunk,
        ep: [*]Value,
        args: []const Value,
        mode: ArityMode,
    ) VMError!void {
        const lc = target_chunk.locals_count;
        // Helper to read/write a local slot by 0-based index
        const setLocal = struct {
            fn call(ep2: [*]Value, lc2: u16, idx: usize, val: Value) void {
                (ep2 - lc2 + @as(u16, @intCast(idx)))[0] = val;
            }
        }.call;
        const getLocal = struct {
            fn call(ep2: [*]Value, lc2: u16, idx: usize) Value {
                return (ep2 - lc2 + @as(u16, @intCast(idx)))[0];
            }
        }.call;

        var effective_args = args;
        if (mode == .lenient and args.len == 1 and args[0].isArray()) {
            const positional_slots = target_chunk.arity + target_chunk.optional_params.items.len + target_chunk.post_required_count;
            const wants_destructuring =
                positional_slots > 1 or
                (positional_slots > 0 and target_chunk.rest_param_index != null);
            if (wants_destructuring) {
                effective_args = args[0].toArrayObject().elements.items;
            }
        }

        const optional_count = target_chunk.optional_params.items.len;
        const min_required = target_chunk.arity + target_chunk.post_required_count;
        const max_without_rest = target_chunk.arity + optional_count + target_chunk.post_required_count;

        const min_args = min_required;
        const max_args = if (target_chunk.rest_param_index != null)
            std.math.maxInt(usize)
        else
            max_without_rest;

        if (mode == .strict) {
            if (effective_args.len < min_args) {
                return self.raiseArgumentErrorWrongArgCountAtLeast(effective_args.len, min_args);
            }
            if (target_chunk.rest_param_index == null and effective_args.len > max_args) {
                return self.raiseArgumentErrorWrongArgCount(effective_args.len, max_args);
            }
        }

        var arg_idx: usize = 0;
        var local_idx: usize = 0;

        // 1. Bind pre-optional required parameters
        var i: usize = 0;
        while (i < target_chunk.arity) : (i += 1) {
            if (arg_idx < effective_args.len) {
                setLocal(ep, lc, local_idx, effective_args[arg_idx]);
                arg_idx += 1;
            } else if (mode == .lenient) {
                setLocal(ep, lc, local_idx, Value.nil());
            }
            local_idx += 1;
        }

        // 2. Handle optional parameters
        if (optional_count > 0) {
            const args_remaining = if (arg_idx < effective_args.len) effective_args.len - arg_idx else 0;
            const args_available_for_optionals = if (args_remaining > target_chunk.post_required_count)
                args_remaining - target_chunk.post_required_count
            else
                0;

            const optionals_from_args = if (args_available_for_optionals > optional_count)
                optional_count
            else
                args_available_for_optionals;

            i = 0;
            while (i < optionals_from_args) : (i += 1) {
                setLocal(ep, lc, local_idx, effective_args[arg_idx]);
                arg_idx += 1;
                local_idx += 1;
            }

            while (i < optional_count) : (i += 1) {
                const opt_info = target_chunk.optional_params.items[i];
                const default_chunk = self.program.child_chunks.get(opt_info.default_chunk_id) orelse {
                    return error.Fatal;
                };
                const default_value = try self.executeDefaultExpression(default_chunk, ep);
                const current_ep = self.currentFrame().ep;
                setLocal(current_ep, lc, local_idx, default_value);
                local_idx += 1;
            }
        }

        // 3. Handle rest parameter
        if (target_chunk.rest_param_index) |rest_idx| {
            const args_remaining_after_optionals = if (arg_idx < effective_args.len) effective_args.len - arg_idx else 0;
            const available_for_rest = if (args_remaining_after_optionals > target_chunk.post_required_count)
                args_remaining_after_optionals - target_chunk.post_required_count
            else
                0;

            const rest_array = try self.createArray();
            var j: usize = 0;
            while (j < available_for_rest) : (j += 1) {
                rest_array.elements.append(self.gc_allocator, effective_args[arg_idx]) catch return error.Fatal;
                arg_idx += 1;
            }
            setLocal(ep, lc, rest_idx, Value.fromObject(&rest_array.object));
            local_idx = rest_idx + 1;
        }

        // 4. Bind post-required parameters
        i = 0;
        while (i < target_chunk.post_required_count) : (i += 1) {
            const post_start = if (effective_args.len > target_chunk.post_required_count)
                effective_args.len - target_chunk.post_required_count
            else
                0;
            const post_arg_idx = post_start + i;
            if (post_arg_idx < effective_args.len and post_arg_idx >= arg_idx) {
                setLocal(ep, lc, local_idx, effective_args[post_arg_idx]);
            } else if (mode == .lenient) {
                setLocal(ep, lc, local_idx, Value.nil());
            }
            local_idx += 1;
        }
        _ = getLocal; // may be unused
    }

    pub fn hashKeyHash(self: *VM, key: Value) VMError!u64 {
        if (key.isNil() or
            key.isBool() or
            key.isInteger() or
            key.isFloat() or
            key.isString() or
            key.isSymbol())
        {
            return key.hash();
        }

        var args = [_]Value{};
        const hash_value = try self.callMethodByName(key, "hash", args[0..], null);
        const coerced = try hash_value.coerceToIntegerValue(
            self,
            "can't convert hash result to Integer",
            "can't convert hash result to Integer",
        );
        return coerced.hash();
    }

    pub fn hashKeysEqual(self: *VM, lookup_key: Value, stored_key: Value) VMError!bool {
        if (lookup_key.raw == stored_key.raw) return true;
        var args = [_]Value{stored_key};
        const result = self.callMethodByName(lookup_key, "eql?", args[0..], null) catch |err| {
            if (err == error.Unwind and
                self.pendingException() != null and
                self.pendingException().?.object.class == self.no_method_error_class)
            {
                self.setPendingException(null);
                return lookup_key.eql(stored_key);
            }
            return err;
        };
        return result.is_truthy();
    }

    pub fn hashFindEntryIndex(_: *VM, hash_obj: *value.HashObject, key: Value) VMError!?usize {
        if (hash_obj.compare_by_identity) {
            for (hash_obj.entries.items, 0..) |entry, idx| {
                if (entry.key.raw == key.raw) return idx;
            }
            return null;
        }
        return try hash_obj.map.get(key);
    }

    pub fn hashGetEntry(self: *VM, hash_obj: *value.HashObject, key: Value) VMError!?*value.HashEntry {
        const idx = (try self.hashFindEntryIndex(hash_obj, key)) orelse return null;
        return &hash_obj.entries.items[idx];
    }

    fn normalizeHashKeyForStorage(self: *VM, key: Value) VMError!Value {
        if (!key.isString()) return key;
        if (key.isFrozen()) return key;

        const string_obj = key.toStringObject();
        var stored_key = try self.newStringForClassWithEncoding(self.getClass(key), string_obj.str, false, string_obj.encoding);
        const src_obj = key.getObjectPointer().?;
        const dst_obj = stored_key.getObjectPointer().?;
        try self.copyObjectInstanceVariables(src_obj, dst_obj);
        try self.copyPackedPointerTargets(string_obj, stored_key.toStringObject());
        stored_key.freeze();
        return stored_key;
    }

    pub fn hashRebuildIndexes(self: *VM, hash_obj: *value.HashObject) VMError!void {
        hash_obj.map.clearRetainingCapacity();
        for (hash_obj.entries.items, 0..) |entry, idx| {
            hash_obj.map.put(entry.key, idx) catch |err| {
                if (err == error.OutOfMemory) return error.Fatal;
                return @errorCast(err);
            };
        }
        _ = self;
    }

    pub fn hashSetEntry(self: *VM, hash_obj: *value.HashObject, key: Value, new_value: Value) VMError!void {
        if (hash_obj.compare_by_identity) {
            for (hash_obj.entries.items) |*entry| {
                if (entry.key.raw == key.raw) {
                    entry.value = new_value;
                    return;
                }
            }
            hash_obj.entries.append(self.gc_allocator, .{ .key = key, .value = new_value }) catch return error.Fatal;
            return;
        }

        const stored_key = try self.normalizeHashKeyForStorage(key);
        const gop = hash_obj.map.getOrPut(stored_key) catch |err| {
            if (err == error.OutOfMemory) return error.Fatal;
            return @errorCast(err);
        };
        if (gop.found_existing) {
            hash_obj.entries.items[gop.value_ptr.*].value = new_value;
            return;
        }

        const new_idx = hash_obj.entries.items.len;
        hash_obj.entries.append(self.gc_allocator, .{ .key = stored_key, .value = new_value }) catch return error.Fatal;
        gop.value_ptr.* = new_idx;
    }

    pub fn hashDeleteEntry(self: *VM, hash_obj: *value.HashObject, key: Value) VMError!?Value {
        if (hash_obj.compare_by_identity) {
            const idx = (try self.hashFindEntryIndex(hash_obj, key)) orelse return null;
            return hash_obj.entries.orderedRemove(idx).value;
        }

        const removed = try hash_obj.map.fetchRemove(key);
        const idx = removed orelse return null;
        const deleted = hash_obj.entries.orderedRemove(idx.value).value;
        try self.hashRebuildIndexes(hash_obj);
        return deleted;
    }

    fn coerceKwSplatToHash(self: *VM, kw_val: Value) VMError!?*value.HashObject {
        if (kw_val.isNil()) return null;

        return switch (try self.probeToHash(kw_val)) {
            .hash => |hash| hash.toHashObject(),
            .missing => {
                const exc = try self.createException(self.type_error_class, "no implicit conversion into Hash");
                self.setPendingException(exc);
                return error.Unwind;
            },
            .nil_result => {
                const exc = try self.createException(self.type_error_class, "can't convert to Hash");
                self.setPendingException(exc);
                return error.Unwind;
            },
            .non_hash => {
                const exc = try self.createException(self.type_error_class, "can't convert to Hash");
                self.setPendingException(exc);
                return error.Unwind;
            },
        };
    }

    fn mergeKwSplatInto(self: *VM, target_hash: *value.HashObject, source_value: Value) VMError!void {
        const source_hash = try self.coerceKwSplatToHash(source_value) orelse return;
        for (source_hash.entries.items) |entry| {
            try self.hashSetEntry(target_hash, entry.key, entry.value);
        }
    }

    fn extractKeywordPairsFromHash(
        self: *VM,
        kw_hash_value: Value,
        out_keys: []Value,
        out_values: []Value,
    ) VMError!usize {
        _ = self;
        if (!kw_hash_value.isHash()) {
            return error.Fatal;
        }
        const entries = kw_hash_value.toHashObject().entries.items;
        if (entries.len > out_keys.len or entries.len > out_values.len) {
            return error.Fatal;
        }

        for (entries, 0..) |entry, i| {
            out_keys[i] = entry.key;
            out_values[i] = entry.value;
        }
        return entries.len;
    }

    fn createHashFromKeywordPairs(self: *VM, kw_keys: []const Value, kw_values: []const Value) VMError!Value {
        if (kw_keys.len != kw_values.len) return error.Fatal;

        const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
        kw_hash.* = .{
            .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
            .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
            .entries = .empty,
            .default_value = null,
            .default_proc = null,
            .compare_by_identity = false,
        };

        for (kw_values, 0..) |kw_value, i| {
            try self.hashSetEntry(kw_hash, kw_keys[i], kw_value);
        }

        return Value.fromObject(&kw_hash.object);
    }

    fn bindKeywordArguments(
        self: *VM,
        target_chunk: *const Chunk,
        ep: [*]Value,
        kw_keys: []const Value,
        kw_values: []const Value,
    ) VMError!void {
        if (kw_keys.len != kw_values.len) return error.Fatal;
        const lc = target_chunk.locals_count;

        var matched = self.allocator.alloc(bool, kw_values.len) catch return error.Fatal;
        defer self.allocator.free(matched);
        @memset(matched, false);

        for (target_chunk.required_keywords.items) |req_kw| {
            const req_name = target_chunk.constants.items[req_kw.name_idx].string;
            const req_symbol = try self.intern(req_name);

            var found = false;
            for (kw_keys, 0..) |kw_key, i| {
                if (!kw_key.isSymbol()) continue;
                if (kw_key.toSymbolObject() == req_symbol) {
                    (ep - lc + req_kw.param_slot)[0] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                const msg = std.fmt.allocPrint(self.gc_allocator, "missing keyword: {s}", .{req_name}) catch return error.Fatal;
                const exc = try self.createException(self.argument_error_class, msg);
                self.setPendingException(exc);
                return error.Unwind;
            }
        }

        for (target_chunk.optional_keywords.items) |opt_kw| {
            const opt_name = target_chunk.constants.items[opt_kw.name_idx].string;
            const opt_symbol = try self.intern(opt_name);

            var found = false;
            for (kw_keys, 0..) |kw_key, i| {
                if (!kw_key.isSymbol()) continue;
                if (kw_key.toSymbolObject() == opt_symbol) {
                    (ep - lc + opt_kw.param_slot)[0] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                const default_chunk = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                const default_value = try self.executeDefaultExpression(default_chunk, ep);
                (ep - lc + opt_kw.param_slot)[0] = default_value;
            }
        }

        if (target_chunk.keyword_rest_index) |rest_idx| {
            const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
            kw_hash.* = .{
                .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                .entries = .empty,
                .default_value = null,
                .default_proc = null,
                .compare_by_identity = false,
            };

            for (kw_values, 0..) |kw_value, i| {
                if (!matched[i]) {
                    try self.hashSetEntry(kw_hash, kw_keys[i], kw_value);
                }
            }

            (ep - lc + rest_idx)[0] = Value.fromObject(&kw_hash.object);
        } else {
            for (matched, 0..) |is_matched, i| {
                if (!is_matched) {
                    const key = kw_keys[i];
                    const msg = if (key.isSymbol())
                        std.fmt.allocPrint(self.gc_allocator, "unknown keyword: {s}", .{key.toSymbolObject().name}) catch return error.Fatal
                    else if (key.isString())
                        std.fmt.allocPrint(self.gc_allocator, "unknown keyword: \"{s}\"", .{key.toStringObject().str}) catch return error.Fatal
                    else
                        std.fmt.allocPrint(self.gc_allocator, "unknown keyword", .{}) catch return error.Fatal;
                    const exc = try self.createException(self.argument_error_class, msg);
                    self.setPendingException(exc);
                    return error.Unwind;
                }
            }
        }
    }

    pub fn createException(self: *VM, class: *ClassObject, message: []const u8) VMError!*value.ExceptionObject {
        const exc = self.gc_allocator.create(value.ExceptionObject) catch return error.Fatal;
        const msg_str = try self.newString(message, false);
        const backtrace = try self.captureBacktrace();

        exc.* = .{
            .object = .{
                .type_tag = .exception,
                .flags = 0,
                .class = class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .message = msg_str.toStringObject(),
            .backtrace = backtrace,
            .cause = self.pendingException(),
            .receiver = null,
            .key = null,
        };

        return exc;
    }

    /// Capture current call stack as a backtrace
    fn captureBacktraceFromFrames(self: *VM, frames: []const CallFrame) VMError!?*value.ArrayObject {
        const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_obj.* = .{
            .object = .{
                .type_tag = .array,
                .flags = 0,
                .class = self.array_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .elements = .empty,
        };

        // Walk the call frames and build backtrace strings
        var i = frames.len;
        while (i > 0) {
            i -= 1;
            const frame = &frames[i];

            const frame_line = self.backtraceLineForFrame(frame);
            const frame_source = frame.chunk.source_file orelse frame.chunk.name;
            const backtrace_str = if (frame.method_name) |method_name|
                if (frame.frame_type == .builtin)
                    std.fmt.allocPrint(
                        self.gc_allocator,
                        "{s}:{d}:in '{s}'",
                        .{ frame_source, frame_line, method_name },
                    ) catch return error.Fatal
                else
                    std.fmt.allocPrint(
                        self.gc_allocator,
                        "{s}:{d}:in '{s}#{s}'",
                        .{ frame_source, frame_line, self.getClass(frame.self_value).module.name.name, method_name },
                    ) catch return error.Fatal
            else
                std.fmt.allocPrint(
                    self.gc_allocator,
                    "{s}:{d}:in '<main>'",
                    .{ frame_source, frame_line },
                ) catch return error.Fatal;

            const str_val = try self.newString(backtrace_str, false);
            array_obj.elements.append(self.gc_allocator, str_val) catch return error.Fatal;
        }

        return array_obj;
    }

    fn captureBacktrace(self: *VM) VMError!?*value.ArrayObject {
        return self.captureBacktraceFromFrames(self.frames.items);
    }

    pub fn captureThreadBacktrace(self: *VM, thread: *value.ThreadObject) VMError!?*value.ArrayObject {
        return self.captureBacktraceFromFrames(thread.frames.items);
    }

    pub fn backtraceLineForFrame(_: *VM, frame: *const CallFrame) u32 {
        if (frame.chunk.line_info.items.len == 0) return 1;
        const ip = if (frame.ip == 0) 0 else frame.ip - 1;
        const line = frame.chunk.getLine(ip);
        return if (line == 0) 1 else line;
    }

    fn writeFormattedException(_: *VM, writer: anytype, exc: *value.ExceptionObject, limit: ?usize) VMError!void {
        const class_name = exc.object.class.?.module.name.name;

        if (exc.backtrace == null or exc.backtrace.?.elements.items.len == 0) {
            writer.*.print("{s} ({s})\n", .{ exc.message.str, class_name }) catch return error.Fatal;
            return;
        }

        const lines = exc.backtrace.?.elements.items;
        writer.*.print("{s}: {s} ({s})\n", .{ lines[0].toStringObject().str, exc.message.str, class_name }) catch return error.Fatal;

        const total_tail = lines.len - 1;
        const shown_tail = if (limit) |tail_limit|
            @min(total_tail, tail_limit)
        else
            total_tail;

        var i: usize = 0;
        while (i < shown_tail) : (i += 1) {
            writer.*.print("\tfrom {s}\n", .{lines[i + 1].toStringObject().str}) catch return error.Fatal;
        }

        if (limit) |tail_limit| {
            if (total_tail > tail_limit) {
                writer.*.print("\t ... {d} levels...\n", .{total_tail - tail_limit}) catch return error.Fatal;
            }
        }
    }

    pub fn exceptionFullMessage(self: *VM, exc: *value.ExceptionObject) VMError!Value {
        var buf: std.Io.Writer.Allocating = .init(self.allocator);
        defer buf.deinit();

        const writer = &buf.writer;
        try self.writeFormattedException(&writer, exc, self.backtrace_limit);

        const full_message = buf.toOwnedSlice() catch return error.Fatal;
        defer self.allocator.free(full_message);
        return try self.newString(full_message, false);
    }

    /// Unwind the call stack looking for exception handlers
    pub fn unwindStack(self: *VM) VMError!void {
        if (try self.unwindStackUntilFrameDepth(0)) {
            return;
        }

        if (self.pendingException() == null and self.pendingThrow() != null) {
            const pending_throw = self.pendingThrow().?;
            self.setPendingException(try self.createUncaughtThrowError(pending_throw.tag, pending_throw.value));
        }

        // No handler was found in any frame.
        // Caller (main.zig) will print the unhandled exception.
        return error.UnhandledException;
    }

    fn unwindStackUntilFrameDepth(self: *VM, min_frame_len: usize) VMError!bool {
        const stop_frame_len = self.controlFlowStopFrameLen(min_frame_len);
        while (self.frames.items.len > stop_frame_len) {
            const frame_idx = self.frames.items.len - 1;

            if (self.pendingControlFlow() != null) {
                if (try self.findEnsureHandler(frame_idx)) |ensure_byte_offset| {
                    try setFrameIp(&self.frames.items[frame_idx], ensure_byte_offset);
                    return true;
                }
            } else if (self.pendingThrow() != null) {
                if (try self.findEnsureHandler(frame_idx)) |ensure_byte_offset| {
                    try setFrameIp(&self.frames.items[frame_idx], ensure_byte_offset);
                    return true;
                }
            } else if (try self.findExceptionHandler(frame_idx)) |handler_info| {
                if (handler_info.rescue_idx) |rescue_idx| {
                    const rescue_handler = &handler_info.handler.rescue_handlers.items[rescue_idx];
                    try setFrameIp(&self.frames.items[frame_idx], rescue_handler.catch_byte_offset);
                    return true;
                } else if (handler_info.handler.ensure_byte_offset) |ensure_byte_offset| {
                    try setFrameIp(&self.frames.items[frame_idx], ensure_byte_offset);
                    return true;
                }
            }

            if (self.pendingControlFlow()) |cf| {
                switch (cf.kind) {
                    .redo_, .retry_ => {
                        if (cf.target_frame_idx == frame_idx) {
                            const target_ip = cf.target_ip orelse return error.Fatal;
                            try setFrameIp(&self.frames.items[frame_idx], target_ip);
                            self.setPendingControlFlow(null);
                            return true;
                        }
                    },
                    else => {},
                }
            }

            const unwind_locals_base = self.frames.items[frame_idx].locals_base;
            try self.popFrame();
            self.stack.shrinkRetainingCapacity(unwind_locals_base);

            if (self.pendingControlFlow()) |cf| {
                switch (cf.kind) {
                    .return_, .break_, .next_ => {
                        if (cf.target_frame_idx) |target_frame_idx| {
                            if (self.frames.items.len <= target_frame_idx) {
                                try self.placePendingControlFlowValue();
                                return true;
                            }
                        }
                    },
                    .redo_, .retry_ => {},
                }
            }
        }

        if (self.pendingControlFlow() != null) {
            try self.placePendingControlFlowValue();
        }

        return false;
    }

    fn controlFlowStopFrameLen(self: *VM, min_frame_len: usize) usize {
        if (self.pendingControlFlow()) |cf| {
            switch (cf.kind) {
                .return_, .break_, .next_ => if (cf.target_frame_idx) |target_frame_idx| {
                    return @min(min_frame_len, target_frame_idx);
                },
                .redo_, .retry_ => {},
            }
        }
        return min_frame_len;
    }

    fn placePendingControlFlowValue(self: *VM) VMError!void {
        if (self.pendingControlFlowPtr()) |cf| {
            if (!cf.value_placed) {
                try self.push(cf.value);
                cf.value_placed = true;
            }
        }
    }

    fn findEnsureHandler(self: *VM, frame_idx: usize) VMError!?usize {
        const frame = self.frames.items[frame_idx];
        const ip = frame.ip;

        for (frame.chunk.exception_handlers.items) |*handler| {
            if (ip >= handler.try_start_byte_offset and ip < handler.try_end_byte_offset) {
                if (handler.ensure_byte_offset) |ensure_byte_offset| return ensure_byte_offset;
            }
        }

        return null;
    }

    /// Execute a sub-call (method/block/proc invoked from builtins).
    /// On exception, unwinds only within the callee; propagates error.Unwind to caller.
    /// Execute a sub-call (method, block, proc) until it returns, using the slow
    /// executeInstruction() dispatch. Uses bounded unwinding that stops at caller_frame_depth,
    /// returning error.Unwind if no handler is found — preventing exceptions from unwinding
    /// past the caller's frame. Used by invokeResolvedMethod, yieldToBlock, callProcObject, etc.
    fn executeUntilReturn(self: *VM, caller_frame_depth: usize) VMError!void {
        const target_frame_depth = caller_frame_depth + 1;
        while (self.frames.items.len >= target_frame_depth) {
            self.executeInstruction() catch |err| switch (err) {
                error.Unwind => {
                    if (!try self.unwindStackUntilFrameDepth(caller_frame_depth)) {
                        if (self.pendingControlFlow() != null)
                            return;
                        return error.Unwind;
                    }
                    // Handler found — if it's in a frame below our target (shouldn't happen),
                    // propagate since the callee frame is gone.
                    if (self.frames.items.len < target_frame_depth) {
                        if (self.pendingControlFlow() != null)
                            return;
                        return error.Unwind;
                    }
                },
                else => return err,
            };
        }
    }

    fn finishSubcall(self: *VM, caller_frame_depth: usize) VMError!SubcallOutcome {
        return self.finishSubcallFromStack(caller_frame_depth, 0);
    }

    fn finishSubcallFromStack(self: *VM, caller_frame_depth: usize, saved_stack_len: usize) VMError!SubcallOutcome {
        if (self.pendingControlFlow()) |cf| {
            const result = cf.value;
            if (cf.value_placed) {
                _ = self.popStackAboveOrNil(saved_stack_len);
            }
            self.setPendingControlFlow(null);
            return switch (cf.kind) {
                .return_ => .{ .non_local_return = result },
                .break_ => .{ .broke = result },
                .next_ => .{ .returned = result },
                .redo_, .retry_ => return error.Fatal,
            };
        }

        const escaped = self.frames.items.len < caller_frame_depth;
        const result = if (escaped)
            self.peekStackOrNil()
        else
            self.popStackAboveOrNil(saved_stack_len);

        if (escaped) return .{ .non_local_return = result };
        return .{ .returned = result };
    }

    fn peekStackOrNil(self: *VM) Value {
        if (self.stack.items.len == 0) return Value.nil();
        return self.stack.items[self.stack.items.len - 1];
    }

    fn popStackAboveOrNil(self: *VM, saved_stack_len: usize) Value {
        if (self.stack.items.len <= saved_stack_len) return Value.nil();
        return self.pop();
    }

    fn executeRescueTypeExpression(
        self: *VM,
        rescue_type_chunk: *const Chunk,
        ep: [*]Value,
        self_value: Value,
    ) VMError!Value {
        const saved_stack_len = self.stack.items.len;
        const saved = self.frames.items.len;
        const original_exception = self.pendingException();

        // Share the current frame's ep (no new locals allocated for rescue type checks).
        const rescue_type_frame = CallFrame{
            .chunk = @constCast(rescue_type_chunk),
            .ip = 0,
            .locals_base = self.stack.items.len,
            .ep = ep,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .frame_type = .method,
            .block = null,
        };

        self.frames.append(self.gc_allocator, rescue_type_frame) catch return error.Fatal;

        try self.executeUntilReturn(saved);
        const result = (try self.finishSubcallFromStack(saved, saved_stack_len)).value();
        self.setPendingException(original_exception);
        return result;
    }

    fn matchesExceptionClassOrModule(self: *VM, exception: *value.ExceptionObject, rescue_type: Value) VMError!bool {
        if (rescue_type.isClass()) {
            return self.matchesException(exception, rescue_type.toClassObject());
        } else if (rescue_type.isModule()) {
            const type_module = rescue_type.toModuleObject();
            var current_class: ?*ClassObject = exception.object.class;
            while (current_class) |class| {
                if (&class.module == type_module) {
                    return true;
                }
                for (class.module.prepended_modules.items) |module| {
                    if (module == type_module) return true;
                }
                for (class.module.included_modules.items) |module| {
                    if (module == type_module) return true;
                }
                current_class = class.superclass;
            }
            return false;
        } else {
            return self.raiseExceptionFmt(self.type_error_class, "class or module required for rescue clause", .{});
        }
    }

    /// Find an exception handler in the current frame
    fn findExceptionHandler(self: *VM, frame_idx: usize) VMError!?struct {
        handler: *chunk.ExceptionHandler,
        rescue_idx: ?usize,
    } {
        const frame = self.frames.items[frame_idx];
        const ip = frame.ip;
        const frame_ep = frame.ep;
        const frame_self = frame.self_value;
        const frame_chunk = frame.chunk;

        // Search the exception handler table
        for (frame_chunk.exception_handlers.items) |*handler| {

            // Check if IP is in the protected region
            if (ip >= handler.try_start_byte_offset and ip < handler.try_end_byte_offset) {
                // Search for a matching rescue handler
                for (handler.rescue_handlers.items, 0..) |*rescue, idx| {
                    // Check if exception matches any of the rescue types
                    if (rescue.exception_type_exprs.items.len == 0) {
                        // Bare rescue catches StandardError
                        if (self.matchesException(self.pendingException().?, self.standard_error_class)) {
                            return .{ .handler = handler, .rescue_idx = idx };
                        }
                    } else {
                        var rescue_eval_raised = false;

                        // Check each specified exception type expression
                        for (rescue.exception_type_exprs.items) |type_expr| {
                            const rescue_type_chunk = self.program.child_chunks.get(type_expr.chunk_id) orelse {
                                return error.Fatal;
                            };

                            const rescue_type = self.executeRescueTypeExpression(rescue_type_chunk, frame_ep, frame_self) catch |err| {
                                switch (err) {
                                    error.Unwind => {
                                        rescue_eval_raised = true;
                                        break;
                                    },
                                    else => return err,
                                }
                            };

                            if (rescue_eval_raised) break;

                            if (type_expr.splat) {
                                const expanded = self.expandSplatValue(rescue_type) catch |err| {
                                    switch (err) {
                                        error.Unwind => {
                                            rescue_eval_raised = true;
                                            break;
                                        },
                                        else => return err,
                                    }
                                };

                                if (rescue_eval_raised) break;

                                for (expanded.toArrayObject().elements.items) |expanded_type| {
                                    const matches = self.matchesExceptionClassOrModule(self.pendingException().?, expanded_type) catch |err| {
                                        switch (err) {
                                            error.Unwind => {
                                                rescue_eval_raised = true;
                                                break;
                                            },
                                            else => return err,
                                        }
                                    };

                                    if (rescue_eval_raised) break;
                                    if (matches) return .{ .handler = handler, .rescue_idx = idx };
                                }
                            } else {
                                const matches = self.matchesExceptionClassOrModule(self.pendingException().?, rescue_type) catch |err| {
                                    switch (err) {
                                        error.Unwind => {
                                            rescue_eval_raised = true;
                                            break;
                                        },
                                        else => return err,
                                    }
                                };

                                if (rescue_eval_raised) break;
                                if (matches) {
                                    return .{ .handler = handler, .rescue_idx = idx };
                                }
                            }
                        }

                        if (rescue_eval_raised) {
                            if (handler.ensure_byte_offset != null) {
                                return .{ .handler = handler, .rescue_idx = null };
                            }
                            return null;
                        }
                    }
                }

                // No matching rescue, but might have ensure
                if (handler.ensure_byte_offset != null) {
                    return .{ .handler = handler, .rescue_idx = null };
                }
            }
        }

        return null;
    }

    /// Check if an exception matches a given exception class (walk inheritance chain)
    fn matchesException(_: *VM, exception: *value.ExceptionObject, type_class: *ClassObject) bool {
        var current_class: ?*ClassObject = exception.object.class;

        while (current_class) |class| {
            if (class == type_class) {
                return true;
            }
            current_class = class.superclass;
        }

        return false;
    }

    /// Print an unhandled exception
    pub fn printUnhandledException(self: *VM) void {
        const writer = self.stderr.?;
        if (self.pendingException()) |exc| {
            self.writeFormattedException(writer, exc, self.backtrace_limit) catch {};
            _ = writer.flush() catch {};
        } else {
            // Someone forgot to set a pending exception.
            writer.print("unknown error\n", .{}) catch {};
            _ = writer.flush() catch {};
        }
    }

    pub fn unhandledExceptionExitStatus(self: *VM) ?u8 {
        const exc = self.pendingException() orelse return null;
        if (self.isClassOrSubclassOf(exc.object.class.?, self.system_exit_class)) {
            const status = self.getInstanceVariable(Value.fromObject(&exc.object), "@status") catch return 1;
            if (!status.isInteger()) return 0;
            const code: u8 = @intCast(status.toInteger());
            return code;
        }

        if (self.isClassOrSubclassOf(exc.object.class.?, self.signal_exception_class)) {
            const status = self.getInstanceVariable(Value.fromObject(&exc.object), "@signo") catch return 1;
            if (!status.isInteger()) return 1;
            const signo = status.toInteger();
            if (signo < 0 or signo > 127) return 1;
            return @intCast(128 + signo);
        }

        return null;
    }
};
