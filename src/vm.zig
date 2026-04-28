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
const value = @import("value.zig");
const prism = @import("prism.zig");
const builtins = @import("builtins/builtins.zig");
const comparable_builtin = @import("builtins/comparable.zig");
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

const MAX_FIBER_STACK_SIZE: usize = 4096;
const MAX_FIBER_FRAMES: usize = 2048;
const MAX_FIBER_ENVS: usize = 2048;
const MAX_BUILTIN_KEYWORDS: usize = 256;
const SMALL_CALL_VALUES: usize = 16;
const DEFAULT_THREAD_PREEMPT_QUANTUM_OPS: u32 = 10_000;

fn parseThreadPreemptQuantumOps() u32 {
    const value_z = getenv("CORA_THREAD_QUANTUM_OPS") orelse return DEFAULT_THREAD_PREEMPT_QUANTUM_OPS;
    const value_slice = std.mem.span(value_z);
    const parsed = std.fmt.parseInt(u32, value_slice, 10) catch return DEFAULT_THREAD_PREEMPT_QUANTUM_OPS;
    return if (parsed == 0) DEFAULT_THREAD_PREEMPT_QUANTUM_OPS else parsed;
}

pub const VMError = error{
    // Unhandled Ruby exception returned by VM.run()
    // Exception object is in pending_exception.
    // Caller should probably call printUnhandledException().
    UnhandledException,

    // Unrecoverable VM error (e.g., OOM, corrupted bytecode)
    Fatal,

    // Triggers stack unwind internally
    // This shouldn't escape VM.run().
    Unwind,
};

pub const Method = union(enum) {
    chunk: *Chunk,
    builtin: *const fn (*VM, Value, []Value, ?Block) VMError!Value,
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

pub const Environment = struct {
    // Back pointer to outer environment (forms a chain for closures)
    parent: ?*Environment,

    // Lexical scope for constant lookup
    lexical_scope: ?*LexicalScope,

    // Variable storage - fixed size array for speed (like Ruby's CallFrame locals)
    variables: [32]Value = undefined,
    variables_len: u8 = 0,

    // If non-null, this is a forwarding pointer to the heap-allocated version
    // Used when a stack-allocated environment is promoted to the heap
    heap_forwarding_ptr: ?*Environment = null,
};

pub const Block = struct {
    pub const ChunkData = struct {
        chunk: *Chunk,
        defining_ep: *Environment,
        defining_self: Value,
        return_target_ep: ?*Environment,
    };

    kind: union(enum) {
        chunk: ChunkData,
        symbol: *SymbolObject,
        builtin: *const fn (*VM, []Value) VMError!Value,
        callable: Value,
    },
};

pub const CallFrame = struct {
    pub const FrameType = enum { method, lambda, proc, fiber };

    chunk: *Chunk,
    ip: usize,
    stack_base: usize,
    self_value: Value,
    ep: *Environment,
    block: ?Block = null,
    frame_type: FrameType = .method,
    return_target_ep: ?*Environment = null,
    method_name: ?[]const u8 = null,
    super_defining_class: ?*ClassObject = null,
    dir_returns_nil: bool = false,
};

pub const FiberValueStack = FixedBufferList(Value, MAX_FIBER_STACK_SIZE);
pub const FiberFrameStack = FixedBufferList(CallFrame, MAX_FIBER_FRAMES);
pub const FiberEnvironmentStack = FixedBufferList(Environment, MAX_FIBER_ENVS);
pub const FiberCoro = zio.coro.Coroutine;
pub const FiberCoroContext = zio.coro.Context;

pub const BuiltinKeywordContext = struct {
    kw_keys_storage: [256]Value = undefined,
    kw_values_storage: [256]Value = undefined,
    kw_keys: []const Value = &.{},
    kw_values: []const Value = &.{},
    consumed: [MAX_BUILTIN_KEYWORDS]bool = [_]bool{false} ** MAX_BUILTIN_KEYWORDS,
    cached_hash: ?Value = null,
    hash_materialized: bool = false,
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

    // Environment stack for optimistic allocation
    env_stack: *FiberEnvironmentStack,

    symbols: std.HashMap(SymbolKey, *SymbolObject, SymbolKeyContext, std.hash_map.default_max_load_percentage),
    globals: std.StringHashMap(Value),
    fstring_cache: std.StringHashMap(Value),
    canonical_fstrings: std.ArrayList(Value) = .empty,
    packed_pointer_targets: std.AutoHashMap(*StringObject, PackedPointerTargets),

    program: *compiler.CompiledProgram,

    current_lexical_scope: ?*LexicalScope = null,
    lexical_scopes: std.ArrayList(*LexicalScope) = .empty,

    basic_object_class: *value.ClassObject,
    class_class: *value.ClassObject,
    integer_class: *value.ClassObject,
    float_class: *value.ClassObject,
    module_class: *value.ClassObject,
    numeric_class: *value.ClassObject,
    object_class: *value.ClassObject,
    string_class: *value.ClassObject,
    symbol_class: *value.ClassObject,
    io_class: *value.ClassObject,
    array_class: *value.ClassObject,
    hash_class: *value.ClassObject,
    file_class: *value.ClassObject,
    dir_class: *value.ClassObject,
    binding_class: *value.ClassObject,
    range_class: *value.ClassObject,
    proc_class: *value.ClassObject,
    fiber_class: *value.ClassObject,
    regexp_class: *value.ClassObject,
    match_data_class: *value.ClassObject,
    nil_class: *value.ClassObject,
    true_class: *value.ClassObject,
    false_class: *value.ClassObject,
    kernel_module: *value.ModuleObject,
    process_module: *value.ModuleObject,
    warning_module: *value.ModuleObject,
    warning_deprecated_enabled: bool = true,
    process_status_class: *value.ClassObject,
    main_self: Value,
    main_fiber: *value.FiberObject,
    current_fiber: *value.FiberObject,
    thread_class: *value.ClassObject,
    thread_error_class: *value.ClassObject,
    thread_kill_exception_class: *value.ClassObject,
    main_thread: ?*value.ThreadObject = null,
    current_thread: ?*value.ThreadObject = null,
    thread_list: std.ArrayList(*value.ThreadObject) = .empty,
    runnable_queue: std.ArrayList(*value.ThreadObject) = .empty,
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
    fiber_error_class: *value.ClassObject,
    load_error_class: *value.ClassObject,
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

    // Exception handling state
    pending_exception: ?*value.ExceptionObject = null,
    ensure_pending_exceptions: std.ArrayList(?*value.ExceptionObject) = .empty,
    backtrace_limit: ?usize = null,
    retry_point: ?struct {
        frame_idx: usize,
        byte_offset: usize,
    } = null,

    // Block break state
    break_occurred: bool = false,
    builtin_keyword_ctx: ?*BuiltinKeywordContext = null,

    at_exit_handlers: std.ArrayList(Value) = .empty,
    io_objects: std.ArrayList(*value.IoObject) = .empty,

    // File loading infrastructure
    loaded_files: std.StringHashMap(void) = undefined,
    loaded_paths: std.ArrayList([]const u8) = .empty,
    load_path: std.ArrayList([]const u8) = .empty,
    current_loading_file: ?[]const u8 = null,
    env_object: ?Value = null,
    next_chunk_id: u16 = 1,
    method_state_version: u64 = 1,
    integer_changed: bool = false,
    recursion_guard: RecursionGuard = .{},
    tcc_jit_enabled: bool = false,
    dump_jit_source: bool = false,
    jit_chunk_states: JitChunkStates,

    // Buffered writers for production
    stdout_buffer: [4096]u8 = undefined,
    stderr_buffer: [4096]u8 = undefined,
    stdout_writer: ?std.fs.File.Writer = null,
    stderr_writer: ?std.fs.File.Writer = null,

    // Type-erased writers (tests can override these)
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,

    pub fn initEmpty(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, gc_allocator_atomic: std.mem.Allocator) VM {
        return VM{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .gc_allocator_atomic = gc_allocator_atomic,
            .stack = undefined,
            .frames = undefined,
            .env_stack = undefined,
            .symbols = std.HashMap(SymbolKey, *SymbolObject, SymbolKeyContext, std.hash_map.default_max_load_percentage).init(gc_allocator),
            .globals = std.StringHashMap(Value).init(gc_allocator),
            .fstring_cache = std.StringHashMap(Value).init(allocator),
            .canonical_fstrings = .empty,
            .packed_pointer_targets = std.AutoHashMap(*StringObject, PackedPointerTargets).init(allocator),
            .loaded_files = std.StringHashMap(void).init(gc_allocator),
            .program = undefined,
            .basic_object_class = undefined,
            .class_class = undefined,
            .integer_class = undefined,
            .float_class = undefined,
            .module_class = undefined,
            .numeric_class = undefined,
            .object_class = undefined,
            .string_class = undefined,
            .symbol_class = undefined,
            .io_class = undefined,
            .array_class = undefined,
            .hash_class = undefined,
            .file_class = undefined,
            .dir_class = undefined,
            .binding_class = undefined,
            .range_class = undefined,
            .proc_class = undefined,
            .fiber_class = undefined,
            .regexp_class = undefined,
            .match_data_class = undefined,
            .nil_class = undefined,
            .true_class = undefined,
            .false_class = undefined,
            .kernel_module = undefined,
            .process_module = undefined,
            .warning_module = undefined,
            .process_status_class = undefined,
            .main_fiber = undefined,
            .current_fiber = undefined,
            .thread_class = undefined,
            .thread_error_class = undefined,
            .thread_kill_exception_class = undefined,
            .main_thread = null,
            .current_thread = null,
            .thread_list = .empty,
            .runnable_queue = .empty,
            .thread_preempt_quantum_ops = DEFAULT_THREAD_PREEMPT_QUANTUM_OPS,
            .exception_class = undefined,
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
            .fiber_error_class = undefined,
            .load_error_class = undefined,
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
            .tcc_jit_enabled = false,
            .dump_jit_source = false,
            .jit_chunk_states = JitChunkStates.init(allocator),
        };
    }

    pub fn prepare(self: *VM, program: *compiler.CompiledProgram) VMError!void {
        self.program = program;
        self.zio_coroutines = .empty;
        zio.coro.setupStackGrowth() catch return error.Fatal;
        self.zio_stack_growth_ready = true;

        // Initialize file loading infrastructure
        self.loaded_files = std.StringHashMap(void).init(self.allocator);
        self.loaded_paths = .empty;
        self.load_path = .empty;
        const dot = self.allocator.dupe(u8, ".") catch return error.Fatal;
        self.load_path.append(self.allocator, dot) catch return error.Fatal;
        self.next_chunk_id = program.next_chunk_id;
        self.thread_preempt_quantum_ops = parseThreadPreemptQuantumOps();

        if (program.main_chunk.source_file) |main_file| {
            const abs_path = try self.resolveAbsolutePath(main_file);
            self.loaded_files.put(abs_path, {}) catch return error.Fatal;
            self.current_loading_file = abs_path;
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

        const numeric_name_sym = try self.intern("Numeric");
        const numeric_class_val = try self.newClass(numeric_name_sym, self.object_class);
        self.numeric_class = numeric_class_val.toClassObject();

        const integer_name_sym = try self.intern("Integer");
        const integer_class_val = try self.newClass(integer_name_sym, self.numeric_class);
        self.integer_class = integer_class_val.toClassObject();

        const float_name_sym = try self.intern("Float");
        const float_class_val = try self.newClass(float_name_sym, self.numeric_class);
        self.float_class = float_class_val.toClassObject();

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

        const fiber_name_sym = try self.intern("Fiber");
        const fiber_class_val = try self.newClassWithType(fiber_name_sym, self.object_class, .fiber);
        self.fiber_class = fiber_class_val.toClassObject();

        const thread_name_sym = try self.intern("Thread");
        const thread_class_val = try self.newClass(thread_name_sym, self.object_class);
        self.thread_class = thread_class_val.toClassObject();

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

        const warning_name_sym = try self.intern("Warning");
        const warning_module_val = try self.newModule(warning_name_sym);
        self.warning_module = warning_module_val.toModuleObject();

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

        const standard_error_name_sym = try self.intern("StandardError");
        const standard_error_class_val = try self.newClass(standard_error_name_sym, self.exception_class);
        self.standard_error_class = standard_error_class_val.toClassObject();

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

        const fiber_error_name_sym = try self.intern("FiberError");
        const fiber_error_class_val = try self.newClass(fiber_error_name_sym, self.standard_error_class);
        self.fiber_error_class = fiber_error_class_val.toClassObject();

        const thread_error_name_sym = try self.intern("ThreadError");
        const thread_error_class_val = try self.newClass(thread_error_name_sym, self.standard_error_class);
        self.thread_error_class = thread_error_class_val.toClassObject();

        const thread_kill_name_sym = try self.intern("ThreadKillSignal");
        const thread_kill_class_val = try self.newClass(thread_kill_name_sym, self.exception_class);
        self.thread_kill_exception_class = thread_kill_class_val.toClassObject();

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
        self.object_class.module.constants.put(class_name_sym, class_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(basic_object_name_sym, basic_object_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(object_name_sym, object_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(module_name_sym, module_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(numeric_name_sym, numeric_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(integer_name_sym, integer_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(float_name_sym, float_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(string_name_sym, string_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(symbol_name_sym, symbol_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(io_name_sym, io_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(array_name_sym, array_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(hash_name_sym, hash_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(file_name_sym, file_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(dir_name_sym, dir_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(binding_name_sym, binding_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(range_name_sym, range_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(proc_name_sym, proc_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(fiber_name_sym, fiber_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(thread_name_sym, thread_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(regexp_name_sym, regexp_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(match_data_name_sym, match_data_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(nil_class_name_sym, nil_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(true_class_name_sym, true_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(false_class_name_sym, false_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(kernel_name_sym, kernel_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(process_name_sym, process_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(warning_name_sym, warning_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(comparable_name_sym, comparable_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(enumerable_name_sym, enumerable_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(exception_name_sym, exception_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(standard_error_name_sym, standard_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(runtime_error_name_sym, runtime_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(syntax_error_name_sym, syntax_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(not_implemented_error_name_sym, not_implemented_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(frozen_error_name_sym, frozen_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(argument_error_name_sym, argument_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(key_error_name_sym, key_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(type_error_name_sym, type_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(zero_division_error_name_sym, zero_division_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(name_error_name_sym, name_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(no_method_error_name_sym, no_method_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(local_jump_error_name_sym, local_jump_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(io_error_name_sym, io_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(fiber_error_name_sym, fiber_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(thread_error_name_sym, thread_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(load_error_name_sym, load_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(encoding_error_name_sym, encoding_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(range_error_name_sym, range_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(regexp_error_name_sym, regexp_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(index_error_name_sym, index_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(stop_iteration_name_sym, stop_iteration_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(enumerator_name_sym, enumerator_class_val) catch return error.Fatal;
        self.enumerator_class.module.constants.put(yielder_name_sym, yielder_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(encoding_name_sym, encoding_class_val) catch return error.Fatal;
        const ruby_engine_sym = try self.intern("RUBY_ENGINE");
        const ruby_version_sym = try self.intern("RUBY_VERSION");
        const ruby_platform_sym = try self.intern("RUBY_PLATFORM");
        const ruby_engine_val = try self.newString("cora", false);
        const ruby_version_val = try self.newString("4.0.0", false);
        const ruby_platform = comptime std.fmt.comptimePrint("{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
        const ruby_platform_val = try self.newString(ruby_platform, false);
        self.object_class.module.constants.put(ruby_engine_sym, ruby_engine_val) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_version_sym, ruby_version_val) catch return error.Fatal;
        self.object_class.module.constants.put(ruby_platform_sym, ruby_platform_val) catch return error.Fatal;
        try self.setArgv(&[_][]const u8{});

        const stdin_sym = try self.intern("STDIN");
        const stdout_sym = try self.intern("STDOUT");
        const stderr_sym = try self.intern("STDERR");
        const stdin_obj = try self.newIo(self.io_class, 0, false, true, false, false);
        const stdout_obj = try self.newIo(self.io_class, 1, false, false, true, false);
        const stderr_obj = try self.newIo(self.io_class, 2, false, false, true, false);
        self.object_class.module.constants.put(stdin_sym, stdin_obj) catch return error.Fatal;
        self.object_class.module.constants.put(stdout_sym, stdout_obj) catch return error.Fatal;
        self.object_class.module.constants.put(stderr_sym, stderr_obj) catch return error.Fatal;
        try self.setGlobal("$stdin", stdin_obj);
        try self.setGlobal("$stdout", stdout_obj);
        try self.setGlobal("$stderr", stderr_obj);
        try self.setGlobal("$/", try self.newString("\n", false));
        try self.setGlobal("$-0", Value.nil());

        const env_obj = try self.newInstance(self.object_class);
        self.env_object = env_obj;
        const env_sym = try self.intern("ENV");
        self.object_class.module.constants.put(env_sym, env_obj) catch return error.Fatal;

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

        const utf8_val = Value.fromObject(self.encoding_utf8);
        const cesu8_val = Value.fromObject(self.encoding_cesu8);
        const ascii_8bit_val = Value.fromObject(self.encoding_ascii_8bit);
        const us_ascii_val = Value.fromObject(self.encoding_us_ascii);
        const shift_jis_val = Value.fromObject(self.encoding_shift_jis);
        const windows_31j_val = Value.fromObject(self.encoding_windows_31j);
        const euc_jp_val = Value.fromObject(self.encoding_euc_jp);
        const cp437_val = Value.fromObject(self.encoding_cp437);
        const iso_8859_9_val = Value.fromObject(self.encoding_iso_8859_9);
        const iso_8859_15_val = Value.fromObject(self.encoding_iso_8859_15);
        const utf7_val = Value.fromObject(self.encoding_utf7);
        const utf16_val = Value.fromObject(self.encoding_utf16);
        const utf32_val = Value.fromObject(self.encoding_utf32);
        const utf16le_val = Value.fromObject(self.encoding_utf16le);
        const utf16be_val = Value.fromObject(self.encoding_utf16be);
        const utf32le_val = Value.fromObject(self.encoding_utf32le);
        const utf32be_val = Value.fromObject(self.encoding_utf32be);
        const encoding_converter_class_val = try self.newClass(converter_const_sym, self.object_class);

        self.encoding_class.module.constants.put(utf8_const_sym, utf8_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(cesu8_const_sym, cesu8_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(ascii_8bit_const_sym, ascii_8bit_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(binary_const_sym, ascii_8bit_val) catch return error.Fatal; // BINARY is alias for ASCII_8BIT
        self.encoding_class.module.constants.put(us_ascii_const_sym, us_ascii_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(ascii_const_sym, us_ascii_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(shift_jis_const_sym, shift_jis_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(shift_jis_mixed_const_sym, shift_jis_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(sjis_const_sym, windows_31j_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(windows_31j_const_sym, windows_31j_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(euc_jp_const_sym, euc_jp_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_1_const_sym, iso_8859_15_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_9_const_sym, iso_8859_9_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso8859_9_const_sym, iso_8859_9_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_8859_15_const_sym, iso_8859_15_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf7_const_sym, utf7_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16_const_sym, utf16_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16le_const_sym, utf16le_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf16be_const_sym, utf16be_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32_const_sym, utf32_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32le_const_sym, utf32le_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(utf32be_const_sym, utf32be_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(iso_2022_jp_const_sym, Value.fromObject(self.encoding_iso_2022_jp)) catch return error.Fatal;
        self.encoding_class.module.constants.put(emacs_mule_const_sym, windows_31j_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(windows_1251_const_sym, iso_8859_15_val) catch return error.Fatal;
        const ibm437_const_sym = try self.intern("IBM437");
        self.encoding_class.module.constants.put(ibm437_const_sym, cp437_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(converter_const_sym, encoding_converter_class_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_compatibility_error_name_sym, encoding_compatibility_error_class_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_converter_not_found_error_name_sym, encoding_converter_not_found_error_class_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_undefined_conversion_error_name_sym, encoding_undefined_conversion_error_class_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(encoding_invalid_byte_sequence_error_name_sym, encoding_invalid_byte_sequence_error_class_val) catch return error.Fatal;

        // --- Stage 5: Register built-in methods ---
        builtins.registerAll(self) catch return error.Fatal;
        comparable_builtin.register(self, comparable_module_val.toModuleObject()) catch return error.Fatal;
        self.integer_changed = false;

        // Initialize last process status global.
        try self.setGlobal("$?", Value.nil());
        try self.clearLastMatch();

        try self.includeModule(self.object_class, self.kernel_module);
        try self.includeModule(self.array_class, enumerable_module_val.toModuleObject());
        try self.includeModule(self.hash_class, enumerable_module_val.toModuleObject());
        try self.includeModule(self.string_class, comparable_module_val.toModuleObject());
        try self.includeModule(self.symbol_class, comparable_module_val.toModuleObject());

        // Create top-level self (Ruby "main" object)
        self.main_self = try self.newInstance(self.object_class);

        // --- Stage 6: Initialize top-level lexical scope ---
        self.current_lexical_scope = try self.createLexicalScope(Value.fromObject(self.object_class), null);

        // --- Stage 7: Initialize main fiber and bind VM state to it ---
        const main_fiber_obj = self.gc_allocator.create(value.FiberObject) catch return error.Fatal;
        main_fiber_obj.object = .{ .type_tag = .fiber, .flags = 0, .class = self.fiber_class, .singleton_class = null, .instance_variables = null };
        main_fiber_obj.state = .running;
        main_fiber_obj.block = null;
        initFiberValueStackInPlace(&main_fiber_obj.stack);
        initFiberFrameStackInPlace(&main_fiber_obj.frames);
        initFiberEnvironmentStackInPlace(&main_fiber_obj.env_stack);
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
        self.restoreFiberState(main_fiber_obj);
        self.zio_main_context = undefined;

        try self.buildProgramCallsiteDescriptors();
        try self.internProgramLiteralSymbols();
        try self.captureMainGcStackBase();
        self.registerVmRootForGc();
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

    // Create new stack-allocated environment
    // Dereference environment pointer, following forwarding pointer if needed
    pub fn derefEnvironment(env: *Environment) *Environment {
        // If this is a forwarding pointer, return the heap environment
        if (env.heap_forwarding_ptr) |heap_env| {
            return heap_env;
        }
        // Otherwise, return the environment itself (either stack or heap)
        return env;
    }

    pub fn createStackEnvironment(self: *VM, parent: ?*Environment, lexical_scope: ?*LexicalScope) VMError!*Environment {
        if (self.env_stack.items.len >= self.env_stack.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber environment stack overflow");
            self.pending_exception = exc;
            return error.Unwind;
        }
        const env_index = self.env_stack.items.len;
        self.env_stack.items = self.env_stack.storage[0 .. env_index + 1];

        const env = &self.env_stack.storage[env_index];
        env.parent = parent;
        env.lexical_scope = lexical_scope;
        env.variables = undefined;
        env.variables_len = 0;
        env.heap_forwarding_ptr = null;
        return env;
    }

    // Get variable by walking environment chain
    fn getVariableAtDepth(ep: *Environment, depth: usize, idx: usize) ?Value {
        var current_ep = derefEnvironment(ep);
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            current_ep = derefEnvironment(current_ep.parent orelse return null);
        }
        if (idx < current_ep.variables_len) {
            return current_ep.variables[idx];
        }
        return null;
    }

    fn setVariableAtDepth(ep: *Environment, depth: usize, idx: usize, val: Value) VMError!void {
        var current_ep = derefEnvironment(ep);
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            current_ep = derefEnvironment(current_ep.parent orelse return);
        }
        if (idx < 32) { // Fixed size limit
            current_ep.variables[idx] = val;
            if (idx >= current_ep.variables_len) {
                current_ep.variables_len = @intCast(idx + 1);
            }
        } else {
            return error.Fatal;
        }
    }

    fn currentNonLocalReturnTarget(self: *VM) ?*Environment {
        if (self.frames.items.len == 0) return null;

        var frame_idx = self.frames.items.len;
        while (frame_idx > 0) {
            frame_idx -= 1;
            const frame = self.frames.items[frame_idx];
            if (frame.frame_type != .method) continue;
            if (frame.method_name == null) continue;
            return derefEnvironment(frame.ep);
        }

        return null;
    }

    fn findActiveReturnTargetMethodFrameIndex(self: *VM, target_ep: *Environment) ?usize {
        if (self.frames.items.len == 0) return null;

        const real_target = derefEnvironment(target_ep);
        var frame_idx = self.frames.items.len;
        while (frame_idx > 0) {
            frame_idx -= 1;
            const frame = self.frames.items[frame_idx];
            if (frame.frame_type != .method) continue;
            if (derefEnvironment(frame.ep) == real_target) return frame_idx;
        }

        return null;
    }

    fn handleNonLocalReturn(self: *VM, frame_type: CallFrame.FrameType, return_target_ep: ?*Environment, result: Value) VMError!void {
        if (frame_type == .fiber) {
            const exc = try self.createException(self.local_jump_error_class, "return from fiber");
            self.pending_exception = exc;
            return error.Unwind;
        }

        const target_ep = return_target_ep orelse {
            const exc = try self.createException(self.local_jump_error_class, "unexpected return");
            self.pending_exception = exc;
            return error.Unwind;
        };
        const target_frame_idx = self.findActiveReturnTargetMethodFrameIndex(target_ep) orelse {
            const exc = try self.createException(self.local_jump_error_class, "unexpected return");
            self.pending_exception = exc;
            return error.Unwind;
        };

        while (self.frames.items.len > target_frame_idx) {
            const unwind_stack_base = self.frames.items[self.frames.items.len - 1].stack_base;
            try self.popFrame();
            self.stack.shrinkRetainingCapacity(unwind_stack_base);
        }

        try self.push(result);
    }

    fn promoteEnvironmentToHeap(self: *VM, stack_env: *Environment) VMError!*Environment {
        // 1. Idempotent check - if already on heap or promoted
        if (stack_env.heap_forwarding_ptr) |heap_env| {
            if (heap_env == stack_env) {
                // Points to itself - already a heap environment
                return stack_env;
            } else {
                // Points to different address - this is a forwarding pointer
                return heap_env;
            }
        }

        // 2. Recursively promote parent chain
        var heap_parent: ?*Environment = null;
        if (stack_env.parent) |parent| {
            // Guard against accidental self-parenting to avoid infinite recursion
            if (parent == stack_env) @panic("Something went wrong");
            // Promote parent if it's a stack environment
            heap_parent = try self.promoteEnvironmentToHeap(parent);
        }

        // 3. Allocate heap copy
        const heap_env = self.gc_allocator.create(Environment) catch return error.Fatal;
        const initialized_len = @min(@as(usize, stack_env.variables_len), stack_env.variables.len);
        heap_env.* = .{
            .parent = heap_parent,
            .lexical_scope = stack_env.lexical_scope,
            .variables = undefined,
            .variables_len = @intCast(initialized_len),
            .heap_forwarding_ptr = null,
        };
        if (initialized_len > 0) {
            @memcpy(heap_env.variables[0..initialized_len], stack_env.variables[0..initialized_len]);
        }
        heap_env.heap_forwarding_ptr = heap_env; // Points to itself to mark as heap-allocated

        // 4. Update all references
        try self.updateEnvironmentReferences(stack_env, heap_env);

        // 5. Convert stack slot to forwarding pointer
        stack_env.heap_forwarding_ptr = heap_env;

        return heap_env;
    }

    fn updateEnvironmentReferences(self: *VM, old_env: *Environment, new_env: *Environment) VMError!void {
        // Update CallFrame references
        for (self.frames.items) |*frame| {
            if (frame.ep == old_env) {
                frame.ep = new_env;
            }
            if (frame.block) |*blk| {
                switch (blk.kind) {
                    .chunk => |*chunk_blk| {
                        if (chunk_blk.defining_ep == old_env) {
                            chunk_blk.defining_ep = new_env;
                        }
                        if (chunk_blk.return_target_ep == old_env) {
                            chunk_blk.return_target_ep = new_env;
                        }
                    },
                    .symbol, .builtin, .callable => {},
                }
            }
        }

        // Update Environment.parent chains in stack
        for (self.env_stack.items) |*env| {
            // Skip forwarding pointers (already promoted)
            if (env.heap_forwarding_ptr != null) continue;
            if (env.parent) |parent| {
                if (parent == old_env) {
                    env.parent = new_env;
                }
            }
        }
    }

    fn findConstantInLexicalScope(_: *VM, scope: *LexicalScope, name: *value.SymbolObject) VMError!?Value {
        var current_scope: ?*LexicalScope = scope;
        while (current_scope) |s| {
            if (s.getModule().constants.get(name)) |val| {
                return val;
            }
            current_scope = s.parent;
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
        if (frame.ep.lexical_scope) |scope| {
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

    fn lookupClassVariable(
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

    pub fn setupOutput(self: *VM) void {
        if (self.stdout == null) {
            // Use streaming mode: stdout is typically a pipe/tty where pwritev
            // fails (Unseekable), and positional mode handles that poorly across fork().
            self.stdout_writer = std.fs.File.stdout().writerStreaming(&self.stdout_buffer);
            self.stdout = &self.stdout_writer.?.interface;
        }

        if (self.stderr == null) {
            self.stderr_writer = std.fs.File.stderr().writerStreaming(&self.stderr_buffer);
            self.stderr = &self.stderr_writer.?.interface;
        }
    }

    pub fn init(
        allocator: std.mem.Allocator,
        gc_allocator: std.mem.Allocator,
        gc_allocator_atomic: std.mem.Allocator,
        program: *compiler.CompiledProgram,
    ) VMError!VM {
        var vm = initEmpty(allocator, gc_allocator, gc_allocator_atomic);
        vm.prepare(program) catch return error.Fatal;
        return vm;
    }

    pub fn setArgv(self: *VM, args: []const []const u8) VMError!void {
        const argv_array = try self.createArray();
        for (args) |arg| {
            const arg_str = try self.newString(arg, false);
            argv_array.elements.append(self.gc_allocator, arg_str) catch return error.Fatal;
        }

        const argv_sym = try self.intern("ARGV");
        self.object_class.module.constants.put(argv_sym, Value.fromObject(argv_array)) catch return error.Fatal;
    }

    pub fn setInputRecordSeparator(self: *VM, separator: []const u8, frozen: bool) VMError!void {
        const separator_value = try self.newString(separator, frozen);
        try self.setGlobal("$/", separator_value);
        try self.setGlobal("$-0", separator_value);
    }

    pub fn allocCStringZ(self: *VM, bytes: []const u8) VMError![:0]u8 {
        const out = self.allocator.allocSentinel(u8, bytes.len, 0) catch return error.Fatal;
        @memcpy(out[0..bytes.len], bytes);
        return out;
    }

    pub fn envGet(self: *VM, key: []const u8) VMError!Value {
        const key_z = try self.allocCStringZ(key);
        defer self.allocator.free(key_z);
        const value_z = getenv(key_z.ptr) orelse return Value.nil();
        return self.newString(std.mem.span(value_z), false);
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
        var env_map = std.process.getEnvMap(self.allocator) catch return error.Fatal;
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const key_val = try self.newString(entry.key_ptr.*, false);
            const value_val = try self.newString(entry.value_ptr.*, false);
            try self.hashSetEntry(hash_obj, key_val, value_val);
        }

        return Value.fromObject(hash_obj);
    }

    pub fn envToArray(self: *VM) VMError!Value {
        const array_obj = try self.createArray();
        var env_map = std.process.getEnvMap(self.allocator) catch return error.Fatal;
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const pair = try self.createArray();
            const key_val = try self.newString(entry.key_ptr.*, false);
            const value_val = try self.newString(entry.value_ptr.*, false);
            pair.elements.append(self.gc_allocator, key_val) catch return error.Fatal;
            pair.elements.append(self.gc_allocator, value_val) catch return error.Fatal;
            array_obj.elements.append(self.gc_allocator, Value.fromObject(pair)) catch return error.Fatal;
        }

        return Value.fromObject(array_obj);
    }

    pub fn envSize(self: *VM) VMError!Value {
        var env_map = std.process.getEnvMap(self.allocator) catch return error.Fatal;
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
        for (self.loaded_paths.items) |path| {
            self.allocator.free(path);
        }
        self.loaded_paths.deinit(self.allocator);
        for (self.load_path.items) |path| {
            self.allocator.free(path);
        }
        self.load_path.deinit(self.allocator);

        self.stack.deinit(self.gc_allocator);
        self.frames.deinit(self.gc_allocator);
        self.env_stack.deinit(self.gc_allocator);
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
        self.canonical_fstrings.deinit(self.allocator);
        var packed_targets_iter = self.packed_pointer_targets.valueIterator();
        while (packed_targets_iter.next()) |targets| {
            targets.deinit();
        }
        self.packed_pointer_targets.deinit();
        self.ensure_pending_exceptions.deinit(self.allocator);
        self.at_exit_handlers.deinit(self.gc_allocator);
        self.recursion_guard.deinit(self.allocator);
        var jit_iter = self.jit_chunk_states.valueIterator();
        while (jit_iter.next()) |state| {
            state.deinit(self.allocator);
        }
        self.jit_chunk_states.deinit();
        for (self.io_objects.items) |io_obj| {
            if (io_obj.owns_fd and !io_obj.closed and io_obj.fd >= 0) {
                std.posix.close(@intCast(io_obj.fd));
                io_obj.closed = true;
            }
        }
        self.io_objects.deinit(self.gc_allocator);
        for (self.lexical_scopes.items) |scope| {
            self.allocator.destroy(scope);
        }
        self.lexical_scopes.deinit(self.allocator);
        self.runnable_queue.deinit(self.allocator);
        self.thread_list.deinit(self.allocator);
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

    pub fn setDumpJitSource(self: *VM, enabled: bool) void {
        self.dump_jit_source = enabled;
    }

    pub fn runAtExitHandlers(self: *VM) VMError!void {
        if (self.at_exit_handlers.items.len == 0) return;

        const original_exception = self.pending_exception;
        var last_exception: ?*value.ExceptionObject = null;

        while (self.at_exit_handlers.items.len > 0) {
            const handler = self.at_exit_handlers.pop().?;
            _ = self.callMethodByName(handler, "call", &[_]Value{}, null) catch |err| {
                switch (err) {
                    error.Unwind => {
                        if (self.pending_exception) |exc| {
                            last_exception = exc;
                            self.pending_exception = null;
                        }
                    },
                    else => return err,
                }
            };
        }

        if (last_exception) |exc| {
            self.pending_exception = exc;
            return error.UnhandledException;
        }

        self.pending_exception = original_exception;
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

    fn mulIntegerValues(self: *VM, lhs: Value, rhs: Value) VMError!Value {
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
        const stack = self.stack;
        const len = stack.items.len;
        if (len >= stack.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber stack overflow");
            self.pending_exception = exc;
            return error.Unwind;
        }

        stack.storage[len] = val;
        stack.items = stack.storage[0 .. len + 1];
    }

    pub inline fn pop(self: *VM) Value {
        const stack = self.stack;
        const len = stack.items.len;
        if (len == 0) return Value.nil();

        const idx = len - 1;
        const val = stack.storage[idx];
        stack.items = stack.storage[0..idx];
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
            return proc_obj.block;
        } else if (block_chunk_id != 0) {
            // Literal block: look up chunk
            if (self.program.child_chunks.get(block_chunk_id)) |bc| {
                bc.lexical_scope = self.current_lexical_scope;
                const defining_ep = try self.promoteEnvironmentToHeap(frame.ep);
                return Block{
                    .kind = .{ .chunk = .{
                        .chunk = bc,
                        .defining_ep = defining_ep,
                        .defining_self = frame.self_value,
                        .return_target_ep = self.currentNonLocalReturnTarget(),
                    } },
                };
            } else {
                return error.Fatal;
            }
        }
        return null;
    }

    fn pushFrame(self: *VM, ch: *Chunk, self_value: Value, block: ?Block) VMError!void {
        if (self.frames.items.len >= self.frames.capacity) {
            const exc = try self.createException(self.fiber_error_class, "fiber call stack overflow");
            self.pending_exception = exc;
            return error.Unwind;
        }

        // Get parent environment (current frame's ep, if any)
        const parent_env = if (self.frames.items.len > 0)
            self.frames.items[self.frames.items.len - 1].ep
        else
            null;

        const env = try self.createStackEnvironment(parent_env, ch.lexical_scope orelse self.current_lexical_scope);

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = ch,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .ep = env,
            .block = block,
        }) catch return error.Fatal;

        // Update current_lexical_scope to the frame's scope
        if (ch.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }
    }

    fn popFrame(self: *VM) VMError!void {
        if (self.frames.items.len > 0) {
            _ = self.frames.pop();

            const expected_len = self.frames.items.len;
            if (self.env_stack.items.len > expected_len) {
                self.env_stack.items.len = expected_len;
            }

            // Restore current_lexical_scope to the previous frame's scope
            if (self.frames.items.len > 0) {
                const prev_frame = &self.frames.items[self.frames.items.len - 1];
                const prev_ep = derefEnvironment(prev_frame.ep);
                self.current_lexical_scope = prev_ep.lexical_scope;
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

    inline fn initFiberEnvironmentStackInPlace(envs: *FiberEnvironmentStack) void {
        envs.storage = undefined;
        envs.items = envs.storage[0..0];
        envs.capacity = MAX_FIBER_ENVS;
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
                    self.env_stack = &owner_thread.env_stack;
                    self.current_lexical_scope = owner_thread.current_lexical_scope;
                    return;
                }
            }
        }
        self.stack = &fiber.stack;
        self.frames = &fiber.frames;
        self.env_stack = &fiber.env_stack;
        self.current_lexical_scope = fiber.current_lexical_scope;
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
                    fiber.coro_exception = self.pending_exception;
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
                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                const fiber_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = chunk_blk.chunk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = chunk_blk.defining_self,
                    .ep = fiber_env,
                    .block = null,
                    .frame_type = .fiber,
                }) catch return error.Fatal;

                if (chunk_blk.chunk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

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
            .builtin => |func| {
                const result = func(self, fiber.first_resume_args[0..fiber.first_resume_argc]) catch |err| {
                    if (err == error.Unwind) {
                        fiber.state = .terminated;
                        fiber.coro_exception = self.pending_exception;
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
            self.pending_exception = exc;
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
                self.pending_exception = fiber.coro_exception orelse return error.Fatal;
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
        initFiberEnvironmentStackInPlace(&main_thread_obj.env_stack);
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
        main_thread_obj.preempt_requested = false;
        main_thread_obj.ops_until_preempt = self.thread_preempt_quantum_ops;
        main_thread_obj.args = null;
        main_thread_obj.main_fiber = self.main_fiber;
        main_thread_obj.current_fiber = self.main_fiber;
        main_thread_obj.owner_vm = self;
        self.main_fiber.owner_thread = main_thread_obj;
        self.main_thread = main_thread_obj;
        self.current_thread = main_thread_obj;
        self.setCurrentFiber(self.main_fiber);
        self.thread_list.append(self.allocator, main_thread_obj) catch return error.Fatal;
        return main_thread_obj;
    }

    pub fn newThreadUnstarted(self: *VM, class_obj: *value.ClassObject) VMError!*value.ThreadObject {
        _ = try self.ensureMainThread();
        const thread_obj = self.gc_allocator.create(value.ThreadObject) catch return error.Fatal;
        thread_obj.object = .{ .type_tag = .thread, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null };
        thread_obj.state = .created;
        thread_obj.block = null;
        initFiberValueStackInPlace(&thread_obj.stack);
        initFiberFrameStackInPlace(&thread_obj.frames);
        initFiberEnvironmentStackInPlace(&thread_obj.env_stack);
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
        thread_obj.preempt_requested = false;
        thread_obj.ops_until_preempt = self.thread_preempt_quantum_ops;
        thread_obj.args = null;
        const root_fiber = self.gc_allocator.create(value.FiberObject) catch return error.Fatal;
        root_fiber.object = .{ .type_tag = .fiber, .flags = 0, .class = self.fiber_class, .singleton_class = null, .instance_variables = null };
        root_fiber.state = .running;
        root_fiber.block = null;
        initFiberValueStackInPlace(&root_fiber.stack);
        initFiberFrameStackInPlace(&root_fiber.frames);
        initFiberEnvironmentStackInPlace(&root_fiber.env_stack);
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
        self.thread_list.append(self.allocator, thread_obj) catch return error.Fatal;
        self.runnable_queue.append(self.allocator, thread_obj) catch return error.Fatal;
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
        self.env_stack = &thread.env_stack;
        self.current_lexical_scope = thread.current_lexical_scope;
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
            switch (err) {
                error.UnhandledException => {
                    if (self.pending_exception) |exc| {
                        if (exc.object.class == self.thread_kill_exception_class) {
                            thread.terminated_normally = true;
                            thread.exception = null;
                            thread.result = Value.nil();
                            self.pending_exception = null;
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
                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                const thread_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = chunk_blk.chunk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = chunk_blk.defining_self,
                    .ep = thread_env,
                    .block = null,
                    .frame_type = .fiber,
                }) catch return error.Fatal;

                if (chunk_blk.chunk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

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
                if (thread.coro) |c| c.yield();
                return;
            },
            .builtin => |func| {
                var empty_args = [_]Value{};
                const thread_args = thread.args orelse &empty_args;
                const result = func(self, thread_args) catch |err| {
                    if (err == error.Unwind) {
                        thread.state = .terminated;
                        thread.exception = self.pending_exception;
                        thread.terminated_normally = false;
                        if (thread.coro) |c| c.yield();
                        return;
                    }
                    return err;
                };
                thread.state = .terminated;
                thread.result = result;
                thread.terminated_normally = true;
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
                self.pending_exception = try self.createException(self.thread_kill_exception_class, "");
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

    inline fn resetThreadPreemptBudget(self: *VM, thread: *value.ThreadObject) void {
        thread.preempt_requested = false;
        thread.ops_until_preempt = self.thread_preempt_quantum_ops;
    }

    inline fn isThreadPreemptSafePoint(op: bytecode.OpCode) bool {
        return switch (op) {
            .JUMP, .JUMP_IF_FALSE, .RETURN => true,
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
            self.pending_exception = try self.createException(self.thread_kill_exception_class, "");
            return error.Unwind;
        }
    }

    pub fn maybePreemptCurrentThread(self: *VM, safe_point: bool) VMError!void {
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
                    .string => |s| try self.newStringWithEncoding(s, false, literalStringEncodingForChunk(frame.chunk.source_encoding, s)),
                    .encoded_string => |s| try self.newStringWithEncoding(s.bytes, false, s.encoding),
                    .symbol => |s| Value.fromObject(s),
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
                        try self.push(Value.fromObject(try self.internWithEncoding(name, symbol_encoding)));
                    },
                    .encoded_string => |name| {
                        try self.push(Value.fromObject(try self.internWithEncoding(name.bytes, name.encoding)));
                    },
                    .symbol => |sym| try self.push(Value.fromObject(sym)),
                    else => return error.Fatal,
                }
            },

            .GET_LOCAL => {
                const local_idx = readByteFrom(frame, operands, &operand_cursor);
                // Fast path: direct access to current environment, no depth walking
                const ep = derefEnvironment(frame.ep);
                const val = if (local_idx < ep.variables_len) ep.variables[local_idx] else Value.nil();
                try self.push(val);
            },

            .SET_LOCAL => {
                const local_idx = readByteFrom(frame, operands, &operand_cursor);
                const val = self.pop();
                try setVariableAtDepth(frame.ep, 0, local_idx, val);
                try self.push(val);
            },

            .GET_LOCAL_DEEP => {
                const local_idx = readByteFrom(frame, operands, &operand_cursor);
                const depth = readByteFrom(frame, operands, &operand_cursor);
                const val = getVariableAtDepth(frame.ep, depth, local_idx) orelse Value.nil();
                try self.push(val);
            },

            .SET_LOCAL_DEEP => {
                const local_idx = readByteFrom(frame, operands, &operand_cursor);
                const depth = readByteFrom(frame, operands, &operand_cursor);
                const val = self.pop();
                try setVariableAtDepth(frame.ep, depth, local_idx, val);
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
                    self.pending_exception = exc;
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

                // Walk lexical scope chain first
                if (frame.ep.lexical_scope) |scope| {
                    if (try self.findConstantInLexicalScope(scope, name_sym)) |val| {
                        try self.push(val);
                        return;
                    }
                }

                // Fallback: top-level Object constants
                if (self.object_class.module.constants.get(name_sym)) |const_val| {
                    try self.push(const_val);
                } else {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized constant {s}",
                        .{constant.string},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            },

            .GET_CONST_OR_NIL => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);

                if (frame.ep.lexical_scope) |scope| {
                    if (try self.findConstantInLexicalScope(scope, name_sym)) |val| {
                        try self.push(val);
                        return;
                    }
                }

                if (self.object_class.module.constants.get(name_sym)) |const_val| {
                    try self.push(const_val);
                } else {
                    try self.push(Value.nil());
                }
            },

            .SET_CONST => {
                const idx = readU16From(frame, operands, &operand_cursor);
                const val = self.pop();
                const constant = constants[idx];
                const name_sym = try self.intern(constant.string);

                // Set in current lexical scope's module (or Object if no scope)
                if (frame.ep.lexical_scope) |scope| {
                    scope.getModule().constants.put(name_sym, val) catch return error.Fatal;
                } else {
                    self.object_class.module.constants.put(name_sym, val) catch return error.Fatal;
                }
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
                if (module.constants.get(name_sym)) |const_val| {
                    try self.push(const_val);
                } else {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized constant {s}::{s}",
                        .{ module.name.name, constant.string },
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.pending_exception = exc;
                    return error.Unwind;
                }
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
                                                self.frames.items.len < self.frames.capacity and
                                                self.env_stack.items.len < self.env_stack.capacity)
                                            {
                                                // Ultra-fast path: inline frame + env setup
                                                const env_index = self.env_stack.items.len;
                                                self.env_stack.items = self.env_stack.storage[0 .. env_index + 1];
                                                const env = &self.env_stack.storage[env_index];
                                                env.parent = frame.ep;
                                                env.lexical_scope = method_chunk.lexical_scope orelse self.current_lexical_scope;
                                                env.heap_forwarding_ptr = null;

                                                if (argc > 0) {
                                                    @memcpy(env.variables[0..argc], self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                                }
                                                env.variables_len = @intCast(argc);

                                                self.stack.items = self.stack.storage[0..receiver_index];

                                                self.frames.storage[self.frames.items.len] = CallFrame{
                                                    .chunk = method_chunk,
                                                    .ip = 0,
                                                    .stack_base = receiver_index,
                                                    .self_value = receiver,
                                                    .ep = env,
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
                                            try self.setupChunkCallFrame(
                                                method_chunk,
                                                receiver,
                                                self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)],
                                                null,
                                                null,
                                                cached.method_name.name,
                                                cached.owner_class,
                                                block,
                                            );
                                            self.stack.shrinkRetainingCapacity(receiver_index);
                                            self.currentFrame().stack_base = receiver_index;
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
                                        try self.setupChunkCallFrame(
                                            method_chunk,
                                            receiver,
                                            self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)],
                                            null,
                                            null,
                                            method.name.name,
                                            method.owner_class,
                                            block,
                                        );
                                        self.stack.shrinkRetainingCapacity(receiver_index);
                                        self.currentFrame().stack_base = receiver_index;
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

                try self.callMethodHelperForExecuteInstruction(frame, callsite_byte_offset, method_name_sym, call_style, receiver, args, null, null, block);
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
                                kw_key_slice.?[idx] = Value.fromObject(key_sym);
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
                            kw_key_slice.?[idx] = Value.fromObject(key_sym);
                        }
                    }
                    self.stack.shrinkRetainingCapacity(receiver_index);
                }

                // Call method with keywords
                try self.callMethodHelperForExecuteInstruction(frame, callsite_byte_offset, method_name_sym, call_style, receiver, args, kw_key_slice, kw_value_slice, block);
            },

            .RETURN => {
                const is_explicit = readByteFrom(frame, operands, &operand_cursor);
                const current_frame = self.currentFrame();
                const frame_stack_base = current_frame.stack_base;
                const frame_type = current_frame.frame_type;
                const return_target_ep = current_frame.return_target_ep;
                const result = self.pop();

                // Fast path: implicit return or explicit return from method/lambda
                if (is_explicit == 0 or (frame_type != .fiber and frame_type != .proc)) {
                    self.stack.shrinkRetainingCapacity(frame_stack_base);
                    // Inline fast popFrame: just decrement frame and env stack lengths
                    const new_frame_len = self.frames.items.len - 1;
                    self.frames.items = self.frames.storage[0..new_frame_len];
                    if (self.env_stack.items.len > new_frame_len) {
                        self.env_stack.items = self.env_stack.storage[0..new_frame_len];
                    }
                    // Restore lexical scope from previous frame
                    if (new_frame_len > 0) {
                        const prev_ep = derefEnvironment(self.frames.storage[new_frame_len - 1].ep);
                        self.current_lexical_scope = prev_ep.lexical_scope;
                    }
                    try self.push(result);
                } else {
                    try self.handleNonLocalReturn(frame_type, return_target_ep, result);
                }
            },

            .DEF_MODULE => {
                const name_idx = readU16From(frame, operands, &operand_cursor);
                const body_chunk_id = readU16From(frame, operands, &operand_cursor);

                const constant = constants[name_idx];
                if (constant == .string) {
                    const target = try self.resolveDefinitionTarget(frame.ep.lexical_scope, constant.string);

                    const module_val = blk: {
                        if (target.existing_value) |em| {
                            if (em.isModule()) break :blk em;
                            const exc = try self.createException(self.type_error_class, "constant is not a module");
                            self.pending_exception = exc;
                            return error.Unwind;
                        }

                        const fresh_module = try self.newModule(target.name_sym);
                        target.owner_module.constants.put(target.name_sym, fresh_module) catch return error.Fatal;
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
                    self.pending_exception = exc;
                    return error.Unwind;
                }

                const constant = constants[name_idx];
                if (constant == .string) {
                    const target = try self.resolveDefinitionTarget(frame.ep.lexical_scope, constant.string);

                    var class_val: Value = undefined;
                    if (target.existing_value) |ec| {
                        if (ec.isClass()) {
                            // Reopen existing class
                            class_val = ec;
                        } else {
                            // Name exists but isn't a class - error
                            const exc = try self.createException(self.type_error_class, "constant is not a class");
                            self.pending_exception = exc;
                            return error.Unwind;
                        }
                    } else {
                        // Create new class
                        class_val = try self.newClass(target.name_sym, superclass);
                        target.owner_module.constants.put(target.name_sym, class_val) catch return error.Fatal;
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
                    Value.fromObject(self.nil_class)
                else if (receiver.isBool())
                    Value.fromObject(if (receiver.toBool()) self.true_class else self.false_class)
                else if (receiver.isInteger() or receiver.isFloat() or receiver.isSymbol())
                    return self.raiseExceptionFmt(self.type_error_class, "can't define singleton", .{})
                else blk: {
                    const singleton_class = try self.getOrCreateSingletonClass(receiver);
                    break :blk Value.fromObject(singleton_class);
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
                    const current_self = frame.self_value;
                    const methods = current_self.getModuleMethods() orelse &self.object_class.module.methods;
                    const entry: MethodEntry = .{
                        .method = .{ .chunk = chunk_ptr },
                        .visibility = visibility,
                    };
                    methods.put(method_name_sym, entry) catch return error.Fatal;
                    self.markIntegerChangedForReceiver(current_self);
                    self.bumpMethodStateVersion();

                    // module_function mode (set by Module#module_function with no args)
                    // also creates a public singleton method copy on the defining module.
                    if (module_function_mode and current_self.isModule()) {
                        const singleton_class = try self.getOrCreateSingletonClass(current_self);
                        var singleton_entry = entry;
                        singleton_entry.visibility = .public;
                        singleton_class.module.methods.put(method_name_sym, singleton_entry) catch return error.Fatal;
                        self.markIntegerChangedForReceiver(Value.fromObject(singleton_class));
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
                    const visibility = self.currentDefaultMethodVisibility();

                    // Pop the receiver from stack (compiled by compileMethod)
                    const receiver = self.pop();

                    // Get or create singleton class for the receiver
                    const singleton_class = try self.getOrCreateSingletonClass(receiver);

                    // Store method on singleton class
                    singleton_class.module.methods.put(method_name_sym, .{
                        .method = .{ .chunk = chunk_ptr },
                        .visibility = visibility,
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

                try self.push(Value.fromObject(array_obj));
            },

            .ARRAY_APPEND => {
                const value_to_append = self.pop();
                const array_val = self.pop();
                if (!array_val.isArray()) {
                    const exc = try self.createException(self.type_error_class, "internal error: ARRAY_APPEND target is not an Array");
                    self.pending_exception = exc;
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
                    self.pending_exception = exc;
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

                try self.push(Value.fromObject(hash_obj));
            },

            .HASH_SET_CONST_KEY => {
                const key_name_idx = readU16From(frame, operands, &operand_cursor);
                if (self.stack.items.len < 2) return error.Fatal;

                const value_to_set = self.pop();
                const target_hash_val = self.peek(0);
                if (!target_hash_val.isHash()) {
                    const exc = try self.createException(self.type_error_class, "internal error: HASH_SET_CONST_KEY target is not a Hash");
                    self.pending_exception = exc;
                    return error.Unwind;
                }

                if (key_name_idx >= frame.chunk.constants.items.len) return error.Fatal;
                const key_name = switch (frame.chunk.constants.items[key_name_idx]) {
                    .string => |s| s,
                    .symbol => |sym| sym.name,
                    else => return error.Fatal,
                };
                const key_sym = try self.intern(key_name);
                try self.hashSetEntry(target_hash_val.toHashObject(), Value.fromObject(key_sym), value_to_set);
            },

            .HASH_MERGE_KW => {
                if (self.stack.items.len < 2) return error.Fatal;
                const source_val = self.pop();
                const target_hash_val = self.peek(0);
                if (!target_hash_val.isHash()) {
                    const exc = try self.createException(self.type_error_class, "internal error: HASH_MERGE_KW target is not a Hash");
                    self.pending_exception = exc;
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
                        self.pending_exception = exc;
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

                var buf: std.ArrayList(u8) = .empty;
                defer buf.deinit(self.allocator);
                const writer = buf.writer(self.allocator);
                if (self.stack.items.len < part_count) return error.Fatal;
                const start = self.stack.items.len - part_count;
                var i: usize = 0;
                while (i < part_count) : (i += 1) {
                    const val = self.stack.items[start + i];
                    const str_val = self.callMethodByName(val, "to_s", &[_]Value{}, null) catch |err| {
                        if (err == error.Unwind and self.pending_exception != null) {
                            return error.Unwind;
                        }
                        return err;
                    };
                    if (!str_val.isString()) {
                        const exc = try self.createException(self.type_error_class, "to_s did not return String");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                    writer.writeAll(str_val.toStringObject().str) catch return error.Fatal;
                }
                self.stack.items.len = start;

                const final_str = buf.toOwnedSlice(self.allocator) catch return error.Fatal;
                defer self.allocator.free(final_str);
                try self.push(try self.newString(final_str, false));
            },

            .HALT => {
                try self.popFrame();
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
                    self.pending_exception = exc;
                    return error.Unwind;
                };
                switch (block.kind) {
                    .chunk => |chunk_blk| {
                        // De-recursed: push block frame inline, return to dispatch loop
                        const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                        const block_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                        self.frames.append(self.gc_allocator, CallFrame{
                            .chunk = chunk_blk.chunk,
                            .ip = 0,
                            .stack_base = self.stack.items.len,
                            .self_value = chunk_blk.defining_self,
                            .ep = block_env,
                            .block = frame.block,
                            .frame_type = if (chunk_blk.chunk.is_lambda) .lambda else .proc,
                            .return_target_ep = chunk_blk.return_target_ep,
                        }) catch return error.Fatal;

                        if (chunk_blk.chunk.lexical_scope) |scope| {
                            self.current_lexical_scope = scope;
                        }

                        const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                        const block_frame = self.currentFrame();
                        try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, yield_args[0..argc], arity_mode);
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
                    self.pending_exception = exc;
                    return error.Unwind;
                };

                const splat_args = args_array_val.toArrayObject().elements.items;
                switch (block.kind) {
                    .chunk => |chunk_blk| {
                        // De-recursed: push block frame inline, return to dispatch loop
                        const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                        const block_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                        self.frames.append(self.gc_allocator, CallFrame{
                            .chunk = chunk_blk.chunk,
                            .ip = 0,
                            .stack_base = self.stack.items.len,
                            .self_value = chunk_blk.defining_self,
                            .ep = block_env,
                            .block = frame.block,
                            .frame_type = if (chunk_blk.chunk.is_lambda) .lambda else .proc,
                            .return_target_ep = chunk_blk.return_target_ep,
                        }) catch return error.Fatal;

                        if (chunk_blk.chunk.lexical_scope) |scope| {
                            self.current_lexical_scope = scope;
                        }

                        const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                        const block_frame = self.currentFrame();
                        try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, splat_args, arity_mode);
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
                    } },
                };

                // Create a Proc value from the block
                const proc_val = try self.newProc(block);
                try self.push(proc_val);
            },

            .PUSH_REGEXP => {
                const pattern_idx = readU16From(frame, operands, &operand_cursor);
                const options = readU16From(frame, operands, &operand_cursor);
                const pattern = constants[pattern_idx].string;
                const result = try self.newRegexp(pattern, options);
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
                    const resolved = self.lookupMethod(current_self.toClassObject(), old_name_sym) orelse break :blk null;
                    break :blk resolved.entry;
                } else if (current_self.isModule())
                    methods.get(old_name_sym)
                else
                    methods.get(old_name_sym);

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
                    self.pending_exception = exc;
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
                        self.pending_exception = exc;
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
                        try self.push(Value.fromObject(array_obj));
                    },
                }
            },

            .BREAK => {
                // Break value is already on stack (pushed by compileBreakStatement)
                self.break_occurred = true;
                // Return from block frame like RETURN does
                try self.popFrame();
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

                // Save retry point (current frame and IP after TRY_BEGIN)
                // This allows 'retry' to jump back to the beginning of the begin block
                self.retry_point = .{
                    .frame_idx = self.frames.items.len - 1,
                    .byte_offset = self.currentFrame().ip,
                };
            },

            .TRY_END, .CATCH_END => {
                // These opcodes are just markers, no action needed during normal execution
            },

            .ENSURE_START => {
                // Preserve an in-flight exception while executing ensure body. Any rescue
                // inside the ensure may clear pending_exception; ENSURE_END restores this.
                self.ensure_pending_exceptions.append(self.allocator, self.pending_exception) catch return error.Fatal;
            },

            .RETRY => {
                // Jump back to the beginning of the current begin block
                if (self.retry_point) |retry_pt| {
                    // Verify we're in the same frame
                    const current_frame_idx = self.frames.items.len - 1;
                    if (retry_pt.frame_idx == current_frame_idx) {
                        // Clear pending exception (if any) - we're starting fresh
                        self.pending_exception = null;

                        // Jump back to the saved retry point
                        try setFrameIp(frame, retry_pt.byte_offset);
                    } else {
                        // Retry called from wrong frame - this shouldn't happen with proper compilation
                        const exc = try self.createException(self.runtime_error_class, "retry called from wrong frame");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                } else {
                    // No retry point set - retry called outside of rescue block
                    const exc = try self.createException(self.runtime_error_class, "retry called outside of rescue");
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            },

            .ENSURE_END => {
                // Pop the ensure block's return value (it's ignored)
                _ = self.pop();

                const saved_exception = if (self.ensure_pending_exceptions.items.len > 0)
                    self.ensure_pending_exceptions.pop().?
                else
                    null;

                // A new exception raised in ensure body takes precedence.
                if (self.pending_exception != null) {
                    return error.Unwind;
                }
                // Otherwise, restore any outer exception that entered ensure.
                if (saved_exception) |exc| {
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            },

            .CATCH_START => {
                // Read variable index
                const var_idx = readByteFrom(frame, operands, &operand_cursor);

                // Store exception in local variable if binding exists
                if (var_idx != 255) {
                    if (self.pending_exception) |exc| {
                        frame.ep.variables[var_idx] = Value.fromObject(exc);
                        if (var_idx >= frame.ep.variables_len) {
                            frame.ep.variables_len = @as(u8, @intCast(var_idx + 1));
                        }
                    }
                }

                // Clear pending exception - it's now caught
                self.pending_exception = null;
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
                        self.pending_exception = exc;
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

                // Get forwarding arguments from current method's environment
                var fwd_buf: [256]Value = undefined;
                const fwd_args = self.getForwardingArguments(frame, &fwd_buf);

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
            // Handle BREAK from de-recursed block frames:
            // BREAK pops the block frame and sets break_occurred.
            // We need to also pop the yielding method's frame.
            if (self.break_occurred) {
                self.break_occurred = false;
                try self.popFrame();
                continue;
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
                    const local_idx = code[f.ip + 1];
                    f.ip += 2;
                    const ep = derefEnvironment(f.ep);
                    const val = if (local_idx < ep.variables_len) ep.variables[local_idx] else Value.nil();
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
                    // Only handle fast-path implicit return from methods
                    const is_explicit = code[f.ip + 1];
                    if (is_explicit == 0 or f.frame_type == .method or f.frame_type == .lambda) {
                        const s_len = self.stack.items.len;
                        const result = self.stack.storage[s_len - 1];
                        self.stack.items = self.stack.storage[0..f.stack_base];
                        // Pop frame
                        const new_frame_len = self.frames.items.len - 1;
                        self.frames.items = self.frames.storage[0..new_frame_len];
                        if (self.env_stack.items.len > new_frame_len) {
                            self.env_stack.items = self.env_stack.storage[0..new_frame_len];
                        }
                        if (new_frame_len > 0) {
                            const prev_ep = derefEnvironment(self.frames.storage[new_frame_len - 1].ep);
                            self.current_lexical_scope = prev_ep.lexical_scope;
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
                                                    continue;
                                                }
                                                if (method_chunk.is_simple_positional and
                                                    argc == method_chunk.arity and
                                                    self.frames.items.len < self.frames.capacity and
                                                    self.env_stack.items.len < self.env_stack.capacity)
                                                {
                                                    // Ultra-fast inline call
                                                    const env_index = self.env_stack.items.len;
                                                    self.env_stack.items = self.env_stack.storage[0 .. env_index + 1];
                                                    const env = &self.env_stack.storage[env_index];
                                                    env.parent = f.ep;
                                                    env.lexical_scope = method_chunk.lexical_scope orelse self.current_lexical_scope;
                                                    env.heap_forwarding_ptr = null;

                                                    if (argc > 0) {
                                                        @memcpy(env.variables[0..argc], self.stack.items[(receiver_index + 1)..(receiver_index + 1 + argc)]);
                                                    }
                                                    env.variables_len = @intCast(argc);

                                                    self.stack.items = self.stack.storage[0..receiver_index];

                                                    const new_fl = self.frames.items.len;
                                                    self.frames.storage[new_fl] = CallFrame{
                                                        .chunk = method_chunk,
                                                        .ip = 0,
                                                        .stack_base = receiver_index,
                                                        .self_value = call_receiver,
                                                        .ep = env,
                                                        .block = null,
                                                    };
                                                    self.frames.items = self.frames.storage[0 .. new_fl + 1];

                                                    if (method_chunk.lexical_scope) |scope| {
                                                        self.current_lexical_scope = scope;
                                                    }
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
        }
    }

    fn currentDefaultMethodVisibility(self: *VM) MethodVisibility {
        if (self.current_lexical_scope) |scope| {
            return scope.default_method_visibility;
        }
        return .public;
    }

    fn isClassOrSubclassOf(_: *VM, class: *ClassObject, candidate_ancestor: *ClassObject) bool {
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
            .private => return call_style == .implicit_self,
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
        // First, check singleton class
        if (receiver.getObjectPointer() != null) {
            const singleton_class = self.getOrCreateSingletonClass(receiver) catch return error.Fatal;
            switch (self.lookupMethodDetailed(singleton_class, method_name_sym)) {
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

    pub fn lookupMethodDetailed(self: *VM, class: *ClassObject, method_name: *value.SymbolObject) LookupMethodResult {
        var current_class: ?*ClassObject = class;
        while (current_class) |c| {
            // 1. Check prepended modules first (in reverse order - most recently prepended at highest index is checked first)
            var i = c.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.prepended_modules.items[i];
                if (module.methods.get(method_name)) |entry| {
                    return self.resolveLookupEntry(method_name, c, entry);
                }
            }

            // 2. Check class's own methods
            if (c.module.methods.get(method_name)) |entry| {
                return self.resolveLookupEntry(method_name, c, entry);
            }

            // 3. Check included modules (in reverse order - most recently included at highest index is checked first)
            i = c.included_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.included_modules.items[i];
                if (module.methods.get(method_name)) |entry| {
                    return self.resolveLookupEntry(method_name, c, entry);
                }
            }

            current_class = c.superclass;
        }

        return .not_found;
    }

    fn raiseNoMethod(self: *VM, receiver: Value, method_name: []const u8) VMError!void {
        const class = self.getClass(receiver);
        const class_name = class.module.name.name;
        const msg = std.fmt.allocPrint(
            self.gc_allocator,
            "undefined method '{s}' for {s}",
            .{ method_name, class_name },
        ) catch return error.Fatal;
        const exc = try self.createException(self.no_method_error_class, msg);
        self.pending_exception = exc;
        return error.Unwind;
    }

    inline fn setupChunkCallFrame(
        self: *VM,
        method_chunk: *Chunk,
        receiver: Value,
        args: []const Value,
        kw_keys: ?[]const Value,
        kw_values: ?[]const Value,
        method_name: ?[]const u8,
        super_defining_class: ?*ClassObject,
        block: ?Block,
    ) VMError!void {
        const has_keywords = kw_values != null and kw_values.?.len > 0;

        if (method_chunk.no_keywords and has_keywords) {
            const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
            self.pending_exception = exc;
            return error.Unwind;
        }

        if (!has_keywords and method_chunk.required_keywords.items.len > 0) {
            const msg = "missing required keyword arguments";
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.Unwind;
        }

        try self.pushFrame(method_chunk, receiver, block);
        const callee_frame = self.currentFrame();
        callee_frame.method_name = method_name;
        callee_frame.super_defining_class = super_defining_class;
        if (method_chunk.is_simple_positional) {
            if (args.len != method_chunk.arity) {
                return self.raiseArgumentErrorWrongArgCount(args.len, method_chunk.arity);
            }

            if (args.len > 0) {
                @memcpy(callee_frame.ep.variables[0..args.len], args);
            }
            callee_frame.ep.variables_len = @intCast(args.len);
        } else {
            try self.copyArgumentsWithRestParam(method_chunk, callee_frame.ep, args, .strict);
        }

        if (has_keywords) {
            const keys = kw_keys orelse return error.Fatal;
            const kw_vals = kw_values.?;
            try self.bindKeywordArguments(method_chunk, callee_frame.ep, keys, kw_vals);
        } else {
            if (method_chunk.optional_keywords.items.len > 0 or method_chunk.keyword_rest_index != null) {
                var max_slot: u8 = callee_frame.ep.variables_len;
                for (method_chunk.optional_keywords.items) |opt_kw| {
                    if (opt_kw.param_slot >= max_slot) max_slot = opt_kw.param_slot + 1;
                }
                if (method_chunk.keyword_rest_index) |rest_idx| {
                    if (rest_idx >= max_slot) max_slot = rest_idx + 1;
                }
                callee_frame.ep.variables_len = max_slot;

                for (method_chunk.optional_keywords.items) |opt_kw| {
                    const default_chunk = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                    const current_ep = self.currentFrame().ep;
                    const default_value = try self.executeDefaultExpression(default_chunk, current_ep);
                    const f = &self.frames.items[self.frames.items.len - 1];
                    f.ep.variables[opt_kw.param_slot] = default_value;
                }

                if (method_chunk.keyword_rest_index) |rest_idx| {
                    const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                    kw_hash.* = .{
                        .object = .{ .type_tag = .hash, .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                        .map = value.HashMapType.initContext(self.gc_allocator, .{ .vm = self }),
                        .entries = .empty,
                        .default_value = null,
                        .default_proc = null,
                    };
                    const f = &self.frames.items[self.frames.items.len - 1];
                    f.ep.variables[rest_idx] = Value.fromObject(kw_hash);
                }
            }
        }

        if (method_chunk.block_param_index) |block_idx| {
            const current_frame = &self.frames.items[self.frames.items.len - 1];

            if (current_frame.block) |blk| {
                const proc_val = try self.newProc(blk);
                const f = &self.frames.items[self.frames.items.len - 1];
                f.ep.variables[block_idx] = proc_val;
            } else {
                current_frame.ep.variables[block_idx] = Value.nil();
            }

            const f = &self.frames.items[self.frames.items.len - 1];
            if (block_idx >= f.ep.variables_len) {
                f.ep.variables_len = block_idx + 1;
            }
        }
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
        fun_ptr: *const fn (*VM, Value, []Value, ?Block) VMError!Value,
        receiver: Value,
        args: []Value,
        block: ?Block,
        keyword_ctx: ?*BuiltinKeywordContext,
    ) VMError!Value {
        const previous_ctx = self.builtin_keyword_ctx;
        self.builtin_keyword_ctx = keyword_ctx;
        defer self.builtin_keyword_ctx = previous_ctx;

        const result = fun_ptr(self, receiver, args, block) catch |err| {
            if (self.pending_exception != null) {
                return error.Unwind;
            }
            return err;
        };
        return result;
    }

    pub fn keywordArgsGiven(self: *VM) bool {
        return self.builtin_keyword_ctx != null and self.builtin_keyword_ctx.?.kw_values.len > 0;
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
        return self.materializeKeywordHashForContext(ctx);
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
        switch (resolved.entry.method) {
            .chunk => |method_chunk| {
                const saved_frame_count = self.frames.items.len;
                const kw_keys = if (keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_keys else null else null;
                const kw_values = if (keyword_ctx) |ctx| if (ctx.kw_values.len > 0) ctx.kw_values else null else null;
                try self.setupChunkCallFrame(
                    method_chunk,
                    receiver,
                    args,
                    kw_keys,
                    kw_values,
                    resolved.name.name,
                    resolved.owner_class,
                    block,
                );

                try self.executeUntilReturn(saved_frame_count);
                return self.pop();
            },
            .builtin => |fun_ptr| {
                return self.invokeBuiltinMethod(fun_ptr, receiver, args, block, keyword_ctx);
            },
            .proc => |proc_obj| {
                if (keyword_ctx) |ctx| {
                    if (ctx.kw_values.len > 0) {
                        const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                }
                return self.callProcAsMethod(proc_obj, receiver, args, block, resolved.name.name, resolved.owner_class);
            },
            .undefined => unreachable,
        }
    }

    fn invokeResolvedMethod(self: *VM, resolved: ResolvedMethod, receiver: Value, args: []Value, block: ?Block) VMError!Value {
        return self.invokeResolvedMethodWithKeywords(resolved, receiver, args, block, null);
    }

    fn bindMethodBlockParam(self: *VM, method_chunk: *Chunk, frame: *CallFrame, block: ?Block) VMError!void {
        if (method_chunk.block_param_index) |block_idx| {
            if (block) |blk| {
                const proc_val = try self.newProc(blk);
                frame.ep.variables[block_idx] = proc_val;
            } else {
                frame.ep.variables[block_idx] = Value.nil();
            }

            if (block_idx >= frame.ep.variables_len) {
                frame.ep.variables_len = block_idx + 1;
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
            try self.raiseNoMethod(receiver, missing_method_sym.name);
        }

        const method_missing_sym = try self.intern("method_missing");
        const resolved = try self.findMethod(receiver, method_missing_sym);
        if (resolved == null) {
            try self.raiseNoMethod(receiver, missing_method_sym.name);
        }

        var missing_args: [258]Value = undefined;
        missing_args[0] = Value.fromObject(missing_method_sym);
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

    /// Call a method by name string (not from bytecode constant pool)
    pub fn callMethodByName(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callMethodByNameInternal(receiver, method_name, args, block, null);
    }

    /// Call a method by name while forwarding the current builtin keyword context.
    pub fn callMethodByNameForwardingKeywords(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        return self.callMethodByNameInternal(receiver, method_name, args, block, self.builtin_keyword_ctx);
    }

    pub fn respondsToMethodByName(self: *VM, receiver: Value, method_name: []const u8, include_private: bool) VMError!bool {
        const method_name_sym = try self.intern(method_name);
        var respond_args: [2]Value = .{
            Value.fromObject(method_name_sym),
            Value.boolean(include_private),
        };
        const responds = try self.callMethodByName(receiver, "respond_to?", respond_args[0..], null);
        return responds.is_truthy();
    }

    /// MRI-like check-call helper for optional conversion/probe calls.
    /// Returns null when receiver does not respond to the method.
    /// If receiver responds, performs a normal call (including method_missing behavior).
    pub fn checkCallMethodByName(self: *VM, receiver: Value, method_name: []const u8, include_private: bool, args: []Value, block: ?Block) VMError!?Value {
        if (!try self.respondsToMethodByName(receiver, method_name, include_private)) return null;
        return try self.callMethodByName(receiver, method_name, args, block);
    }

    /// Result from yielding to a block
    const YieldResult = struct {
        value: Value,
        break_occurred: bool,
        non_local_return_occurred: bool,
    };

    /// Yield to a block with arguments, handling break and exceptions
    /// Returns the block's result value and whether a break occurred
    pub fn yieldToBlock(self: *VM, block: Block, yield_args: []const Value) VMError!YieldResult {
        return switch (block.kind) {
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
            .callable => |callable| .{
                .value = try self.callMethodByName(callable, "call", @constCast(yield_args), null),
                .break_occurred = false,
                .non_local_return_occurred = false,
            },
            .chunk => |chunk_blk| blk: {
                // Dereference defining_ep in case it's a forwarding pointer
                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                const block_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;
                const enclosing_block = if (self.frames.items.len > 0) self.currentFrame().block else null;

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = chunk_blk.chunk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = chunk_blk.defining_self,
                    .ep = block_env,
                    .block = enclosing_block,
                    .frame_type = if (chunk_blk.chunk.is_lambda) .lambda else .proc,
                    .return_target_ep = chunk_blk.return_target_ep,
                }) catch return error.Fatal;

                // Update current_lexical_scope to the block's scope
                if (chunk_blk.chunk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

                const arity_mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                const block_frame = self.currentFrame();
                try self.copyArgumentsWithRestParam(chunk_blk.chunk, block_frame.ep, yield_args, arity_mode);

                self.break_occurred = false;
                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);

                const break_occurred = self.break_occurred;
                if (break_occurred) {
                    self.break_occurred = false;
                }
                const non_local_return_occurred = self.frames.items.len < saved_frame_count;

                const result = if (self.stack.items.len > 0) self.pop() else Value.nil();
                break :blk YieldResult{
                    .value = result,
                    .break_occurred = break_occurred,
                    .non_local_return_occurred = non_local_return_occurred,
                };
            },
        };
    }

    /// Execute a ProcObject as a method body
    fn callProcAsMethod(
        self: *VM,
        proc_obj: *value.ProcObject,
        receiver: Value,
        args: []const Value,
        block: ?Block,
        method_name: ?[]const u8,
        defining_class: ?*ClassObject,
    ) VMError!Value {
        return switch (proc_obj.block.kind) {
            .symbol => |sym| self.invokeSymbolProc(sym, args, block),
            .builtin => |func| func(self, @constCast(args)),
            .callable => |callable| self.callMethodByName(callable, "call", @constCast(args), block),
            .chunk => |chunk_blk| blk: {
                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                const proc_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = chunk_blk.chunk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = receiver,
                    .ep = proc_env,
                    .block = block,
                    .frame_type = .method,
                    .method_name = method_name,
                    .super_defining_class = defining_class,
                }) catch return error.Fatal;

                const current_frame = self.currentFrame();
                try self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, args, .strict);
                try self.bindMethodBlockParam(chunk_blk.chunk, current_frame, block);

                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);

                break :blk self.pop();
            },
        };
    }

    fn invokeSymbolProc(self: *VM, symbol: *SymbolObject, args: []const Value, block: ?Block) VMError!Value {
        try self.requireMinArgCount(args, 1);
        var forwarded_args: [256]Value = undefined;
        if (args.len > 1) {
            @memcpy(forwarded_args[0 .. args.len - 1], args[1..]);
        }
        return self.callMethodByName(args[0], symbol.name, forwarded_args[0 .. args.len - 1], block);
    }

    pub fn callProcObject(self: *VM, proc_obj: *value.ProcObject, args: []const Value, block: ?Block, self_override: ?Value) VMError!Value {
        return switch (proc_obj.block.kind) {
            .symbol => |sym| self.invokeSymbolProc(sym, args, block),
            .builtin => |func| func(self, @constCast(args)),
            .callable => |callable| self.callMethodByName(callable, "call", @constCast(args), block),
            .chunk => |chunk_blk| blk: {
                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                const proc_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                const mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                try self.copyArgumentsWithRestParam(chunk_blk.chunk, proc_env, args, mode);

                if (chunk_blk.chunk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = chunk_blk.chunk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = self_override orelse chunk_blk.defining_self,
                    .ep = proc_env,
                    .block = block,
                    .frame_type = if (chunk_blk.chunk.is_lambda) .lambda else .proc,
                    .return_target_ep = chunk_blk.return_target_ep,
                }) catch return error.Fatal;

                const saved_frame_count = self.frames.items.len - 1;
                try self.executeUntilReturn(saved_frame_count);
                break :blk self.pop();
            },
        };
    }

    /// Ensure a block was given, or raise an error
    pub fn requireBlock(self: *VM, block: ?Block) VMError!Block {
        return block orelse {
            const exc = try self.createException(self.argument_error_class, "no block given");
            self.pending_exception = exc;
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
    fn callMethodHelperForExecuteInstruction(
        self: *VM,
        frame: *CallFrame,
        callsite_byte_offset: usize,
        method_name_sym: *SymbolObject,
        call_style: ReceiverCallStyle,
        receiver: Value,
        args: []const Value,
        kw_keys: ?[]Value,
        kw_values: ?[]Value,
        block: ?Block,
    ) VMError!void {
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

        switch (method.entry.method) {
            .chunk => |method_chunk| {
                try self.setupChunkCallFrame(
                    method_chunk,
                    receiver,
                    args,
                    if (kw_keys) |keys| keys else null,
                    if (kw_values) |vals| vals else null,
                    method.name.name,
                    method.owner_class,
                    block,
                );
            },
            .builtin => |fun_ptr| {
                // Special case: Proc#call on chunk proc — push frame inline to avoid recursion
                if (kwargc == 0 and receiver.isProc()) {
                    const proc_obj = receiver.toProcObject();
                    switch (proc_obj.block.kind) {
                        .chunk => |chunk_blk| {
                            const mn = method.name.name;
                            if (std.mem.eql(u8, mn, "call") or std.mem.eql(u8, mn, "[]") or std.mem.eql(u8, mn, "yield")) {
                                const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                                const proc_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                                const mode: ArityMode = if (chunk_blk.chunk.is_lambda) .strict else .lenient;
                                try self.copyArgumentsWithRestParam(chunk_blk.chunk, proc_env, args, mode);

                                if (chunk_blk.chunk.lexical_scope) |scope| {
                                    self.current_lexical_scope = scope;
                                }

                                self.frames.append(self.gc_allocator, CallFrame{
                                    .chunk = chunk_blk.chunk,
                                    .ip = 0,
                                    .stack_base = self.stack.items.len,
                                    .self_value = chunk_blk.defining_self,
                                    .ep = proc_env,
                                    .block = null,
                                    .frame_type = if (chunk_blk.chunk.is_lambda) .lambda else .proc,
                                    .return_target_ep = chunk_blk.return_target_ep,
                                }) catch return error.Fatal;
                                return;
                            }
                        },
                        else => {},
                    }
                }

                const maybe_keyword_ctx: ?*BuiltinKeywordContext = if (kwargc > 0) blk: {
                    const keyword_ctx = self.gc_allocator.create(BuiltinKeywordContext) catch return error.Fatal;
                    keyword_ctx.* = .{
                        .kw_keys_storage = undefined,
                        .kw_values_storage = undefined,
                    };
                    @memcpy(keyword_ctx.kw_keys_storage[0..kwargc], kw_keys.?);
                    @memcpy(keyword_ctx.kw_values_storage[0..kwargc], kw_values.?);
                    keyword_ctx.kw_keys = keyword_ctx.kw_keys_storage[0..kwargc];
                    keyword_ctx.kw_values = keyword_ctx.kw_values_storage[0..kwargc];
                    break :blk keyword_ctx;
                } else null;

                const result = try self.invokeBuiltinMethod(fun_ptr, receiver, @constCast(args), block, maybe_keyword_ctx);
                try self.push(result);
            },
            .proc => |proc_obj| {
                if (kwargc > 0) {
                    const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                    self.pending_exception = exc;
                    return error.Unwind;
                }
                switch (proc_obj.block.kind) {
                    .chunk => |chunk_blk| {
                        // De-recursed: push frame inline, return to dispatch loop
                        const real_defining_ep = derefEnvironment(chunk_blk.defining_ep);
                        const proc_env = self.createStackEnvironment(real_defining_ep, chunk_blk.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

                        self.frames.append(self.gc_allocator, CallFrame{
                            .chunk = chunk_blk.chunk,
                            .ip = 0,
                            .stack_base = self.stack.items.len,
                            .self_value = receiver,
                            .ep = proc_env,
                            .block = block,
                            .frame_type = .method,
                            .method_name = method.name.name,
                            .super_defining_class = method.owner_class,
                        }) catch return error.Fatal;

                        const current_frame = self.currentFrame();
                        try self.copyArgumentsWithRestParam(chunk_blk.chunk, current_frame.ep, args, .strict);
                        try self.bindMethodBlockParam(chunk_blk.chunk, current_frame, block);
                    },
                    .symbol => |sym| {
                        const result = try self.invokeSymbolProc(sym, args, block);
                        try self.push(result);
                    },
                    .builtin => |func| {
                        const result = try func(self, @constCast(args));
                        try self.push(result);
                    },
                    .callable => |callable| {
                        const result = try self.callMethodByName(callable, "call", @constCast(args), block);
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
                    if (try self.findConstantInLexicalScope(scope, first_sym)) |val| break :blk val;
                }
            }
            break :blk self.object_class.module.constants.get(first_sym) orelse return null;
        };

        while (segments.next()) |segment| {
            if (segment.len == 0) continue;
            if (!current.isClass() and !current.isModule()) return null;

            const segment_sym = try self.intern(segment);
            const module_obj = if (current.isClass())
                &current.toClassObject().module
            else
                current.toModuleObject();
            current = module_obj.constants.get(segment_sym) orelse return null;
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
                Value.fromObject(self.object_class)
            else
                (try self.resolveConstantPathFrom(lexical_scope, normalized_owner_path, prefer_lexical)) orelse {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "uninitialized constant {s}",
                        .{normalized_owner_path},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.name_error_class, msg);
                    self.pending_exception = exc;
                    return error.Unwind;
                };

            if (!owner_val.isClass() and !owner_val.isModule()) {
                const exc = try self.createException(self.type_error_class, "constant path does not refer to class/module");
                self.pending_exception = exc;
                return error.Unwind;
            }

            const owner_module = if (owner_val.isClass())
                &owner_val.toClassObject().module
            else
                owner_val.toModuleObject();
            const name_sym = try self.intern(child_name);
            return .{
                .owner_module = owner_module,
                .existing_value = owner_module.constants.get(name_sym),
                .name_sym = name_sym,
            };
        }

        const name_sym = try self.intern(raw_name);
        const existing_value = if (lexical_scope) |scope|
            try self.findConstantInLexicalScope(scope, name_sym)
        else
            null;

        return .{
            .owner_module = if (lexical_scope) |scope| scope.getModule() else &self.object_class.module,
            .existing_value = existing_value orelse self.object_class.module.constants.get(name_sym),
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

    /// Look up a method in the superclass chain starting from defining_class.superclass
    fn lookupMethodForSuper(self: *VM, defining_class: *ClassObject, method_name: *value.SymbolObject) ?ResolvedMethod {
        // Start from the superclass, not the defining class itself
        const start_class = defining_class.superclass orelse return null;
        return self.lookupMethod(start_class, method_name);
    }

    fn lookupMethodForSuperFromIncludedModule(
        self: *VM,
        receiver_class: *ClassObject,
        defining_module: *value.ModuleObject,
        method_name: *value.SymbolObject,
    ) ?ResolvedMethod {
        var current_class: ?*ClassObject = receiver_class;
        var found_owner = false;

        while (current_class) |klass| {
            var i = klass.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module_obj = klass.prepended_modules.items[i];
                if (!found_owner) {
                    if (module_obj == defining_module) found_owner = true;
                    continue;
                }
                if (module_obj.methods.get(method_name)) |entry| {
                    return switch (self.resolveLookupEntry(method_name, klass, entry)) {
                        .found => |resolved| resolved,
                        .undefined, .not_found => null,
                    };
                }
            }

            if (found_owner) {
                if (klass.module.methods.get(method_name)) |entry| {
                    return switch (self.resolveLookupEntry(method_name, klass, entry)) {
                        .found => |resolved| resolved,
                        .undefined, .not_found => null,
                    };
                }
            } else if (&klass.module == defining_module) {
                found_owner = true;
            }

            i = klass.included_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module_obj = klass.included_modules.items[i];
                if (!found_owner) {
                    if (module_obj == defining_module) found_owner = true;
                    continue;
                }
                if (module_obj.methods.get(method_name)) |entry| {
                    return switch (self.resolveLookupEntry(method_name, klass, entry)) {
                        .found => |resolved| resolved,
                        .undefined, .not_found => null,
                    };
                }
            }

            current_class = klass.superclass;
        }

        return null;
    }

    pub fn methodArityValue(self: *VM, resolved: ResolvedMethod) VMError!Value {
        _ = self;
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
                .symbol, .builtin, .callable => Value.integer(-1),
            },
            .builtin => blk: {
                if (std.mem.eql(u8, resolved.name.name, "send") or
                    std.mem.eql(u8, resolved.name.name, "__send__") or
                    std.mem.eql(u8, resolved.name.name, "raise") or
                    std.mem.eql(u8, resolved.name.name, "fail") or
                    std.mem.eql(u8, resolved.name.name, "to_enum") or
                    std.mem.eql(u8, resolved.name.name, "enum_for"))
                {
                    break :blk Value.integer(-1);
                }
                break :blk Value.integer(0);
            },
            .undefined => unreachable,
        };
    }

    /// Copy forwarding arguments into the provided buffer.
    /// Without rest params, this copies param slots directly from the environment.
    /// With rest params, the rest array is expanded inline.
    /// Returns the slice of buf that was filled.
    fn getForwardingArguments(_: *VM, frame: *CallFrame, buf: *[256]Value) []Value {
        const ch = frame.chunk;
        const env = derefEnvironment(frame.ep);
        const param_count = ch.arity + ch.optional_params.items.len + ch.post_required_count;

        if (ch.rest_param_index == null) {
            // Common case: copy param slots into buffer
            @memcpy(buf[0..param_count], env.variables[0..param_count]);
            return buf[0..param_count];
        }

        // Rest param case: copy slots, expanding the rest array inline
        const rest_idx = ch.rest_param_index.?;
        const total_slots = param_count + 1; // +1 for the rest slot itself
        var out: usize = 0;
        for (0..total_slots) |slot| {
            if (slot == rest_idx) {
                if (slot < env.variables_len and env.variables[slot].isArray()) {
                    for (env.variables[slot].toArrayObject().elements.items) |elem| {
                        buf[out] = elem;
                        out += 1;
                    }
                }
            } else {
                buf[out] = if (slot < env.variables_len) env.variables[slot] else Value.nil();
                out += 1;
            }
        }

        return buf[0..out];
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
                .module => |defining_module| self.lookupMethodForSuperFromIncludedModule(self.getClass(frame.self_value), defining_module, method_name_sym),
                .class => |defining_class| if (frame.super_defining_class) |explicit_defining_class|
                    self.lookupMethodForSuper(explicit_defining_class, method_name_sym)
                else
                    self.lookupMethodForSuper(defining_class, method_name_sym),
            }
        else if (frame.super_defining_class) |defining_class|
            self.lookupMethodForSuper(defining_class, method_name_sym)
        else
            null;

        const resolved = maybe_resolved orelse {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "super: no superclass method '{s}' for {s}",
                .{ method_name, self.getClass(frame.self_value).module.name.name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.no_method_error_class, msg);
            self.pending_exception = exc;
            return error.Unwind;
        };

        // Call with the same receiver (self)
        const receiver = frame.self_value;

        switch (resolved.entry.method) {
            .chunk => |method_chunk| {
                // Push frame with receiver as self_value
                try self.pushFrame(method_chunk, receiver, block);

                // Copy arguments with rest parameter handling
                const new_frame = self.currentFrame();
                try self.copyArgumentsWithRestParam(method_chunk, new_frame.ep, args, .strict);

                // Bind block parameter if present
                if (method_chunk.block_param_index) |block_idx| {
                    const current_frame = &self.frames.items[self.frames.items.len - 1];

                    if (current_frame.block) |blk| {
                        const proc_val = try self.newProc(blk);
                        const f = &self.frames.items[self.frames.items.len - 1];
                        f.ep.variables[block_idx] = proc_val;
                    } else {
                        current_frame.ep.variables[block_idx] = Value.nil();
                    }

                    const f = &self.frames.items[self.frames.items.len - 1];
                    if (block_idx >= f.ep.variables_len) {
                        f.ep.variables_len = block_idx + 1;
                    }
                }
            },
            .builtin => |fun_ptr| {
                // For builtin methods, we need a mutable copy
                var args_copy: [256]Value = undefined;
                @memcpy(args_copy[0..args.len], args);
                const result = try self.invokeBuiltinMethod(fun_ptr, receiver, args_copy[0..args.len], block, null);
                try self.push(result);
            },
            .proc => |proc_obj| {
                const result = try self.callProcAsMethod(proc_obj, receiver, args, block, resolved.name.name, resolved.owner_class);
                try self.push(result);
            },
            .undefined => unreachable,
        }
    }

    pub fn getOrCreateSingletonClass(self: *VM, obj_val: value.Value) VMError!*ClassObject {
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
            self.pending_exception = exc;
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
                        break :blk try self.getOrCreateSingletonClass(Value.fromObject(super));
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
                .constants = std.AutoHashMap(*value.SymbolObject, value.Value).init(self.gc_allocator),
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

        for (source_singleton.prepended_modules.items) |module_obj| {
            target_singleton.prepended_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        for (source_singleton.included_modules.items) |module_obj| {
            target_singleton.included_modules.append(self.gc_allocator, module_obj) catch return error.Fatal;
        }

        target_singleton.module.object.flags |= source_singleton.module.object.flags & value.Object.FROZEN_FLAG;
        self.bumpMethodStateVersion();
    }

    pub fn copyObjectInstanceVariables(self: *VM, source_obj: *const Object, target_obj: *Object) VMError!void {
        const src_ivars = source_obj.instance_variables orelse return;

        var copied_ivars = std.AutoHashMap(*value.SymbolObject, Value).init(self.gc_allocator);
        var iter = src_ivars.iterator();
        while (iter.next()) |entry| {
            copied_ivars.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
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
        const probe_key = SymbolKey{
            .bytes = str,
            .encoding_tag = @as(SymbolEncodingTag, symbol_encoding),
        };
        if (self.symbols.get(probe_key)) |symbol_obj| {
            return symbol_obj;
        }

        const key_bytes = self.gc_allocator_atomic.dupe(u8, str) catch return error.Fatal;
        const map_key = SymbolKey{
            .bytes = key_bytes,
            .encoding_tag = @as(SymbolEncodingTag, symbol_encoding),
        };

        const symbol_obj = self.gc_allocator.create(SymbolObject) catch return error.Fatal;
        symbol_obj.* = .{
            .object = .{ .type_tag = .symbol, .flags = Object.FROZEN_FLAG, .class = self.symbol_class, .singleton_class = null, .instance_variables = null },
            .name = key_bytes,
            .encoding = symbol_encoding,
        };
        self.symbols.put(map_key, symbol_obj) catch return error.Fatal;
        return symbol_obj;
    }

    // ==== Object creation ====

    pub fn newModule(self: *VM, name: *SymbolObject) VMError!Value {
        const module_obj = self.gc_allocator.create(value.ModuleObject) catch return error.Fatal;
        module_obj.* = .{
            .object = .{ .type_tag = .module, .flags = 0, .class = self.module_class, .singleton_class = null, .instance_variables = null },
            .name = name,
            .methods = std.AutoHashMap(*SymbolObject, MethodEntry).init(self.gc_allocator),
            .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
            .class_variables = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
        };
        return Value.fromObject(module_obj);
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
                .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
                .class_variables = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
            },
        };
        return Value.fromObject(class_obj);
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
        initFiberEnvironmentStackInPlace(&fiber_obj.env_stack);
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
        return Value.fromObject(fiber_obj);
    }

    pub fn newIo(
        self: *VM,
        class_obj: *ClassObject,
        fd: i32,
        owns_fd: bool,
        readable: bool,
        writable: bool,
        append: bool,
    ) VMError!Value {
        const io_obj = self.gc_allocator.create(value.IoObject) catch return error.Fatal;
        io_obj.* = .{
            .object = .{ .type_tag = .io, .flags = 0, .class = class_obj, .singleton_class = null, .instance_variables = null },
            .fd = fd,
            .owns_fd = owns_fd,
            .closed = false,
            .readable = readable,
            .writable = writable,
            .append = append,
        };
        self.io_objects.append(self.gc_allocator, io_obj) catch return error.Fatal;
        return Value.fromObject(io_obj);
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
        return Value.fromObject(range_obj);
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
        return Value.fromObject(regexp_obj);
    }

    pub fn newRegexp(self: *VM, pattern: []const u8, options: u16) VMError!Value {
        return self.newRegexpWithEncoding(pattern, options, .{ .utf8 = .{} });
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

        return Value.fromObject(md);
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
        const match_val = Value.fromObject(match_data);
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
            return Value.fromObject(try self.createException(class_obj, ""));
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
                break :blk Value.fromObject(array_obj);
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
                };
                break :blk Value.fromObject(hash_obj);
            },
            .range => self.newRange(class_obj),
            .fiber => try self.newFiber(class_obj, null),
            .io => try self.newIo(class_obj, -1, false, false, false, false),
            .instance => self.newInstance(class_obj),
        };
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

    pub fn setInstanceVariable(self: *VM, receiver: Value, name: []const u8, val: Value) VMError!void {
        const obj_ptr = receiver.getObjectPointer() orelse {
            const exc = try self.createException(self.type_error_class, "can't define singleton method for literals");
            self.pending_exception = exc;
            return error.Unwind;
        };

        if (obj_ptr.instance_variables == null) {
            obj_ptr.instance_variables = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator);
        }

        const name_sym = try self.intern(name);
        obj_ptr.instance_variables.?.put(name_sym, val) catch return error.Fatal;
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

    pub fn setLastProcessStatus(self: *VM, exitstatus: i64) VMError!void {
        const status_obj = try self.newInstance(self.process_status_class);
        try self.setInstanceVariable(status_obj, "@exitstatus", Value.integer(exitstatus));
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
        self.canonical_fstrings.append(self.allocator, frozen) catch return error.Fatal;
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

        self.canonical_fstrings.append(self.allocator, string_value) catch return error.Fatal;
        return string_value;
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
        return Value.fromObject(float_obj);
    }

    pub fn newBigIntegerFromI64(self: *VM, n: i64) VMError!Value {
        const managed = std.math.big.int.Managed.initSet(self.gc_allocator, n) catch return error.Fatal;
        const big_obj = self.gc_allocator.create(BigIntegerObject) catch return error.Fatal;
        big_obj.* = .{
            .object = .{ .type_tag = .big_integer, .flags = 0, .class = self.integer_class, .singleton_class = null, .instance_variables = null },
            .value = managed,
        };
        return Value.fromObject(big_obj);
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
        return Value.fromObject(big_obj);
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
        return Value.fromObject(big_obj);
    }

    pub fn registerPackedPointerTarget(self: *VM, packed_str: *StringObject, offset: usize, target: *StringObject) VMError!void {
        if (self.packed_pointer_targets.getPtr(packed_str)) |targets| {
            targets.put(offset, target) catch return error.Fatal;
            return;
        }

        var targets = PackedPointerTargets.init(self.allocator);
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
        var copied = PackedPointerTargets.init(self.allocator);
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
        return Value.fromObject(string_obj);
    }

    pub fn inspectTargetEncoding(self: *VM) enc.Encoding {
        return inspect_util.targetEncoding(
            if (self.default_internal_encoding) |encoding_obj| encoding_obj.encoding else null,
            self.default_external_encoding.encoding,
        );
    }

    pub fn encodingToValue(self: *VM, encoding_value: enc.Encoding) Value {
        return switch (encoding_value) {
            .utf8 => Value.fromObject(self.encoding_utf8),
            .cesu8 => Value.fromObject(self.encoding_cesu8),
            .ascii_8bit => Value.fromObject(self.encoding_ascii_8bit),
            .us_ascii => Value.fromObject(self.encoding_us_ascii),
            .shift_jis => Value.fromObject(self.encoding_shift_jis),
            .windows_31j => Value.fromObject(self.encoding_windows_31j),
            .euc_jp => Value.fromObject(self.encoding_euc_jp),
            .cp437 => Value.fromObject(self.encoding_cp437),
            .iso_2022_jp => Value.fromObject(self.encoding_iso_2022_jp),
            .iso_8859_9 => Value.fromObject(self.encoding_iso_8859_9),
            .iso_8859_15 => Value.fromObject(self.encoding_iso_8859_15),
            .utf7 => Value.fromObject(self.encoding_utf7),
            .utf16 => Value.fromObject(self.encoding_utf16),
            .utf32 => Value.fromObject(self.encoding_utf32),
            .utf16le => Value.fromObject(self.encoding_utf16le),
            .utf16be => Value.fromObject(self.encoding_utf16be),
            .utf32le => Value.fromObject(self.encoding_utf32le),
            .utf32be => Value.fromObject(self.encoding_utf32be),
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
                .symbol => block,
                .builtin => block,
                .callable => block,
                .chunk => |chunk_blk| .{ .kind = .{ .chunk = .{
                    .chunk = chunk_blk.chunk,
                    .defining_ep = self.promoteEnvironmentToHeap(chunk_blk.defining_ep) catch return error.Fatal,
                    .defining_self = chunk_blk.defining_self,
                    .return_target_ep = if (chunk_blk.return_target_ep) |target_ep|
                        self.promoteEnvironmentToHeap(target_ep) catch return error.Fatal
                    else
                        null,
                } } },
            },
        };
        return Value.fromObject(proc_obj);
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
        return Value.fromObject(enum_obj);
    }

    pub fn newYielder(self: *VM, block: Block) VMError!Value {
        const yielder_obj = self.gc_allocator.create(value.YielderObject) catch return error.Fatal;
        yielder_obj.* = .{
            .object = .{ .type_tag = .yielder, .flags = 0, .class = self.yielder_class, .singleton_class = null, .instance_variables = null },
            .block = block,
        };
        return Value.fromObject(yielder_obj);
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
        for (self.integer_class.prepended_modules.items) |prepended| {
            if (prepended == module) return true;
        }
        for (self.integer_class.included_modules.items) |included| {
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

    pub fn includeModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) VMError!void {
        class.included_modules.append(self.gc_allocator, module) catch return error.Fatal;
        if (class == self.integer_class) {
            self.integer_changed = true;
        }
        self.bumpMethodStateVersion();
    }

    pub fn prependModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) VMError!void {
        class.prepended_modules.append(self.gc_allocator, module) catch return error.Fatal;
        if (class == self.integer_class) {
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
        chunk_ptr.setSourceFile(self.current_loading_file orelse self.program.main_chunk.source_file) catch return error.Fatal;
        chunk_ptr.lexical_scope = self.current_lexical_scope;
        chunk_ptr.arity = if (kind == .reader) 0 else 1;

        const name_idx = chunk_ptr.addConstant(.{ .string = ivar_name }) catch return error.Fatal;

        switch (kind) {
            .reader => {
                chunk_ptr.emitOpU16(.GET_IVAR, @intCast(name_idx), 0) catch return error.Fatal;
                chunk_ptr.emitOpU8(.RETURN, 0, 0) catch return error.Fatal;
            },
            .writer => {
                chunk_ptr.emitOpU8(.GET_LOCAL, 0, 0) catch return error.Fatal;
                chunk_ptr.emitOpU16(.SET_IVAR, @intCast(name_idx), 0) catch return error.Fatal;
                chunk_ptr.emitOpU8(.RETURN, 0, 0) catch return error.Fatal;
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
            .thread => arg.isThread(),
        };
        if (!matches) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "argument is not {s} {s}",
                .{ if (type_name[0] == 'A' or type_name[0] == 'I' or type_name[0] == 'O') "an" else "a", type_name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.type_error_class, msg);
            self.pending_exception = exc;
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
            self.pending_exception = exc;
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

    pub fn probeToAry(self: *VM, arg: Value) VMError!ToAryResult {
        if (arg.isArray()) return .{ .array = arg };

        const maybe_array = try self.checkCallMethodByName(arg, "to_ary", false, &[_]Value{}, null);
        const coerced = maybe_array orelse return .missing;
        if (coerced.isNil()) return .nil_result;
        if (coerced.isArray()) return .{ .array = coerced };

        return self.raiseExceptionFmt(
            self.type_error_class,
            "can't convert {s} to Array ({s}#to_ary gives {s})",
            .{ self.className(arg), self.className(arg), self.className(coerced) },
        );
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
        if (arg.isNil()) return Value.fromObject(try self.createArray());

        if (try self.checkCallMethodByName(arg, "to_a", false, &[_]Value{}, null)) |coerced| {
            if (coerced.isNil()) {
                const wrapped = try self.createArray();
                wrapped.elements.append(self.gc_allocator, arg) catch return error.Fatal;
                return Value.fromObject(wrapped);
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
        return Value.fromObject(wrapped);
    }

    pub fn coerceToPath(self: *VM, arg: Value, type_error_message: []const u8) VMError![]const u8 {
        const maybe_candidate = try self.checkCallMethodByName(arg, "to_path", false, &[_]Value{}, null);
        const candidate = maybe_candidate orelse arg;

        return candidate.coerceToStr(self, type_error_message);
    }

    pub fn coerceToPathValue(self: *VM, arg: Value, type_error_message: []const u8) VMError!Value {
        const maybe_candidate = try self.checkCallMethodByName(arg, "to_path", false, &[_]Value{}, null);
        const candidate = maybe_candidate orelse arg;

        return candidate.coerceToStringValue(self, type_error_message);
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
        self.pending_exception = exc;
        return error.Unwind;
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
            if (self.pending_exception) |exc| {
                self.pending_exception = exc;
                return error.Unwind;
            }
            return self.raiseExceptionFmt(self.runtime_error_class, "{s}", .{no_current_exception_message});
        }

        if (args.len == 1) {
            if (args[0].isException()) {
                self.pending_exception = args[0].toExceptionObject();
                return error.Unwind;
            } else if (args[0].isClass()) {
                const exc = self.createException(args[0].toClassObject(), "") catch return error.Fatal;
                self.pending_exception = exc;
                return error.Unwind;
            } else if (args[0].isString()) {
                const exc = self.createException(self.runtime_error_class, args[0].toStringObject().str) catch return error.Fatal;
                self.pending_exception = exc;
                return error.Unwind;
            } else {
                return self.raiseExceptionFmt(self.type_error_class, "exception class/object expected", .{});
            }
        }

        if (args.len == 2) {
            if (!args[0].isClass()) {
                return self.raiseExceptionFmt(self.type_error_class, "exception class/object expected", .{});
            }
            const msg_str = if (args[1].isString()) args[1].toStringObject().str else "";
            const exc = self.createException(args[0].toClassObject(), msg_str) catch return error.Fatal;
            self.pending_exception = exc;
            return error.Unwind;
        }

        return self.raiseArgumentErrorWrongArgCountGeneric();
    }

    // File loading helper methods

    pub fn resolveAbsolutePath(self: *VM, path: []const u8) VMError![]const u8 {
        var path_buffer: [4096]u8 = undefined;
        const absolute = std.fs.cwd().realpath(path, &path_buffer) catch {
            if (std.fs.path.isAbsolute(path)) {
                return self.allocator.dupe(u8, path) catch return error.Fatal;
            }
            return error.Fatal;
        };
        return self.allocator.dupe(u8, absolute) catch return error.Fatal;
    }

    pub fn fileExists(_: *VM, path: []const u8) bool {
        const file = std.fs.cwd().openFile(path, .{}) catch return false;
        file.close();
        return true;
    }

    pub fn searchLoadPath(self: *VM, feature: []const u8) VMError!?[]const u8 {
        if (std.fs.path.isAbsolute(feature)) {
            if (self.fileExists(feature)) {
                return try self.resolveAbsolutePath(feature);
            }
            return null;
        }

        for (self.load_path.items) |dir| {
            const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ dir, feature }) catch return error.Fatal;
            defer self.allocator.free(full_path);

            if (self.fileExists(full_path)) {
                return try self.resolveAbsolutePath(full_path);
            }
        }

        const with_rb = std.fmt.allocPrint(self.allocator, "{s}.rb", .{feature}) catch return error.Fatal;
        defer self.allocator.free(with_rb);

        for (self.load_path.items) |dir| {
            const full_path = std.fs.path.join(self.allocator, &[_][]const u8{ dir, with_rb }) catch return error.Fatal;
            defer self.allocator.free(full_path);

            if (self.fileExists(full_path)) {
                return try self.resolveAbsolutePath(full_path);
            }
        }

        return null;
    }

    pub fn loadFile(self: *VM, absolute_path: []const u8) VMError!void {
        const file_handle = std.fs.cwd().openFile(absolute_path, .{}) catch return error.Fatal;
        defer file_handle.close();

        const file_size = file_handle.getEndPos() catch return error.Fatal;
        const code_buffer = self.gc_allocator_atomic.alloc(u8, file_size) catch return error.Fatal;

        const bytes_read = file_handle.readAll(code_buffer) catch return error.Fatal;
        if (bytes_read != file_size) return error.Fatal;

        var parser = prism.Parser.init(self.allocator, code_buffer, absolute_path) catch return error.Fatal;
        defer parser.deinit();

        var program = compiler.Compiler.compile(self.allocator, &parser, self.next_chunk_id) catch return error.Fatal;
        // Ensure cleanup of the loaded program's chunks on error
        defer {
            program.main_chunk.deinit();
            program.child_chunks.deinit();
        }

        self.next_chunk_id = program.next_chunk_id;
        try self.buildChunkCallsiteDescriptors(&program.main_chunk);
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
        self.current_loading_file = absolute_path;
        defer self.current_loading_file = prev_file;

        try self.executeChunk(&program.main_chunk);
    }

    pub fn evalSource(self: *VM, source: []const u8, source_file: ?[]const u8) VMError!Value {
        return self.evalSourceWithEncoding(source, source_file, null);
    }

    pub fn evalSourceWithEncoding(self: *VM, source: []const u8, source_file: ?[]const u8, source_encoding: ?enc.Encoding) VMError!Value {
        return self.evalSourceWithEncodingAndContext(source, source_file, source_encoding, null);
    }

    pub const EvalContext = struct {
        self_value: Value,
        parent_env: ?*Environment,
        lexical_scope: ?*LexicalScope,
        dir_returns_nil: bool = false,
    };

    pub fn evalSourceWithEncodingAndContext(
        self: *VM,
        source: []const u8,
        source_file: ?[]const u8,
        source_encoding: ?enc.Encoding,
        context: ?EvalContext,
    ) VMError!Value {
        var parser = prism.Parser.initWithEncoding(self.allocator, source, source_file, source_encoding) catch {
            return self.raiseExceptionFmt(self.syntax_error_class, "{s}: syntax error", .{source_file orelse "(eval)"});
        };
        defer parser.deinit();

        var eval_program = compiler.Compiler.compile(self.allocator, &parser, self.next_chunk_id) catch {
            return self.raiseExceptionFmt(self.syntax_error_class, "{s}: syntax error", .{source_file orelse "(eval)"});
        };
        defer eval_program.main_chunk.deinit();
        defer eval_program.child_chunks.deinit();

        self.next_chunk_id = eval_program.next_chunk_id;

        try self.buildChunkCallsiteDescriptors(&eval_program.main_chunk);
        var iter = eval_program.child_chunks.valueIterator();
        while (iter.next()) |chunk_ptr| {
            try self.buildChunkCallsiteDescriptors(chunk_ptr.*);
        }

        var ownership_iter = eval_program.child_chunks.iterator();
        while (ownership_iter.next()) |entry| {
            self.program.child_chunks.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        if (context) |ctx| {
            return self.executeChunkInContextWithOptions(
                &eval_program.main_chunk,
                ctx.self_value,
                ctx.parent_env,
                ctx.lexical_scope,
                ctx.dir_returns_nil,
            );
        }

        if (self.frames.items.len > 0) {
            const current_frame = self.currentFrame();
            return self.executeChunkInContext(
                &eval_program.main_chunk,
                current_frame.self_value,
                current_frame.ep,
                self.current_lexical_scope,
            );
        }

        return self.executeChunkInContext(
            &eval_program.main_chunk,
            self.main_self,
            null,
            self.current_lexical_scope,
        );
    }

    fn executeChunk(self: *VM, target_chunk: *Chunk) VMError!void {
        _ = try self.executeChunkInContext(
            target_chunk,
            self.main_self,
            null,
            target_chunk.lexical_scope orelse self.current_lexical_scope,
        );
    }

    fn executeChunkInContext(
        self: *VM,
        target_chunk: *Chunk,
        self_value: Value,
        parent_env: ?*Environment,
        lexical_scope: ?*LexicalScope,
    ) VMError!Value {
        return self.executeChunkInContextWithOptions(target_chunk, self_value, parent_env, lexical_scope, false);
    }

    fn executeChunkInContextWithOptions(
        self: *VM,
        target_chunk: *Chunk,
        self_value: Value,
        parent_env: ?*Environment,
        lexical_scope: ?*LexicalScope,
        dir_returns_nil: bool,
    ) VMError!Value {
        const env = try self.createStackEnvironment(parent_env, lexical_scope);
        const saved_stack_len = self.stack.items.len;
        const caller_frame_depth = self.frames.items.len;

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = target_chunk,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .ep = env,
            .block = null,
            .frame_type = .method,
            .dir_returns_nil = dir_returns_nil,
        }) catch return error.Fatal;

        if (lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }

        try self.executeUntilReturn(caller_frame_depth);

        return if (self.stack.items.len > saved_stack_len)
            self.pop()
        else
            Value.nil();
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
        };
        return hash_ptr;
    }

    pub fn createBinding(self: *VM, self_value: Value, env: ?*Environment, lexical_scope: ?*LexicalScope) VMError!*value.BindingObject {
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
            .env = env,
            .lexical_scope = lexical_scope,
        };
        return binding_ptr;
    }

    pub const ArityMode = enum { strict, lenient };

    /// Execute a default parameter expression chunk and return its value
    fn executeDefaultExpression(
        self: *VM,
        default_chunk: *const Chunk,
        env: *Environment,
    ) VMError!Value {
        const saved_stack_len = self.stack.items.len;

        // Push frame for default expression (use current env directly)
        const default_frame = CallFrame{
            .chunk = @constCast(default_chunk),
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self.currentFrame().self_value,
            .ep = env, // Use current environment directly
            .frame_type = .method,
            .block = null,
        };

        self.frames.append(self.gc_allocator, default_frame) catch return error.Fatal;

        // Execute instructions until this frame completes
        const saved = self.frames.items.len - 1;
        try self.executeUntilReturn(saved);

        // Pop result from stack (default chunk returns a value)
        const default_value = if (self.stack.items.len > saved_stack_len)
            self.pop()
        else
            Value.nil();

        return default_value;
    }

    pub fn copyArgumentsWithRestParam(
        self: *VM,
        target_chunk: *const Chunk,
        env: *Environment,
        args: []const Value,
        mode: ArityMode,
    ) VMError!void {
        var effective_args = args;
        if (mode == .lenient and args.len == 1 and args[0].isArray()) {
            const positional_slots = target_chunk.arity + target_chunk.optional_params.items.len + target_chunk.post_required_count;
            if (positional_slots > 1) {
                effective_args = args[0].toArrayObject().elements.items;
            }
        }

        const optional_count = target_chunk.optional_params.items.len;
        const min_required = target_chunk.arity + target_chunk.post_required_count;
        const max_without_rest = target_chunk.arity + optional_count + target_chunk.post_required_count;

        // Calculate min/max args based on whether rest param exists
        const min_args = min_required;
        const max_args = if (target_chunk.rest_param_index != null)
            std.math.maxInt(usize)
        else
            max_without_rest;

        // Arity checking
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
                env.variables[local_idx] = effective_args[arg_idx];
                arg_idx += 1;
            } else if (mode == .lenient) {
                env.variables[local_idx] = Value.nil();
            }
            local_idx += 1;
        }
        // Update variables_len so defaults can access earlier parameters
        env.variables_len = @intCast(local_idx);

        // 2. Handle optional parameters
        if (optional_count > 0) {
            // Determine how many optionals get arguments vs defaults
            // We need to reserve args for post-required params
            const args_remaining = if (arg_idx < effective_args.len) effective_args.len - arg_idx else 0;
            const args_available_for_optionals = if (args_remaining > target_chunk.post_required_count)
                args_remaining - target_chunk.post_required_count
            else
                0;

            const optionals_from_args = if (args_available_for_optionals > optional_count)
                optional_count
            else
                args_available_for_optionals;

            // Bind optionals that receive arguments
            i = 0;
            while (i < optionals_from_args) : (i += 1) {
                env.variables[local_idx] = effective_args[arg_idx];
                arg_idx += 1;
                local_idx += 1;
                env.variables_len = @intCast(local_idx); // Update so later defaults can see earlier optionals
            }

            // Evaluate defaults for remaining optionals
            while (i < optional_count) : (i += 1) {
                const opt_info = target_chunk.optional_params.items[i];
                const default_chunk = self.program.child_chunks.get(opt_info.default_chunk_id) orelse {
                    return error.Fatal;
                };

                // Execute default expression chunk and bind the result
                // (the default may set side-effect locals beyond local_idx via SET_LOCAL)
                const default_value = try self.executeDefaultExpression(default_chunk, env);
                env.variables[local_idx] = default_value;
                local_idx += 1;
                env.variables_len = @max(@as(u8, @intCast(local_idx)), env.variables_len);
            }
        }

        // 3. Handle rest parameter
        if (target_chunk.rest_param_index) |rest_idx| {
            // Calculate how many args go into rest array
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
            env.variables[rest_idx] = Value.fromObject(rest_array);
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
                env.variables[local_idx] = effective_args[post_arg_idx];
            } else if (mode == .lenient) {
                env.variables[local_idx] = Value.nil();
            }
            local_idx += 1;
        }

        env.variables_len = @max(@as(u8, @intCast(local_idx)), env.variables_len);
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
                self.pending_exception != null and
                self.pending_exception.?.object.class == self.no_method_error_class)
            {
                self.pending_exception = null;
                return lookup_key.eql(stored_key);
            }
            return err;
        };
        return result.is_truthy();
    }

    pub fn hashFindEntryIndex(_: *VM, hash_obj: *value.HashObject, key: Value) VMError!?usize {
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
        const removed = try hash_obj.map.fetchRemove(key);
        const idx = removed orelse return null;
        const deleted = hash_obj.entries.orderedRemove(idx.value).value;
        try self.hashRebuildIndexes(hash_obj);
        return deleted;
    }

    fn coerceKwSplatToHash(self: *VM, kw_val: Value) VMError!?*value.HashObject {
        if (kw_val.isNil()) return null;
        if (kw_val.isHash()) return kw_val.toHashObject();

        const empty_args = [_]Value{};
        const maybe_hash = try self.checkCallMethodByName(kw_val, "to_hash", false, empty_args[0..], null);
        if (maybe_hash == null) {
            const exc = try self.createException(self.type_error_class, "no implicit conversion into Hash");
            self.pending_exception = exc;
            return error.Unwind;
        }
        if (!maybe_hash.?.isHash()) {
            const exc = try self.createException(self.type_error_class, "can't convert to Hash");
            self.pending_exception = exc;
            return error.Unwind;
        }

        return maybe_hash.?.toHashObject();
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
        };

        for (kw_values, 0..) |kw_value, i| {
            try self.hashSetEntry(kw_hash, kw_keys[i], kw_value);
        }

        return Value.fromObject(kw_hash);
    }

    fn bindKeywordArguments(
        self: *VM,
        target_chunk: *const Chunk,
        env: *Environment,
        kw_keys: []const Value,
        kw_values: []const Value,
    ) VMError!void {
        if (kw_keys.len != kw_values.len) return error.Fatal;

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
                    env.variables[req_kw.param_slot] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                const msg = std.fmt.allocPrint(self.gc_allocator, "missing keyword: {s}", .{req_name}) catch return error.Fatal;
                const exc = try self.createException(self.argument_error_class, msg);
                self.pending_exception = exc;
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
                    env.variables[opt_kw.param_slot] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                const default_chunk = self.program.child_chunks.get(opt_kw.default_chunk_id).?;
                const default_value = try self.executeDefaultExpression(default_chunk, env);
                env.variables[opt_kw.param_slot] = default_value;
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
            };

            for (kw_values, 0..) |kw_value, i| {
                if (!matched[i]) {
                    try self.hashSetEntry(kw_hash, kw_keys[i], kw_value);
                }
            }

            env.variables[rest_idx] = Value.fromObject(kw_hash);
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
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            }
        }

        var max_slot: u8 = 0;
        for (target_chunk.required_keywords.items) |req_kw| {
            if (req_kw.param_slot >= max_slot) max_slot = req_kw.param_slot + 1;
        }
        for (target_chunk.optional_keywords.items) |opt_kw| {
            if (opt_kw.param_slot >= max_slot) max_slot = opt_kw.param_slot + 1;
        }
        if (target_chunk.keyword_rest_index) |rest_idx| {
            if (rest_idx >= max_slot) max_slot = rest_idx + 1;
        }
        if (max_slot > env.variables_len) {
            env.variables_len = max_slot;
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
            .cause = self.pending_exception,
            .receiver = null,
            .key = null,
        };

        return exc;
    }

    /// Capture current call stack as a backtrace
    fn captureBacktrace(self: *VM) VMError!?*value.ArrayObject {
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
        var i = self.frames.items.len;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames.items[i];

            const line = self.backtraceLineForFrame(frame);
            const source = frame.chunk.source_file orelse frame.chunk.name;
            const backtrace_str = if (frame.method_name) |method_name|
                std.fmt.allocPrint(
                    self.gc_allocator,
                    "{s}:{d}:in '{s}#{s}'",
                    .{ source, line, self.getClass(frame.self_value).module.name.name, method_name },
                ) catch return error.Fatal
            else
                std.fmt.allocPrint(
                    self.gc_allocator,
                    "{s}:{d}:in '<main>'",
                    .{ source, line },
                ) catch return error.Fatal;

            const str_val = try self.newString(backtrace_str, false);
            array_obj.elements.append(self.gc_allocator, str_val) catch return error.Fatal;
        }

        return array_obj;
    }

    fn backtraceLineForFrame(_: *VM, frame: *const CallFrame) u32 {
        if (frame.chunk.line_info.items.len == 0) return 1;
        const ip = if (frame.ip == 0) 0 else frame.ip - 1;
        const line = frame.chunk.getLine(ip);
        return if (line == 0) 1 else line;
    }

    fn writeFormattedException(_: *VM, writer: anytype, exc: *value.ExceptionObject, limit: ?usize) VMError!void {
        const class_name = exc.object.class.?.module.name.name;

        if (exc.backtrace == null or exc.backtrace.?.elements.items.len == 0) {
            writer.print("{s} ({s})\n", .{ exc.message.str, class_name }) catch return error.Fatal;
            return;
        }

        const lines = exc.backtrace.?.elements.items;
        writer.print("{s}: {s} ({s})\n", .{ lines[0].toStringObject().str, exc.message.str, class_name }) catch return error.Fatal;

        const total_tail = lines.len - 1;
        const shown_tail = if (limit) |tail_limit|
            @min(total_tail, tail_limit)
        else
            total_tail;

        var i: usize = 0;
        while (i < shown_tail) : (i += 1) {
            writer.print("\tfrom {s}\n", .{lines[i + 1].toStringObject().str}) catch return error.Fatal;
        }

        if (limit) |tail_limit| {
            if (total_tail > tail_limit) {
                writer.print("\t ... {d} levels...\n", .{total_tail - tail_limit}) catch return error.Fatal;
            }
        }
    }

    pub fn exceptionFullMessage(self: *VM, exc: *value.ExceptionObject) VMError!Value {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);
        try self.writeFormattedException(&writer, exc, self.backtrace_limit);

        const full_message = buf.toOwnedSlice(self.allocator) catch return error.Fatal;
        defer self.allocator.free(full_message);
        return try self.newString(full_message, false);
    }

    /// Unwind the call stack looking for exception handlers
    pub fn unwindStack(self: *VM) VMError!void {
        if (try self.unwindStackUntilFrameDepth(0)) {
            return;
        }

        // No handler was found in any frame.
        // Caller (main.zig) will print the unhandled exception.
        return error.UnhandledException;
    }

    fn unwindStackUntilFrameDepth(self: *VM, min_frame_len: usize) VMError!bool {
        while (self.frames.items.len > min_frame_len) {
            const frame_idx = self.frames.items.len - 1;

            if (try self.findExceptionHandler(frame_idx)) |handler_info| {
                if (handler_info.rescue_idx) |rescue_idx| {
                    const rescue_handler = &handler_info.handler.rescue_handlers.items[rescue_idx];
                    try setFrameIp(&self.frames.items[frame_idx], rescue_handler.catch_byte_offset);
                    return true;
                } else if (handler_info.handler.ensure_byte_offset) |ensure_byte_offset| {
                    try setFrameIp(&self.frames.items[frame_idx], ensure_byte_offset);
                    return true;
                }
            }

            const unwind_stack_base = self.frames.items[frame_idx].stack_base;
            try self.popFrame();
            self.stack.shrinkRetainingCapacity(unwind_stack_base);
        }

        return false;
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
                    if (!try self.unwindStackUntilFrameDepth(caller_frame_depth))
                        return error.Unwind;
                    // Handler found — if it's in a frame below our target (shouldn't happen),
                    // propagate since the callee frame is gone.
                    if (self.frames.items.len < target_frame_depth)
                        return error.Unwind;
                },
                else => return err,
            };
        }
    }

    fn executeRescueTypeExpression(
        self: *VM,
        rescue_type_chunk: *const Chunk,
        env: *Environment,
        self_value: Value,
    ) VMError!Value {
        const saved_stack_len = self.stack.items.len;
        const saved = self.frames.items.len;

        const rescue_type_frame = CallFrame{
            .chunk = @constCast(rescue_type_chunk),
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .ep = env,
            .frame_type = .method,
            .block = null,
        };

        self.frames.append(self.gc_allocator, rescue_type_frame) catch return error.Fatal;

        try self.executeUntilReturn(saved);

        const rescue_type = if (self.stack.items.len > saved_stack_len)
            self.pop()
        else
            Value.nil();

        return rescue_type;
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
                for (class.prepended_modules.items) |module| {
                    if (module == type_module) return true;
                }
                for (class.included_modules.items) |module| {
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
                    if (rescue.exception_type_expr_chunks.items.len == 0) {
                        // Bare rescue catches StandardError
                        if (self.matchesException(self.pending_exception.?, self.standard_error_class)) {
                            return .{ .handler = handler, .rescue_idx = idx };
                        }
                    } else {
                        var rescue_eval_raised = false;

                        // Check each specified exception type expression
                        for (rescue.exception_type_expr_chunks.items) |type_expr_chunk_id| {
                            const rescue_type_chunk = self.program.child_chunks.get(type_expr_chunk_id) orelse {
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

                            const matches = self.matchesExceptionClassOrModule(self.pending_exception.?, rescue_type) catch |err| {
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
        if (self.pending_exception) |exc| {
            self.writeFormattedException(writer, exc, self.backtrace_limit) catch {};
            _ = writer.flush() catch {};
        } else {
            // Someone forgot to set pending_exception.
            writer.print("unknown error\n", .{}) catch {};
            _ = writer.flush() catch {};
        }
    }
};
