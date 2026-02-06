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

**Bytecode Chunks:** Each chunk contains code, constants, constant_names (HashMap for named constants), line info, name, chunk_id, arity, is_lambda flag, optional_params (list of OptionalParam entries with param_index and default_chunk_id), rest_param_index (slot for *rest parameter), post_required_count (required params after rest), exception_handlers table, lexical_scope, and source_file. Module bodies, class bodies, methods, blocks, procs, and lambdas are all compiled into separate chunks.

**Constants:** Compile-time constants (integer, string, symbol). Strings/symbols are borrowed from Parser AST (no allocation).

**OpCodes:** Defined in `bytecode.zig` enum. Include literals, variable access, control flow, method calls, OOP definitions, blocks/procs/lambdas (YIELD, PUSH_LAMBDA, BREAK), constant path resolution (GET_CONST_PATH), exception handling (RAISE, TRY_BEGIN, TRY_END, CATCH_START, CATCH_END, ENSURE_START, ENSURE_END, RETRY). RETURN opcode has operand distinguishing implicit (0) vs explicit (1) returns for lambda semantics. Arithmetic operators are method calls, not opcodes.

**CALL Instruction:** Operands are method_idx (U16), argc (U8), block_chunk_id (U8).

**CallFrames:** chunk, ip, stack_base, self_value, ep (Environment pointer), block (optional Block), frame_type (method/lambda/proc). Local variables are stored in the Environment (which has a fixed-size 32-slot variables array), not directly in CallFrame.

**Symbol Interning:** `VM.intern(str)` creates GC-allocated SymbolObject with canonical string, cached in HashMap. Same string always returns same symbol with same memory address.

**Classes/Modules:** Classes have module-like method storage, superclass, prepended/included module lists. Method lookup walks: prepended → class methods → included → superclass.

**Value Types:** Primitives (integer, boolean, nil), heap-allocated (Object, SymbolObject, StringObject, ModuleObject, ClassObject, ArrayObject, HashObject, ExceptionObject, ProcObject).

**Blocks, Procs, and Lambdas:** All compiled into separate bytecode chunks with arity and parameters. Chunks have is_lambda flag distinguishing lambda from proc/block semantics. YIELD executes the block passed to current method. PUSH_LAMBDA creates a ProcObject wrapping a Block (chunk + defining_ep). Block struct contains chunk and defining_ep (the environment where the block was defined). Blocks capture variables from enclosing scopes (closures) via environment parent chain. When blocks escape to Proc objects, environments are promoted from stack to heap. CallFrames track `ep` (current environment) and optionally a `block` (if one was passed).

**Proc vs Lambda Semantics:**
- Lambdas enforce strict arity checking; procs are lenient (fill missing args with nil, ignore extras)
- Lambda return returns from the lambda itself; proc/block return returns from enclosing method
- `Proc#lambda?` returns true for lambdas, false for procs
- Stabby lambda syntax (`-> { }`) and `lambda { }` create lambdas; `proc { }` and `Proc.new { }` create procs

**Environments:** Store local variables in fixed-size array (32 slots) with parent pointer forming chain for closures, plus lexical_scope pointer for constant lookup. Optimistically stack-allocated, promoted to heap when captured. Fields: parent (?*Environment), lexical_scope (?*LexicalScope), variables ([32]Value), variables_len (u8).

**Lexical Scopes:** Chain tracking module/class context for constant lookup.

**Exception Handling:**
- Exception classes: Exception, StandardError, RuntimeError, ArgumentError, TypeError, ZeroDivisionError, NoMethodError
- Each chunk has exception_handlers table with ExceptionHandler entries
- ExceptionHandler contains: try_start_ip, try_end_ip, rescue_handlers (list), else_ip (optional), ensure_ip (optional), ensure_end_ip (optional)
- RescueHandler entries contain: exception_types (list of constant pool indices), catch_ip, catch_end_ip, var_idx (optional local slot for exception binding)
- VM tracks pending_exception and retry_point

## Memory Management

**Infrastructure Allocator:** Manages HashMaps, call stack, bytecode chunks. Manually cleaned up.

**GC Allocator (Boehm-Demers-Weiser):** Manages all Ruby heap objects (ClassValue, ModuleValue, InstanceValue, method HashMaps). Conservative GC scans stack/heap. NO manual free().

**Atomic GC Allocator:** For "atomic" objects without internal pointers (string duplication).

**Pointer Lifetimes:**
- Parser strings: Borrowed from AST, valid for VM lifetime
- Constant pool strings: Borrowed from AST (no allocation)
- GC objects: Freed by GC automatically

**Environment Promotion:** Stack environments are promoted to heap (via GC allocator) when captured by closures, using forwarding pointers to update all references.

## Adding Features

**New OpCode:** Add to `OpCode` enum, `opcodeName()`, emit in compiler, handle in VM executeInstruction().

**New Value Type:** Add to `Value.data` union, factory method, update `Value.format()` for display.

**Builtin Methods:** Core methods are registered in `VM.prepare()` on class/module objects using `.{ .builtin = &function }`. Examples include:
- Kernel: `puts`, `p`, `raise`, `proc`, `lambda`, `require`, `require_relative`, `load`, `to_s`, `inspect`
- Object: `new`
- Module: `include`, `prepend`
- Integer: `+`, `-`, `*`, `==`, `<`, `<=`, `>`, `>=`, `to_s`, `inspect`
- Array: `push`, `length`, `each`, `to_s`, `inspect`
- Hash: `[]`, `[]=`, `keys`, `values`, `each`, `size`, `to_s`, `inspect`
- String: `+`, `to_s`, `inspect`
- Proc: `new`, `call`, `lambda?`
- Exception: `message`
- TrueClass, FalseClass, NilClass: `to_s`, `inspect`

**New Builtin Method:** Write function, register in `VM.prepare()` on appropriate class using `.{ .builtin = &function }`.

## Testing & Debugging

```bash
# pass/fail status -- no ouput. Status 0 means success.
zig build test

# short summary
zig build test --summary all

# filter to tests having the word "Proc" (case sensitive)
zig build test -Dtest-filter="Proc"

# filter by name and print every test description that matched
zig build test -Dtest-filter="Proc" -Dtest-verbose
```

Tests are in `src/test/language/*.zig`. When adding new test files, remember to add them to `src/all_test.zig`.

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

## Ruby Specs

We have tests in both `*_test.zig` files and in `*_spec.rb` files.

The zig tests are for bootstrapping language features or for edge cases not expressed in ruby spec files.

The spec files come from [ruby/spec](https://github.com/ruby/spec), which is a community-maintained repository of specs describing Ruby. When implementing one of these specs, we'll copy it over and try to get it passing. Specs in `src/test/spec`
should automatically be run. Look in `../ruby_spec` for the files before going to the web.
