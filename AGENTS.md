# Cora Interpreter - Agent Context Guide

Cora is a Ruby interpreter written in Zig using the Prism parser. It uses a **two-stage compilation model**: Prism AST → Bytecode → VM execution.

## Core Architecture

**Execution Pipeline:**
1. **Parsing:** Prism C library parses Ruby source → AST (stored in `Parser.ast`)
2. **Compilation:** `Compiler.compile()` walks AST → generates bytecode chunks
3. **VM Execution:** `VM.run()` interprets bytecode with stack-based VM

**Key Files:**
- `src/main.zig` - CLI entry point
- `src/prism.zig` - Prism C library wrapper with typed Node union (note that prism generated sources are in `zig-out/prism` - C and header files for you to examine)
- `src/compiler.zig` - Converts Prism AST to bytecode chunks
- `src/chunk.zig` - Bytecode chunks (code, constants, line info, exception handlers)
- `src/bytecode.zig` - OpCode definitions
- `src/vm.zig` - Stack-based bytecode interpreter
- `src/value.zig` - Runtime value types and factory methods

## Key Concepts

**Bytecode Chunks:** Each chunk contains code, constants, line info, name, chunk_id, arity, exception_handlers table, and lexical_scope. Module bodies, class bodies, methods, and blocks are all compiled into separate chunks.

**Constants:** Compile-time constants (integer, string, symbol). Strings/symbols are borrowed from Parser AST (no allocation).

**OpCodes:** Defined in `bytecode.zig` enum. Include literals, variable access, control flow, method calls, OOP definitions, blocks, constant path resolution (GET_CONST_PATH), exception handling (RAISE, TRY_BEGIN, TRY_END, CATCH_START, CATCH_END, ENSURE_START, ENSURE_END, RETRY). Arithmetic operators are method calls, not opcodes.

**CALL Instruction:** Operands are method_idx (U16), argc (U8), block_chunk_id (U8).

**CallFrames:** Fixed-size locals array (32 slots), chunk, ip, stack_base, self_value, block_chunk, lexical_scope. Uses fixed-size array for performance.

**Symbol Interning:** `VM.intern(str)` creates GC-allocated SymbolObject with canonical string, cached in HashMap. Same string always returns same symbol with same memory address.

**Classes/Modules:** Classes have module-like method storage, superclass, prepended/included module lists. Method lookup walks: prepended → class methods → included → superclass.

**Value Types:** Primitives (integer, boolean, nil), heap-allocated (Object, SymbolObject, StringObject, ModuleObject, ClassObject, ArrayObject, HashObject, ExceptionObject).

**Blocks:** Compiled into separate bytecode chunks with arity and parameters. YIELD executes the block passed to current method.

**Lexical Scopes:** Chain tracking module/class context for constant lookup.

**Exception Handling:** 
- Exception classes: Exception, StandardError, RuntimeError, ArgumentError, TypeError, ZeroDivisionError, NoMethodError
- Each chunk has exception_handlers table with RescueHandler entries (exception types, catch_ip, var_idx)
- ExceptionHandler contains protected region, rescue handlers, else/ensure IPs
- VM tracks pending_exception and retry_point

## Memory Management

**Infrastructure Allocator:** Manages HashMaps, call stack, bytecode chunks. Manually cleaned up.

**GC Allocator (Boehm-Demers-Weiser):** Manages all Ruby heap objects (ClassValue, ModuleValue, InstanceValue, method HashMaps). Conservative GC scans stack/heap. NO manual free().

**Atomic GC Allocator:** For "atomic" objects without internal pointers (string duplication).

**Pointer Lifetimes:**
- Parser strings: Borrowed from AST, valid for VM lifetime
- Constant pool strings: Borrowed from AST (no allocation)
- GC objects: Freed by GC automatically

## Adding Features

**New OpCode:** Add to `OpCode` enum, `opcodeName()`, emit in compiler, handle in VM executeInstruction().

**New Value Type:** Add to `Value.data` union, factory method, update `printValue()`.

**New Builtin Method:** Write function, register in `VM.prepare()` on appropriate class using `.{ .builtin = &function }`.

## Testing & Debugging

```bash
zig build test --summary all
```

Tests are in `src/test/language/*.zig`.

**Running the CLI:**

```bash
zig build run -- [flags] [filename]
# or
zig-out/bin/cora [flags] [filename]
```

**CLI Flags:**
- `-e` - Run with a code string
- `--ast` - Dump Prism AST to see node structure
- `--dump-bytecode` - Show compiled bytecode (opcodes, constants, chunks)

## Idiomatic Zig

Use "unmanaged" ArrayList: `field: ArrayList(*Value) = .empty` (allocator passed to append/insert).
