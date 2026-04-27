# Cora Ruby Interpreter

This is a Ruby interpreter written in Zig, mostly authored by AI with some oversight from a human.
This is both an exploration of Zig and an LLM's ability to write code where the end result is well-defined.

The goal is to get a working Ruby interpreter that can pass most or all of [ruby/spec](https://github.com/ruby/spec).

## Prerequisites

You need:

- Zig
- Ruby
- `rake`
- `make`
- a C toolchain
- autotools for the bundled Onigmo build, including `autoreconf`

If you use [Devbox](https://www.jetify.com/devbox/), the repo includes a `devbox.json` with the needed prerequisites already:

```bash
devbox shell
```

## Build

```bash
zig build
```

This installs the main CLI at:

```bash
zig-out/bin/cora
```

To run:

```bash
zig-out/bin/cora [flags] [filename]
```

Useful CLI flags:

- `-e` - run a code string
- `--ast` - dump the Prism AST
- `--dump-bytecode` - dump compiled bytecode

## Testing

Run the full Zig test suite:

```bash
zig build test
```

Run only matching tests:

```bash
zig build test -Dtest-filter="Proc"
```

Run matching tests and print each matched test name:

```bash
zig build test -Dtest-filter="Proc" -Dtest-verbose
```

## Optimized Release Build

Build an optimized release binary with:

```bash
zig build -Doptimize=ReleaseFast
```

If you want extra runtime safety checks in an optimized build, use:

```bash
zig build -Doptimize=ReleaseSafe
```

Copyright (c) 2026 Tim Morgan. Licensed MIT.
