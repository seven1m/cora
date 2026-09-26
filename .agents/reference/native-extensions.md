# Native Extensions And Builtin Gems

Cora supports loading MRI-style C extension `.so` files and ships a growing set
of vendored builtin gems under `ext/`. This doc covers both layers and how they
are built and tested.

## Layout At A Glance

- `ext/<gem>/` - vendored gem sources. Submodules for gems with their own
  upstream repo (`ext/prism`, `ext/onigmo`, `ext/tinycc`, `ext/rubygems`, `ext/ipaddr`,
  `ext/logger`, `ext/time`, `ext/optparse`, `ext/uri`, `ext/delegate`,
  `ext/tmpdir`, `ext/tempfile`, `ext/cgi`, `ext/erb`, `ext/forwardable`,
  `ext/timeout`, `ext/singleton`, `ext/open3`, `ext/shellwords`, `ext/yaml`,
  `ext/weakref`, `ext/psych`, `ext/strscan`, `ext/csv`, `ext/json`,
  `ext/test-unit`, `ext/power_assert`).
- `lib/stdlib/` - pure-Ruby standard library code vendored outside the gem
  layout (`fileutils.rb`, `securerandom.rb`, `monitor.rb`, `pathname.rb`,
  `openssl.rb`, `zlib.rb`, `stringio.rb`, `date.rb`, `set.rb`, `digest.rb`,
  `English.rb`, `etc.rb`, `thread.rb`, plus `io/`, `digest/`, `json/`,
  `random/`, `rbconfig/` subdirs). Loaded straight off `$LOAD_PATH`.
- `include/cora/ruby.h` - the C ABI header ext authors `#include` so their
  source compiles against Cora.
- `src/cext.zig` - implementation of every `rb_*` symbol Cora exposes.
- `src/load_path.zig` - the static `repo_load_paths` table the VM pushes onto
  `$LOAD_PATH` at startup.

Some pure-Ruby vendored gems are added directly to `repo_load_paths` by their
`ext/<gem>/lib` directory. Default gems are installed under
`build/lib/gems/4.0.0/gems/<name>-<version>/`; those with native extensions
ship their compiled `.so` next to the `lib/` tree.

Bundled gems are ordinary installed gems shipped with Cora. The set includes
`csv`, `test-unit`, and its `power_assert` dependency. Their sources are pinned as
submodules, installed under `build/lib/gems/4.0.0/gems/`, and registered by
gemspecs in `build/lib/gems/4.0.0/specifications/`. Unlike default gems,
they are not placed directly on `$LOAD_PATH`; RubyGems activates them when
required. `Gem::Specification#default_gem?` is false for them.

## Builtin Gem Registration

`src/load_path.zig` defines the load-path ordering used by both `main.zig`
(`configureLoadPath`) and the test helpers. Entries are evaluated relative to
the runtime root (or `build/` in test mode).

- Pure-Ruby stdlib goes through `lib/stdlib/`.
- Vendored non-default gem trees are listed by their `ext/<gem>/lib` path
  (e.g. `ext/rubygems/lib`, `ext/psych/lib`).
- Default gem trees are referenced by their installed layout via
  `defaultGemLibPath(name, version)` which builds
  `lib/gems/4.0.0/gems/<name>-<version>/lib`.
- Bundled gem trees are absent from this static table. RubyGems finds them
  through `Gem.path`, so `--disable-gems` and an explicit `GEM_PATH` that
  excludes Cora's gem root hide them.

Tests, the test runner, and the test helper append each entry through
`VM.appendLoadPath` plus `realPathFile` so both absolute and in-tree
invocations resolve correctly.

## Build Pipeline

`build.zig` controls how vendored gems are wired in. Key knobs:

- `runtime_ext_dirs` - list of `ext/<gem>` directories copied wholesale into
  the install prefix (`build/ext/<gem>`). Used for gem trees that are loaded
  directly from `ext/<gem>/lib` and do not need a gem layout.
- `addInstallGemDir` - installs `ext/<gem>` (or a build copy) into
  `build/lib/gems/4.0.0/gems/<name>-<version>/`.
- `addInstallDefaultGemNativeLib` - installs a single compiled `.so` into the
  default gem's `lib/` directory.
- `addWriteGemSpec` - loads each upstream `.gemspec` and writes a serialized
  spec into `specifications/default/` for default gems or `specifications/`
  for bundled gems. `bundled_gems` lists the pinned bundled versions.

The dev shell sets `GEM_HOME` to `.gem` for local installs but leaves
`GEM_PATH` unset. RubyGems still searches `.gem` and also includes the
interpreter's shipped gem directory in its default search path.

Steps per gem:

- `psych` - pure C extension built via `ext/psych/ext/psych/extconf.rb` plus
  `make -C build/psych/ext`.
- `strscan` - copied into `build/strscan`, patched with `ext/strscan.patch`,
  then built with its own `extconf.rb` and `make`.
- `json` - installed as a default gem with native parser and generator `.so`
  files.
- `yaml` - pure Ruby; installed as a default gem without an `.so`.
- `csv`, `test-unit`, `power_assert` - pure Ruby; installed as ordinary bundled gems
  with `test-unit` depending on `power_assert`.

The TinyCC JIT and Onigmo use the same pattern as the gems: copy from
`ext/<lib>` to `build/<lib>`, run the upstream configure step, and link the
resulting `libtcc.a` / `libonigmo.a` into the executable.

## Per-Step Build Targets

```bash
zig build                    # build everything
zig build run                # build and run
zig build test               # build and run the test suite
zig build watch              # rebuild + retest on source changes (needs `entr`)
zig build onigmo             # just build Onigmo
zig build prism              # just build Prism
zig build psych              # just build the psych native extension
zig build strscan            # just build the strscan native extension
zig build tinycc             # just build TinyCC
zig build cext-fixture       # build the test fixture .so used by cext_test
```

## Common Build Options

```bash
zig build -Doptimize=ReleaseFast        # default; writes the result to build/bin/cora
zig build -Doptimize=Debug              # full safety + debug info
zig build -Doptimize=ReleaseSafe        # release performance with runtime safety
zig build -Dsubmodule-update=false      # skip `git submodule update --init`
zig build test -Dtest-jobs=8            # parallelize tests across workers
```

## CLI Flags That Affect Gem Loading

- `-I PATH[:PATH...]` - prepend to `$LOAD_PATH` before the script runs.
- `-r LIBRARY` / `-rLIBRARY` - `require` before the script body.
- `--disable-gems` - skip RubyGems setup entirely; useful for debugging
  require resolution against the static `repo_load_paths`.
- `-x` - skip leading text until a `#!/usr/bin/env cora` or `#!…ruby` line,
  matching MRI. The `bin/gem` polyglot script relies on this.

## Native C Extensions

### What Cora Supports

The C ABI Cora currently implements is intentionally narrow. The supported
surface lives in `include/cora/ruby.h` and is implemented in `src/cext.zig`.

Key categories:

- Object lifecycle: `rb_define_module`, `rb_define_class_under`,
  `rb_define_module_under`, `rb_define_method`, `rb_define_module_function`,
  `rb_define_singleton_method`, `rb_define_private_method`,
  `rb_define_alloc_func`, `rb_define_const`, plus `rb_alias`, `rb_define_alias`.
- Method invocation: `rb_funcall`, `rb_funcallv`, `rb_yield`,
  `rb_yield_values` (with non-local return unwinding).
- String / encoding: `rb_str_new`, `rb_str_new2`, `rb_usascii_str_new_cstr`,
  `rb_enc_str_new`, `rb_utf8_str_new_cstr`, `rb_string_value`,
  `rb_string_value_cstr`, `rb_string_value_ptr`, `rb_str_cat2`, `rb_str_dump`,
  `rb_sprintf`, `rb_string_ptr`, `rb_string_len`, the `rb_enc_*` family, plus
  `rb_isspace`.
- Array helpers: `rb_ary_new`, `rb_ary_new3`, `rb_ary_new4`, `rb_ary_push`,
  `rb_ary_entry`, `rb_ary_const_ptr`.
- Symbol / hash: `rb_intern`, `rb_sym2str`, `rb_check_hash_type`,
  `rb_get_kwargs`.
- Exceptions: `rb_enc_raise`, `rb_memerror`.
- Constants: `rb_const_get`, `rb_const_set`, `rb_const_defined`, plus the
  `rb_intern`/`rb_define_const` pair used by most extension authors.

The full list lives in `src/cext.zig` (179 `export fn rb_*` symbols at last
count). Anything not implemented there is **not** in the supported surface
yet.

### Loading And Dispatch

- Cora `dlopen`s the `.so` and resolves `Init_<name>` to register methods.
- Each registration goes through `class_ptr.module.methods.put(sym, entry)`
  with `MethodEntry{ .method = .{ .cext = .{ .func, .argc } } }` and bumps
  `VM.method_state_version`.
- `Class#new` consults `class_ptr.cext_alloc_func` first; set that with
  `rb_define_alloc_func` when the C side wants to allocate the Ruby wrapper.
- Loaded `DynLib` handles are kept on `VM.cext_handles` and freed on
  `VM.deinit`.

### Non-Local Returns Across C Frames

`rb_yield` and `rb_funcall` may trigger non-local returns (e.g. block `return`
or proc unwinding). Cora installs a setjmp/longjmp-style buffer on
`VM.cext_jmp_buf` before entering C extension code, and mirrors the unwound
`PendingControlFlow` on `VM.cext_pending_control_flow`. The mirror only ever
holds `.return_`; other control flow kinds (`next`, `break`, `redo`, `retry`)
stay local to the Ruby block and must not be projected to the C side as a
non-local return. The C frame returns normally and the caller in
`src/vm.zig` checks `cext_pending_control_flow` to continue unwinding the
Ruby stack.

Explicit keyword arguments are passed to C methods as a trailing hash.
`rb_scan_args` preserves the positional argument count and extracts that hash
for formats containing the `:` directive.

### Testing C Extensions

The smallest end-to-end fixture lives at:

- `test/support/cext_fixture.c` - a hand-written `.c` file using
  `include/cora/ruby.h` to define `String#cora_cext_test` and a few
  `CoraCExt` module functions covering `rb_funcall`, `rb_yield`, and nested
  non-local returns.
- `test/core/cext_test.zig` - Zig tests that `$LOAD_PATH << "build/cext"`,
  `require "fixture.so"`, and exercise the fixture through Ruby code.
- `build.zig` - `buildCExtFixture` compiles the fixture with `gcc -shared
  -fPIC -I include/cora` to `build/cext/fixture.so`, installed to
  `build/cext/fixture.so`. The `test` step depends on this.

Use this fixture as the template when adding new `rb_*` ABI surface area: copy
`cext_fixture.c`, add a Zig test in `test/core/cext_test.zig`, register the
new test in `test/all_test.zig`, then re-run `zig build test`.

When porting real gems with native extensions (like `psych` and `strscan`),
prefer keeping the upstream `ext/<gem>/ext/<gem>/extconf.rb` and `Makefile`
working as-is. The build pipeline in `build.zig` is the integration point.
