# Clara Interpreter - Agent Context Guide

Clara is a Ruby interpreter written in Zig using the Prism parser for AST generation. It uses a **two-stage compilation model**: Prism AST → Bytecode → VM execution.

## Core Architecture

**Execution Pipeline:**
1. **Parsing:** Prism C library parses Ruby source → AST (stored in `Parser.ast`)
2. **Compilation:** `Compiler.compile()` walks AST → generates bytecode chunks
3. **VM Execution:** `VM.run()` interprets bytecode with stack-based VM

**Key Files:**
- `src/main.zig` - CLI entry point, orchestrates parse → compile → execute
- `src/prism.zig` - Prism C library wrapper with typed Node union
- `src/compiler.zig` - Converts Prism AST to bytecode chunks
- `src/chunk.zig` - Bytecode chunks (code, constants, line info)
- `src/bytecode.zig` - OpCode definitions (PUSH_INT, CALL, RETURN, etc.) and built-ins
- `src/vm.zig` - Stack-based bytecode interpreter
- `src/value.zig` - Runtime value types and factory methods

**Value Types:** String, Integer, Boolean, Nil, Symbol (interned), Module, Class, Instance

**VM State:**
- `allocator: Allocator` - Infrastructure allocator for HashMaps, call stack, constants
- `gc_allocator: Allocator` - GC allocator (Boehm-Demers-Weiser) for Ruby objects
- `parser: Parser` - Parser instance (stores AST; lifetime = VM lifetime)
- `stack: ArrayList(Value)` - Execution stack for bytecode interpreter
- `frames: ArrayList(CallFrame)` - Call frames with execution state
- `constants: StringHashMap(Value)` - Top-level constants, classes, modules
- `symbols: StringHashMap(Value)` - Interned symbols (key: string, value: symbol Value)
- `program: CompiledProgram` - Compiled bytecode (main chunk + method chunks)

## Key Concepts

**Bytecode Chunks:** Each chunk contains:
- `code: ArrayList(u8)` - Bytecode instructions
- `constants: ArrayList(Constant)` - Compile-time constants (integer, string, symbol)
- `line_info: ArrayList(u32)` - Line numbers for debugging
- `name: []const u8` - Chunk name (e.g., "main", "foo")

**Constant Type** (compile-time, not runtime):
```zig
pub const Constant = union(enum) {
    integer: i64,
    string: []const u8,   // Borrowed from Parser AST
    symbol: []const u8,   // Borrowed from Parser AST
};
```
Constants are NOT allocated—strings/symbols are borrowed from the Parser AST. The Parser lives as long as the VM, so pointers are valid for VM lifetime.

**OpCodes** (major ones):
- `PUSH_INT`, `PUSH_CONST` - Push constant from pool onto stack
- `GET_LOCAL`, `SET_LOCAL` - Access local variables
- `CALL`, `CALL_BUILTIN` - Method calls
- `DEF_CLASS`, `DEF_MODULE`, `DEF_METHOD` - Define OOP structures
- `JUMP`, `JUMP_IF_FALSE` - Control flow
- `ADD`, `SUB`, `EQ` - Arithmetic/comparison
- `RETURN`, `HALT` - Return from function, halt VM

**CallFrames:** Fixed-size locals (32 slots) stored on stack as part of CallFrame:
```zig
pub const CallFrame = struct {
    chunk: *Chunk,
    ip: usize,
    stack_base: usize,
    self_value: Value,
    locals: [32]Value,    // Fixed-size array (no allocation)
    locals_len: u8,       // Number of initialized locals
};
```
This avoids allocating an ArrayList per function call (major performance win for recursive functions).

**Symbol Interning:** `VM.intern(str)` creates a GC-allocated canonical string and stores it in `symbols` map. Same string always returns same symbol Value with same memory address.

**Method Storage:** Methods are Chunk pointers stored in class/module `.methods` HashMap. Method lookup walks inheritance chain from receiver's class up to Object.

## Adding Features

**New OpCode:**
1. Add variant to `OpCode` enum in `bytecode.zig`
2. Add case to `opcodeName()` function
3. Emit the opcode in `compiler.zig` (in appropriate compileNode() case)
4. Handle the opcode in `vm.zig` (in executeInstruction() switch)

**New Value Type:**
1. Add variant to `Value.data` union in `value.zig`
2. Add factory method (e.g., `pub fn myType(...) Value`)
3. Update `constantToValue()` in `vm.zig` if needed
4. Add case in `printValue()` for output
5. Test with manual execution

**New Builtin Method:**
1. Add variant to `BuiltinId` enum in `bytecode.zig`
2. Add case in `compiler.zig` (check method name, emit CALL_BUILTIN)
3. Handle in `vm.zig` (callBuiltin() switch)

## Memory Management

**Two Allocators:**

1. **Infrastructure Allocator** (`allocator: GeneralPurposeAllocator`)
   - Manages interpreter internals: constants HashMap, symbols HashMap, call stack, bytecode chunks
   - Manually cleaned up in `VM.deinit()`
   - Leak detection enabled in tests

2. **GC Allocator** (`gc_allocator: Boehm-Demers-Weiser`)
   - Manages all Ruby heap objects: ClassValue, ModuleValue, InstanceValue
   - Manages method HashMaps (created with gc_allocator, owned by classes/modules)
   - Automatically collects unreachable objects
   - Conservative GC scans stack and heap for pointers
   - NO manual free() calls needed for GC-allocated objects

**Pointer Lifetimes:**

- **Parser Strings:** Borrowed from Parser AST, valid for VM lifetime
- **Interned Strings:** GC-allocated by `VM.intern()`, stored in `symbols` HashMap
- **Constant Pool Strings:** Borrowed from Parser AST (no allocation needed)
- **GC Objects:** Allocated with `gc_allocator`, freed by GC automatically

**How to Create Ruby Objects:**
```zig
// All GC-managed objects - allocation is transparent
const cls = Value.class(gc_allocator, name, superclass);
const mod = Value.module(gc_allocator, name);
const inst = Value.instance(gc_allocator, class_ptr);
```

**When Objects Are Freed:**
- GC-managed objects: During GC collection cycles
- Infrastructure objects: When `VM.deinit()` is called
- Chunks are freed by `CompiledProgram.deinit()`

## Implemented Ruby Features

**Literals & Basics:**
- String/Integer/Boolean/Nil literals
- Symbols (interned, same symbol has same memory address)
- Constants (module/class/top-level)
- Local variables

**Control Flow:**
- if/else/elsif/end statements
- Truthy/falsy evaluation (only nil and false are falsy)

**Methods:**
- Built-in methods: `puts`, `new`
- User-defined methods with parameters
- Method calls with receivers
- `self` keyword

**OOP:**
- Modules and Classes
- Inheritance (defaults to Object)
- `ClassName.new` instantiation
- Instance method calls
- Method definitions in class/module/top-level context

**Arithmetic & Comparison:**
- Binary operators: `+`, `-`, `==`
- Integer arithmetic

## Performance Optimizations

**Fixed-Size Locals:** CallFrames use `[32]Value` array instead of ArrayList. This eliminates ~240K allocations for `fib(25)`, resulting in **8.7x speedup** (11.8s → 1.36s).

**Constant Pool Borrowing:** Chunk constants borrow strings from Parser AST rather than allocating. Zero allocation for compile-time constants.

**Symbol Caching:** Interned symbols cached in HashMap, same string always returns same symbol Value.
