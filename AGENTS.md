# Cora Agent Guide

Cora is a Ruby interpreter written in Zig using a two-stage pipeline:
Prism AST -> bytecode -> VM execution.

## Read This First

- Main entrypoints: `src/compiler.zig`, `src/vm.zig`, `src/value.zig`, `src/chunk.zig`, `src/bytecode.zig`, `src/prism.zig`, `src/main.zig`
- Prefer reading the relevant `.agents/reference/*.md` file for the task you are doing before making changes.
- Prefer general and reusable bytecode/runtime changes over feature-specific one-offs.
- Do not expose runtime-only implementation details to Ruby code via fake hidden ivars or methods.
- Prefer shared VM coercion, dispatch, warning, and arity helpers over per-builtin ad hoc logic.
- Prefer `VM.probeToHash` for optional `to_hash` probes where missing/nil should be handled by the caller.
- Keep imports at the top of the file; avoid inline `@import(...)` expressions.

## Task Routing

- Compiler, VM, runtime model, memory model: `.agents/reference/architecture.md`
- TinyCC JIT, eligibility rules, and debug workflow: `.agents/reference/jit.md`
- Builtins and Ruby-facing conventions: `.agents/reference/builtins.md`
- Testing, CLI usage, and debug workflow: `.agents/reference/testing.md`
- Ruby spec workflow: `.agents/reference/ruby-specs.md`

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
zig build run -- [flags] [filename]
zig-out/bin/cora [flags] [filename]
```
