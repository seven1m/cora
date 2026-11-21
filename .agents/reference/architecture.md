# Architecture Reference

## Core Architecture

**Execution pipeline:**
1. **Parsing:** Prism C library parses Ruby source -> AST (stored in `Parser.ast`)
2. **Compilation:** `Compiler.compile()` walks AST -> generates bytecode chunks
3. **VM execution:** `VM.run()` interprets bytecode with a stack-based VM

**Key files:**
- `src/main.zig` - CLI entry point
- `src/prism.zig` - Prism C library wrapper with typed Node union
- `build/prism` - generated Prism C/header sources when you need to inspect parser internals
- `src/cext.zig` - Ruby C extension ABI implementation (`rb_*` exports for `dlopen`'d `.so` files)
- `include/cora/ruby.h` - C header that ext authors `#include` to get the `VALUE` ABI Cora supports
- `src/load_path.zig` - static `repo_load_paths` table that registers vendored gems at startup
- `bin/cora`, `bin/gem` - polyglot wrapper scripts installed alongside the binary
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

**CALL instruction:** `CALL` operands are `method_idx` (`U16`), `argc` (`U8`), call flags (`U8`), `block_chunk_id` (`U16`), and `callsite_id` (`U16`). `CALL_KW` adds keyword count and a keyword metadata index before the block/site IDs. Forwarding call opcodes also end with a `callsite_id`. IDs are dense within each chunk and index its cache/descriptor arrays; byte offsets are used for control flow and block handlers, not cache allocation.

**Call-site storage:** Descriptors are pointer-free packed 16-byte records; method symbols live in the constant pool. Cache pointer arrays allocate on first use; descriptor buffers are trimmed after compilation. Cache slots point to immutable GC-owned dispatch results. A bounded sharing index reuses results for the same dispatch class, method name, and method-state version. The GC root hook traces populated chunks' cache slots, drops stale versions, and stops tracking emptied chunks; temporary load/eval chunks unregister their slots before destruction.

**CallFrames:** A frame contains `chunk`, `ip`, `stack_base`, `self_value`, `ep` (Environment pointer), optional `block`, and `frame_type` (method/lambda/proc). Local variables are stored in the `Environment`, not directly in the `CallFrame`.

**Execution buffers:** Fiber/Thread objects hold small descriptors for separate GC-scanned value and frame buffers. The main fiber allocates them during VM setup; workers and ordinary fibers allocate them on first execution. A worker root fiber uses its thread's buffers, and the main thread uses its main fiber's buffers, without a duplicate pair. Buffer capacities remain fixed and addresses never move while executing. Completed fibers and retired threads detach their buffers; interior environment/frame references can keep detached buffers alive through GC.

**Symbol interning:** `VM.intern(str)` creates a GC-allocated `SymbolObject` with canonical string storage and caches it in a HashMap. The same symbol string should map to the same symbol object identity.

**Classes/modules:** Classes store module-like method tables plus superclass and prepended/included module lists. Method lookup walks prepended modules -> class methods -> included modules -> superclass. `Class#new` consults `ClassObject.cext_alloc_func` first when present, so a C extension can install its own allocator for the Ruby wrapper.

**Method entries:** A `MethodEntry.method` is one of `.undefined`, `.builtin`, or `.cext` (`{ func: *anyopaque, argc: c_int }`). C extension methods are registered by `rb_define_method`/`rb_define_module_function`/etc. in `src/cext.zig`, bump `VM.method_state_version` so JIT/lookup caches invalidate, and dispatch goes through `cext_method` arms in `src/vm.zig` and `src/builtins/method_common.zig`. Explicit keywords reach C methods as a trailing hash that `rb_scan_args` can extract with its `:` format directive. See `.agents/reference/native-extensions.md` for the supported C ABI surface and the cext fixture.

**Builtin keyword contexts:** The context header, copied keyword keys/values, and consumption flags share one GC-scanned allocation sized to the actual keyword count. Contexts can survive nested callbacks and coroutine suspension through saved call state; their storage must not borrow temporary argument buffers.

**Value types:** Primitives include integer, float, boolean, and nil. Heap-allocated types include object instances, symbols, strings, modules, classes, arrays, hashes, ranges, exceptions, procs, fibers, regexps, and encodings.

**Blocks, procs, and lambdas:** All are compiled into separate bytecode chunks with arity and parameter metadata. `is_lambda` distinguishes lambda versus proc/block semantics. `YIELD` executes the block passed to the current method. `PUSH_LAMBDA` creates a `ProcObject` wrapping a `Block` (`chunk` + `defining_ep`). Blocks capture through the environment parent chain. Escaping blocks promote captured environments from stack to heap.

**Proc vs lambda semantics:**
- Lambdas enforce strict arity; procs are lenient.
- Lambda `return` returns from the lambda itself.
- Proc/block `return` returns from the enclosing method.
- `Proc#lambda?` is true only for lambdas.
- `-> {}` and `lambda {}` create lambdas; `proc {}` and `Proc.new {}` create procs.

**Environments:** Frames store locals in stack slots plus a small `env_data` trailer addressed by `ep`. `ep[0]` is the parent environment pointer, `ep[1]` stores lexical-scope/frame context, and `ep[2]` stores `locals_count`. When a closure escapes, that environment is promoted to a heap `HeapEnv` whose layout mirrors the stack layout.

**Lexical scopes:** Lexical scope chains track module/class context for constant lookup.

**Backtrace labels:** Chunks record the lexical base label and block nesting depth.
Frames retain the resolved definition node, so aliases, included module methods,
and copied UnboundMethods report their original owner. Method and UnboundMethod
APIs are registered once on their classes; captured method objects hold only
the implementation and binding metadata. Binding objects keep a
GC-owned label context for later evals, independently of temporary eval chunks.
Ruby core methods are embedded from `src/builtins/kernel.rb`;
their source locations use `<internal:kernel>` while caller locations borrow the
user call site, matching MRI's treatment of internal Ruby methods.
File-backed chunks also retain the canonical absolute path captured before
execution. `__FILE__` and location `path` preserve the logical source filename;
location `absolute_path`, `__dir__`, and `require_relative` use the saved identity
so directory changes or removed symlinks cannot change the file's origin.
Eval chunks keep a nil canonical path even when given a display filename.

## Thread Scheduling

Threads share one native execution thread and hand off directly between saved
coroutine contexts, following MRI's running/ready/waiting ownership model.
`VM.runnable_queue` contains ready threads, excluding the current thread.
`schedulerYield` dequeues one ready thread, requeues a runnable caller, saves
its active fiber and call context, restores the target, and transfers ownership
with `zio.coro.switchContext`. It never runs another thread through a recursive
scheduler call. Thread creation enqueues work; thread exit transfers ownership
without requeuing the terminated thread.

Both main and worker threads are preempted at bytecode safe points. A thread's
`scheduling_context` can point to its active fiber, so thread scheduling does
not change Ruby fiber caller relationships. Handoffs preserve pending unwinds,
builtin keyword/indexed-yield contexts, C extension jump buffers and keyword
hashes, and the current loading file. Suspended native stacks remain GC roots.

Sleep and I/O waiters become ready when their deadline expires, their descriptor
is ready, or they are interrupted. When no thread is ready, the scheduler polls
descriptors and the nearest deadline, with bounded waits for asynchronous events.
Thread join/value waiters park with a target thread and become ready when that
target terminates; timed joins also use a sleep deadline.
Process signal handlers run on the main thread, waking it when necessary.

New workers inherit `Thread.report_on_exception` when created. Unhandled worker
exceptions are reported through Ruby `$stderr` before abort-on-exception delivery
to the main thread. Once the body has finished, queued interrupts are discarded;
diagnostic and scheduler callbacks keep the native stack runnable until they
return. SystemExit propagates to the main thread without a thread-error report.

Each thread has an ordered interrupt queue for raises and termination, plus a
stack of inherited interrupt masks. `Thread.handle_interrupt` snapshots its hash
and applies the innermost matching mask, preferring the most specific ancestor.
Immediate events run at safe points; `:on_blocking` events also run at blocking
wait boundaries, including zero-duration sleep; `:never` events wait until the
mask permits delivery. Default signal exceptions use the main thread's queue.
Termination bypasses rescue while preserving `$!`, runs active ensure clauses,
and propagates through the active Fiber resume chain. Self-kill is immediate.

Terminated workers are retired after ownership transfers to another native stack,
either at a new thread entrypoint or when `schedulerYield` resumes. Retirement
unregisters their thread and fiber coroutines before freeing native stacks, drops
scheduler/group roots and per-thread bookkeeping, and detaches execution buffers.
Results, exceptions, escaped closures/bindings, and observable thread/fiber locals
remain available through retained Ruby objects. Removed GC-owned list slots are
cleared even outside `items.len`, since the collector scans the whole allocation.

Ruby Fiber scheduler objects are stored per thread in `ThreadObject.fiber_scheduler`.
Their close hooks run on replacement and during thread/interpreter shutdown.
Nonblocking fibers joining a thread (including through `Thread#value`) call the
scheduler's `block` hook with the target and remaining timeout. Thread completion
calls `unblock` with the waiting thread and fiber. Waiter cleanup handles timeout,
unwind, and thread retirement. Finishing workers stay runnable while callbacks
execute so preemption cannot retire a live native stack.
Sleep and I/O waits still use the native thread scheduler; dispatch to Ruby
Fiber scheduler sleep and I/O wait hooks is not connected yet.

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

Scanned GC allocations recognize interior pointers into execution stacks and
environments. Only large atomic buffers use ignore-off-page allocation.

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
