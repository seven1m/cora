# Stack Depth: Cora vs MRI

## Current Cora Limits (compile-time constants in `src/vm.zig`)

| Constant | Value | Size per entry | Total |
|---|---|---|---|
| `MAX_FIBER_STACK_SIZE` (value stack) | 4,096 | 8 bytes | 32 KB |
| `MAX_FIBER_FRAMES` (call frames) | 2,048 | ~80 bytes | ~160 KB |
| `MAX_FIBER_ENVS` (environments) | 2,048 | ~288 bytes | ~576 KB |
| **Total per fiber** | | | **~768 KB** |

Practical max recursion depth: **~2,046 method calls**.

## MRI Defaults (64-bit, Ruby 3.x)

| Setting | Default | Env var |
|---|---|---|
| Thread VM stack | 1 MB | `RUBY_THREAD_VM_STACK_SIZE` |
| Thread machine stack | 8 MB | `RUBY_THREAD_MACHINE_STACK_SIZE` |
| Fiber VM stack | 128 KB | `RUBY_FIBER_VM_STACK_SIZE` |
| Fiber machine stack | 512 KB | `RUBY_FIBER_MACHINE_STACK_SIZE` |

Practical max recursion depth: **~4,000–10,000 method calls** (varies by method complexity).

## Differences to Address

### 1. Recursion depth is ~2x lower than MRI

Our 2,048 frame/env limit yields ~2,046 levels. MRI typically allows 4,000–10,000. We can't simply double the limits because each Environment is ~288 bytes (fixed 32-slot variable array), so 4,096 envs ≈ 1.15 MB per fiber — which already blows up fiber coroutine stacks.

**Possible fix:** Dynamically-sized variable arrays in Environment, or heap-allocate environments for deep frames beyond a threshold.

### 2. Fibers share the same limits as the main thread

MRI has separate, smaller limits for fibers (128 KB VM stack) vs threads (1 MB). Cora uses identical `MAX_FIBER_*` constants for the main fiber and spawned fibers. This means either the main thread is artificially constrained, or spawned fibers are oversized.

**Possible fix:** Separate constants for main vs spawned fibers (e.g., `MAX_MAIN_FRAMES = 4096`, `MAX_FIBER_FRAMES = 1024`).

### 3. Environment struct is the memory bottleneck

Each `Environment` is ~288 bytes due to the fixed `variables: [32]Value` array. Most methods use far fewer than 32 locals. MRI uses a single contiguous stack for both locals and temporaries, which is more memory-efficient.

### 4. Wrong error class for stack overflow

Cora raises `FiberError: fiber call stack overflow`. MRI raises `SystemStackError: stack level too deep`. We should add `SystemStackError` as a subclass of `Exception` (not `StandardError`).

### 5. Not configurable at runtime

MRI supports env vars (`RUBY_THREAD_VM_STACK_SIZE`, etc.) to tune stack sizes at boot. Cora's limits are compile-time constants. Low priority but worth noting for compatibility.

## De-recursion Status

As of the dispatch de-recursion work, these VM paths are now iterative (no C stack growth per Ruby call):

- **YIELD / YIELD_SPLAT** → chunk blocks pushed inline
- **CALL** → chunk methods via `setupChunkCallFrame` (was already iterative)
- **CALL** → proc-as-method with chunk blocks pushed inline
- **Proc#call** → chunk procs detected and pushed inline in the builtin path

These paths still recurse (C→Ruby boundary, bounded by builtin nesting depth):

- `yieldToBlock()` called from builtins (Array#each, Hash#each, Integer#times, etc.)
- `callProcObject()` called from builtins (symbol/builtin proc kinds only)
- `invokeResolvedMethod()` called from `callMethodByName()` (builtins calling Ruby methods like `to_s`, `==`)
