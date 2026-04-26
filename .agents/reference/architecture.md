# Architecture Reference

## Core Architecture

**Execution pipeline:**
1. **Parsing:** Prism C library parses Ruby source -> AST (stored in `Parser.ast`)
2. **Compilation:** `Compiler.compile()` walks AST -> generates bytecode chunks
3. **VM execution:** `VM.run()` interprets bytecode with a stack-based VM

**Key files:**
- `src/main.zig` - CLI entry point
- `src/prism.zig` - Prism C library wrapper with typed Node union
- `zig-out/prism` - generated Prism C/header sources when you need to inspect parser internals
- `src/compiler.zig` - converts Prism AST to bytecode chunks
- `src/chunk.zig` - bytecode chunks, constants, line info, handlers
- `src/bytecode.zig` - `OpCode` definitions
- `src/vm.zig` - stack-based bytecode interpreter
- `src/value.zig` - runtime value types and factory methods

## Runtime Model

**Bytecode chunks:** Each chunk contains code, constants, `constant_names` (HashMap for named constants), line info, name, `chunk_id`, arity, `is_lambda`, `optional_params` (with `param_index` and `default_chunk_id`), `rest_param_index`, `post_required_count`, keyword metadata (required/optional keywords, `**kwargs` slot, `**nil` flag), `block_param_index`, `exception_handlers`, `lexical_scope`, and `source_file`. Module bodies, class bodies, methods, blocks, procs, and lambdas are all separate chunks.

**Constants:** Compile-time constants are integers, strings, and symbols. Strings and symbols are borrowed from the Prism AST rather than newly allocated.

**OpCodes:** Defined in `bytecode.zig`. Existing families include literals, variable and constant access, control flow, method calls (`CALL`, `CALL_KW`), OOP definitions, blocks/procs/lambdas (`YIELD`, `PUSH_LAMBDA`, `BREAK`), constant path resolution (`GET_CONST_PATH`), exception handling, `super`, regexp support, aliasing, and multi-assignment prep. `RETURN` uses an operand to distinguish implicit (`0`) from explicit (`1`) returns for lambda semantics.

Prefer not to add new opcodes when an existing mechanism can be extended. When a new opcode is necessary, keep it general and reusable. For example, prefer adding array-manipulation support plus a call flag over inventing a feature-specific `CALL_*` opcode.

**CALL instruction:** `CALL` operands are `method_idx` (`U16`), `argc` (`U8`), and `block_chunk_id` (`U16`), plus call flags for implicit-self and args-array mode. `CALL_KW` extends that core with keyword count and a keyword metadata index.

**CallFrames:** A frame contains `chunk`, `ip`, `stack_base`, `self_value`, `ep` (Environment pointer), optional `block`, and `frame_type` (method/lambda/proc). Local variables are stored in the `Environment`, not directly in the `CallFrame`.

**Symbol interning:** `VM.intern(str)` creates a GC-allocated `SymbolObject` with canonical string storage and caches it in a HashMap. The same symbol string should map to the same symbol object identity.

**Classes/modules:** Classes store module-like method tables plus superclass and prepended/included module lists. Method lookup walks prepended modules -> class methods -> included modules -> superclass.

**Value types:** Primitives include integer, float, boolean, and nil. Heap-allocated types include object instances, symbols, strings, modules, classes, arrays, hashes, ranges, exceptions, procs, fibers, regexps, and encodings.

**Blocks, procs, and lambdas:** All are compiled into separate bytecode chunks with arity and parameter metadata. `is_lambda` distinguishes lambda versus proc/block semantics. `YIELD` executes the block passed to the current method. `PUSH_LAMBDA` creates a `ProcObject` wrapping a `Block` (`chunk` + `defining_ep`). Blocks capture through the environment parent chain. Escaping blocks promote captured environments from stack to heap.

**Proc vs lambda semantics:**
- Lambdas enforce strict arity; procs are lenient.
- Lambda `return` returns from the lambda itself.
- Proc/block `return` returns from the enclosing method.
- `Proc#lambda?` is true only for lambdas.
- `-> {}` and `lambda {}` create lambdas; `proc {}` and `Proc.new {}` create procs.

**Environments:** `Environment` stores locals in a fixed-size 32-slot array, plus `parent` and `lexical_scope`. Environments start stack-allocated and are promoted to heap when captured.

**Lexical scopes:** Lexical scope chains track module/class context for constant lookup.

## Exception Handling

- Built-in exception classes include `Exception`, `StandardError`, `RuntimeError`, `ArgumentError`, `TypeError`, `ZeroDivisionError`, and `NoMethodError`.
- Each chunk has an `exception_handlers` table.
- `ExceptionHandler` tracks `try_start_ip`, `try_end_ip`, rescue handlers, optional `else_ip`, optional `ensure_ip`, and optional `ensure_end_ip`.
- `RescueHandler` tracks exception-type expression chunk IDs, `catch_ip`, `catch_end_ip`, and optional `var_idx` for rescue binding.
- The VM tracks `pending_exception` and `retry_point`.

## Memory Management

**Infrastructure allocator:** Use for VM housekeeping such as HashMaps, call stack storage, and bytecode chunks. Clean it up manually.

**GC allocator (Boehm-Demers-Weiser):** Use for Ruby heap objects such as classes, modules, object instances, arrays, hashes, procs, fibers, regexps, and method/constant maps. Do not manually `free()` GC-managed objects.

**Atomic GC allocator:** Use for atomic objects without internal pointers, such as duplicated string storage.

**Pointer lifetimes:**
- Parser strings are borrowed from the AST and valid for the VM lifetime.
- Constant-pool strings are borrowed from the AST.
- GC objects are freed automatically by the collector.

**Environment promotion:** Captured stack environments are promoted to the heap via the GC allocator, using forwarding pointers so existing references can be updated.

## Adding Features

**New opcode:** Add it to the `OpCode` enum, `opcodeName()`, compiler emission, and VM execution.

**New value type:** Add it to the `Value.data` union, add a factory method, and update `Value.format()`.

**Builtin registration:** Core builtins are registered via `src/builtins/builtins.zig` from `VM.prepare()`, delegating to per-type registrars such as `src/builtins/integer.zig`.

**New builtin file or method:**
1. Add the builtin function in the appropriate `src/builtins/<type>.zig` file, or create a new builtins file.
2. Register it in that file's `register(vm: *VM)` using `.{ .builtin = &function }`.
3. If you created a new builtins file, import it and call its `register(vm)` from `src/builtins/builtins.zig` `registerAll()`.

## Zig Notes

Use unmanaged `ArrayList`: `field: ArrayList(*Value) = .empty`, passing the allocator to mutating operations.
