# Cora Roadmap

This roadmap is organized around two compatibility milestones:

1. Run enough of RubyGems to support Cora's own `gem` command.
2. Use that `gem` command to install Rack.

The goal is not to clone MRI all at once. Each stage should unlock real Ruby
programs, increase ruby/spec coverage, and reduce the amount of Cora-specific
patching needed by ordinary Ruby code.

## Guiding Principles

- Prefer MRI-compatible behavior over Cora-only shortcuts.
- Prefer reusable core, stdlib, VM, and builtin improvements over narrow fixes
  for RubyGems or Rack.
- Keep each stage runnable from the Cora binary so progress can be demonstrated
  without depending on another Ruby.
- Treat missing methods discovered by RubyGems and Rack as spec targets, then
  port the relevant ruby/spec coverage when practical.
- Keep compatibility work focused on the standard Ruby load model, object model,
  IO model, exceptions, and core collection/string semantics.

## Milestone 1: RubyGems

RubyGems is the first external compatibility target. The desired end state is
that Cora can run a bundled or vendored RubyGems entrypoint and expose a Cora
owned `gem` command capable of installing pure-Ruby gems.

### Stage 1: RubyGems Discovery Harness

Build a repeatable way to run RubyGems code under Cora and see the next missing
feature clearly.

Deliverables:

- Vendor or otherwise pin a known RubyGems version for compatibility work.
- Add a Cora command or script that runs a small RubyGems smoke test.
- Capture missing constants, missing methods, load failures, and exception
  mismatches in a focused compatibility TODO.
- Add regression tests for every Cora feature fixed while advancing the harness.

Expected pressure areas:

- `require`, `require_relative`, `load`, `$LOAD_PATH`, `$LOADED_FEATURES`
- `__FILE__`, `__dir__`, `ARGV`, process status, and current working directory
- Backtraces, exception classes, and error messages
- Basic reflection used by library code

### Stage 2: Load System And Ruby Process Surface

Make Cora's script and library loading model close enough to MRI that RubyGems
can find and load its own files predictably.

Deliverables:

- More complete load path resolution for `.rb` files.
- Correct loaded-feature tracking and idempotent `require`.
- Better support for command entrypoints and executable scripts.
- Useful CLI behavior for `-e`, script args, exit codes, warnings, and failures.
- Compatibility tests covering relative loads, repeated requires, and load
  errors.

Expected pressure areas:

- `$0`, `$PROGRAM_NAME`, `$:`, `$LOAD_PATH`, `$"`, `$LOADED_FEATURES`
- `Kernel#warn`, `$stderr`, `$stdout`
- `SystemExit`, `LoadError`, `NameError`, `NoMethodError`, `SystemStackError`
- File path normalization across relative and absolute paths

### Stage 3: Core Library Coverage For RubyGems

Fill in the high-use core methods RubyGems expects from ordinary Ruby objects.

Deliverables:

- Broader `Enumerable`, `Array`, `Hash`, `String`, `Symbol`, `Integer`, and
  `Module` behavior.
- More complete block, proc, lambda, keyword argument, splat, and block
  forwarding behavior.
- Reflection and method visibility behavior used by library DSLs.
- Ported ruby/spec files for the highest-risk methods added in this stage.

Expected pressure areas:

- `Enumerable#find`, `#detect`, `#inject`, `#reduce`, `#group_by`,
  `#each_with_object`, `#sort_by`
- `Array#flatten`, `#compact`, `#delete`, `#values_at`, `#zip`, `#to_h`
- `Hash#merge`, `#update`, `#each_value`, `#transform_keys`,
  `#transform_values`, `#fetch_values`
- `String#gsub`, `#sub`, `#strip`, `#lstrip`, `#rstrip`, `#chomp`, `#lines`
- `Module#const_get`, `#const_defined?`, `#remove_const`, `#autoload?`
- `Object#instance_eval`, `#class_eval`, `#public_send`

### Stage 4: Minimal Stdlib Set For RubyGems

Implement or vendor enough standard library surface for RubyGems to run without
large local patches.

Deliverables:

- A documented Cora stdlib subset loaded by normal `require`.
- Pure-Ruby stdlib files where possible, Zig builtins where host integration or
  performance makes that more practical.
- Compatibility tests for stdlib APIs used directly by RubyGems.

Expected pressure areas:

- `rbconfig`
- `fileutils`
- `pathname`
- `time`
- `digest`
- `zlib`
- `stringio`
- `tempfile`
- `tmpdir`
- `uri`
- `set`
- `forwardable`
- `delegate`
- `optparse`
- `shellwords`

### Stage 5: Filesystem, IO, And Archive Support

Support the parts of RubyGems that inspect, unpack, and write gem contents.

Deliverables:

- File and directory APIs needed for gem install, uninstall, and listing.
- IO APIs needed by RubyGems and stdlib archive readers.
- Tar/gzip path for `.gem` package extraction.
- Permission, mode, mtime, and path behavior accurate enough for installed gem
  layouts.

Expected pressure areas:

- `File.open`, `File.read`, `File.write`, `File.binread`, `File.exist?`,
  `File.directory?`, `File.file?`, `File.stat`, `FileUtils`
- `Dir.glob`, `Dir.entries`, `Dir.mkdir`, recursive directory creation
- `IO#read`, `#write`, `#gets`, `#each_line`, `#flush`, `#binmode`, `#close`
- `StringIO` as an IO-compatible in-memory object
- `Gem::Package`, tar headers, gzip streams, checksums

### Stage 6: Gem Metadata And Dependency Model

Run enough RubyGems internals to parse gemspecs, resolve simple dependencies,
and create an install plan.

Deliverables:

- `Gem::Specification` loading for installed and packaged gems.
- Version and requirement comparisons.
- Platform handling sufficient for pure-Ruby gems.
- Local gem repository layout under a Cora-controlled gem home.
- Tests using small fixture gems.

Expected pressure areas:

- `Gem::Version`
- `Gem::Requirement`
- `Gem::Dependency`
- YAML or Marshal support, depending on the pinned RubyGems path
- `Time`, `Date`, and metadata normalization

### Stage 7: Cora `gem` Command

Expose RubyGems through Cora as a working command.

Deliverables:

- `cora gem` or `zig-out/bin/gem` command entrypoint.
- `gem env`, `gem list`, `gem install <local .gem>`, and `gem uninstall` for
  pure-Ruby gems.
- Installation into a Cora gem home without relying on MRI.
- Clear errors for unsupported native extensions or unsupported platforms.

Expected pressure areas:

- Executable generation and shebang behavior
- Cora-specific gem paths
- Environment variables such as `GEM_HOME` and `GEM_PATH`
- User install versus project-local install semantics

### Stage 8: Remote Gem Install

Teach Cora's `gem` command to install from a gem source.

Deliverables:

- Fetch gem metadata and `.gem` files from a configured source.
- Basic HTTPS story, either native or through an explicit documented transport
  layer.
- Cache downloaded gems in the Cora gem home.
- Install a pure-Ruby gem by name without MRI.

Expected pressure areas:

- `net/http`, `openssl`, `uri`, and certificates, or a deliberately smaller
  Cora transport abstraction
- Compact index parsing
- Redirects, errors, retries, and cache invalidation

## Milestone 2: Rack

Rack is the first target gem to install through Cora's own RubyGems path. The
desired end state is:

```bash
cora gem install rack
cora -rrack -e 'p Rack.release'
```

### Stage 1: Install Rack As A Pure-Ruby Gem

Use the Cora `gem` command to install Rack and make its files loadable.

Deliverables:

- `gem install rack` succeeds for a pinned Rack version.
- `require "rack"` works from Cora.
- Rack's gemspec metadata and runtime files install into the expected location.
- Unsupported optional integrations fail lazily rather than during basic load.

Expected pressure areas:

- RubyGems activation
- `$LOAD_PATH` modification for installed gems
- Rack's `require` graph
- Additional stdlib files pulled in by Rack

### Stage 2: Rack Core API Smoke Tests

Run Rack's central interfaces without starting a production server.

Deliverables:

- `Rack::Request` and `Rack::Response` smoke tests.
- A Rack app callable as `app.call(env)`.
- Header, status, and body handling compatible with simple Rack examples.
- A small Cora test suite that exercises Rack with hand-built env hashes.

Expected pressure areas:

- `StringIO`
- `URI`
- query parsing
- case-insensitive headers
- Enumerable response bodies
- exception and status handling

### Stage 3: Rack Server Adapter For Cora

Run a Rack app through Cora's socket and IO support.

Deliverables:

- A minimal Rack handler backed by Cora's `TCPServer`.
- Static responses, dynamic routes, query strings, and request bodies.
- Example Rack app served by Cora.
- Integration test that performs an HTTP request against the running app.

Expected pressure areas:

- Socket lifecycle and blocking IO
- `IO#readpartial` or an acceptable equivalent
- request body buffering
- response streaming enough for simple bodies
- process signal handling for shutdown

### Stage 4: Rack Test Suite Subset

Use Rack's own tests as the next compatibility driver.

Deliverables:

- A documented subset of Rack tests that Cora can run.
- A skip list that distinguishes missing Cora features from intentionally
  unsupported Rack integrations.
- Cora regressions for each interpreter or stdlib bug found by Rack tests.

Expected pressure areas:

- More precise encoding behavior
- More complete regular expressions and match data
- `Tempfile`, multipart parsing, and file upload helpers
- richer IO duck typing
- subtle Hash/String coercion behavior

### Stage 5: Unmodified Rack Install And Basic App

Remove local Rack patches and run a small unmodified Rack app end to end.

Deliverables:

- `cora gem install rack` from the configured source.
- `require "rack"` without Rack source edits.
- A simple Rack app served by Cora from installed gem code.
- Documentation for supported Rack features and known gaps.

## Cross-Cutting Compatibility Tracks

These tracks should advance continuously while working through the milestones.

### ruby/spec Coverage

- Port specs for every core method added for RubyGems or Rack.
- Prefer small, passing spec slices over broad unchecked imports.
- Track partial specs explicitly so compatibility debt remains visible.

### Stdlib Shape

- Prefer pure-Ruby stdlib implementations when they are clear and performant
  enough.
- Use Zig builtins for OS integration, binary formats, cryptography, compression,
  sockets, and places where pure Ruby would require unsupported primitives.
- Keep stdlib APIs loaded through normal Ruby `require`.

### Diagnostics

- Make missing features obvious: method name, receiver class, file, line, and
  backtrace should point at the real failure.
- Improve parser, compiler, and VM errors when RubyGems or Rack exposes unclear
  failures.
- Keep compatibility TODOs tied to failing commands or tests.

### Native Extensions

Native extensions are not required for the initial RubyGems and Rack milestones.
The `gem` command should detect them and produce a clear unsupported message.

Native extension support can be evaluated after pure-Ruby gem installation and
Rack are reliable.

## Success Criteria

RubyGems milestone is complete when Cora can install, list, activate, and
uninstall pure-Ruby gems through its own `gem` command without invoking MRI.

Rack milestone is complete when Cora can install Rack through that command,
`require "rack"`, and serve a small Rack app using Rack code loaded from the
installed gem.
