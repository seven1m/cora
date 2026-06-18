# Testing And Debugging

## Test Commands

```bash
# pass/fail status only, no details
zig build test

# filter to tests having the word "Proc" (case sensitive)
# filter supports `|` OR matching, e.g. -Dtest-filter="Proc|Lambda"
zig build test -Dtest-filter="Proc"

# filter by name and print every test description that matched
zig build test -Dtest-filter="Proc" -Dtest-verbose

# show times per test file
zig build test -Dtest-timing

# show times per test file and limit each file to 10 seconds
# slow tests will error with: FAIL (SpecTimeout)
zig build test -Dtest-timing -Dtest-timeout=10

# run tests in parallel across N worker processes
zig build test -Dtest-jobs=8
```

Tests live under `test/` including `test/core/*.zig`, `test/language/*.zig`,
top-level gem/library smoke tests (`test/strscan_test.zig`,
`test/json_test.zig`, etc.), and integration helpers/spec runner code. When
adding a new test file, add it to `test/all_test.zig`.

The `test` step automatically builds the Prism static lib, Onigmo, and the
C extension fixture (`build/cext/fixture.so`). Build TinyCC first via
`-Dtcc-jit=true` if any of your tests need it.

## Focused/Skipped Specs

When debugging ruby spec behavior, it can be helpful to "focus" a single spec
by changing the `it` to `fit`.

Similarly, you can "skip" a spec by changing `it` to `xit`. Focused specs
will run exclusively, while skipped specs will be ignored.

## Running The CLI

```bash
zig build run -- [flags] [filename]

# or, after a build has produced the binary
build/bin/cora [flags] [filename]
```

The `bin/cora` and `bin/gem` shims in the repo root locate `build/bin/cora`
for you and re-exec it; `bin/gem` is a polyglot sh+Ruby script that adds
`ext/rubygems/lib` to `$LOAD_PATH` and dispatches to `Gem::GemRunner`.

## CLI Flags

Input:
- `-e CODE` - run CODE instead of reading a file
- `FILE` - run Ruby source from FILE; remaining args become `ARGV`

Inspection:
- `--ast` - dump Prism AST, then exit
- `--dump-bytecode` - dump compiled bytecode (opcodes, constants, chunks), then exit
- `--dump-jit-source` - print TinyCC JIT C source for compiled methods; requires `-Dtcc-jit=true`

Load path and requires:
- `-I PATH[:PATH...]` - add directories to `$LOAD_PATH` (colon-separated)
- `-r LIBRARY` - `require` LIBRARY before the script body
- `--disable-gems` - skip RubyGems setup (useful for debugging require resolution against the static `repo_load_paths`)

Runtime:
- `-v` - print the version string and run
- `-0[OCTAL]` - set the input record separator (`$/`) from an octal byte (e.g. `-0` for NUL, `-040` for space)
- `-x` - skip leading text until a `#!/usr/bin/env cora` or `#!...ruby` line, matching MRI
- `--backtrace-limit=N` - limit printed backtrace frames

Help:
- `-h`, `--help` - print help and exit
- `--version` - print version and exit

## Build Steps And Options

Per-target steps (each one is independently runnable):

```bash
zig build run                # build + run
zig build test               # build + run the test suite
zig build watch              # rebuild + retest on source changes (requires `entr`)
zig build onigmo             # build Onigmo only
zig build prism              # build Prism only
zig build psych              # build the psych native extension only
zig build strscan            # build the strscan native extension only
zig build tinycc             # build TinyCC only (needed for -Dtcc-jit=true)
zig build cext-fixture       # build build/cext/fixture.so for the cext test suite
```

Options that change what gets built:

- `-Doptimize=ReleaseFast` (default), `-Doptimize=Debug`,
  `-Doptimize=ReleaseSafe`, `-Doptimize=ReleaseSmall` - optimization mode
  (persisted to `build/build-mode` between runs).
- `-Dtcc-jit=true` - link TinyCC and enable the experimental JIT.
- `-Dsubmodule-update=false` - skip the auto-run of `git submodule update
  --init` at the start of the build.
- `-Dtest-verbose`, `-Dtest-timing`, `-Dtest-jobs=N`, `-Dtest-timeout=N`,
  `-Dtest-filter=…` - forwarded to the test runner.

The TinyCC JIT and per-gem native extension build steps (`psych`, `strscan`,
`onigmo`, `tinycc`, `cext-fixture`) are documented in
`.agents/reference/native-extensions.md`.
