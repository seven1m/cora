const std = @import("std");
const bytecode = @import("bytecode.zig");
const chunk = @import("chunk.zig");
const compiler = @import("compiler.zig");
const value = @import("value.zig");
const prism = @import("prism.zig");

const Value = value.Value;
const Object = value.Object;
const ClassObject = value.ClassObject;
const LexicalScope = value.LexicalScope;
const StringObject = value.StringObject;
const SymbolObject = value.SymbolObject;
const Method = value.Method;
const RuntimeError = value.RuntimeError;
const Chunk = chunk.Chunk;

pub const Environment = struct {
    object: Object,

    // Back pointer to outer environment (forms a chain for closures)
    parent: ?*Environment,

    // Lexical scope for constant lookup
    lexical_scope: ?*LexicalScope,

    // Variable storage - fixed size array for speed (like Ruby's CallFrame locals)
    variables: [32]Value = undefined,
    variables_len: u8 = 0,
};

pub const CallFrame = struct {
    chunk: *Chunk,
    ip: usize,
    stack_base: usize,
    self_value: Value,
    ep: *Environment,
    block_chunk: ?*Chunk = null,
    block_defining_ep: ?*Environment = null, // Environment where block was defined (for closures)
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,
    gc_allocator_atomic: std.mem.Allocator,

    parser: prism.Parser,

    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(CallFrame) = .empty,

    symbols: std.StringHashMap(*SymbolObject),

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
    nil_class: *value.ClassObject,
    true_class: *value.ClassObject,
    false_class: *value.ClassObject,
    kernel_module: *value.ModuleObject,

    // Exception classes
    exception_class: *value.ClassObject,
    standard_error_class: *value.ClassObject,
    runtime_error_class: *value.ClassObject,
    argument_error_class: *value.ClassObject,
    type_error_class: *value.ClassObject,
    zero_division_error_class: *value.ClassObject,
    no_method_error_class: *value.ClassObject,

    // Exception handling state
    pending_exception: ?*value.ExceptionObject = null,
    retry_point: ?struct {
        frame_idx: usize,
        ip: usize,
    } = null,

    // Block break state
    break_occurred: bool = false,

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
            .symbols = std.StringHashMap(*SymbolObject).init(allocator),
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
            .no_method_error_class = undefined,
        };
    }

    pub fn prepare(self: *VM, program: *compiler.CompiledProgram) !void {
        self.program = program;

        // --- Stage 1: Create Class and BasicObject ---
        const class_name_sym = try self.intern("Class");
        const class_class_val = self.newClass(class_name_sym, null);
        self.class_class = class_class_val.data.class;
        self.class_class.module.object.class = self.class_class;

        const basic_object_name_sym = try self.intern("BasicObject");
        const basic_object_class_val = self.newClass(basic_object_name_sym, null);
        self.basic_object_class = basic_object_class_val.data.class;

        // --- Stage 2: Create classes that inherit from BasicObject or Object ---
        const object_name_sym = try self.intern("Object");
        const object_class_val = self.newClass(object_name_sym, self.basic_object_class);
        self.object_class = object_class_val.data.class;

        const module_name_sym = try self.intern("Module");
        const module_class_val = self.newClass(module_name_sym, self.object_class);
        self.module_class = module_class_val.data.class;

        const numeric_name_sym = try self.intern("Numeric");
        const numeric_class_val = self.newClass(numeric_name_sym, self.object_class);
        self.numeric_class = numeric_class_val.data.class;

        const integer_name_sym = try self.intern("Integer");
        const integer_class_val = self.newClass(integer_name_sym, self.numeric_class);
        self.integer_class = integer_class_val.data.class;

        const string_name_sym = try self.intern("String");
        const string_class_val = self.newClass(string_name_sym, self.object_class);
        self.string_class = string_class_val.data.class;

        const symbol_name_sym = try self.intern("Symbol");
        const symbol_class_val = self.newClass(symbol_name_sym, self.object_class);
        self.symbol_class = symbol_class_val.data.class;

        const array_name_sym = try self.intern("Array");
        const array_class_val = self.newClass(array_name_sym, self.object_class);
        self.array_class = array_class_val.data.class;

        const hash_name_sym = try self.intern("Hash");
        const hash_class_val = self.newClass(hash_name_sym, self.object_class);
        self.hash_class = hash_class_val.data.class;

        const nil_class_name_sym = try self.intern("NilClass");
        const nil_class_val = self.newClass(nil_class_name_sym, self.object_class);
        self.nil_class = nil_class_val.data.class;

        const true_class_name_sym = try self.intern("TrueClass");
        const true_class_val = self.newClass(true_class_name_sym, self.object_class);
        self.true_class = true_class_val.data.class;

        const false_class_name_sym = try self.intern("FalseClass");
        const false_class_val = self.newClass(false_class_name_sym, self.object_class);
        self.false_class = false_class_val.data.class;

        const kernel_name_sym = try self.intern("Kernel");
        const kernel_module_val = self.newModule(kernel_name_sym);
        self.kernel_module = kernel_module_val.data.module;

        // Exception class hierarchy
        const exception_name_sym = try self.intern("Exception");
        const exception_class_val = self.newClass(exception_name_sym, self.object_class);
        self.exception_class = exception_class_val.data.class;

        const standard_error_name_sym = try self.intern("StandardError");
        const standard_error_class_val = self.newClass(standard_error_name_sym, self.exception_class);
        self.standard_error_class = standard_error_class_val.data.class;

        const runtime_error_name_sym = try self.intern("RuntimeError");
        const runtime_error_class_val = self.newClass(runtime_error_name_sym, self.standard_error_class);
        self.runtime_error_class = runtime_error_class_val.data.class;

        const argument_error_name_sym = try self.intern("ArgumentError");
        const argument_error_class_val = self.newClass(argument_error_name_sym, self.standard_error_class);
        self.argument_error_class = argument_error_class_val.data.class;

        const type_error_name_sym = try self.intern("TypeError");
        const type_error_class_val = self.newClass(type_error_name_sym, self.standard_error_class);
        self.type_error_class = type_error_class_val.data.class;

        const zero_division_error_name_sym = try self.intern("ZeroDivisionError");
        const zero_division_error_class_val = self.newClass(zero_division_error_name_sym, self.standard_error_class);
        self.zero_division_error_class = zero_division_error_class_val.data.class;

        const no_method_error_name_sym = try self.intern("NoMethodError");
        const no_method_error_class_val = self.newClass(no_method_error_name_sym, self.standard_error_class);
        self.no_method_error_class = no_method_error_class_val.data.class;

        // --- Stage 3: Set Class's superclass to Module ---
        self.class_class.superclass = self.module_class;

        // --- Stage 4: Register constants in Object ---
        try self.object_class.module.constants.put(class_name_sym, class_class_val);
        try self.object_class.module.constants.put(basic_object_name_sym, basic_object_class_val);
        try self.object_class.module.constants.put(object_name_sym, object_class_val);
        try self.object_class.module.constants.put(module_name_sym, module_class_val);
        try self.object_class.module.constants.put(numeric_name_sym, numeric_class_val);
        try self.object_class.module.constants.put(integer_name_sym, integer_class_val);
        try self.object_class.module.constants.put(symbol_name_sym, symbol_class_val);
        try self.object_class.module.constants.put(array_name_sym, array_class_val);
        try self.object_class.module.constants.put(hash_name_sym, hash_class_val);
        try self.object_class.module.constants.put(nil_class_name_sym, nil_class_val);
        try self.object_class.module.constants.put(true_class_name_sym, true_class_val);
        try self.object_class.module.constants.put(false_class_name_sym, false_class_val);
        try self.object_class.module.constants.put(kernel_name_sym, kernel_module_val);
        try self.object_class.module.constants.put(exception_name_sym, exception_class_val);
        try self.object_class.module.constants.put(standard_error_name_sym, standard_error_class_val);
        try self.object_class.module.constants.put(runtime_error_name_sym, runtime_error_class_val);
        try self.object_class.module.constants.put(argument_error_name_sym, argument_error_class_val);
        try self.object_class.module.constants.put(type_error_name_sym, type_error_class_val);
        try self.object_class.module.constants.put(zero_division_error_name_sym, zero_division_error_class_val);
        try self.object_class.module.constants.put(no_method_error_name_sym, no_method_error_class_val);

        // --- Stage 5: Register built-in methods ---
        // Register Kernel built-in methods
        const puts_sym = try self.intern("puts");
        try self.kernel_module.methods.put(puts_sym, .{ .builtin = &builtinKernelPuts });

        // Register Object built-in methods
        const new_sym = try self.intern("new");
        try self.object_class.module.methods.put(new_sym, .{ .builtin = &builtinObjectNew });

        const include_sym = try self.intern("include");
        try self.object_class.module.methods.put(include_sym, .{ .builtin = &builtinModuleInclude });

        const prepend_sym = try self.intern("prepend");
        try self.object_class.module.methods.put(prepend_sym, .{ .builtin = &builtinModulePrepend });

        try self.includeModule(self.object_class, self.kernel_module);

        // Register Integer builtins
        const plus_sym = try self.intern("+");
        try self.integer_class.module.methods.put(plus_sym, .{ .builtin = &builtinIntegerPlus });

        const minus_sym = try self.intern("-");
        try self.integer_class.module.methods.put(minus_sym, .{ .builtin = &builtinIntegerMinus });

        const equal_sym = try self.intern("==");
        try self.integer_class.module.methods.put(equal_sym, .{ .builtin = &builtinIntegerEqual });

        const less_than_sym = try self.intern("<");
        try self.integer_class.module.methods.put(less_than_sym, .{ .builtin = &builtinIntegerLessThan });

        const less_than_or_equal_sym = try self.intern("<=");
        try self.integer_class.module.methods.put(less_than_or_equal_sym, .{ .builtin = &builtinIntegerLessThanOrEqual });

        const greater_than_sym = try self.intern(">");
        try self.integer_class.module.methods.put(greater_than_sym, .{ .builtin = &builtinIntegerGreaterThan });

        const greater_than_or_equal_sym = try self.intern(">=");
        try self.integer_class.module.methods.put(greater_than_or_equal_sym, .{ .builtin = &builtinIntegerGreaterThanOrEqual });

        // Register Array builtins
        const push_sym = try self.intern("<<");
        try self.array_class.module.methods.put(push_sym, .{ .builtin = &builtinArrayPush });

        const array_each_sym = try self.intern("each");
        try self.array_class.module.methods.put(array_each_sym, .{ .builtin = &builtinArrayEach });

        // Register Hash builtins
        const bracket_sym = try self.intern("[]");
        try self.hash_class.module.methods.put(bracket_sym, .{ .builtin = &builtinHashBracket });

        const bracket_set_sym = try self.intern("[]=");
        try self.hash_class.module.methods.put(bracket_set_sym, .{ .builtin = &builtinHashBracketSet });

        const keys_sym = try self.intern("keys");
        try self.hash_class.module.methods.put(keys_sym, .{ .builtin = &builtinHashKeys });

        const values_sym = try self.intern("values");
        try self.hash_class.module.methods.put(values_sym, .{ .builtin = &builtinHashValues });

        const size_sym = try self.intern("size");
        try self.hash_class.module.methods.put(size_sym, .{ .builtin = &builtinHashSize });

        const length_sym = try self.intern("length");
        try self.hash_class.module.methods.put(length_sym, .{ .builtin = &builtinHashSize });

        const each_sym = try self.intern("each");
        try self.hash_class.module.methods.put(each_sym, .{ .builtin = &builtinHashEach });

        // Register String builtins
        const string_plus_sym = try self.intern("+");
        try self.string_class.module.methods.put(string_plus_sym, .{ .builtin = &builtinStringPlus });

        // Register to_s methods
        const to_s_sym = try self.intern("to_s");
        try self.integer_class.module.methods.put(to_s_sym, .{ .builtin = &builtinIntegerToS });
        try self.string_class.module.methods.put(to_s_sym, .{ .builtin = &builtinStringToS });
        try self.symbol_class.module.methods.put(to_s_sym, .{ .builtin = &builtinSymbolToS });
        try self.nil_class.module.methods.put(to_s_sym, .{ .builtin = &builtinNilClassToS });
        try self.true_class.module.methods.put(to_s_sym, .{ .builtin = &builtinTrueClassToS });
        try self.false_class.module.methods.put(to_s_sym, .{ .builtin = &builtinFalseClassToS });
        try self.array_class.module.methods.put(to_s_sym, .{ .builtin = &builtinArrayToS });
        try self.hash_class.module.methods.put(to_s_sym, .{ .builtin = &builtinHashToS });
        try self.kernel_module.methods.put(to_s_sym, .{ .builtin = &builtinKernelToS });

        // Register inspect methods
        const inspect_sym = try self.intern("inspect");
        try self.kernel_module.methods.put(inspect_sym, .{ .builtin = &builtinKernelInspect });
        try self.integer_class.module.methods.put(inspect_sym, .{ .builtin = &builtinIntegerInspect });
        try self.string_class.module.methods.put(inspect_sym, .{ .builtin = &builtinStringInspect });
        try self.symbol_class.module.methods.put(inspect_sym, .{ .builtin = &builtinSymbolInspect });
        try self.nil_class.module.methods.put(inspect_sym, .{ .builtin = &builtinNilClassInspect });
        try self.true_class.module.methods.put(inspect_sym, .{ .builtin = &builtinTrueClassInspect });
        try self.false_class.module.methods.put(inspect_sym, .{ .builtin = &builtinFalseClassInspect });
        try self.array_class.module.methods.put(inspect_sym, .{ .builtin = &builtinArrayInspect });
        try self.hash_class.module.methods.put(inspect_sym, .{ .builtin = &builtinHashInspect });

        // Register p method
        const p_sym = try self.intern("p");
        try self.kernel_module.methods.put(p_sym, .{ .builtin = &builtinKernelP });

        // Register raise method
        const raise_sym = try self.intern("raise");
        try self.kernel_module.methods.put(raise_sym, .{ .builtin = &builtinKernelRaise });

        // Register Exception#message method
        const message_sym = try self.intern("message");
        try self.exception_class.module.methods.put(message_sym, .{ .builtin = &builtinExceptionMessage });

        // --- Stage 6: Initialize top-level lexical scope ---
        self.current_lexical_scope = try self.createLexicalScope(&self.object_class.module, null);
    }

    pub fn createLexicalScope(self: *VM, scope_module: *value.ModuleObject, parent: ?*LexicalScope) !*LexicalScope {
        const scope = self.gc_allocator.create(LexicalScope) catch unreachable;
        scope.* = .{
            .scope_module = scope_module,
            .parent = parent,
        };
        return scope;
    }

    // Create new stack-allocated environment
    fn createStackEnvironment(self: *VM, parent: ?*Environment, lexical_scope: ?*LexicalScope) !*Environment {
        const env = self.gc_allocator.create(Environment) catch unreachable;
        env.* = .{
            .object = .{ .flags = 0, .class = self.object_class, .singleton_class = null },
            .parent = parent,
            .lexical_scope = lexical_scope,
            .variables = undefined,
            .variables_len = 0,
        };
        return env;
    }

    // Get variable by walking environment chain
    fn getVariableAtDepth(ep: *Environment, depth: usize, idx: usize) ?Value {
        var current_ep = ep;
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            current_ep = current_ep.parent orelse return null;
        }
        if (idx < current_ep.variables_len) {
            return current_ep.variables[idx];
        }
        return null;
    }

    fn setVariableAtDepth(ep: *Environment, depth: usize, idx: usize, val: Value) !void {
        var current_ep = ep;
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            current_ep = current_ep.parent orelse return;
        }
        if (idx < 32) { // Fixed size limit
            current_ep.variables[idx] = val;
            if (idx >= current_ep.variables_len) {
                current_ep.variables_len = @intCast(idx + 1);
            }
        } else {
            return error.TooManyLocals;
        }
    }

    fn findConstantInLexicalScope(_: *VM, scope: *LexicalScope, name: *value.SymbolObject) !?Value {
        var current_scope: ?*LexicalScope = scope;
        while (current_scope) |s| {
            if (s.scope_module.constants.get(name)) |val| {
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

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator, gc_allocator_atomic: std.mem.Allocator, parser: prism.Parser, program: *compiler.CompiledProgram) VM {
        var vm = initEmpty(allocator, gc_allocator, gc_allocator_atomic, parser);
        vm.prepare(program) catch unreachable;
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();
        self.stack.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.symbols.deinit();
    }

    pub fn run(self: *VM) !Value {
        self.setupOutput();

        try self.pushFrame(&self.program.main_chunk, Value.nil(), null, null);

        while (self.frames.items.len > 0) {
            try self.executeInstruction();
        }

        if (self.stack.pop()) |val| {
            return val;
        }
        return Value.nil();
    }

    fn currentFrame(self: *VM) *CallFrame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn currentChunk(self: *VM) *Chunk {
        return self.currentFrame().chunk;
    }

    fn constantToValue(self: *VM, constant: chunk.Constant) !Value {
        return switch (constant) {
            .integer => |i| Value.integer(i),
            .string => |s| self.newString(s, true),
            .symbol => |s| Value{ .data = .{ .symbol = (try self.intern(s)) } },
        };
    }

    fn push(self: *VM, val: Value) !void {
        try self.stack.append(self.allocator, val);
    }

    fn pop(self: *VM) Value {
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

    fn pushFrame(self: *VM, ch: *Chunk, self_value: Value, block_chunk: ?*Chunk, block_defining_ep: ?*Environment) !void {
        // Get parent environment (current frame's ep, if any)
        const parent_env = if (self.frames.items.len > 0)
            self.frames.items[self.frames.items.len - 1].ep
        else
            null;

        // Create environment for this frame
        // TODO: allocate on stack at first and promote to heap later
        const env = try self.createStackEnvironment(parent_env, ch.lexical_scope orelse self.current_lexical_scope);

        try self.frames.append(self.allocator, CallFrame{
            .chunk = ch,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .self_value = self_value,
            .ep = env,
            .block_chunk = block_chunk,
            .block_defining_ep = block_defining_ep,
        });

        // Update current_lexical_scope to the frame's scope
        if (ch.lexical_scope) |scope| {
            self.current_lexical_scope = scope;
        }
    }

    fn popFrame(self: *VM) !void {
        if (self.frames.items.len > 0) {
            _ = self.frames.pop();

            // Restore current_lexical_scope to the previous frame's scope
            if (self.frames.items.len > 0) {
                const prev_frame = &self.frames.items[self.frames.items.len - 1];
                self.current_lexical_scope = prev_frame.ep.lexical_scope;
            }
        }
    }

    fn executeInstruction(self: *VM) !void {
        const frame = self.currentFrame();
        if (frame.ip >= frame.chunk.code.items.len) {
            try self.popFrame();
            return;
        }

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

            .PUSH_INT => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                const val = try self.constantToValue(constant);
                try self.push(val);
            },

            .PUSH_CONST => {
                const idx = self.readU16();
                const constant = self.currentChunk().constants.items[idx];
                const val = try self.constantToValue(constant);
                try self.push(val);
            },

            .GET_LOCAL => {
                const local_idx = self.readByte();
                // Phase 1: Always depth 0 (no closures yet)
                const val = getVariableAtDepth(frame.ep, 0, local_idx) orelse Value.nil();
                try self.push(val);
            },

            .SET_LOCAL => {
                const local_idx = self.readByte();
                const val = self.pop();
                // Phase 1: Always depth 0
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
                        try self.push(Value.nil());
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
                        try scope.scope_module.constants.put(name_sym, val);
                    } else {
                        try self.object_class.module.constants.put(name_sym, val);
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

                    // Look up constant in the parent module/class
                    const result = switch (parent_val.data) {
                        .module => |m| m.constants.get(name_sym),
                        .class => |c| c.module.constants.get(name_sym),
                        else => null,
                    };

                    if (result) |const_val| {
                        try self.push(const_val);
                    } else {
                        try self.push(Value.nil());
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
                const block_chunk_id = self.readByte();

                // Pop arguments
                var args: [256]Value = undefined;
                var i: usize = 0;
                while (i < argc) : (i += 1) {
                    args[argc - 1 - i] = self.pop();
                }

                // Pop receiver
                const receiver = self.pop();

                // Look up block chunk if ID != 0
                var block_chunk: ?*Chunk = null;
                var block_defining_ep: ?*Environment = null;
                if (block_chunk_id != 0) {
                    if (self.program.method_chunks.get(block_chunk_id)) |bc| {
                        block_chunk = bc;
                        // Capture current lexical scope for the block
                        bc.lexical_scope = self.current_lexical_scope;
                        // Capture current environment for closures
                        block_defining_ep = frame.ep;
                    } else {
                        return error.UndefinedChunk;
                    }
                }

                try self.callMethod(method_idx, receiver, &args, argc, block_chunk, block_defining_ep);
            },

            .RETURN => {
                const result = self.pop();
                try self.popFrame();

                if (self.frames.items.len > 0) {
                    try self.push(result);
                } else {
                    try self.push(result);
                }
            },

            .DEF_MODULE => {
                const name_idx = self.readU16();
                const body_chunk_id = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);
                    const module_val = self.newModule(name_sym);

                    // Store constant in current lexical scope (or Object if no scope)
                    if (frame.ep.lexical_scope) |scope| {
                        try scope.scope_module.constants.put(name_sym, module_val);
                    } else {
                        try self.object_class.module.constants.put(name_sym, module_val);
                    }

                    // Execute module body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.method_chunks.get(body_chunk_id)) |body_chunk_ptr| {
                            // Create new lexical scope for this module
                            body_chunk_ptr.lexical_scope = try self.createLexicalScope(module_val.data.module, self.current_lexical_scope);

                            // Call the body chunk with the module as self
                            // pushFrame will update current_lexical_scope
                            try self.pushFrame(body_chunk_ptr, module_val, null, null);
                        } else {
                            return error.UndefinedChunk;
                        }
                    } else {
                        try self.push(module_val);
                    }
                } else {
                    return error.InvalidModuleName;
                }
            },

            .DEF_CLASS => {
                const name_idx = self.readU16();
                const body_chunk_id = self.readByte();

                // Pop superclass (or nil)
                const superclass_val = self.pop();

                var superclass: ?*value.ClassObject = null;
                if (superclass_val.data == .class) {
                    superclass = superclass_val.data.class;
                } else if (superclass_val.data != .nil) {
                    return error.InvalidSuperclass;
                }

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant == .string) {
                    const name_sym = try self.intern(constant.string);
                    const class_val = self.newClass(name_sym, superclass);

                    // Store constant in current lexical scope (or Object if no scope)
                    if (frame.ep.lexical_scope) |scope| {
                        try scope.scope_module.constants.put(name_sym, class_val);
                    } else {
                        try self.object_class.module.constants.put(name_sym, class_val);
                    }

                    // Execute class body if it exists
                    if (body_chunk_id != 0) {
                        if (self.program.method_chunks.get(body_chunk_id)) |body_chunk_ptr| {
                            // Create new lexical scope for this class
                            body_chunk_ptr.lexical_scope = try self.createLexicalScope(&class_val.data.class.module, self.current_lexical_scope);

                            // Call the body chunk with the class as self
                            // pushFrame will update current_lexical_scope
                            try self.pushFrame(body_chunk_ptr, class_val, null, null);
                        } else {
                            return error.UndefinedChunk;
                        }
                    } else {
                        try self.push(class_val);
                    }
                } else {
                    return error.InvalidClassName;
                }
            },

            .DEF_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant != .symbol) {
                    return error.InvalidMethodName;
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
                        try current_self.data.class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr });
                    } else if (current_self.data == .module) {
                        // Adding method to a module
                        try current_self.data.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr });
                    } else {
                        // Top-level: add to Object (look it up from constants)
                        // TODO: we need `main` to clean this up a bit
                        try self.object_class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr });
                    }
                } else {
                    std.debug.print("Error: undefined method chunk {d}\n", .{chunk_idx});
                    return error.UndefinedChunk;
                }
            },

            .DEF_SINGLETON_METHOD => {
                const name_idx = self.readU16();
                const chunk_idx = self.readByte();

                const constant = self.currentChunk().constants.items[name_idx];
                if (constant != .symbol) {
                    return error.InvalidMethodName;
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
                    try singleton_class.module.methods.put(method_name_sym, .{ .chunk = chunk_ptr });
                } else {
                    return error.UndefinedChunk;
                }
            },

            .PUSH_ARRAY => {
                const element_count = self.readByte();

                const array_obj = self.gc_allocator.create(value.ArrayObject) catch unreachable;
                array_obj.* = .{
                    .object = .{ .flags = 0, .class = self.array_class, .singleton_class = null },
                    .elements = .empty,
                };

                var i: usize = 0;
                while (i < element_count) : (i += 1) {
                    const elem = self.pop();
                    array_obj.elements.append(self.gc_allocator, elem) catch unreachable;
                }

                try self.push(.{ .data = .{ .array = array_obj } });
            },

            .PUSH_HASH => {
                const pair_count = self.readByte();

                const hash_obj = self.gc_allocator.create(value.HashObject) catch unreachable;
                hash_obj.* = .{
                    .object = .{ .flags = 0, .class = self.hash_class, .singleton_class = null },
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
                    }) catch unreachable;
                    hash_obj.map.put(key_hash, new_idx) catch unreachable;
                }

                try self.push(.{ .data = .{ .hash = hash_obj } });
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
                const blk = frame.block_chunk orelse {
                    const exc = try self.createException(
                        self.argument_error_class,
                        "no block given",
                    );
                    self.pending_exception = exc;
                    try self.unwindStack();
                    return;
                };

                // Check arity
                if (blk.arity != argc) {
                    const msg = std.fmt.allocPrint(
                        self.gc_allocator,
                        "wrong number of block arguments (given {d}, expected {d})",
                        .{ argc, blk.arity },
                    ) catch unreachable;
                    const exc = try self.createException(self.argument_error_class, msg);
                    self.pending_exception = exc;
                    try self.unwindStack();
                    return;
                }

                // Push frame with block's chunk, using block_defining_ep as parent for closure support
                // We need to manually create the environment with the right parent
                // Create environment with block_defining_ep as parent (lexical scoping)
                const block_env = try self.createStackEnvironment(frame.block_defining_ep, blk.lexical_scope orelse self.current_lexical_scope);

                try self.frames.append(self.allocator, CallFrame{
                    .chunk = blk,
                    .ip = 0,
                    .stack_base = self.stack.items.len,
                    .self_value = frame.self_value,
                    .ep = block_env,
                    .block_chunk = frame.block_chunk,
                    .block_defining_ep = null,
                });

                // Update current_lexical_scope to the block's scope
                if (blk.lexical_scope) |scope| {
                    self.current_lexical_scope = scope;
                }

                // Copy yield arguments to block's environment
                var block_frame = self.currentFrame();
                for (yield_args[0..argc], 0..) |arg, idx| {
                    block_frame.ep.variables[idx] = arg;
                    block_frame.ep.variables_len = @as(u8, @intCast(idx + 1));
                }

                // Execute until block returns
                self.break_occurred = false;
                const saved_frame_count = self.frames.items.len - 1;
                while (self.frames.items.len > saved_frame_count) {
                    try self.executeInstruction();
                }

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
                        try self.raise(.{ .data = .{ .exception = exc } });
                    } else {
                        // No exception to re-raise
                        return error.RuntimeError;
                    }
                } else if (argc == 1) {
                    // Single argument: exception instance or class
                    const arg = self.pop();

                    switch (arg.data) {
                        .exception => {
                            // Already an exception, raise it
                            try self.raise(arg);
                        },
                        .class => |cls| {
                            // Exception class with empty message
                            const exc = try self.createException(cls, "");
                            try self.raise(.{ .data = .{ .exception = exc } });
                        },
                        .string => |str| {
                            // String message - create RuntimeError
                            const exc = try self.createException(self.runtime_error_class, str.str);
                            try self.raise(.{ .data = .{ .exception = exc } });
                        },
                        else => {
                            // Invalid argument type
                            return error.WrongArgumentType;
                        },
                    }
                } else if (argc == 2) {
                    // Two arguments: class and message
                    const message = self.pop();
                    const class_arg = self.pop();

                    if (class_arg.data != .class) {
                        return error.WrongArgumentType;
                    }

                    const msg_str = if (message.data == .string)
                        message.data.string.str
                    else
                        "";

                    const exc = try self.createException(class_arg.data.class, msg_str);
                    try self.raise(.{ .data = .{ .exception = exc } });
                } else {
                    // Invalid number of arguments
                    return error.WrongArgumentCount;
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
                        return error.RuntimeError;
                    }
                } else {
                    // No retry point set - retry called outside of rescue block
                    return error.RuntimeError;
                }
            },

            .ENSURE_END => {
                // Pop the ensure block's return value (it's ignored)
                _ = self.pop();

                // If there's a pending exception, re-raise it after ensure block
                if (self.pending_exception != null) {
                    try self.unwindStack();
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
        }
    }

    /// Call a method by name string (not from bytecode constant pool)
    fn callMethodByName(self: *VM, receiver: Value, method_name: []const u8, args: []Value, block_chunk: ?*Chunk) RuntimeError!Value {
        const method_name_sym = self.intern(method_name) catch return error.RuntimeError;
        const class = self.getClass(receiver);
        const method = self.lookupMethod(class, method_name_sym);

        if (method == null) {
            std.debug.print("Error: undefined method '{s}'\n", .{method_name});
            return error.UndefinedMethod;
        }

        if (method) |m| {
            switch (m) {
                .chunk => |chunk_ptr| {
                    // Save current execution state
                    const saved_frame_count = self.frames.items.len;

                    // Push frame with receiver as self_value
                    self.pushFrame(chunk_ptr, receiver, block_chunk, null) catch return error.RuntimeError;

                    // Copy arguments to environment
                    var frame = self.currentFrame();
                    for (args, 0..) |arg, i| {
                        frame.ep.variables[i] = arg;
                        frame.ep.variables_len = @as(u8, @intCast(i + 1));
                    }

                    // Execute until we return to saved frame count
                    while (self.frames.items.len > saved_frame_count) {
                        self.executeInstruction() catch return error.RuntimeError;
                    }

                    // Result is on top of stack
                    return self.pop();
                },
                .builtin => |fun_ptr| {
                    return try fun_ptr(self, receiver, args, block_chunk);
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
    fn yieldToBlock(self: *VM, block: *Chunk, receiver: Value, yield_args: []const Value) RuntimeError!YieldResult {
        // Push block frame (no nested block for builtin-called blocks)
        self.pushFrame(block, receiver, null, null) catch |err| {
            const exc = try self.createException(self.runtime_error_class, @errorName(err));
            self.pending_exception = exc;
            return error.RuntimeError;
        };

        // Copy arguments to environment
        var block_frame = self.currentFrame();
        for (yield_args, 0..) |arg, i| {
            if (i >= 32) break; // Environment has max 32 variables
            block_frame.ep.variables[i] = arg;
        }
        block_frame.ep.variables_len = @as(u8, @intCast(yield_args.len));

        // Execute until block returns
        self.break_occurred = false;
        const saved_frame_count = self.frames.items.len - 1;
        while (self.frames.items.len > saved_frame_count) {
            self.executeInstruction() catch |exec_err| {
                // Check if exception was already set
                if (self.pending_exception != null) {
                    return error.RuntimeError;
                }
                const exc = try self.createException(self.runtime_error_class, @errorName(exec_err));
                self.pending_exception = exc;
                return error.RuntimeError;
            };
        }

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

    /// Ensure a block was given, or raise an error
    fn requireBlock(self: *VM, block: ?*Chunk) RuntimeError!*Chunk {
        return block orelse {
            const exc = try self.createException(self.argument_error_class, "no block given");
            self.pending_exception = exc;
            return error.RuntimeError;
        };
    }

    fn callMethod(self: *VM, method_idx: u16, receiver: Value, args: *[256]Value, argc: usize, block_chunk: ?*Chunk, block_defining_ep: ?*Environment) !void {
        if (method_idx >= self.currentChunk().constants.items.len) {
            return error.InvalidMethodIndex;
        }

        const constant = self.currentChunk().constants.items[method_idx];
        if (constant != .string) {
            return error.InvalidMethodName;
        }

        // TODO: method name should be a symbol
        const method_name = constant.string;
        const method_name_sym = try self.intern(method_name);

        var method: ?Method = null;

        // First, check singleton class (create if needed)
        if (receiver.getObjectPointer() != null) {
            const singleton_class = try self.getOrCreateSingletonClass(receiver);
            method = self.lookupMethod(singleton_class, method_name_sym);
        }

        // If not found in singleton class, check regular class
        if (method == null) {
            const class = self.getClass(receiver);
            method = self.lookupMethod(class, method_name_sym);
        }

        if (method == null) {
            // Method not found - create NoMethodError exception
            const class = self.getClass(receiver);
            const class_name = class.module.name.name;
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "undefined method '{s}' for {s}",
                .{ method_name, class_name },
            ) catch unreachable;
            const exc = try self.createException(self.no_method_error_class, msg);
            self.pending_exception = exc;
            try self.unwindStack();
            return; // Never reached if no handler found
        }

        if (method) |m| {
            switch (m) {
                .chunk => |chunk_ptr| {
                    // Push frame with receiver as self_value
                    try self.pushFrame(chunk_ptr, receiver, block_chunk, block_defining_ep);

                    // Copy arguments to locals
                    var frame = self.currentFrame();
                    var i: usize = 0;
                    while (i < argc) : (i += 1) {
                        frame.ep.variables[i] = args[i];
                        frame.ep.variables_len = @as(u8, @intCast(i + 1));
                    }
                },
                .builtin => |fun_ptr| {
                    const args_slice = args[0..argc];
                    const result = fun_ptr(self, receiver, args_slice, block_chunk) catch |err| {
                        // Check if exception was raised
                        if (self.pending_exception != null) {
                            try self.unwindStack();
                            return; // Never reached if no handler found
                        }
                        return err;
                    };
                    try self.push(result);
                },
            }
        }
    }

    fn getClass(self: *VM, val: Value) *ClassObject {
        switch (val.data) {
            // Types with Object headers - use the class field from the header
            .instance => |i| return i.class.?,
            .string => |s| return s.object.class.?,
            .symbol => |s| return s.object.class.?,
            .array => |a| return a.object.class.?,
            .hash => |h| return h.object.class.?,
            .exception => |e| return e.object.class.?,
            .module => |m| return m.object.class.?,
            .class => |c| return c.module.object.class.?,

            // Primitives without Object headers - hardcode the class
            .integer => return self.integer_class,
            .nil => return self.nil_class,
            .boolean => |b| if (b) return self.true_class else return self.false_class,
        }
    }

    fn getObjectPointer(_: *VM, obj_val: value.Value) ?*value.Object {
        return switch (obj_val.data) {
            .class => |c| &c.module.object,
            .module => |m| &m.object,
            .instance => |i| i,
            .string => |s| &s.object,
            .symbol => |s| &s.object,
            .array => |a| &a.object,
            .hash => |h| &h.object,
            .exception => |e| &e.object,
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

    fn getOrCreateSingletonClass(self: *VM, obj_val: value.Value) !*ClassObject {
        // Return existing singleton class if already created
        if (obj_val.getSingletonClass()) |singleton| {
            return singleton;
        }

        // Get the object pointer (returns null for primitives)
        const obj_ptr = obj_val.getObjectPointer() orelse return error.CannotDefineSingletonMethod;

        // Create singleton class name: "#<Class:#<hex_address>>"
        const singleton_name = try std.fmt.allocPrint(
            self.gc_allocator,
            "#<Class:#{x}>",
            .{@intFromPtr(obj_ptr)},
        );
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
            else => unreachable,
        };

        // Create the singleton ClassObject
        const singleton_class = self.gc_allocator.create(ClassObject) catch unreachable;
        singleton_class.* = .{
            .superclass = singleton_superclass,
            .module = .{
                .object = .{
                    .flags = 0,
                    .class = self.class_class,
                    .singleton_class = null,
                },
                .name = singleton_name_sym,
                .methods = std.AutoHashMap(*value.SymbolObject, value.Method).init(self.gc_allocator),
                .constants = std.AutoHashMap(*value.SymbolObject, value.Value).init(self.gc_allocator),
            },
        };

        // Link back to object
        obj_ptr.singleton_class = singleton_class;

        return singleton_class;
    }

    pub fn intern(self: *VM, str: []const u8) !*SymbolObject {
        // Check if already interned
        if (self.symbols.get(str)) |symbol_obj| {
            return symbol_obj;
        }

        // Create a symbol and store it
        const symbol_obj = self.gc_allocator.create(SymbolObject) catch unreachable;
        symbol_obj.* = .{
            .object = .{ .flags = Object.FROZEN_FLAG, .class = self.symbol_class, .singleton_class = null },
            .name = str,
        };
        try self.symbols.put(str, symbol_obj);

        return symbol_obj;
    }

    // ==== Object creation ====

    pub fn newModule(self: *VM, name: *SymbolObject) Value {
        const module_obj = self.gc_allocator.create(value.ModuleObject) catch unreachable;
        module_obj.* = .{
            .object = .{ .flags = 0, .class = self.module_class, .singleton_class = null },
            .name = name,
            .methods = std.AutoHashMap(*SymbolObject, Method).init(self.gc_allocator),
            .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
        };
        return .{ .data = .{ .module = module_obj } };
    }

    pub fn newClass(self: *VM, name: *SymbolObject, superclass: ?*ClassObject) Value {
        const class_obj = self.gc_allocator.create(ClassObject) catch unreachable;
        class_obj.* = .{
            .superclass = superclass,
            .module = .{
                .object = .{ .flags = 0, .class = self.class_class, .singleton_class = null },
                .name = name,
                .methods = std.AutoHashMap(*SymbolObject, Method).init(self.gc_allocator),
                .constants = std.AutoHashMap(*SymbolObject, Value).init(self.gc_allocator),
            },
        };
        return .{ .data = .{ .class = class_obj } };
    }

    pub fn newInstance(self: *VM, class_obj: *ClassObject) Value {
        const obj = self.gc_allocator.create(Object) catch unreachable;
        obj.* = .{
            .flags = 0,
            .class = class_obj,
            .singleton_class = null,
        };
        return .{ .data = .{ .instance = obj } };
    }

    pub fn newString(self: *VM, str: []const u8, frozen: bool) Value {
        var copy = str;
        var flags: u32 = 0;
        if (frozen) {
            flags = Object.FROZEN_FLAG;
        } else {
            copy = self.gc_allocator_atomic.dupe(u8, str) catch unreachable;
        }

        const string_obj = self.gc_allocator.create(StringObject) catch unreachable;
        string_obj.* = .{
            .object = .{ .flags = flags, .class = self.string_class, .singleton_class = null },
            .str = copy,
        };
        return .{ .data = .{ .string = string_obj } };
    }

    pub fn includeModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) !void {
        try class.included_modules.append(self.gc_allocator, module);
    }

    pub fn prependModule(self: *VM, class: *value.ClassObject, module: *value.ModuleObject) !void {
        try class.prepended_modules.append(self.gc_allocator, module);
    }

    // ==== Built-in methods ====

    fn builtinObjectNew(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        // receiver should be a class
        if (receiver.data == .class) {
            const class_ptr = receiver.data.class;
            const instance = self.newInstance(class_ptr);
            return instance;
        } else {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Class",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
    }

    fn builtinKernelPuts(self: *VM, _: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len == 0) {
            // puts with no args prints empty line
            self.stdout.?.print("\n", .{}) catch return RuntimeError.RuntimeError;
            _ = self.stdout.?.flush() catch {};
            return Value.nil();
        }

        for (args) |arg| {
            if (arg.data == .array) {
                // Special case: flatten arrays, call to_s on each element
                for (arg.data.array.elements.items) |elem| {
                    const str_val = try self.callMethodByName(elem, "to_s", &[_]Value{}, null);
                    if (str_val.data != .string) return error.RuntimeError;
                    self.stdout.?.print("{s}\n", .{str_val.data.string.str}) catch return RuntimeError.RuntimeError;
                }
            } else {
                // Normal case: call to_s on the argument
                const str_val = try self.callMethodByName(arg, "to_s", &[_]Value{}, null);
                if (str_val.data != .string) return error.RuntimeError;
                self.stdout.?.print("{s}\n", .{str_val.data.string.str}) catch return RuntimeError.RuntimeError;
            }
        }
        _ = self.stdout.?.flush() catch {};

        return Value.nil();
    }

    fn builtinKernelRaise(self: *VM, _: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len == 0) {
            // Re-raise current exception
            if (self.pending_exception) |exc| {
                try self.raise(.{ .data = .{ .exception = exc } });
            } else {
                // No exception to re-raise - raise RuntimeError
                const exc = try self.createException(self.runtime_error_class, "No exception to re-raise");
                try self.raise(.{ .data = .{ .exception = exc } });
            }
        } else if (args.len == 1) {
            const arg = args[0];
            switch (arg.data) {
                .exception => {
                    // Already an exception, raise it
                    try self.raise(arg);
                },
                .class => |cls| {
                    // Exception class with empty message
                    const exc = try self.createException(cls, "");
                    try self.raise(.{ .data = .{ .exception = exc } });
                },
                .string => |str| {
                    // String message - create RuntimeError
                    const exc = try self.createException(self.runtime_error_class, str.str);
                    try self.raise(.{ .data = .{ .exception = exc } });
                },
                else => {
                    return error.WrongArgumentType;
                },
            }
        } else if (args.len == 2) {
            const class_arg = args[0];
            const message = args[1];

            if (class_arg.data != .class) {
                return error.WrongArgumentType;
            }

            const msg_str = if (message.data == .string)
                message.data.string.str
            else
                "";

            const exc = try self.createException(class_arg.data.class, msg_str);
            try self.raise(.{ .data = .{ .exception = exc } });
        } else {
            return error.WrongArgumentCount;
        }

        return Value.nil();
    }

    fn builtinIntegerPlus(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer + args[0].data.integer;
        return Value.integer(result);
    }

    fn builtinIntegerMinus(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer - args[0].data.integer;
        return Value.integer(result);
    }

    fn builtinIntegerEqual(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer == args[0].data.integer;
        return Value.boolean(result);
    }

    fn builtinIntegerLessThan(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer < args[0].data.integer;
        return Value.boolean(result);
    }

    fn builtinIntegerLessThanOrEqual(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer <= args[0].data.integer;
        return Value.boolean(result);
    }

    fn builtinIntegerGreaterThan(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer > args[0].data.integer;
        return Value.boolean(result);
    }

    fn builtinIntegerGreaterThanOrEqual(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const result = receiver.data.integer >= args[0].data.integer;
        return Value.boolean(result);
    }

    fn builtinModuleInclude(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .module) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not a Module",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        // receiver must be a class
        if (receiver.data != .class) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Class",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const class = receiver.data.class;
        const module = args[0].data.module;

        self.includeModule(class, module) catch return error.RuntimeError;

        return receiver;
    }

    fn builtinModulePrepend(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args[0].data != .module) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not a Module",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        // receiver must be a class
        if (receiver.data != .class) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Class",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const class = receiver.data.class;
        const module = args[0].data.module;

        self.prependModule(class, module) catch return error.RuntimeError;

        return receiver;
    }

    fn builtinArrayPush(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .array) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Array",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const array = receiver.data.array;
        array.elements.append(self.gc_allocator, args[0]) catch return error.RuntimeError;

        return receiver;
    }

    fn builtinArrayEach(self: *VM, receiver: Value, args: []Value, block: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .array) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Array",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const blk = try self.requireBlock(block);
        const array_obj = receiver.data.array;

        // Iterate over array elements
        for (array_obj.elements.items) |element| {
            const yield_args = [_]Value{element};
            const result = try self.yieldToBlock(blk, receiver, &yield_args);

            // If break occurred, return immediately
            if (result.break_occurred) {
                return receiver;
            }
        }

        return receiver;
    }

    fn builtinIntegerToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .integer) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Integer",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const str = std.fmt.allocPrint(self.gc_allocator, "{d}", .{receiver.data.integer}) catch return error.RuntimeError;
        return self.newString(str, false);
    }

    fn builtinStringToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .string) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a String",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return receiver; // String#to_s returns self
    }

    fn builtinStringPlus(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .string) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a String",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const other_str = args[0];
        if (other_str.data != .string) {
            const exc = try self.createException(
                self.type_error_class,
                "argument is not a String",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const combined_str = std.fmt.allocPrint(
            self.gc_allocator,
            "{s}{s}",
            .{ receiver.data.string.str, other_str.data.string.str },
        ) catch return error.RuntimeError;

        return self.newString(combined_str, false);
    }

    fn builtinSymbolToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .symbol) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Symbol",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const str = std.fmt.allocPrint(self.gc_allocator, "{s}", .{receiver.data.symbol.name}) catch return error.RuntimeError;
        return self.newString(str, false);
    }

    fn builtinNilClassToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .nil) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not nil",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return self.newString("", false);
    }

    fn builtinTrueClassToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .boolean or !receiver.data.boolean) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not true",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return self.newString("true", false);
    }

    fn builtinFalseClassToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .boolean or receiver.data.boolean) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not false",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return self.newString("false", false);
    }

    fn builtinArrayToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .array) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Array",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const array = receiver.data.array;
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(self.allocator);

        writer.writeAll("[") catch return error.RuntimeError;
        for (array.elements.items, 0..) |elem, idx| {
            if (idx > 0) writer.writeAll(", ") catch return error.RuntimeError;

            const elem_str = try self.callMethodByName(elem, "to_s", &[_]Value{}, null);
            if (elem_str.data != .string) return error.RuntimeError;
            writer.writeAll(elem_str.data.string.str) catch return error.RuntimeError;
        }
        writer.writeAll("]") catch return error.RuntimeError;

        const str = buf.toOwnedSlice(self.allocator) catch return error.RuntimeError;
        defer self.allocator.free(str);
        return self.newString(str, false);
    }

    fn builtinKernelToS(self: *VM, receiver: Value, _: []Value, _: ?*Chunk) RuntimeError!Value {
        const class = self.getClass(receiver);
        const class_name = class.module.name.name;

        const object_id = switch (receiver.data) {
            .instance => |i| @intFromPtr(i),
            .string => |s| @intFromPtr(s),
            .symbol => |s| @intFromPtr(s),
            .array => |a| @intFromPtr(a),
            .hash => |h| @intFromPtr(h),
            .exception => |e| @intFromPtr(e),
            .module => |m| @intFromPtr(m),
            .class => |c| @intFromPtr(c),
            // Primitives get a fake object ID for now
            .integer, .boolean, .nil => 0x0000000000000001,
        };

        const str = std.fmt.allocPrint(self.gc_allocator, "#<{s}:0x{x}>", .{ class_name, object_id }) catch return error.RuntimeError;
        return self.newString(str, false);
    }

    // ===== inspect methods =====

    fn builtinIntegerInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        return self.builtinIntegerToS(receiver, args, null);
    }

    fn builtinStringInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .string) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a String",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const input = receiver.data.string.str;
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(self.allocator);

        writer.writeAll("\"") catch return error.RuntimeError;
        for (input) |c| {
            switch (c) {
                '"' => writer.writeAll("\\\"") catch return error.RuntimeError,
                '\\' => writer.writeAll("\\\\") catch return error.RuntimeError,
                '\n' => writer.writeAll("\\n") catch return error.RuntimeError,
                '\t' => writer.writeAll("\\t") catch return error.RuntimeError,
                '\r' => writer.writeAll("\\r") catch return error.RuntimeError,
                '\x08' => writer.writeAll("\\b") catch return error.RuntimeError, // backspace
                '\x0c' => writer.writeAll("\\f") catch return error.RuntimeError, // form feed
                '\x0b' => writer.writeAll("\\v") catch return error.RuntimeError, // vertical tab
                '\x00' => writer.writeAll("\\0") catch return error.RuntimeError, // null
                else => {
                    if (c < 32 or c > 126) {
                        std.fmt.format(writer, "\\x{x:0>2}", .{c}) catch return error.RuntimeError;
                    } else {
                        writer.writeByte(c) catch return error.RuntimeError;
                    }
                },
            }
        }
        writer.writeAll("\"") catch return error.RuntimeError;

        const str = buf.toOwnedSlice(self.allocator) catch return error.RuntimeError;
        defer self.allocator.free(str);
        return self.newString(str, false);
    }

    fn builtinSymbolInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .symbol) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Symbol",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const str = std.fmt.allocPrint(self.gc_allocator, ":{s}", .{receiver.data.symbol.name}) catch return error.RuntimeError;
        return self.newString(str, false);
    }

    fn builtinNilClassInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .nil) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not nil",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return self.newString("nil", false);
    }

    fn builtinTrueClassInspect(self: *VM, receiver: Value, args: []Value, block_chunk: ?*Chunk) RuntimeError!Value {
        return self.builtinTrueClassToS(receiver, args, block_chunk);
    }

    fn builtinFalseClassInspect(self: *VM, receiver: Value, args: []Value, block_chunk: ?*Chunk) RuntimeError!Value {
        return self.builtinFalseClassToS(receiver, args, block_chunk);
    }

    fn builtinArrayInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .array) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Array",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const array = receiver.data.array;
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(self.allocator);

        writer.writeAll("[") catch return error.RuntimeError;
        for (array.elements.items, 0..) |elem, idx| {
            if (idx > 0) writer.writeAll(", ") catch return error.RuntimeError;

            const elem_inspected = try self.callMethodByName(elem, "inspect", &[_]Value{}, null);
            if (elem_inspected.data != .string) return error.RuntimeError;
            writer.writeAll(elem_inspected.data.string.str) catch return error.RuntimeError;
        }
        writer.writeAll("]") catch return error.RuntimeError;

        const str = buf.toOwnedSlice(self.allocator) catch return error.RuntimeError;
        defer self.allocator.free(str);
        return self.newString(str, false);
    }

    fn builtinKernelInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        return self.builtinKernelToS(receiver, args, null);
    }

    fn builtinKernelP(self: *VM, _: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (args.len == 0) {
            self.stdout.?.print("\n", .{}) catch return error.RuntimeError;
            _ = self.stdout.?.flush() catch {};
            return Value.nil();
        }

        for (args, 0..) |arg, idx| {
            const inspected = try self.callMethodByName(arg, "inspect", &[_]Value{}, null);
            if (inspected.data != .string) return error.RuntimeError;

            if (idx > 0) {
                self.stdout.?.print("\n", .{}) catch return error.RuntimeError;
            }
            self.stdout.?.print("{s}", .{inspected.data.string.str}) catch return error.RuntimeError;
        }
        self.stdout.?.print("\n", .{}) catch return error.RuntimeError;
        _ = self.stdout.?.flush() catch {};

        if (args.len == 1) {
            return args[0];
        } else {
            const array_obj = self.gc_allocator.create(value.ArrayObject) catch return error.RuntimeError;
            array_obj.* = .{
                .object = .{ .flags = 0, .class = self.array_class, .singleton_class = null },
                .elements = .empty,
            };

            for (args) |arg| {
                array_obj.elements.append(self.gc_allocator, arg) catch return error.RuntimeError;
            }

            return .{ .data = .{ .array = array_obj } };
        }
    }

    // ===== Exception Handling Methods =====

    /// Create a new exception object
    fn createException(self: *VM, class: *ClassObject, message: []const u8) RuntimeError!*value.ExceptionObject {
        const exc = self.gc_allocator.create(value.ExceptionObject) catch unreachable;
        const msg_str = self.newString(message, false);
        const backtrace = self.captureBacktrace() catch return error.RuntimeError;

        exc.* = .{
            .object = .{
                .flags = 0,
                .class = class,
                .singleton_class = null,
            },
            .message = msg_str.data.string,
            .backtrace = backtrace,
            .cause = self.pending_exception,
        };

        return exc;
    }

    fn builtinExceptionMessage(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .exception) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not an Exception",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const exc = receiver.data.exception;
        return .{ .data = .{ .string = exc.message } };
    }

    fn builtinHashBracket(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 1) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 1)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const hash_obj = receiver.data.hash;
        const key = args[0];
        const key_hash = key.hash();

        if (hash_obj.map.get(key_hash)) |idx| {
            if (hash_obj.entries.items[idx].key.eql(key)) {
                return hash_obj.entries.items[idx].value;
            }
        }

        return Value.nil();
    }

    fn builtinHashBracketSet(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 2) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 2)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (receiver.isFrozen()) {
            const exc = try self.createException(self.runtime_error_class, "can't modify frozen Hash");
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const hash_obj = receiver.data.hash;
        const key = args[0];
        const new_value = args[1];
        const key_hash = key.hash();

        if (hash_obj.map.get(key_hash)) |idx| {
            if (hash_obj.entries.items[idx].key.eql(key)) {
                hash_obj.entries.items[idx].value = new_value;
                return new_value;
            }
        }

        const new_idx = hash_obj.entries.items.len;
        hash_obj.entries.append(self.gc_allocator, .{ .key = key, .value = new_value }) catch unreachable;
        hash_obj.map.put(key_hash, new_idx) catch unreachable;

        return new_value;
    }

    fn builtinHashKeys(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const hash_obj = receiver.data.hash;
        const array_obj = self.gc_allocator.create(value.ArrayObject) catch unreachable;
        array_obj.* = .{
            .object = .{ .flags = 0, .class = self.array_class, .singleton_class = null },
            .elements = .empty,
        };

        for (hash_obj.entries.items) |entry| {
            array_obj.elements.append(self.gc_allocator, entry.key) catch unreachable;
        }

        return .{ .data = .{ .array = array_obj } };
    }

    fn builtinHashValues(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const hash_obj = receiver.data.hash;
        const array_obj = self.gc_allocator.create(value.ArrayObject) catch unreachable;
        array_obj.* = .{
            .object = .{ .flags = 0, .class = self.array_class, .singleton_class = null },
            .elements = .empty,
        };

        for (hash_obj.entries.items) |entry| {
            array_obj.elements.append(self.gc_allocator, entry.value) catch unreachable;
        }

        return .{ .data = .{ .array = array_obj } };
    }

    fn builtinHashSize(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return Value.integer(@intCast(receiver.data.hash.entries.items.len));
    }

    fn builtinHashEach(self: *VM, receiver: Value, args: []Value, block: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }
        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const blk = try self.requireBlock(block);
        const hash_obj = receiver.data.hash;

        // Iterate in insertion order
        for (hash_obj.entries.items) |entry| {
            const yield_args = [_]Value{ entry.key, entry.value };
            const result = try self.yieldToBlock(blk, receiver, &yield_args);

            // If break occurred, return immediately
            if (result.break_occurred) {
                return receiver;
            }
        }

        return receiver;
    }

    fn builtinHashToS(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        const hash_obj = receiver.data.hash;
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.gc_allocator);
        const writer = buf.writer(self.gc_allocator);

        writer.writeAll("{") catch return error.RuntimeError;
        for (hash_obj.entries.items, 0..) |entry, idx| {
            if (idx > 0) {
                writer.writeAll(", ") catch return error.RuntimeError;
            }

            // Check if key is a symbol - use shorthand syntax
            if (entry.key.data == .symbol) {
                // Write symbol name without the : prefix
                const sym = entry.key.data.symbol;
                writer.writeAll(sym.name) catch return error.RuntimeError;
                writer.writeAll(": ") catch return error.RuntimeError;
            } else {
                // Call inspect on non-symbol keys
                const key_val = try self.callMethodByName(entry.key, "inspect", &.{}, null);
                if (key_val.data != .string) return error.RuntimeError;
                writer.writeAll(key_val.data.string.str) catch return error.RuntimeError;
                writer.writeAll(" => ") catch return error.RuntimeError;
            }

            // Call inspect on value
            const value_val = try self.callMethodByName(entry.value, "inspect", &.{}, null);
            if (value_val.data != .string) return error.RuntimeError;
            writer.writeAll(value_val.data.string.str) catch return error.RuntimeError;
        }
        writer.writeAll("}") catch return error.RuntimeError;

        const final_str = buf.toOwnedSlice(self.gc_allocator) catch return error.RuntimeError;
        return self.newString(final_str, false);
    }

    fn builtinHashInspect(self: *VM, receiver: Value, args: []Value, _: ?*Chunk) RuntimeError!Value {
        if (receiver.data != .hash) {
            const exc = try self.createException(
                self.type_error_class,
                "receiver is not a Hash",
            );
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        if (args.len != 0) {
            const msg = std.fmt.allocPrint(
                self.gc_allocator,
                "wrong number of arguments (given {d}, expected 0)",
                .{args.len},
            ) catch unreachable;
            const exc = try self.createException(self.argument_error_class, msg);
            self.pending_exception = exc;
            return error.RuntimeError;
        }

        return try self.builtinHashToS(receiver, args, null);
    }

    /// Capture current call stack as a backtrace
    fn captureBacktrace(self: *VM) RuntimeError!?*value.ArrayObject {
        const array_obj = self.gc_allocator.create(value.ArrayObject) catch unreachable;
        array_obj.* = .{
            .object = .{
                .flags = 0,
                .class = self.array_class,
                .singleton_class = null,
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
            ) catch return error.RuntimeError;

            const str_val = self.newString(backtrace_str, false);
            array_obj.elements.append(self.gc_allocator, str_val) catch return error.RuntimeError;
        }

        return array_obj;
    }

    /// Raise an exception and start unwinding
    fn raise(self: *VM, exception_val: Value) RuntimeError!void {
        const exc = switch (exception_val.data) {
            .exception => |e| e,
            else => {
                // Not an exception object - this is an internal error
                std.debug.print("Internal error: raise() called with non-exception value\n", .{});
                return error.RuntimeError;
            },
        };

        self.pending_exception = exc;
        try self.unwindStack();
    }

    /// Unwind the call stack looking for exception handlers
    fn unwindStack(self: *VM) RuntimeError!void {
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
        return error.RuntimeError;
    }

    /// Find an exception handler in the current frame
    fn findExceptionHandler(self: *VM, frame: *CallFrame) !?struct {
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
                            const class_name_sym = self.intern(class_name) catch continue;
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
        if (self.pending_exception) |exc| {
            const writer = self.stderr.?;

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
        }
    }
};
