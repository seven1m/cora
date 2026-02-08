const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const compiler = @import("compiler.zig");
const enc = @import("encoding.zig");
const value = @import("value.zig");
const prism = @import("prism.zig");
const builtins = @import("builtins/builtins.zig");

const Value = value.Value;
const Object = value.Object;
const ClassObject = value.ClassObject;
const LexicalScope = value.LexicalScope;
const StringObject = value.StringObject;
const SymbolObject = value.SymbolObject;
const Chunk = chunk.Chunk;

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
    chunk: *Chunk,
    defining_ep: *Environment,
    defining_self: Value,
};

pub const CallFrame = struct {
    chunk: *Chunk,
    ip: usize,
    stack_base: usize,
    self_value: Value,
    ep: *Environment,
    block: ?Block = null,
    frame_type: enum { method, lambda, proc } = .method,
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,
    gc_allocator_atomic: std.mem.Allocator,

    parser: prism.Parser,

    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(CallFrame) = .empty,

    // Environment stack for optimistic allocation
    env_stack: std.ArrayList(Environment) = .empty,

    symbols: std.StringHashMap(*SymbolObject),
    globals: std.StringHashMap(Value),

    program: *compiler.CompiledProgram,

    current_lexical_scope: ?*LexicalScope = null,

    basic_object_class: *value.ClassObject,
    class_class: *value.ClassObject,
    integer_class: *value.ClassObject,
    module_class: *value.ClassObject,
    numeric_class: *value.ClassObject,
    object_class: *value.ClassObject,
    string_class: *value.ClassObject,
    symbol_class: *value.ClassObject,
    array_class: *value.ClassObject,
    hash_class: *value.ClassObject,
    proc_class: *value.ClassObject,
    nil_class: *value.ClassObject,
    true_class: *value.ClassObject,
    false_class: *value.ClassObject,
    kernel_module: *value.ModuleObject,
    main_self: Value,

    // Exception classes
    exception_class: *value.ClassObject,
    standard_error_class: *value.ClassObject,
    runtime_error_class: *value.ClassObject,
    argument_error_class: *value.ClassObject,
    type_error_class: *value.ClassObject,
    zero_division_error_class: *value.ClassObject,
    name_error_class: *value.ClassObject,
    no_method_error_class: *value.ClassObject,
    load_error_class: *value.ClassObject,

    // Encoding infrastructure
    encoding_class: *value.ClassObject,
    encoding_utf8: *value.EncodingObject,
    encoding_ascii_8bit: *value.EncodingObject,
    encoding_us_ascii: *value.EncodingObject,

    // Exception handling state
    pending_exception: ?*value.ExceptionObject = null,
    retry_point: ?struct {
        frame_idx: usize,
        ip: usize,
    } = null,

    // Block break state
    break_occurred: bool = false,

    at_exit_handlers: std.ArrayList(Value) = .empty,

    // File loading infrastructure
    loaded_files: std.StringHashMap(void) = std.StringHashMap(void).init(std.heap.page_allocator),
    loaded_paths: std.ArrayList([]const u8) = .empty,
    all_parsers: std.ArrayList(prism.Parser) = .empty,
    load_path: std.ArrayList([]const u8) = .empty,
    current_loading_file: ?[]const u8 = null,
    next_chunk_id: u16 = 1,

    // Buffered writers for production
    stdout_buffer: [4096]u8 = undefined,
    stderr_buffer: [4096]u8 = undefined,
    stdout_writer: ?std.fs.File.Writer = null,
    stderr_writer: ?std.fs.File.Writer = null,

    // Type-erased writers (tests can override these)
    stdout: ?*std.Io.Writer = null,
    stderr: ?*std.Io.Writer = null,

    pub fn initEmpty(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, gc_allocator_atomic: std.mem.Allocator, parser: prism.Parser) VM {
        return VM{
            .allocator = allocator,
            .gc_allocator = gc_allocator,
            .gc_allocator_atomic = gc_allocator_atomic,
            .parser = parser,
            .symbols = std.StringHashMap(*SymbolObject).init(gc_allocator),
            .globals = std.StringHashMap(Value).init(gc_allocator),
            .program = undefined,
            .basic_object_class = undefined,
            .class_class = undefined,
            .integer_class = undefined,
            .module_class = undefined,
            .numeric_class = undefined,
            .object_class = undefined,
            .string_class = undefined,
            .symbol_class = undefined,
            .array_class = undefined,
            .hash_class = undefined,
            .proc_class = undefined,
            .nil_class = undefined,
            .true_class = undefined,
            .false_class = undefined,
            .kernel_module = undefined,
            .exception_class = undefined,
            .standard_error_class = undefined,
            .runtime_error_class = undefined,
            .argument_error_class = undefined,
            .type_error_class = undefined,
            .zero_division_error_class = undefined,
            .name_error_class = undefined,
            .no_method_error_class = undefined,
            .load_error_class = undefined,
            .encoding_class = undefined,
            .encoding_utf8 = undefined,
            .encoding_ascii_8bit = undefined,
            .encoding_us_ascii = undefined,
            .main_self = undefined,
        };
    }

    pub fn prepare(self: *VM, program: *compiler.CompiledProgram) VMError!void {
        self.program = program;

        // Pre-allocate env_stack to prevent reallocations that would invalidate pointers
        // This is max call stack depth, not total calls - we reclaim on popFrame
        self.env_stack.ensureTotalCapacity(self.gc_allocator, 512) catch return error.Fatal;

        // Initialize file loading infrastructure
        self.loaded_files = std.StringHashMap(void).init(self.allocator);
        self.loaded_paths = .empty;
        self.load_path = .empty;
        const dot = self.allocator.dupe(u8, ".") catch return error.Fatal;
        self.load_path.append(self.allocator, dot) catch return error.Fatal;
        self.next_chunk_id = program.next_chunk_id;

        if (self.parser.source_file) |main_file| {
            const abs_path = try self.resolveAbsolutePath(main_file);
            self.loaded_files.put(abs_path, {}) catch return error.Fatal;
            self.current_loading_file = abs_path;
        }

        // --- Stage 1: Create Class and BasicObject ---
        const class_name_sym = try self.intern("Class");
        const class_class_val = try self.newClass(class_name_sym, null);
        self.class_class = class_class_val.data.class;
        self.class_class.module.object.class = self.class_class;

        const basic_object_name_sym = try self.intern("BasicObject");
        const basic_object_class_val = try self.newClass(basic_object_name_sym, null);
        self.basic_object_class = basic_object_class_val.data.class;

        // --- Stage 2: Create classes that inherit from BasicObject or Object ---
        const object_name_sym = try self.intern("Object");
        const object_class_val = try self.newClass(object_name_sym, self.basic_object_class);
        self.object_class = object_class_val.data.class;

        const module_name_sym = try self.intern("Module");
        const module_class_val = try self.newClass(module_name_sym, self.object_class);
        self.module_class = module_class_val.data.class;

        const numeric_name_sym = try self.intern("Numeric");
        const numeric_class_val = try self.newClass(numeric_name_sym, self.object_class);
        self.numeric_class = numeric_class_val.data.class;

        const integer_name_sym = try self.intern("Integer");
        const integer_class_val = try self.newClass(integer_name_sym, self.numeric_class);
        self.integer_class = integer_class_val.data.class;

        const string_name_sym = try self.intern("String");
        const string_class_val = try self.newClass(string_name_sym, self.object_class);
        self.string_class = string_class_val.data.class;

        const symbol_name_sym = try self.intern("Symbol");
        const symbol_class_val = try self.newClass(symbol_name_sym, self.object_class);
        self.symbol_class = symbol_class_val.data.class;

        const array_name_sym = try self.intern("Array");
        const array_class_val = try self.newClass(array_name_sym, self.object_class);
        self.array_class = array_class_val.data.class;

        const hash_name_sym = try self.intern("Hash");
        const hash_class_val = try self.newClass(hash_name_sym, self.object_class);
        self.hash_class = hash_class_val.data.class;

        const proc_name_sym = try self.intern("Proc");
        const proc_class_val = try self.newClass(proc_name_sym, self.object_class);
        self.proc_class = proc_class_val.data.class;

        const nil_class_name_sym = try self.intern("NilClass");
        const nil_class_val = try self.newClass(nil_class_name_sym, self.object_class);
        self.nil_class = nil_class_val.data.class;

        const true_class_name_sym = try self.intern("TrueClass");
        const true_class_val = try self.newClass(true_class_name_sym, self.object_class);
        self.true_class = true_class_val.data.class;

        const false_class_name_sym = try self.intern("FalseClass");
        const false_class_val = try self.newClass(false_class_name_sym, self.object_class);
        self.false_class = false_class_val.data.class;

        const kernel_name_sym = try self.intern("Kernel");
        const kernel_module_val = try self.newModule(kernel_name_sym);
        self.kernel_module = kernel_module_val.data.module;

        // Exception class hierarchy
        const exception_name_sym = try self.intern("Exception");
        const exception_class_val = try self.newClass(exception_name_sym, self.object_class);
        self.exception_class = exception_class_val.data.class;

        const standard_error_name_sym = try self.intern("StandardError");
        const standard_error_class_val = try self.newClass(standard_error_name_sym, self.exception_class);
        self.standard_error_class = standard_error_class_val.data.class;

        const runtime_error_name_sym = try self.intern("RuntimeError");
        const runtime_error_class_val = try self.newClass(runtime_error_name_sym, self.standard_error_class);
        self.runtime_error_class = runtime_error_class_val.data.class;

        const argument_error_name_sym = try self.intern("ArgumentError");
        const argument_error_class_val = try self.newClass(argument_error_name_sym, self.standard_error_class);
        self.argument_error_class = argument_error_class_val.data.class;

        const type_error_name_sym = try self.intern("TypeError");
        const type_error_class_val = try self.newClass(type_error_name_sym, self.standard_error_class);
        self.type_error_class = type_error_class_val.data.class;

        const zero_division_error_name_sym = try self.intern("ZeroDivisionError");
        const zero_division_error_class_val = try self.newClass(zero_division_error_name_sym, self.standard_error_class);
        self.zero_division_error_class = zero_division_error_class_val.data.class;

        const name_error_name_sym = try self.intern("NameError");
        const name_error_class_val = try self.newClass(name_error_name_sym, self.standard_error_class);
        self.name_error_class = name_error_class_val.data.class;

        const no_method_error_name_sym = try self.intern("NoMethodError");
        const no_method_error_class_val = try self.newClass(no_method_error_name_sym, self.name_error_class);
        self.no_method_error_class = no_method_error_class_val.data.class;

        const load_error_name_sym = try self.intern("LoadError");
        const load_error_class_val = try self.newClass(load_error_name_sym, self.standard_error_class);
        self.load_error_class = load_error_class_val.data.class;

        // Encoding class and singleton encoding objects
        const encoding_name_sym = try self.intern("Encoding");
        const encoding_class_val = try self.newClass(encoding_name_sym, self.object_class);
        self.encoding_class = encoding_class_val.data.class;

        // Create singleton encoding objects
        self.encoding_utf8 = try self.createEncodingObject(.{ .utf8 = .{} });
        self.encoding_ascii_8bit = try self.createEncodingObject(.{ .ascii_8bit = .{} });
        self.encoding_us_ascii = try self.createEncodingObject(.{ .us_ascii = .{} });

        // --- Stage 3: Set Class's superclass to Module ---
        self.class_class.superclass = self.module_class;

        // --- Stage 4: Register constants in Object ---
        self.object_class.module.constants.put(class_name_sym, class_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(basic_object_name_sym, basic_object_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(object_name_sym, object_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(module_name_sym, module_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(numeric_name_sym, numeric_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(integer_name_sym, integer_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(symbol_name_sym, symbol_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(array_name_sym, array_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(hash_name_sym, hash_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(proc_name_sym, proc_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(nil_class_name_sym, nil_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(true_class_name_sym, true_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(false_class_name_sym, false_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(kernel_name_sym, kernel_module_val) catch return error.Fatal;
        self.object_class.module.constants.put(exception_name_sym, exception_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(standard_error_name_sym, standard_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(runtime_error_name_sym, runtime_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(argument_error_name_sym, argument_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(type_error_name_sym, type_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(zero_division_error_name_sym, zero_division_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(name_error_name_sym, name_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(no_method_error_name_sym, no_method_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(load_error_name_sym, load_error_class_val) catch return error.Fatal;
        self.object_class.module.constants.put(encoding_name_sym, encoding_class_val) catch return error.Fatal;

        // Register encoding constants on Encoding class
        const utf8_const_sym = try self.intern("UTF_8");
        const ascii_8bit_const_sym = try self.intern("ASCII_8BIT");
        const binary_const_sym = try self.intern("BINARY");
        const us_ascii_const_sym = try self.intern("US_ASCII");

        const utf8_val = Value{ .data = .{ .encoding = self.encoding_utf8 } };
        const ascii_8bit_val = Value{ .data = .{ .encoding = self.encoding_ascii_8bit } };
        const us_ascii_val = Value{ .data = .{ .encoding = self.encoding_us_ascii } };

        self.encoding_class.module.constants.put(utf8_const_sym, utf8_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(ascii_8bit_const_sym, ascii_8bit_val) catch return error.Fatal;
        self.encoding_class.module.constants.put(binary_const_sym, ascii_8bit_val) catch return error.Fatal; // BINARY is alias for ASCII_8BIT
        self.encoding_class.module.constants.put(us_ascii_const_sym, us_ascii_val) catch return error.Fatal;

        // --- Stage 5: Register built-in methods ---
        builtins.registerAll(self) catch return error.Fatal;

        try self.includeModule(self.object_class, self.kernel_module);

        // Create top-level self (Ruby "main" object)
        self.main_self = try self.newInstance(self.object_class);

        // --- Stage 6: Initialize top-level lexical scope ---
        self.current_lexical_scope = try self.createLexicalScope(.{ .data = .{ .class = self.object_class } }, null);
    }

    pub fn createLexicalScope(self: *VM, scope_module_val: Value, parent: ?*LexicalScope) VMError!*LexicalScope {
        const scope = self.gc_allocator.create(LexicalScope) catch return error.Fatal;
        switch (scope_module_val.data) {
            .class => |cls| {
                scope.* = .{
                    .scope_module = .{ .class = cls },
                    .parent = parent,
                };
            },
            .module => |mod| {
                scope.* = .{
                    .scope_module = .{ .module = mod },
                    .parent = parent,
                };
            },
            else => unreachable,
        }
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
        const index = self.env_stack.items.len;
        self.env_stack.append(self.gc_allocator, .{
            .parent = parent,
            .lexical_scope = lexical_scope,
            .variables = undefined,
            .variables_len = 0,
        }) catch return error.Fatal;
        return &self.env_stack.items[index];
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
        heap_env.* = stack_env.*;
        heap_env.parent = heap_parent;
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
                if (blk.defining_ep == old_env) {
                    blk.defining_ep = new_env;
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

    pub fn setupOutput(self: *VM) void {
        if (self.stdout == null) {
            self.stdout_writer = std.fs.File.stdout().writer(&self.stdout_buffer);
            self.stdout = &self.stdout_writer.?.interface;
        }

        if (self.stderr == null) {
            self.stderr_writer = std.fs.File.stderr().writer(&self.stderr_buffer);
            self.stderr = &self.stderr_writer.?.interface;
        }
    }

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, gc_allocator_atomic: std.mem.Allocator, parser: prism.Parser, program: *compiler.CompiledProgram) VMError!VM {
        var vm = initEmpty(allocator, gc_allocator, gc_allocator_atomic, parser);
        vm.prepare(program) catch return error.Fatal;
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();

        for (self.all_parsers.items) |*p| {
            p.deinit();
        }
        self.all_parsers.deinit(self.allocator);

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
        self.symbols.deinit();
        self.globals.deinit();
        self.at_exit_handlers.deinit(self.gc_allocator);
    }

    pub fn run(self: *VM) VMError!Value {
        self.setupOutput();
        try self.pushFrame(&self.program.main_chunk, self.main_self, null);
        try self.executeInstructionsUntilFrameLength(1);
        return self.pop();
    }

    pub fn runAtExitHandlers(self: *VM) VMError!void {
        if (self.at_exit_handlers.items.len == 0) return;

        const original_exception = self.pending_exception;
        var last_exception: ?*value.ExceptionObject = null;

        while (self.at_exit_handlers.items.len > 0) {
            const handler = self.at_exit_handlers.pop().?;
            _ = self.callMethodByName(handler, "call", &[_]Value{}, null) catch |err| {
                switch (err) {
                    error.UnhandledException => {
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

    pub fn currentFrame(self: *VM) *CallFrame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn currentChunk(self: *VM) *Chunk {
        return self.currentFrame().chunk;
    }

    fn constantToValue(self: *VM, constant: chunk.Constant) VMError!Value {
        return switch (constant) {
            .integer => |i| Value.integer(i),
            .string => |s| try self.newString(s, true),
            .symbol => |s| Value{ .data = .{ .symbol = (try self.intern(s)) } },
        };
    }

    fn push(self: *VM, val: Value) VMError!void {
        self.stack.append(self.gc_allocator, val) catch return error.Fatal;
    }

    pub fn pop(self: *VM) Value {
        return self.stack.pop() orelse Value.nil();
    }

    fn peek(self: *VM, distance: usize) Value {
        return self.stack.items[self.stack.items.len - 1 - distance];
    }

    fn readByte(self: *VM) u8 {
        const frame = self.currentFrame();
        const byte = bytecode.readU8(frame.chunk.code.items, frame.ip);
        frame.ip += 1;
        return byte;
    }

    fn readU16(self: *VM) u16 {
        const frame = self.currentFrame();
        const val = bytecode.readU16(frame.chunk.code.items, frame.ip);
        frame.ip += 2;
        return val;
    }

    fn readI16(self: *VM) i16 {
        const frame = self.currentFrame();
        const val = bytecode.readI16(frame.chunk.code.items, frame.ip);
        frame.ip += 2;
        return val;
    }

    /// Resolve a block from its chunk ID. Handles three cases:
    /// - BLOCK_ARG_ON_STACK: pops Proc from stack, extracts Block
    /// - Literal block (1..MAX_CHUNK_ID): looks up chunk, creates Block
    /// - No block (0): returns null
    fn resolveBlock(self: *VM, block_chunk_id: chunk.ChunkId, frame: *CallFrame) VMError!?Block {
        if (block_chunk_id == chunk.BLOCK_ARG_ON_STACK) {
            // Block argument: Proc is on top of stack
            const proc_val = self.pop();

            if (proc_val.data == .proc) {
                return proc_val.data.proc.block;
            } else if (proc_val.data == .nil) {
                return null;
            } else {
                // Type error: not a Proc or nil
                const exc = try self.createException(
                    self.type_error_class,
                    "wrong argument type (expected Proc)",
                );
                self.pending_exception = exc;
                return error.Unwind;
            }
        } else if (block_chunk_id != 0) {
            // Literal block: look up chunk
            if (self.program.method_chunks.get(block_chunk_id)) |bc| {
                bc.lexical_scope = self.current_lexical_scope;
                const defining_ep = try self.promoteEnvironmentToHeap(frame.ep);
                return Block{
                    .chunk = bc,
                    .defining_ep = defining_ep,
                    .defining_self = frame.self_value,
                };
            } else {
                return error.Fatal;
            }
        }
        return null;
    }

    fn pushFrame(self: *VM, ch: *Chunk, self_value: Value, block: ?Block) VMError!void {
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

    pub fn executeInstruction(self: *VM) VMError!void {
        const frame = self.currentFrame();
        if (frame.ip >= frame.chunk.code.items.len)
            @panic("Something went wrong");

        const op = @as(bytecode.OpCode, @enumFromInt(self.readByte()));

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
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                const val = try self.constantToValue(constant);
                try self.push(val);
            },

            .GET_LOCAL => {
                const local_idx = self.readByte();
                const val = getVariableAtDepth(frame.ep, 0, local_idx) orelse Value.nil();
                try self.push(val);
            },

            .SET_LOCAL => {
                const local_idx = self.readByte();
                const val = self.pop();
                try setVariableAtDepth(frame.ep, 0, local_idx, val);
                try self.push(val);
            },

            .GET_LOCAL_DEEP => {
                const local_idx = self.readByte();
                const depth = self.readByte();
                const val = getVariableAtDepth(frame.ep, depth, local_idx) orelse Value.nil();
                try self.push(val);
            },

            .SET_LOCAL_DEEP => {
                const local_idx = self.readByte();
                const depth = self.readByte();
                const val = self.pop();
                try setVariableAtDepth(frame.ep, depth, local_idx, val);
                try self.push(val);
            },

            .GET_GLOBAL => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                const var_name = name_val.symbol;

                const global_val = self.globals.get(var_name) orelse Value.nil();
                try self.push(global_val);
            },

            .SET_GLOBAL => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                const var_name = name_val.symbol;
                const global_val = self.peek(0);

                self.globals.put(var_name, global_val) catch return error.Fatal;
            },

            .GET_IVAR => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                const var_name = name_val.symbol;
                const self_val = frame.self_value;

                const ivar_val = try self.getInstanceVariable(self_val, var_name);
                try self.push(ivar_val);
            },

            .SET_IVAR => {
                const name_idx = self.readU16();
                const name_val = self.currentChunk().constants.items[name_idx];
                const var_name = name_val.symbol;
                const ivar_val = self.peek(0);
                const self_val = frame.self_value;

                try self.setInstanceVariable(self_val, var_name, ivar_val);
            },

            .GET_CONST => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                // TODO: this should be a symbol I think
                if (constant == .string) {
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
                } else {
                    try self.push(Value.nil());
                }
            },

            .SET_CONST => {
                const idx = self.readU16();
                const val = self.pop();
                const constant = self.currentChunk().constants.items[idx];
                // TODO: this should be a symbol I think
                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);

                    // Set in current lexical scope's module (or Object if no scope)
                    if (frame.ep.lexical_scope) |scope| {
                        scope.getModule().constants.put(name_sym, val) catch return error.Fatal;
                    } else {
                        self.object_class.module.constants.put(name_sym, val) catch return error.Fatal;
                    }
                }
                try self.push(val);
            },

            .GET_CONST_PATH => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                const parent_val = self.pop();

                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);

                    const module = switch (parent_val.data) {
                        .class => |c| &c.module,
                        .module => |m| m,
                        else => unreachable,
                    };
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
                } else {
                    try self.push(Value.nil());
                }
            },

            .PUSH_SELF => {
                try self.push(frame.self_value);
            },

            .JUMP => {
                const offset = self.readI16();
                frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
            },

            .JUMP_IF_FALSE => {
                const offset = self.readI16();
                const cond = self.pop();

                const is_falsy = switch (cond.data) {
                    .nil => true,
                    .boolean => !cond.data.boolean,
                    else => false,
                };

                if (is_falsy) {
                    frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
                }
            },

            .JUMP_IF_TRUE => {
                const offset = self.readI16();
                const cond = self.pop();

                const is_truthy = switch (cond.data) {
                    .nil => false,
                    .boolean => cond.data.boolean,
                    else => true,
                };

                if (is_truthy) {
                    frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
                }
            },

            .POP => {
                _ = self.pop();
            },

            .CALL => {
                const method_idx = self.readU16();
                const argc = self.readByte();
                const block_chunk_id = self.readU16();

                // Resolve block first (may pop from stack for &variable syntax)
                const block = try self.resolveBlock(block_chunk_id, frame);

                // Pop arguments
                var args: [256]Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    args[argc - 1 - i] = self.pop();
                }

                // Pop receiver
                const receiver = self.pop();

                try self.callMethodHelperForExecuteInstruction(method_idx, receiver, &args, argc, null, 0, null, block);
            },

            .CALL_KW => {
                const method_idx = self.readU16();
                const argc = self.readByte();
                const kwargc = self.readByte();
                const kw_metadata_idx = self.readU16();
                const block_chunk_id = self.readU16();

                // Resolve block first (may pop from stack for &variable syntax)
                const block = try self.resolveBlock(block_chunk_id, frame);

                // Pop keyword values
                var kw_values: [256]Value = undefined;
                var i: usize = kwargc;
                while (i > 0) {
                    i -= 1;
                    kw_values[i] = self.pop();
                }

                // Pop positional args
                var args: [256]Value = undefined;
                i = argc;
                while (i > 0) {
                    i -= 1;
                    args[i] = self.pop();
                }

                // Pop receiver
                const receiver = self.pop();

                // Get keyword metadata
                const kw_metadata = frame.chunk.keyword_metadata.items[kw_metadata_idx];

                // Call method with keywords
                try self.callMethodHelperForExecuteInstruction(method_idx, receiver, &args, argc, &kw_values, kwargc, kw_metadata, block);
            },

            .RETURN => {
                const is_explicit = self.readByte();
                const result = self.pop();
                const current_frame = self.currentFrame();

                // Explicit returns in procs have special non-local return behavior
                if (is_explicit == 1 and current_frame.frame_type == .proc) {
                    // Proc explicit return: walk back to enclosing method and exit it
                    try self.popFrame(); // Pop proc frame

                    // Find first method frame and exit it (but not if it's the only frame left,
                    // which would be the main/top-level frame when proc is called via .call)
                    var found_method = false;
                    if (self.frames.items.len > 1) {
                        while (self.frames.items.len > 0) {
                            const frame_type = self.frames.items[self.frames.items.len - 1].frame_type;
                            if (frame_type == .method) {
                                try self.popFrame(); // Exit the method
                                found_method = true;
                                break;
                            }
                            try self.popFrame(); // Skip intermediate frames
                        }
                    }

                    // Push result if there are frames left or if we didn't find/pop a method
                    if (self.frames.items.len > 0 or !found_method) {
                        try self.push(result);
                    }
                } else {
                    // Normal return: exit current frame only (for methods, lambdas, implicit returns)
                    try self.popFrame();
                    if (self.frames.items.len > 0) {
                        try self.push(result);
                    } else {
                        try self.push(result);
                    }
                }
            },

            .DEF_MODULE => {
                const name_idx = self.readU16();
                const body_chunk_id = self.readU16();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);
                    const module_val = try self.newModule(name_sym);

                    // Store constant in current lexical scope (or Object if no scope)
                    if (frame.ep.lexical_scope) |scope| {
                        scope.getModule().constants.put(name_sym, module_val) catch return error.Fatal;
                    } else {
                        self.object_class.module.constants.put(name_sym, module_val) catch return error.Fatal;
                    }

                    // Execute module body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.method_chunks.get(body_chunk_id)) |body_chunk_ptr| {
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
                const name_idx = self.readU16();
                const body_chunk_id = self.readU16();

                // Pop superclass (or nil)
                const superclass_val = self.pop();

                var superclass: *value.ClassObject = self.object_class;
                if (superclass_val.data == .class) {
                    superclass = superclass_val.data.class;
                } else if (superclass_val.data != .nil) {
                    const exc = try self.createException(self.type_error_class, "superclass must be a Class");
                    self.pending_exception = exc;
                    return error.Unwind;
                }

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);

                    // Check if class already exists (for reopening)
                    var existing_class: ?Value = null;
                    if (frame.ep.lexical_scope) |scope| {
                        existing_class = try self.findConstantInLexicalScope(scope, name_sym);
                    }
                    if (existing_class == null) {
                        existing_class = self.object_class.module.constants.get(name_sym);
                    }

                    var class_val: Value = undefined;
                    if (existing_class) |ec| {
                        if (ec.data == .class) {
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
                        class_val = try self.newClass(name_sym, superclass);

                        // Store constant in current lexical scope (or Object if no scope)
                        if (frame.ep.lexical_scope) |scope| {
                            scope.getModule().constants.put(name_sym, class_val) catch return error.Fatal;
                        } else {
                            self.object_class.module.constants.put(name_sym, class_val) catch return error.Fatal;
                        }
                    }

                    // Execute class body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.method_chunks.get(body_chunk_id)) |body_chunk_ptr| {
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

            .DEF_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant != .symbol) {
                    return error.Fatal;
                }

                const method_name = constant.symbol;
                const method_name_sym = try self.intern(method_name);

                // Look up the chunk by ID
                if (self.program.method_chunks.get(chunk_idx)) |chunk_ptr| {
                    // Capture the current lexical scope for this method
                    chunk_ptr.lexical_scope = self.current_lexical_scope;

                    // Get current self from the frame
                    const current_self = frame.self_value;

                    if (current_self.data == .class) {
                        // Adding method to a class
                        current_self.data.class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr }) catch return error.Fatal;
                    } else if (current_self.data == .module) {
                        // Adding method to a module
                        current_self.data.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr }) catch return error.Fatal;
                    } else {
                        // Top-level: add to Object (look it up from constants)
                        // TODO: we need `main` to clean this up a bit
                        self.object_class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr }) catch return error.Fatal;
                    }
                } else {
                    std.debug.print("Error: undefined method chunk {d}\n", .{chunk_idx});
                    return error.Fatal;
                }
            },

            .DEF_SINGLETON_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant != .symbol) {
                    return error.Fatal;
                }

                const method_name = constant.symbol;
                const method_name_sym = try self.intern(method_name);

                if (self.program.method_chunks.get(chunk_idx)) |chunk_ptr| {
                    chunk_ptr.lexical_scope = self.current_lexical_scope;

                    // Pop the receiver from stack (compiled by compileMethod)
                    const receiver = self.pop();

                    // Get or create singleton class for the receiver
                    const singleton_class = try self.getOrCreateSingletonClass(receiver);

                    // Store method on singleton class
                    singleton_class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr }) catch return error.Fatal;
                } else {
                    return error.Fatal;
                }
            },

            .PUSH_ARRAY => {
                const element_count = self.readByte();

                const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
                array_obj.* = .{
                    .object = .{ .flags = 0, .class = self.array_class, .singleton_class = null, .instance_variables = null },
                    .elements = .empty,
                };

                var i: usize = 0;
                while (i < element_count) : (i += 1) {
                    const elem = self.pop();
                    array_obj.elements.append(self.gc_allocator, elem) catch return error.Fatal;
                }

                try self.push(.{ .data = .{ .array = array_obj } });
            },

            .PUSH_HASH => {
                const pair_count = self.readByte();

                const hash_obj = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                hash_obj.* = .{
                    .object = .{ .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                    .map = std.AutoHashMap(u64, usize).init(self.gc_allocator),
                    .entries = .empty,
                };

                var i: usize = 0;
                while (i < pair_count) : (i += 1) {
                    const key = self.pop();
                    const val = self.pop();

                    const key_hash = key.hash();

                    if (hash_obj.map.get(key_hash)) |existing_idx| {
                        if (hash_obj.entries.items[existing_idx].key.eql(key)) {
                            hash_obj.entries.items[existing_idx].value = val;
                            continue;
                        }
                    }

                    const new_idx = hash_obj.entries.items.len;
                    hash_obj.entries.append(self.gc_allocator, .{
                        .key = key,
                        .value = val,
                    }) catch return error.Fatal;
                    hash_obj.map.put(key_hash, new_idx) catch return error.Fatal;
                }

                try self.push(.{ .data = .{ .hash = hash_obj } });
            },

            .INTERPOLATE_STRING => {
                const part_count = self.readByte();

                var buf: std.ArrayList(u8) = .empty;
                defer buf.deinit(self.allocator);
                const writer = buf.writer(self.allocator);

                var i: usize = 0;
                while (i < part_count) : (i += 1) {
                    const val = self.pop();
                    const str_val = self.callMethodByName(val, "to_s", &[_]Value{}, null) catch |err| {
                        if (err == error.Unwind and self.pending_exception != null) {
                            return error.Unwind;
                        }
                        return err;
                    };
                    if (str_val.data != .string) {
                        const exc = try self.createException(self.type_error_class, "to_s did not return String");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                    writer.writeAll(str_val.data.string.str) catch return error.Fatal;
                }

                const final_str = buf.toOwnedSlice(self.allocator) catch return error.Fatal;
                defer self.allocator.free(final_str);
                try self.push(try self.newString(final_str, false));
            },

            .HALT => {
                try self.popFrame();
            },

            .YIELD => {
                const argc = self.readByte();

                // Pop arguments
                var yield_args: [256]Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    yield_args[argc - 1 - i] = self.pop();
                }

                // Check for block and push frame
                const block = frame.block orelse {
                    const exc = try self.createException(
                        self.argument_error_class,
                        "no block given",
                    );
                    self.pending_exception = exc;
                    return error.Unwind;
                };

                const blk = block.chunk;

                // Push frame with block's chunk, using block_defining_ep as parent for closure support
                // We need to manually create the environment with the right parent
                // Dereference block_defining_ep in case it's a forwarding pointer
                const real_defining_ep = derefEnvironment(block.defining_ep);

                const block_env = try self.createStackEnvironment(real_defining_ep, blk.lexical_scope orelse self.current_lexical_scope);

                self.frames.append(self.gc_allocator, CallFrame{
                    .chunk = blk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = frame.self_value,
                    .ep = block_env,
                    .block = null,
                }) catch return error.Fatal;

                // Update current_lexical_scope to the block's scope
                if (blk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

                // Copy arguments with rest parameter handling
                const block_frame = self.currentFrame();
                try self.copyArgumentsWithRestParam(blk, block_frame.ep, yield_args[0..argc], .strict);

                // Execute until block returns
                self.break_occurred = false;
                const saved_frame_count = self.frames.items.len - 1;
                try self.executeInstructionsUntilFrameLength(saved_frame_count + 1);

                // Check if break occurred in block
                if (self.break_occurred) {
                    self.break_occurred = false;
                    // Break value is already on stack from BREAK opcode
                    // Break causes the yielding method to return early with the break value
                    try self.popFrame();
                } else {
                    // Normal return - value is on stack from RETURN
                }
            },

            .PUSH_LAMBDA => {
                const chunk_id = self.readU16();
                const lambda_chunk = self.program.method_chunks.get(chunk_id) orelse unreachable;

                // Create a block with the lambda chunk and current environment
                const block = Block{
                    .chunk = lambda_chunk,
                    .defining_ep = frame.ep,
                    .defining_self = frame.self_value,
                };

                // Create a Proc value from the block
                const proc_val = try self.newProc(block);
                try self.push(proc_val);
            },

            .BREAK => {
                // Break value is already on stack (pushed by compileBreakStatement)
                self.break_occurred = true;
                // Return from block frame like RETURN does
                try self.popFrame();
            },

            .RAISE => {
                const argc = self.readByte();

                if (argc == 0) {
                    // Re-raise current exception
                    if (self.pending_exception) |exc| {
                        self.pending_exception = exc;
                        return error.Unwind;
                    } else {
                        // No exception to re-raise
                        const exc = try self.createException(self.runtime_error_class, "no current exception");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                } else if (argc == 1) {
                    // Single argument: exception instance or class
                    const arg = self.pop();

                    switch (arg.data) {
                        .exception => |exc| {
                            // Already an exception, raise it
                            self.pending_exception = exc;
                            return error.Unwind;
                        },
                        .class => |cls| {
                            // Exception class with empty message
                            const exc = try self.createException(cls, "");
                            self.pending_exception = exc;
                            return error.Unwind;
                        },
                        .string => |str| {
                            // String message - create RuntimeError
                            const exc = try self.createException(self.runtime_error_class, str.str);
                            self.pending_exception = exc;
                            return error.Unwind;
                        },
                        else => {
                            // Invalid argument type
                            const exc = try self.createException(self.type_error_class, "exception class/object expected");
                            self.pending_exception = exc;
                            return error.Unwind;
                        },
                    }
                } else if (argc == 2) {
                    // Two arguments: class and message
                    const message = self.pop();
                    const class_arg = self.pop();

                    if (class_arg.data != .class) {
                        const exc = try self.createException(self.type_error_class, "exception class/object expected");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }

                    const msg_str = if (message.data == .string)
                        message.data.string.str
                    else
                        "";

                    const exc = try self.createException(class_arg.data.class, msg_str);
                    self.pending_exception = exc;
                    return error.Unwind;
                } else {
                    // Invalid number of arguments
                    const exc = try self.createException(self.argument_error_class, "wrong number of arguments");
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            },

            .TRY_BEGIN => {
                // Skip the handler index operand
                _ = self.readU16();

                // Save retry point (current frame and IP after TRY_BEGIN)
                // This allows 'retry' to jump back to the beginning of the begin block
                self.retry_point = .{
                    .frame_idx = self.frames.items.len - 1,
                    .ip = self.currentFrame().ip,
                };
            },

            .TRY_END, .CATCH_END, .ENSURE_START => {
                // These opcodes are just markers, no action needed during normal execution
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
                        frame.ip = retry_pt.ip;
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

                // If there's a pending exception, re-raise it after ensure block
                if (self.pending_exception != null) {
                    return error.Unwind;
                }
                // Otherwise, ensure block completed normally
            },

            .CATCH_START => {
                // Read variable index
                const var_idx = self.readByte();

                // Store exception in local variable if binding exists
                if (var_idx != 255) {
                    if (self.pending_exception) |exc| {
                        frame.ep.variables[var_idx] = .{ .data = .{ .exception = exc } };
                        if (var_idx >= frame.ep.variables_len) {
                            frame.ep.variables_len = @as(u8, @intCast(var_idx + 1));
                        }
                    }
                }

                // Clear pending exception - it's now caught
                self.pending_exception = null;
            },

            .SUPER => {
                const argc = self.readByte();
                const block_chunk_id = self.readU16();

                // Resolve block first (may pop from stack for &variable syntax)
                const block = try self.resolveBlock(block_chunk_id, frame);

                // Pop arguments
                var args: [256]Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    args[argc - 1 - i] = self.pop();
                }

                try self.callSuper(args[0..argc], block);
            },

            .FORWARDING_SUPER => {
                const block_chunk_id = self.readU16();

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

    pub fn executeInstructionsUntilFrameLength(self: *VM, target_len: usize) VMError!void {
        while (self.frames.items.len >= target_len) {
            self.executeInstruction() catch |err| switch (err) {
                error.Unwind => try self.unwindStack(),
                else => return err,
            };
        }
    }

    /// Find a method on a receiver, checking singleton class first, then regular class
    pub fn findMethod(self: *VM, receiver: Value, method_name_sym: *SymbolObject) VMError!?Method {
        var method: ?Method = null;

        // First, check singleton class
        if (receiver.getObjectPointer() != null) {
            const singleton_class = self.getOrCreateSingletonClass(receiver) catch return error.Fatal;
            method = self.lookupMethod(singleton_class, method_name_sym);
        }

        // If not found in singleton class, check regular class
        if (method == null) {
            const class = self.getClass(receiver);
            method = self.lookupMethod(class, method_name_sym);
        }

        return method;
    }

    /// Call a method by name string (not from bytecode constant pool)
    pub fn callMethodByName(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block: ?Block) VMError!Value {
        const method_name_sym = try self.intern(method_name);
        const method = try self.findMethod(receiver, method_name_sym);

        if (method == null) {
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

        if (method) |m| {
            switch (m) {
                .chunk => |chunk_ptr| {
                    // Save current execution state
                    const saved_frame_count = self.frames.items.len;

                    // Push frame with receiver as self_value
                    self.pushFrame(chunk_ptr, receiver, block) catch return error.Fatal;

                    // Copy arguments to environment
                    var frame = self.currentFrame();
                    for (args, 0..) |arg, i| {
                        frame.ep.variables[i] = arg;
                        frame.ep.variables_len = @as(u8, @intCast(i + 1));
                    }

                    // Execute until we return to saved frame count
                    try self.executeInstructionsUntilFrameLength(saved_frame_count + 1);

                    // Result is on top of stack
                    return self.pop();
                },
                .builtin => |fun_ptr| {
                    return try fun_ptr(self, receiver, args, block);
                },
                .proc => |proc_obj| {
                    return try self.callProcAsMethod(proc_obj, receiver, args, block);
                },
            }
        }
        unreachable;
    }

    /// Result from yielding to a block
    const YieldResult = struct {
        value: Value,
        break_occurred: bool,
    };

    /// Yield to a block with arguments, handling break and exceptions
    /// Returns the block's result value and whether a break occurred
    pub fn yieldToBlock(self: *VM, block: Block, yield_args: []const Value) VMError!YieldResult {
        // Dereference defining_ep in case it's a forwarding pointer
        const real_defining_ep = derefEnvironment(block.defining_ep);

        const block_env = self.createStackEnvironment(real_defining_ep, block.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

        // Push block frame (no nested block for builtin-called blocks)
        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = block.chunk,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = block.defining_self,
            .ep = block_env,
            .block = null,
        }) catch return error.Fatal;

        // Update current_lexical_scope to the block's scope
        if (block.chunk.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }

        // Copy arguments with rest parameter handling
        const block_frame = self.currentFrame();
        try self.copyArgumentsWithRestParam(block.chunk, block_frame.ep, yield_args, .strict);

        // Execute until block returns
        self.break_occurred = false;
        const saved_frame_count = self.frames.items.len - 1;
        try self.executeInstructionsUntilFrameLength(saved_frame_count + 1);

        // Handle break or normal return
        const break_occurred = self.break_occurred;
        if (break_occurred) {
            self.break_occurred = false;
            // Break value is on stack from BREAK opcode
            _ = try self.popFrame();
        }

        // Get result from stack (top of stack is at distance 0)
        const result = if (self.stack.items.len > 0) self.peek(0) else Value.nil();

        return YieldResult{
            .value = result,
            .break_occurred = break_occurred,
        };
    }

    /// Execute a ProcObject as a method body
    fn callProcAsMethod(self: *VM, proc_obj: *value.ProcObject, receiver: Value, args: []const Value, block: ?Block) VMError!Value {
        const real_defining_ep = derefEnvironment(proc_obj.block.defining_ep);
        const proc_env = self.createStackEnvironment(real_defining_ep, proc_obj.block.chunk.lexical_scope orelse self.current_lexical_scope) catch return error.Fatal;

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = proc_obj.block.chunk,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = receiver,
            .ep = proc_env,
            .block = block,
            .frame_type = .method,
        }) catch return error.Fatal;

        const current_frame = self.currentFrame();
        try self.copyArgumentsWithRestParam(proc_obj.block.chunk, current_frame.ep, args, .strict);

        // Execute until this frame completes
        const saved_frame_count = self.frames.items.len - 1;
        try self.executeInstructionsUntilFrameLength(saved_frame_count + 1);

        return self.pop();
    }

    /// Ensure a block was given, or raise an error
    pub fn requireBlock(self: *VM, block: ?Block) VMError!Block {
        return block orelse {
            const exc = try self.createException(self.argument_error_class, "no block given");
            self.pending_exception = exc;
            return error.Unwind;
        };
    }

    /// Used by executeInstruction to implement both CALL and CALL_KW
    /// For a Chunk, it sets up the frame and returns.
    /// For a builtin function pointer, it calls it and pushes the return value onto the stack.
    /// Don't call this from anywhere else because stack unwinding won't work right.
    fn callMethodHelperForExecuteInstruction(
        self: *VM,
        method_idx: u16,
        receiver: Value,
        args: *[256]Value,
        argc: usize,
        kw_values: ?*[256]Value,
        kwargc: usize,
        kw_metadata: ?chunk.KeywordMetadata,
        block: ?Block,
    ) VMError!void {
        if (method_idx >= self.currentChunk().constants.items.len) {
            return error.Fatal;
        }

        const constant = self.currentChunk().constants.items[method_idx];
        if (constant != .string) {
            return error.Fatal;
        }

        const method_name = constant.string;
        const method_name_sym = try self.intern(method_name);

        const method = try self.findMethod(receiver, method_name_sym);

        if (method == null) {
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

        if (method) |m| {
            switch (m) {
                .chunk => |method_chunk| {
                    const has_keywords = kwargc > 0;

                    // Check for **nil
                    if (method_chunk.no_keywords and has_keywords) {
                        const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }

                    // Check if method requires keywords but none were provided
                    if (!has_keywords and method_chunk.required_keywords.items.len > 0) {
                        const msg = "missing required keyword arguments";
                        const exc = try self.createException(self.argument_error_class, msg);
                        self.pending_exception = exc;
                        return error.Unwind;
                    }

                    // Get caller's chunk BEFORE pushing new frame (needed for keyword metadata)
                    const caller_chunk = if (has_keywords) self.currentFrame().chunk else null;

                    // Push frame with receiver as self_value
                    try self.pushFrame(method_chunk, receiver, block);

                    // Copy positional arguments with rest parameter handling
                    const frame = self.currentFrame();
                    try self.copyArgumentsWithRestParam(method_chunk, frame.ep, args[0..argc], .strict);

                    if (has_keywords) {
                        // Bind keyword arguments
                        try self.bindKeywordArguments(method_chunk, frame.ep, kw_values.?[0..kwargc], kw_metadata.?, caller_chunk.?);
                    } else {
                        // Bind optional keywords with defaults and keyword rest (when no keywords provided)
                        if (method_chunk.optional_keywords.items.len > 0 or method_chunk.keyword_rest_index != null) {
                            // FIRST: Update variables length to cover all keyword slots
                            var max_slot: u8 = frame.ep.variables_len;
                            for (method_chunk.optional_keywords.items) |opt_kw| {
                                if (opt_kw.param_slot >= max_slot) max_slot = opt_kw.param_slot + 1;
                            }
                            if (method_chunk.keyword_rest_index) |rest_idx| {
                                if (rest_idx >= max_slot) max_slot = rest_idx + 1;
                            }
                            frame.ep.variables_len = max_slot;

                            // THEN: Bind optional keywords with their defaults
                            for (method_chunk.optional_keywords.items) |opt_kw| {
                                const default_chunk = self.program.method_chunks.get(opt_kw.default_chunk_id).?;
                                // Re-get frame pointer at start of each iteration
                                const current_ep = self.currentFrame().ep;
                                const default_value = try self.executeDefaultExpression(default_chunk, current_ep);
                                // Re-get frame pointer after executeDefaultExpression
                                const f = &self.frames.items[self.frames.items.len - 1];
                                f.ep.variables[opt_kw.param_slot] = default_value;
                            }

                            // THEN: Set up keyword rest with empty hash
                            if (method_chunk.keyword_rest_index) |rest_idx| {
                                const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
                                kw_hash.* = .{
                                    .object = .{ .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                                    .map = std.AutoHashMap(u64, usize).init(self.gc_allocator),
                                    .entries = .empty,
                                };
                                // Re-get frame pointer
                                const f = &self.frames.items[self.frames.items.len - 1];
                                f.ep.variables[rest_idx] = Value{ .data = .{ .hash = kw_hash } };
                            }
                        }
                    }

                    // Bind block parameter if present
                    if (method_chunk.block_param_index) |block_idx| {
                        // Re-get frame pointer (newProc may cause reallocation)
                        const current_frame = &self.frames.items[self.frames.items.len - 1];

                        if (current_frame.block) |blk| {
                            // Convert Block to ProcObject
                            const proc_val = try self.newProc(blk);
                            // Re-get frame pointer again after newProc
                            const f = &self.frames.items[self.frames.items.len - 1];
                            f.ep.variables[block_idx] = proc_val;
                        } else {
                            // No block passed - store nil
                            current_frame.ep.variables[block_idx] = Value.nil();
                        }

                        // Ensure variables_len covers block parameter slot
                        const f = &self.frames.items[self.frames.items.len - 1];
                        if (block_idx >= f.ep.variables_len) {
                            f.ep.variables_len = block_idx + 1;
                        }
                    }
                },
                .builtin => |fun_ptr| {
                    var final_args: []Value = undefined;
                    if (kwargc > 0) {
                        // For builtin methods with keywords, convert keywords to hash
                        const kw_hash = try self.createHashFromKeywords(kw_values.?[0..kwargc], kw_metadata.?);
                        args[argc] = kw_hash;
                        final_args = args[0..(argc + 1)];
                    } else {
                        final_args = args[0..argc];
                    }

                    const result = fun_ptr(self, receiver, final_args, block) catch |err| {
                        if (self.pending_exception != null) {
                            return error.Unwind;
                        }
                        return err;
                    };
                    try self.push(result);
                },
                .proc => |proc_obj| {
                    if (kwargc > 0) {
                        const exc = try self.createException(self.argument_error_class, "this method does not accept keyword arguments");
                        self.pending_exception = exc;
                        return error.Unwind;
                    }
                    const result = try self.callProcAsMethod(proc_obj, receiver, args[0..argc], block);
                    try self.push(result);
                },
            }
        }
    }

    pub fn getClass(self: *VM, val: Value) *ClassObject {
        switch (val.data) {
            // Types with Object headers - use the class field from the header
            .instance => |i| return i.class.?,
            .string => |s| return s.object.class.?,
            .symbol => |s| return s.object.class.?,
            .array => |a| return a.object.class.?,
            .hash => |h| return h.object.class.?,
            .exception => |e| return e.object.class.?,
            .encoding => |e| return e.object.class.?,
            .module => |m| return m.object.class.?,
            .class => |c| return c.module.object.class.?,
            .proc => |p| return p.object.class.?,

            // Primitives without Object headers - hardcode the class
            .integer => return self.integer_class,
            .nil => return self.nil_class,
            .boolean => |b| if (b) return self.true_class else return self.false_class,
        }
    }

    fn getObjectPointer(_: *VM, obj_val: value.Value) ?*value.Object {
        return switch (obj_val.data) {
            .class => |c| &c.module.object,
            .encoding => |e| &e.object,
            .module => |m| &m.object,
            .instance => |i| i,
            .string => |s| &s.object,
            .symbol => |s| &s.object,
            .array => |a| &a.object,
            .hash => |h| &h.object,
            .exception => |e| &e.object,
            .proc => |p| &p.object,
            .integer, .nil, .boolean => null,
        };
    }

    fn lookupMethod(_: *VM, class: *ClassObject, method_name: *value.SymbolObject) ?Method {
        var current_class: ?*ClassObject = class;
        while (current_class) |c| {
            // 1. Check prepended modules first (in reverse order - most recently prepended at highest index is checked first)
            var i = c.prepended_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.prepended_modules.items[i];
                if (module.methods.get(method_name)) |method| {
                    return method;
                }
            }

            // 2. Check class's own methods
            if (c.module.methods.get(method_name)) |method| {
                return method;
            }

            // 3. Check included modules (in reverse order - most recently included at highest index is checked first)
            i = c.included_modules.items.len;
            while (i > 0) {
                i -= 1;
                const module = c.included_modules.items[i];
                if (module.methods.get(method_name)) |method| {
                    return method;
                }
            }

            current_class = c.superclass;
        }
        return null;
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
    fn lookupMethodForSuper(self: *VM, defining_class: *ClassObject, method_name: *value.SymbolObject) ?Method {
        // Start from the superclass, not the defining class itself
        const start_class = defining_class.superclass orelse return null;
        return self.lookupMethod(start_class, method_name);
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
                if (slot < env.variables_len and env.variables[slot].data == .array) {
                    for (env.variables[slot].data.array.elements.items) |elem| {
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

        // Get method name from current chunk
        const method_name = frame.chunk.name;
        const method_name_sym = try self.intern(method_name);

        // Get the defining class from the current method's lexical scope
        const defining_class = self.getDefiningClassForSuper(frame.chunk) orelse {
            const exc = try self.createException(self.no_method_error_class, "super called outside of method");
            self.pending_exception = exc;
            return error.Unwind;
        };

        // Look up method in superclass chain
        const method = self.lookupMethodForSuper(defining_class, method_name_sym) orelse {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "super: no superclass method '{s}' for {s}",
                .{ method_name, defining_class.module.name.name },
            ) catch return error.Fatal;
            const exc = try self.createException(self.no_method_error_class, msg);
            self.pending_exception = exc;
            return error.Unwind;
        };

        // Call with the same receiver (self)
        const receiver = frame.self_value;

        switch (method) {
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
                const result = fun_ptr(self, receiver, args_copy[0..args.len], block) catch |err| {
                    if (self.pending_exception != null) {
                        return error.Unwind;
                    }
                    return err;
                };
                try self.push(result);
            },
            .proc => |proc_obj| {
                const result = try self.callProcAsMethod(proc_obj, receiver, args, block);
                try self.push(result);
            },
        }
    }

    pub fn getOrCreateSingletonClass(self: *VM, obj_val: value.Value) VMError!*ClassObject {
        // Return existing singleton class if already created
        if (obj_val.getSingletonClass()) |singleton| {
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
        const singleton_superclass: *ClassObject = switch (obj_val.data) {
            .class => |c| blk: {
                // For classes: singleton's superclass is parent class's singleton
                if (c.superclass) |super| {
                    break :blk try self.getOrCreateSingletonClass(.{ .data = .{ .class = super } });
                } else {
                    break :blk self.class_class; // Root class singletons inherit from Class
                }
            },
            .instance => |i| i.class.?, // Instance singleton inherits from instance's class
            .module => self.module_class,
            .string => self.string_class,
            .symbol => self.symbol_class,
            .array => self.array_class,
            .hash => self.hash_class,
            .exception => self.exception_class,
            .encoding => self.encoding_class,
            .proc => self.proc_class,
            .integer, .boolean, .nil => unreachable, // Primitives can't have singleton classes
        };

        // Create the singleton ClassObject
        const singleton_class = self.gc_allocator.create(ClassObject) catch return error.Fatal;
        singleton_class.* = .{
            .superclass = singleton_superclass,
            .module = .{
                .object = .{
                    .flags = 0,
                    .class = self.class_class,
                    .singleton_class = null,
                    .instance_variables = null,
                },
                .name = singleton_name_sym,
                .methods = std.AutoHashMap(*value.SymbolObject, Method).init(self.gc_allocator),
                .constants = std.AutoHashMap(*value.SymbolObject, value.Value).init(self.gc_allocator),
            },
        };

        // Link back to object
        obj_ptr.singleton_class = singleton_class;

        return singleton_class;
    }

    pub fn intern(self: *VM, str: []const u8) VMError!*SymbolObject {
        // Check if already interned
        if (self.symbols.get(str)) |symbol_obj| {
            return symbol_obj;
        }

        const key = self.gc_allocator_atomic.dupe(u8, str) catch return error.Fatal;

        // Create a symbol and store it
        const symbol_obj = self.gc_allocator.create(SymbolObject) catch return error.Fatal;
        symbol_obj.* = .{
            .object = .{ .flags = Object.FROZEN_FLAG, .class = self.symbol_class, .singleton_class = null, .instance_variables = null },
            .name = key,
        };
        self.symbols.put(key, symbol_obj) catch return error.Fatal;

        return symbol_obj;
    }

    // ==== Object creation ====

    pub fn newModule(self: *VM, name: *SymbolObject) VMError!Value {
        const module_obj = self.gc_allocator.create(value.ModuleObject) catch return error.Fatal;
        module_obj.* = .{
            .object = .{ .flags = 0, .class = self.module_class, .singleton_class = null, .instance_variables = null },
            .name = name,
            .methods = std.AutoHashMap(*SymbolObject, Method).init(self.gc_allocator),
            .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
        };
        return .{ .data = .{ .module = module_obj } };
    }

    pub fn newClass(self: *VM, name: *SymbolObject, superclass: ?*ClassObject) VMError!Value {
        const class_obj = self.gc_allocator.create(ClassObject) catch return error.Fatal;
        class_obj.* = .{
            .superclass = superclass,
            .module = .{
                .object = .{ .flags = 0, .class = self.class_class, .singleton_class = null, .instance_variables = null },
                .name = name,
                .methods = std.AutoHashMap(*SymbolObject, Method).init(self.gc_allocator),
                .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
            },
        };
        return .{ .data = .{ .class = class_obj } };
    }

    pub fn newInstance(self: *VM, class_obj: *ClassObject) VMError!Value {
        const obj = self.gc_allocator.create(Object) catch return error.Fatal;
        obj.* = .{
            .flags = 0,
            .class = class_obj,
            .singleton_class = null,
            .instance_variables = null,
        };
        return .{ .data = .{ .instance = obj } };
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

    pub fn newString(self: *VM, str: []const u8, frozen: bool) VMError!Value {
        return self.newStringWithEncoding(str, frozen, .{ .utf8 = .{} });
    }

    pub fn newStringWithEncoding(self: *VM, str: []const u8, frozen: bool, encoding: enc.Encoding) VMError!Value {
        var copy = str;
        var flags: u32 = 0;
        if (frozen) {
            flags = Object.FROZEN_FLAG;
        } else {
            copy = self.gc_allocator_atomic.dupe(u8, str) catch return error.Fatal;
        }

        const string_obj = self.gc_allocator.create(StringObject) catch return error.Fatal;
        string_obj.* = .{
            .object = .{ .flags = flags, .class = self.string_class, .singleton_class = null, .instance_variables = null },
            .str = copy,
            .encoding = encoding,
        };
        return .{ .data = .{ .string = string_obj } };
    }

    fn createEncodingObject(self: *VM, encoding: enc.Encoding) VMError!*value.EncodingObject {
        const encoding_obj = self.gc_allocator.create(value.EncodingObject) catch return error.Fatal;
        encoding_obj.* = .{
            .object = .{
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
        const heap_ep = self.promoteEnvironmentToHeap(block.defining_ep) catch return error.Fatal;

        const proc_obj = self.gc_allocator.create(value.ProcObject) catch return error.Fatal;
        proc_obj.* = .{
            .object = .{ .flags = 0, .class = self.proc_class, .singleton_class = null, .instance_variables = null },
            .block = .{
                .chunk = block.chunk,
                .defining_ep = heap_ep,
                .defining_self = block.defining_self,
            },
        };
        return .{ .data = .{ .proc = proc_obj } };
    }

    pub fn includeModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) VMError!void {
        class.included_modules.append(self.gc_allocator, module) catch return error.Fatal;
    }

    pub fn prependModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) VMError!void {
        class.prepended_modules.append(self.gc_allocator, module) catch return error.Fatal;
    }

    pub fn requireArgCount(self: *VM, args: []Value, expected: usize) VMError!void {
        if (args.len != expected) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected {d})",
                .{ args.len, expected },
            ) catch return error.Fatal;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.Unwind;
        }
    }

    const AccessorKind = enum { reader, writer };

    pub fn createAccessorChunk(self: *VM, base_name: []const u8, kind: AccessorKind) VMError!*Chunk {
        if (self.next_chunk_id > chunk.MAX_CHUNK_ID) {
            std.debug.print("Too many method chunks\n", .{});
            return error.Fatal;
        }

        const allocator = self.program.allocator;
        const method_name = if (kind == .reader)
            allocator.dupe(u8, base_name) catch return error.Fatal
        else
            std.fmt.allocPrint(allocator, "{s}=", .{base_name}) catch return error.Fatal;
        const ivar_name = std.fmt.allocPrint(allocator, "@{s}", .{base_name}) catch return error.Fatal;

        const chunk_ptr = allocator.create(Chunk) catch return error.Fatal;
        chunk_ptr.* = Chunk.init(allocator, method_name);
        chunk_ptr.chunk_id = self.next_chunk_id;
        self.next_chunk_id += 1;
        chunk_ptr.source_file = self.parser.source_file;
        chunk_ptr.lexical_scope = self.current_lexical_scope;
        chunk_ptr.arity = if (kind == .reader) 0 else 1;

        const name_idx = chunk_ptr.addConstant(.{ .symbol = ivar_name }) catch return error.Fatal;

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

        self.program.method_chunks.put(chunk_ptr.chunk_id.?, chunk_ptr) catch return error.Fatal;
        return chunk_ptr;
    }

    pub fn requireArgType(
        self: *VM,
        args: []Value,
        index: usize,
        comptime expected_tag: std.meta.Tag(@TypeOf(@as(value.Value, undefined).data)),
        comptime type_name: []const u8,
    ) VMError!void {
        if (args[index].data != expected_tag) {
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
        comptime arg_tag: std.meta.Tag(@TypeOf(@as(value.Value, undefined).data)),
        comptime type_name: []const u8,
    ) VMError!void {
        try self.requireArgCount(args, 1);
        try self.requireArgType(args, 0, arg_tag, type_name);
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
        self.all_parsers.append(self.allocator, parser) catch return error.Fatal;

        var program = compiler.Compiler.compile(self.allocator, &parser, self.next_chunk_id) catch return error.Fatal;
        // Ensure cleanup of the loaded program's chunks on error
        defer {
            program.main_chunk.deinit();
            program.method_chunks.deinit();
        }

        self.next_chunk_id = program.next_chunk_id;

        // Transfer ownership of method chunks to main program
        var iter = program.method_chunks.iterator();
        while (iter.next()) |entry| {
            self.program.method_chunks.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.Fatal;
        }

        const prev_file = self.current_loading_file;
        self.current_loading_file = absolute_path;
        defer self.current_loading_file = prev_file;

        try self.executeChunk(&program.main_chunk);
    }

    fn executeChunk(self: *VM, target_chunk: *Chunk) VMError!void {
        const env = try self.createStackEnvironment(null, target_chunk.lexical_scope orelse self.current_lexical_scope);

        self.frames.append(self.gc_allocator, CallFrame{
            .chunk = target_chunk,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self.main_self,
            .ep = env,
            .block = null,
            .frame_type = .method,
        }) catch return error.Fatal;

        if (target_chunk.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }

        // Execute instructions until this frame completes
        const target_frame_depth = self.frames.items.len;
        try self.executeInstructionsUntilFrameLength(target_frame_depth);
    }

    // ===== Exception Handling Methods =====

    /// Create a new exception object
    pub fn createArray(self: *VM) VMError!*value.ArrayObject {
        const array_ptr = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_ptr.* = value.ArrayObject{
            .object = .{
                .flags = 0,
                .class = self.array_class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .elements = .empty,
        };
        return array_ptr;
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
        const target_frame_depth = self.frames.items.len;
        try self.executeInstructionsUntilFrameLength(target_frame_depth);

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
            if (args.len < min_args) {
                const msg = std.fmt.allocPrint(
                    self.gc_allocator,
                    "wrong number of arguments (given {d}, expected {d}+)",
                    .{ args.len, min_args },
                ) catch return error.Fatal;
                const exc = try self.createException(self.argument_error_class, msg);
                self.pending_exception = exc;
                return error.Unwind;
            }
            if (target_chunk.rest_param_index == null and args.len > max_args) {
                const msg = std.fmt.allocPrint(
                    self.gc_allocator,
                    "wrong number of arguments (given {d}, expected {d})",
                    .{ args.len, max_args },
                ) catch return error.Fatal;
                const exc = try self.createException(self.argument_error_class, msg);
                self.pending_exception = exc;
                return error.Unwind;
            }
        }

        var arg_idx: usize = 0;
        var local_idx: usize = 0;

        // 1. Bind pre-optional required parameters
        var i: usize = 0;
        while (i < target_chunk.arity) : (i += 1) {
            if (arg_idx < args.len) {
                env.variables[local_idx] = args[arg_idx];
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
            const args_remaining = if (arg_idx < args.len) args.len - arg_idx else 0;
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
                env.variables[local_idx] = args[arg_idx];
                arg_idx += 1;
                local_idx += 1;
                env.variables_len = @intCast(local_idx); // Update so later defaults can see earlier optionals
            }

            // Evaluate defaults for remaining optionals
            while (i < optional_count) : (i += 1) {
                const opt_info = target_chunk.optional_params.items[i];
                const default_chunk = self.program.method_chunks.get(opt_info.default_chunk_id) orelse {
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
            const args_remaining_after_optionals = if (arg_idx < args.len) args.len - arg_idx else 0;
            const available_for_rest = if (args_remaining_after_optionals > target_chunk.post_required_count)
                args_remaining_after_optionals - target_chunk.post_required_count
            else
                0;

            const rest_array = try self.createArray();
            var j: usize = 0;
            while (j < available_for_rest) : (j += 1) {
                rest_array.elements.append(self.gc_allocator, args[arg_idx]) catch return error.Fatal;
                arg_idx += 1;
            }
            env.variables[rest_idx] = Value{ .data = .{ .array = rest_array } };
            local_idx = rest_idx + 1;
        }

        // 4. Bind post-required parameters
        i = 0;
        while (i < target_chunk.post_required_count) : (i += 1) {
            const post_arg_idx = args.len - target_chunk.post_required_count + i;
            if (post_arg_idx < args.len and post_arg_idx >= arg_idx) {
                env.variables[local_idx] = args[post_arg_idx];
            } else if (mode == .lenient) {
                env.variables[local_idx] = Value.nil();
            }
            local_idx += 1;
        }

        env.variables_len = @max(@as(u8, @intCast(local_idx)), env.variables_len);
    }

    fn bindKeywordArguments(
        self: *VM,
        target_chunk: *const Chunk,
        env: *Environment,
        kw_values: []Value,
        kw_metadata: chunk.KeywordMetadata,
        caller_chunk: *const Chunk,
    ) VMError!void {
        // Track which provided keywords have been matched
        var matched = self.allocator.alloc(bool, kw_values.len) catch return error.Fatal;
        defer self.allocator.free(matched);
        @memset(matched, false);

        // 1. Bind required keywords
        for (target_chunk.required_keywords.items) |req_kw| {
            const req_name = target_chunk.constants.items[req_kw.name_idx].symbol;
            const req_symbol = try self.intern(req_name);

            // Linear scan through provided keywords
            var found = false;
            for (kw_values, 0..) |_, i| {
                const provided_name = caller_chunk.constants.items[kw_metadata.names.items[i]].symbol;
                const provided_symbol = try self.intern(provided_name);

                // O(1) pointer equality check after interning
                if (req_symbol == provided_symbol) {
                    env.variables[req_kw.param_slot] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                const msg = std.fmt.allocPrint(
                    self.gc_allocator,
                    "missing keyword: {s}",
                    .{req_name},
                ) catch return error.Fatal;
                const exc = try self.createException(self.argument_error_class, msg);
                self.pending_exception = exc;
                return error.Unwind;
            }
        }

        // 2. Bind optional keywords
        for (target_chunk.optional_keywords.items) |opt_kw| {
            const opt_name = target_chunk.constants.items[opt_kw.name_idx].symbol;
            const opt_symbol = try self.intern(opt_name);

            var found = false;
            for (kw_values, 0..) |_, i| {
                const provided_name = caller_chunk.constants.items[kw_metadata.names.items[i]].symbol;
                const provided_symbol = try self.intern(provided_name);

                if (opt_symbol == provided_symbol) {
                    env.variables[opt_kw.param_slot] = kw_values[i];
                    matched[i] = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                // Execute default expression
                const default_chunk = self.program.method_chunks.get(opt_kw.default_chunk_id).?;
                const default_value = try self.executeDefaultExpression(default_chunk, env);
                env.variables[opt_kw.param_slot] = default_value;
            }
        }

        // 3. Handle unmatched keywords
        if (target_chunk.keyword_rest_index) |rest_idx| {
            // ONLY create hash when **kwargs is present
            const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
            kw_hash.* = .{
                .object = .{ .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
                .map = std.AutoHashMap(u64, usize).init(self.gc_allocator),
                .entries = .empty,
            };

            // Collect unmatched keywords
            for (kw_values, 0..) |kw_value, i| {
                if (!matched[i]) {
                    const key_name = caller_chunk.constants.items[kw_metadata.names.items[i]].symbol;
                    const key_symbol = try self.intern(key_name);
                    const key = Value{ .data = .{ .symbol = key_symbol } };
                    const key_hash = key.hash();

                    const new_idx = kw_hash.entries.items.len;
                    kw_hash.entries.append(self.gc_allocator, .{
                        .key = key,
                        .value = kw_value,
                    }) catch return error.Fatal;
                    kw_hash.map.put(key_hash, new_idx) catch return error.Fatal;
                }
            }

            env.variables[rest_idx] = Value{ .data = .{ .hash = kw_hash } };
        } else {
            // No keyword rest - check for unmatched keywords
            for (matched, 0..) |is_matched, i| {
                if (!is_matched) {
                    const unknown_name = caller_chunk.constants.items[kw_metadata.names.items[i]].symbol;
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "unknown keyword: {s}",
                        .{unknown_name},
                    ) catch return error.Fatal;
                    const exc = try self.createException(self.argument_error_class, msg);
                    self.pending_exception = exc;
                    return error.Unwind;
                }
            }
        }

        // Update variables length to include keyword parameters
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

    fn createHashFromKeywords(
        self: *VM,
        kw_values: []Value,
        kw_metadata: chunk.KeywordMetadata,
    ) VMError!Value {
        const current_chunk = self.currentChunk();
        const kw_hash = self.gc_allocator.create(value.HashObject) catch return error.Fatal;
        kw_hash.* = .{
            .object = .{ .flags = 0, .class = self.hash_class, .singleton_class = null, .instance_variables = null },
            .map = std.AutoHashMap(u64, usize).init(self.gc_allocator),
            .entries = .empty,
        };

        for (kw_values, 0..) |kw_value, i| {
            const key_name = current_chunk.constants.items[kw_metadata.names.items[i]].symbol;
            const key_symbol = try self.intern(key_name);
            const key = Value{ .data = .{ .symbol = key_symbol } };
            const key_hash = key.hash();

            const new_idx = kw_hash.entries.items.len;
            kw_hash.entries.append(self.gc_allocator, .{
                .key = key,
                .value = kw_value,
            }) catch return error.Fatal;
            kw_hash.map.put(key_hash, new_idx) catch return error.Fatal;
        }

        return Value{ .data = .{ .hash = kw_hash } };
    }

    pub fn createException(self: *VM, class: *ClassObject, message: []const u8) VMError!*value.ExceptionObject {
        const exc = self.gc_allocator.create(value.ExceptionObject) catch return error.Fatal;
        const msg_str = try self.newString(message, false);
        const backtrace = try self.captureBacktrace();

        exc.* = .{
            .object = .{
                .flags = 0,
                .class = class,
                .singleton_class = null,
                .instance_variables = null,
            },
            .message = msg_str.data.string,
            .backtrace = backtrace,
            .cause = self.pending_exception,
        };

        return exc;
    }

    /// Capture current call stack as a backtrace
    fn captureBacktrace(self: *VM) VMError!?*value.ArrayObject {
        const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.Fatal;
        array_obj.* = .{
            .object = .{
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

            // Get line number for current IP
            const line = if (frame.ip > 0 and frame.ip - 1 < frame.chunk.line_info.items.len)
                frame.chunk.line_info.items[frame.ip - 1]
            else
                0;

            // Format: "chunk_name:line"
            const backtrace_str = std.fmt.allocPrint(
                self.gc_allocator,
                "{s}:{d}",
                .{ frame.chunk.name, line },
            ) catch return error.Fatal;

            const str_val = try self.newString(backtrace_str, false);
            array_obj.elements.append(self.gc_allocator, str_val) catch return error.Fatal;
        }

        return array_obj;
    }

    /// Unwind the call stack looking for exception handlers
    pub fn unwindStack(self: *VM) VMError!void {
        while (self.frames.items.len > 0) {
            const frame_idx = self.frames.items.len - 1;
            const frame = &self.frames.items[frame_idx];

            // Look for an exception handler in this frame
            if (try self.findExceptionHandler(frame)) |handler_info| {

                // Found a matching handler
                if (handler_info.rescue_idx) |rescue_idx| {
                    // Jump to rescue clause
                    const rescue_handler = &handler_info.handler.rescue_handlers.items[rescue_idx];
                    frame.ip = rescue_handler.catch_ip;
                    return; // Stop unwinding
                } else if (handler_info.handler.ensure_ip) |ensure_ip| {
                    // No matching rescue, but there's an ensure block
                    frame.ip = ensure_ip;
                    return; // Execute ensure, then continue unwinding
                }
            }

            // No handler in this frame, pop it and continue
            _ = self.frames.pop();

            // Restore stack to frame base
            if (self.frames.items.len > 0) {
                const prev_frame = &self.frames.items[self.frames.items.len - 1];
                self.stack.shrinkRetainingCapacity(prev_frame.stack_base);
            } else {
                self.stack.shrinkRetainingCapacity(0);
            }
        }

        // If we get here, no handler was found - return error
        // Caller (main.zig) will print the unhandled exception
        return error.UnhandledException;
    }

    /// Find an exception handler in the current frame
    fn findExceptionHandler(self: *VM, frame: *CallFrame) VMError!?struct {
        handler: *chunk.ExceptionHandler,
        rescue_idx: ?usize,
    } {
        const ip = frame.ip;

        // Search the exception handler table
        for (frame.chunk.exception_handlers.items) |*handler| {

            // Check if IP is in the protected region
            if (ip >= handler.try_start_ip and ip < handler.try_end_ip) {
                // Search for a matching rescue handler
                for (handler.rescue_handlers.items, 0..) |*rescue, idx| {
                    // Check if exception matches any of the rescue types
                    if (rescue.exception_types.items.len == 0) {
                        // Bare rescue catches StandardError
                        if (self.matchesException(self.pending_exception.?, self.standard_error_class)) {
                            return .{ .handler = handler, .rescue_idx = idx };
                        }
                    } else {
                        // Check each specified exception type
                        for (rescue.exception_types.items) |const_idx| {
                            // Resolve the constant to get the exception class name
                            const constant = frame.chunk.constants.items[const_idx];
                            if (constant != .string) continue;

                            const class_name = constant.string;

                            // Look up the class by name in Object's constants
                            const class_name_sym = self.intern(class_name) catch return error.Fatal;
                            const class_val = self.object_class.module.constants.get(class_name_sym) orelse continue;

                            if (class_val.data != .class) continue;
                            const exception_class = class_val.data.class;

                            // Check if the current exception matches this class
                            if (self.matchesException(self.pending_exception.?, exception_class)) {
                                return .{ .handler = handler, .rescue_idx = idx };
                            }
                        }
                    }
                }

                // No matching rescue, but might have ensure
                if (handler.ensure_ip != null) {
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
            // Print exception class and message
            writer.print("Unhandled exception: {s}: {s}\n", .{
                exc.object.class.?.module.name.name,
                exc.message.str,
            }) catch {};

            // Print backtrace if available
            if (exc.backtrace) |bt| {
                writer.print("Backtrace:\n", .{}) catch {};
                for (bt.elements.items) |line| {
                    if (line.data == .string) {
                        writer.print("  {s}\n", .{line.data.string.str}) catch {};
                    }
                }
            }
            _ = writer.flush() catch {};
        } else {
            // Someone forgot to set pending_exception.
            writer.print("unknown error\n", .{}) catch {};
            _ = writer.flush() catch {};
        }
    }
};
