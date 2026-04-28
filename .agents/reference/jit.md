# TinyCC JIT Reference

## Core Files

- `src/jit.zig` - eligibility checks, bytecode-to-C generation, TinyCC compile orchestration
- `src/tcc.zig` - thin `libtcc` wrapper
- `src/vm.zig` - JIT cache state and dispatch hook (`maybeCallJittedChunk`)
- `src/main.zig` - CLI wiring for JIT debug flags
- `test/core/jit_tcc_test.zig` - focused JIT tests

## Build And Runtime

- Build with TinyCC support using `zig build -Dtcc-jit=true` or `zig build test -Dtcc-jit=true`.
- If Cora is built with `-Dtcc-jit=true`, the JIT is enabled by default at runtime.
- `--dump-jit-source` prints generated C to `stderr` the first time an eligible chunk is compiled.
- `--dump-bytecode` is still useful, but it exits before lazy JIT compilation happens.

## Current JIT Scope

The current JIT is intentionally narrow and proof-of-concept quality.

- Backend: generated C compiled in memory with TinyCC via `tcc_compile_string()`
- Unit of compilation: one method chunk at a time
- Compile timing: lazy, on first eligible call
- Cache key: chunk pointer plus `method_state_version`
- Fallback: any compile failure, guard miss, or unsupported shape falls back to the interpreter

## Eligibility Rules

The current JIT only accepts a narrow subset of method chunks. Prefer reading `src/jit.zig` before changing the boundary.

Stable characteristics of the current subset:

- simple positional methods (`is_simple_positional == true`)
- arity `1`
- integer-only subset with tagged `Value.raw` operations
- self-recursive implicit-self calls only

Examples that fit:

- `examples/fib.rb`
- simple recursive integer methods like `trib`

Examples that do not fit:

- methods with default args
- methods using blocks or `yield`
- methods using floats
- methods with broader Ruby dispatch

## Generated Code Shape

- The generated C preserves bytecode control flow directly.
- Labels map directly to bytecode offsets.
- Branches become `goto`s.
- Arithmetic and recursion still go through shared runtime guard rules.

This is normal for a bytecode-to-C proof of concept. It keeps codegen simple and makes debugging easier.

## Dispatch And Invalidation

- `VM.maybeCallJittedChunk()` is the main runtime hook.
- The JIT is attempted only in chunk-call fast paths.
- Generated code is reused until `method_state_version` changes.
- Integer monkeypatching and runtime guard failures fall back to the interpreter.

## Debugging Tips

- Use `zig-out/bin/cora --dump-bytecode file.rb` to inspect chunk shape before deciding whether a method should be JIT-eligible.
- Use `zig-out/bin/cora --dump-jit-source file.rb` on a `-Dtcc-jit=true` build to see the emitted C.
- For mixed scripts, only eligible methods print JIT source; non-eligible methods stay interpreted silently.
- `test/core/jit_tcc_test.zig` is the smallest focused place to extend or debug the current JIT.
