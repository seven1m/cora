# Cora Ruby Interpreter

This is a Ruby interpreter in Zig, written by various LLMs, fully vibe coded. It's a mess in here. Sorry, not sorry.

This is my sandbox. I'm not trying to make anything better, faster, or groundbreaking. Just something for fun.

The goal is to get a working Ruby interpreter that can pass most or all of [ruby/spec](https://github.com/ruby/spec)
and to explore just-in-time compilation.

## Features

- Uses the [Prism](https://github.com/ruby/prism) parser
- Bytecode compiler
- Stack VM
- Experimental JIT compiler using [TinyCC](https://bellard.org/tcc/)

## What Works

Some gems that are known to work, though I haven't tested each thoroughly:

- rake
- rubygems and bundler
- rack and rackup
- webrick
- sinatra
- erb
- ansi

Cora has over on 10,000 ruby specs passing, which by my math is about a third of the way to being a complete Ruby.

## Prerequisites

To build Cora, you'll need:

- Zig 0.16.x
- GNU make
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

### Debug Build

For local development with full safety checks and debug info, build with:

```bash
zig build -Doptimize=Debug
```

`ReleaseSafe` is also available if you want runtime safety checks without the
debug-build performance hit:

```bash
zig build -Doptimize=ReleaseSafe
```

### TinyCC JIT

Build with the optional TinyCC JIT enabled:

```bash
zig build -Doptimize=ReleaseFast -Dtcc-jit=true
```

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

## Contributing

Go for it! LLM work welcome.

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
| `ext/cgi/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/delegate/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/erb/*` | Masatoshi SEKI and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/forwardable/*` | Keiju ISHITSUKA, Daniel J. Berger, Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/fileutils.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/random/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/open3/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/onigmo/*` | K. Kosako, K. Takata, Yukihiro Matsumoto | BSD-style / Ruby BSDL |
| `ext/prism/*`, `ext/prism-templates/*` | Shopify Inc. | MIT |
| `ext/tinycc/*` | Fabrice Bellard and TinyCC contributors | LGPL 2.1 |
| `ext/logger/*` | Yukihiro Matsumoto | Ruby license / 2-clause BSD |
| `ext/optparse/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/rubygems/*` | Chad Fowler, Rich Kilmer, Jim Weirich, and others | RubyGems license / MIT |
| `ext/singleton/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/tempfile/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/timeout/*` | Network Applied Communication Laboratory, Inc., IPA Japan, and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/tmpdir/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/uri/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/webrick/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |

See each file/directory for the full copyright and license terms.
