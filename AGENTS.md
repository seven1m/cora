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

**Bytecode Chunks:** Each chunk contains code, constants, constant_names (HashMap for named constants), line info, name, chunk_id, arity, is_lambda flag, optional_params (list of OptionalParam entries with param_index and default_chunk_id), rest_param_index (slot for *rest parameter), post_required_count (required params after rest), keyword metadata (required/optional keywords, `**kwargs` slot, `**nil` flag), block_param_index (`&block` slot), exception_handlers table, lexical_scope, and source_file. Module bodies, class bodies, methods, blocks, procs, and lambdas are all compiled into separate chunks.

**Constants:** Compile-time constants (integer, string, symbol). Strings/symbols are borrowed from Parser AST (no allocation).

**OpCodes:** Defined in `bytecode.zig` enum. Include literals, variable/constant access (including globals and instance variables), control flow, method calls (`CALL`, `CALL_KW`), OOP definitions, blocks/procs/lambdas (YIELD, PUSH_LAMBDA, BREAK), constant path resolution (GET_CONST_PATH), exception handling (RAISE, TRY_BEGIN, TRY_END, CATCH_START, CATCH_END, ENSURE_START, ENSURE_END, RETRY), super (`SUPER`, `FORWARDING_SUPER`), regexp (`PUSH_REGEXP`), aliasing (`ALIAS_METHOD`), and multi-assignment prep (`MULTI_ASSIGN_PREPARE`). RETURN opcode has operand distinguishing implicit (0) vs explicit (1) returns for lambda semantics. Arithmetic operators are method calls, not opcodes. Prefer not to add new opcodes when possible, but when necessary, try to make them general and
reusable for future needs, e.g. don't make a new CALL_* opcode for splatted args, instead make general opcodes for
array manipulation and add a flag to CALL to accept an arguments array on the stack.

**CALL Instruction:** `CALL` operands are method_idx (U16), argc (U8), block_chunk_id (U16), with call flags supporting implicit-self and args-array mode. `CALL_KW` carries keyword count and keyword metadata index in addition to the call core operands.

**CallFrames:** chunk, ip, stack_base, self_value, ep (Environment pointer), block (optional Block), frame_type (method/lambda/proc). Local variables are stored in the Environment (which has a fixed-size 32-slot variables array), not directly in CallFrame.

**Symbol Interning:** `VM.intern(str)` creates GC-allocated SymbolObject with canonical string, cached in HashMap. Same string always returns same symbol with same memory address.

**Classes/Modules:** Classes have module-like method storage, superclass, prepended/included module lists. Method lookup walks: prepended → class methods → included → superclass.

**Value Types:** Primitives (integer, float, boolean, nil), heap-allocated (Object instance, SymbolObject, StringObject, ModuleObject, ClassObject, ArrayObject, HashObject, RangeObject, ExceptionObject, ProcObject, FiberObject, RegexpObject, EncodingObject).

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
- RescueHandler entries contain: exception_type_expr_chunks (list of chunk IDs for exception-type expressions), catch_ip, catch_end_ip, var_idx (optional local slot for exception binding)
- VM tracks pending_exception and retry_point

## Current Feature State

- Core object model and classes/modules are implemented, including singleton methods, method aliasing, and method visibility controls.
- Local variables, globals (`$x`), and instance variables (`@x`) are implemented.
- Method parameters support required, optional, rest, keyword, keyword-rest, post-rest required, and block parameters.
- Blocks/procs/lambdas, `yield`, closure capture, and lambda/proc semantic differences are implemented.
- Exception handling covers `raise`, `begin/rescue/else/ensure`, `retry`, `break` from blocks, and dynamic rescue type expressions (for example `rescue (-> { StandardError }.call) => e`).
- `super`/forwarding super, splatted call arguments, ranges, regexps, case/when matching, and string interpolation are implemented.
- Fibers and `at_exit` handlers are implemented.
- `ARGV` is available as a top-level constant and is populated from CLI script args.
- `ENV` is exposed as a singleton object with singleton methods (`[]`, `[]=`, `to_h`). `ENV[]`/`ENV[]=` sync host process environment and `ENV.to_h` returns a fresh Hash snapshot each call.
- `Kernel#__dir__`, backticks/xstring command execution, `require`, `require_relative`, and `load` are implemented.

## Memory Management

**Infrastructure Allocator:** Manages HashMaps, call stack, bytecode chunks. Manually cleaned up.
Prefer this allocator for VM-related housekeeping.

**GC Allocator (Boehm-Demers-Weiser):** Manages all Ruby heap objects (ClassObject, ModuleObject, Object instances, arrays/hashes/procs/fibers/regexps, and method/constant maps). Conservative GC scans stack/heap. NO manual free().

**Atomic GC Allocator:** For "atomic" objects without internal pointers (string duplication).

**Pointer Lifetimes:**
- Parser strings: Borrowed from AST, valid for VM lifetime
- Constant pool strings: Borrowed from AST (no allocation)
- GC objects: Freed by GC automatically

**Environment Promotion:** Stack environments are promoted to heap (via GC allocator) when captured by closures, using forwarding pointers to update all references.

## Adding Features

**New OpCode:** Add to `OpCode` enum, `opcodeName()`, emit in compiler, handle in VM executeInstruction().

**New Value Type:** Add to `Value.data` union, factory method, update `Value.format()` for display.

**Builtin Methods:** Core methods are registered via `src/builtins/builtins.zig` (called from `VM.prepare()`), which delegates to per-class registrars like `src/builtins/integer.zig`. Registration uses `.{ .builtin = &function }`.

**New Builtin Method:**
1. Add the function in the appropriate `src/builtins/<type>.zig` file (or create a new one).
2. Register it in that file's `register(vm: *VM)` by inserting `.{ .builtin = &function }` into the class/module method table.
3. If you added a new builtins file, import it and call its `register(vm)` in `src/builtins/builtins.zig` `registerAll()`.

## Testing & Debugging

```bash
# pass/fail status only, no details
zig build test

# filter to tests having the word "Proc" (case sensitive)
zig build test -Dtest-filter="Proc"

# filter by name and print every test description that matched
zig build test -Dtest-filter="Proc" -Dtest-verbose
```

Tests live under `test/` (`test/core/*.zig`, `test/language/*.zig`, plus integration helpers/spec runner). When adding new test files, remember to add them to `test/all_test.zig`.

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

## Implementation Notes (User Preferences)

- Prefer importing files at the top of the file. Avoid inline `@import(...)` expressions in function bodies or expressions.
- Do not expose runtime implementation details to user Ruby code via fake/hidden instance variables or methods (e.g. `@__store`, `__hidden_methods__`). Keep runtime-only state in VM/runtime structures instead.
- In `src/encoding/*.zig`, keep encoding capability predicates on the concrete encoding structs and have `src/encoding.zig` delegate via `inline else`; avoid hard-coding per-tag switches in the `Encoding` union for flags like `isDummy`/`isUnicode`.
- Always use VM argument-count helpers (`requireArgCount`, `requireArgCountRange`, etc.) instead of manually constructing "wrong number of arguments" exceptions in builtins.
- Prefer `VM.checkCallMethodByName(receiver, "method", args, block)` for optional conversion/probe calls that should gracefully treat missing methods as "not supported" (MRI-style check-call behavior).
- Do not parse exception messages (for example `"undefined method 'to_str'"`) to detect missing methods. Use `checkCallMethodByName` or explicit method lookup + dispatch rules.
- Use normal `callMethodByName` (not check-call) when you must always perform the call or preserve side effects.
- If you add or discover a reusable builtin helper, document it in this file when it is broadly useful for future builtin work.

### General builtin helpers
- `VM.requireArgCount`, `VM.requireArgCountRange`, and related helpers are the canonical path for builtin arity validation.
- `VM.checkCallMethodByName` is the preferred probe/optional-conversion helper when missing methods should be treated as unsupported rather than exceptional.
- `VM.callMethodByName` is the normal dispatch path when the call must happen or its side effects must be preserved.
- `VM.respondsToMethodByName` is the canonical capability-probe helper for `respond_to?` checks when you need to branch on support without forcing the target method call.
- `VM.allocCStringZ` is the shared helper for temporary NUL-terminated C strings when builtins need libc APIs; prefer it over per-builtin duplicate allocators.
- `VM.copyObjectInstanceVariables` centralizes shallow copying of Ruby object instance-variable maps for dup/clone-style object duplication paths.
- `VM.probeToAry` centralizes low-level `to_ary` coercion semantics. It returns array/missing/nil-result distinctly and raises `TypeError` when `to_ary` returns a non-Array.
- `VM.coerceToArrayValue` is the strict array-like coercion helper for APIs such as `Array#+`/`Array#replace`; it raises MRI-style `TypeError` messages for missing `to_ary` and `nil`/wrong-type `to_ary` results.
- `VM.raiseEncodingCompatibilityError` centralizes `Encoding::CompatibilityError` formatting for the common `"incompatible character encodings: ..."` case.
- `VM.coerceToPath` is the canonical path-bytes coercion helper (`to_path` then String coercion); use `VM.coerceToPathValue` when callers must preserve the resulting String object's encoding/value.
- `src/builtins/warning.zig` exposes shared warning helpers such as `writeWarning` and `warnBlockUnused`; prefer these over per-builtin `$stderr` warning writers.

### Builtin naming conventions
- For Ruby `!` methods, name Zig builtin handlers with a `Bang` suffix (for example `String#upcase!` → `builtinStringUpcaseBang`).
- For Ruby `?` methods, prefer descriptive names without punctuation (for example `builtinStringEmpty`, `builtinKernelRespondTo`).
- If a `?` method has a non-`?` sibling with the same stem, use a `Q` suffix to disambiguate (for example `include`/`include?` → `builtinModuleInclude`/`builtinModuleIncludeQ`, `casecmp`/`casecmp?` → `builtinStringCasecmp`/`builtinStringCasecmpQ`).

### String coercion conventions
- Canonical implicit String coercion lives in `Value.coerceToStringValue` (`src/value.zig`). Prefer this for Ruby APIs that require String-like arguments via `to_str` and should raise `TypeError` on failure.
- Use `Value.coerceToStr` when you need `[]const u8` bytes after the same implicit coercion semantics.
- Use `VM.checkCallMethodByName(..., "to_str", ...)` for optional/cooperative conversions (for example `String.try_convert`) where missing method should map to `nil`/fallback instead of raising.
- If you only need capability probing (for example `String#==` checking whether `to_str` is supported before reverse-dispatch), use `respond_to?` semantics rather than forcing a coercion call.
- Use `VM.coerceToPath` for path arguments (`to_path` then String coercion), rather than open-coding path coercion in builtins.
- Avoid per-builtin ad hoc `to_str` coercion helpers unless semantics intentionally differ from the canonical paths; if they do differ, document why near the helper.

## Ruby Specs

We have tests in both `*_test.zig` files and in `*_spec.rb` files.

The Zig tests (in the `test/` directory) are for bootstrapping language features and for edge cases not expressed in Ruby spec files.

The spec files (in the `spec/` directory) come from [ruby/spec](https://github.com/ruby/spec), which is a community-maintained repository of specs describing Ruby. When implementing one of these specs, we'll copy it over and try to get it passing. Look in `../ruby_spec` for the files before going to the web. Prefer to keep the ruby spec matching the upstream copy (add any expectations or test harness needed) to make it work.
