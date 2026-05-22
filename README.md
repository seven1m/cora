# Cora Ruby Interpreter

This is a Ruby interpreter written in Zig, mostly authored by AI with some oversight from a human.
This is both an exploration of Zig and an LLM's ability to write code where the end result is well-defined.

The goal is to get a working Ruby interpreter that can pass most or all of [ruby/spec](https://github.com/ruby/spec).


## Features

- Uses the [Prism](https://github.com/ruby/prism) parser
- Bytecode compiler
- Stack VM
- Experimental JIT compiler using [TinyCC](https://bellard.org/tcc/)

## Prerequisites

You need:

- Zig
- `make`
- a C toolchain
- autotools for the bundled Onigmo build, including `autoreconf`

If you have the [Nix](https://nixos.org/download/) package manager, you can fetch all the dependencies easily with:

```bash
nix-shell
```

If you have [direnv](https://direnv.net/), it will automatically load the nix shell when you `cd` into the cora directory.

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
- `--dump-jit-source` - dump generated TinyCC JIT C source when built with `-Dtcc-jit=true`

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

Build with the optional TinyCC JIT enabled:

```bash
zig build -Doptimize=ReleaseFast -Dtcc-jit=true
```

If you want extra runtime safety checks in an optimized build, use:

```bash
zig build -Doptimize=ReleaseSafe
```

## Copyright & License

Cora is copyright 2026, Tim Morgan. Cora is licensed under the MIT License;
see the `LICENSE` file in this directory for the full text.

Some parts of this program are copied or vendored from other sources, and the
copyright belongs to the respective owner. Such copyright notices are either at
the top of the relevant file, in the same directory with a name like
`LICENSE`, `COPYING`, or `MIT.txt`, or both.

| file(s) | copyright | license |
| ------- | --------- | ------- |
| `ext/dtoa.c` | David M. Gay, Lucent Technologies | custom permissive |
| `lib/stdlib/fileutils.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/random/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/onigmo/*` | K. Kosako, K. Takata, Yukihiro Matsumoto | BSD-style / Ruby BSDL |
| `ext/prism/*`, `ext/prism-templates/*` | Shopify Inc. | MIT |
| `ext/tinycc/*` | Fabrice Bellard and TinyCC contributors | LGPL 2.1 |
| `ext/logger/*` | Yukihiro Matsumoto | Ruby license / 2-clause BSD |
| `ext/rubygems/*` | Chad Fowler, Rich Kilmer, Jim Weirich, and others | RubyGems license / MIT |

See each file/directory for the full copyright and license terms.
