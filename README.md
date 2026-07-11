# Cora Ruby Interpreter

This is a Ruby interpreter in Zig, written by various LLMs, ala Agentic Engineering.

This is my sandbox. I might try to make something better or faster or more flexible with it, but really I'm just having fun.

The goal is to get a working Ruby interpreter that can pass most or all of [ruby/spec](https://github.com/ruby/spec),
to explore just-in-time compilation, and to possibly look into gradual typing or other enhancements.

## Features

- Uses the [Prism](https://github.com/ruby/prism) parser
- Bytecode compiler
- Stack VM
- Experimental JIT compiler using [TinyCC](https://bellard.org/tcc/)
- Experimental App packaging into a single executable

## What Works

Some gems that are known to work, though I haven't tested each thoroughly:

- rake
- rubygems and bundler
- psych and yaml
- rack and rackup
- webrick
- sinatra
- erb

Cora has over on 10,000 ruby specs passing, which by my math is about a third of the way to being a complete Ruby.

## Prerequisites

To build Cora, you'll need:

- Zig 0.16.x
- GNU make
- a C toolchain
- autotools for the bundled Onigmo build, including `autoreconf`

If you have the [Nix](https://nixos.org/download/) package manager, you can fetch all the dependencies easily with:

```bash
nix develop
```

If you have [direnv](https://direnv.net/), it will automatically load the dev shell when you `cd` into the cora directory.

## Build

```bash
zig build
```

This installs the main CLI at:

```bash
build/bin/cora
```

To run:

```bash
build/bin/cora [flags] [filename]
```

Useful CLI flags:

- `-e` - run a code string
- `--ast` - dump the Prism AST
- `--dump-bytecode` - dump compiled bytecode
- `--jit` - enable the experimental TinyCC JIT (disabled by default)
- `--dump-jit-source` - dump generated TinyCC JIT C source when JIT is enabled

### Package an Application

Package a Ruby application as a single executable with `--pack`:

```bash
build/bin/cora --pack -o my-app path/to/main.rb
./my-app [args]
```

Cora appends the application files to its own executable, then extracts them
to a private temporary directory each time the packaged binary starts. The
entrypoint's parent directory is packaged by default; use `--pack-root DIR` to
choose a project root and `.coraignore` to exclude exact file paths or directory
prefixes.

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

Enable the experimental TinyCC-based JIT compiler at runtime with `--jit`:

```bash
zig build -Doptimize=ReleaseFast
build/bin/cora --jit examples/fib.rb
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
| `ext/csv/*` | James Edward Gray II, Yukihiro Matsumoto, SHIBATA Hiroshi, and contributors | Ruby license / 2-clause BSD |
| `ext/delegate/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/erb/*` | Masatoshi SEKI and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/forwardable/*` | Keiju ISHITSUKA, Daniel J. Berger, Ruby contributors | Ruby license / 2-clause BSD |
| `ext/json/*` | Florian Frank, Yukihiro Matsumoto, and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/fileutils.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/mkmf.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/monitor.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/pathname.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/random/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `lib/stdlib/securerandom.rb` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/open3/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/onigmo/*` | K. Kosako, K. Takata, Yukihiro Matsumoto | BSD-style / Ruby BSDL |
| `ext/prism/*`, `ext/prism-templates/*` | Shopify Inc. | MIT |
| `ext/tinycc/*` | Fabrice Bellard and TinyCC contributors | LGPL 2.1 |
| `ext/logger/*` | Yukihiro Matsumoto | Ruby license / 2-clause BSD |
| `ext/optparse/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/psych/*` | Aaron Patterson, SHIBATA Hiroshi, Charles Oliver Nutter, and contributors | MIT |
| `ext/rubygems/*` | Chad Fowler, Rich Kilmer, Jim Weirich, and others | RubyGems license / MIT |
| `ext/singleton/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/tempfile/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/timeout/*` | Network Applied Communication Laboratory, Inc., IPA Japan, and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/tmpdir/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/shellwords/*` | Akinori MUSHA and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/uri/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/webrick/*` | Yukihiro Matsumoto and Ruby contributors | Ruby license / 2-clause BSD |
| `ext/yaml/*` | Aaron Patterson, SHIBATA Hiroshi, and Ruby contributors | Ruby license / 2-clause BSD |

See each file/directory for the full copyright and license terms.
