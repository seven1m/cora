# Cora Agent Guide

Cora is a Ruby interpreter written in Zig using a two-stage pipeline:
Prism AST -> bytecode -> VM execution.

## Read This First

- Main entrypoints: `src/compiler.zig`, `src/vm.zig`, `src/value.zig`, `src/chunk.zig`, `src/bytecode.zig`, `src/prism.zig`, `src/cext.zig`, `src/load_path.zig`, `src/main.zig`
- C extension ABI: `include/cora/ruby.h` + `src/cext.zig`. The test fixture is `test/support/cext_fixture.c` exercised from `test/core/cext_test.zig`.
- Stdlib lives in `lib/stdlib/`. Vendored gem sources live in `ext/<gem>/` as git submodules.
- Prefer reading the relevant `.agents/reference/*.md` file for the task you are doing before making changes.
- Prefer general and reusable bytecode/runtime changes over feature-specific one-offs.
- Do not expose runtime-only implementation details to Ruby code via fake hidden local variables, ivars, or methods.
- Prefer shared VM coercion, dispatch, warning, and arity helpers over per-builtin ad hoc logic.
- Prefer `VM.probeToHash` for optional `to_hash` probes where missing/nil should be handled by the caller.
- Prefer `VM.coerceToHashValue` when `to_hash` is required and standard Ruby `TypeError` details should be preserved.
- For Ruby truthiness checks on `Value`, use `Value.isTruthy()`.
- Keep imports at the top of the file; avoid inline `@import(...)` expressions.
- Prefer adding logging/tracing for concrete evidence when debugging over guessing.
- Blocking syscalls must retry on `EINTR` and call `vm.checkAsyncEvents()` before retrying, so that `Signal.trap` handlers fire promptly. Apply this pattern: `errno_code == .INTR => { try vm.checkAsyncEvents(); continue; }`.

## Task Routing

- Compiler, VM, runtime model, memory model: `.agents/reference/architecture.md`
- Debugging workflow, memory corruption triage: `.agents/reference/debugging.md`
- TinyCC JIT, eligibility rules, and debug workflow: `.agents/reference/jit.md`
- Builtins and Ruby-facing conventions: `.agents/reference/builtins.md`
- Native C extensions, builtin gems, `lib/stdlib/` vs `ext/`: `.agents/reference/native-extensions.md`
- Testing, CLI usage, and debug workflow: `.agents/reference/testing.md`
- Ruby spec workflow: `.agents/reference/ruby-specs.md`
- Zig tips: `.agents/reference/zig.md`

## Fast Facts

- Parsing: Prism C library parses Ruby source and stores the AST on `Parser.ast`.
- Compilation: `Compiler.compile()` walks the Prism AST and emits bytecode chunks.
- Execution: `VM.run()` interprets bytecode with a stack-based VM.
- TinyCC JIT is optional at build time and compiles eligible method chunks lazily on first call.
- Locals live in `Environment`, not `CallFrame`.
- Chunks represent module/class bodies, methods, blocks, procs, and lambdas.
- GC owns Ruby heap objects. Parser strings and constant-pool strings are generally borrowed from the AST.

## Commands

```bash
zig build test
zig build test -Dtest-filter="Proc"
zig build test -Dtest-filter="Proc" -Dtest-verbose
zig build test -Dtest-filter="Proc" -Dtest-verbose -Dtest-timing
zig build test -Dtest-filter="Proc" -Dtest-verbose -Dtest-timing -Dtest-timeout=10
zig build test -Dtest-jobs=8
zig build run -- [flags] [filename]
build/bin/cora [flags] [filename]
bin/gem [gem-args]                  # polyglot sh+Ruby wrapper; uses bin/cora
```

The TinyCC JIT and per-gem native extension build steps (`psych`, `strscan`,
`onigmo`, `tinycc`, `cext-fixture`) are documented in
`.agents/reference/native-extensions.md`.

## Nix

Unless you're running in a nix-shell already, you will need to prefix all zig commands like this:

```bash
nix-shell --command "zig build ..."
```
