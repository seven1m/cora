---
name: ruby-spec-porter
description: Port Ruby specs from ../ruby_spec into this repo and make them pass with minimal divergence from upstream. Use when asked to pick a spec to pull over, copy upstream files and fix parser/compiler/vm/mspec-lite compatibility blockers discovered while running specs.
---

# Ruby Spec Porter

## Overview

Use this skill to add one or more specs from `../ruby_spec` into `spec/`, keep them aligned with upstream, and drive them to green by fixing Cora runtime/compiler/parser or mspec-lite harness gaps.

## Priorities

- Keep copied spec files matching upstream whenever possible.
- Prefer runtime/compiler/parser/spec_helper fixes over spec edits.
- When a copied upstream spec cannot run yet, prefer temporary `CORAFIXME` wrappers over rewriting expectations.
- Treat temporary `CORAFIXME` usage as short-term tactics only; remove once behavior is implemented.
- Implement general mechanisms, not one-off hacks for a single example.
- Fix small foundational blockers early if they unlock many specs.
- Preserve mspec compatibility (not rspec APIs).
- Remove local Zig tests that are fully supplanted by ported Ruby specs so coverage lives in one place.
- Work on specs pauses if you find any fundamental issues with the Cora runtime. Memory errors/leaks, data corruption, and MRI-incompatibility take center stage when you find it.

## TODO Tracking

- Use `spec/TODO.md` as the canonical tracker for ruby/spec porting status.
- Before selecting work, check `spec/TODO.md` for unchecked entries (`[ ]` or `[-]`).
- Keep status markers consistent:
  - `[ ]` Missing spec
  - `[-]` Partial-passing spec (not byte-for-byte matching upstream spec)
  - `[x]` Fully-passing spec
- When you begin porting a spec, keep it as `[ ]` until the file exists locally.
- After copying and getting partial progress (for example temporary `CORAFIXME` wrappers), update the entry to `[-]`.
- Once the spec is passing and byte-for-byte matching the upstream spec, update the entry to `[x]`.
- If it's not possible to fully match the upstream spec, then leave the entry as `[-]`.

## Workflow

1. Pick a candidate spec.
- Start from `spec/TODO.md` and choose an entry marked `[ ]` (or `[-]` if finishing partial work).
- Start with low-risk, high-signal specs in `../ruby_spec/core/*`.
- Prefer specs that map to existing builtins/opcodes and require incremental behavior.
- Avoid immediately choosing specs known to require broad missing subsystems.

2. Copy upstream files unchanged.
- Copy target file from `../ruby_spec/...` to local `spec/...`.
- Also copy required `shared/` and `fixtures/` dependencies from upstream.
- Example:
```bash
cp ../ruby_spec/core/string/start_with_spec.rb spec/core/string/start_with_spec.rb
mkdir -p spec/shared/string
cp ../ruby_spec/shared/string/start_with.rb spec/shared/string/start_with.rb
```

3. Run the spec and classify failures.
- Run the copied spec directly first, then the full test suite to verify there are no regressions.
```bash
zig build run -- spec/core/string/<name>_spec.rb
zig build test
```
- Categorize failures:
  - Parser/compiler gaps (unsupported Prism node/opcode lowering)
  - VM/runtime semantics gaps (method behavior, encoding, exceptions)
  - mspec-lite harness gaps (matchers/mocks/hooks/spec_helper)
  - Truly unsupported upstream assumptions

4. Fix in the right layer.
- Parser/compiler issue: add Prism node mapping and compile support.
- VM/runtime issue: add or correct builtins/opcodes/encoding logic.
- Harness issue: extend `spec/spec_helper.rb` mspec-lite compatibility.
- Prefer reusable abstractions (e.g. general opcode/helper) over ad-hoc branching.
- If a blocker cannot be fixed in the same pass, wrap only the failing example(s) in `CORAFIXME` with a precise description and expected failure class/message.
  Example:
```ruby
it "handles threaded backref isolation" do
  CORAFIXME "Thread is not implemented yet", exception: NameError, message: /uninitialized constant Thread/ do
    cap1, cap2 = nil
    "foo" =~ /(o+)/
    cap1 = $1
    Thread.new { cap2 = $1 }.join
    cap2.should == nil
    cap1.should == "oo"
  end
end
```

5. Re-run and tighten.
- Re-run target spec until green.
- Remove any local Zig tests that now duplicate the same behavior covered by the ported Ruby spec.
- Re-run focused regression tests (language/core tests affected by the change).
- Run ruby/spec aggregate filter to ensure no regressions in existing ported specs.
- If new helper code is generated, verify it's not reinventing a helper we already have.
  Combine or generalize (and co-locate) helpers when possible.
  Helper placement rules:
  - Required implicit String coercion belongs in `src/value.zig` (`Value.coerceToStringValue` / `Value.coerceToStr`).
  - Optional `to_str` probing with fallback-on-missing/nil belongs in `src/vm.zig` (`VM.probeToStringValue`).
  - Optional `to_ary` probing belongs in `src/vm.zig` (`VM.probeToAry`), with strict array coercion built on top.
  - Path coercion belongs in `src/vm.zig` (`VM.coerceToPath` / `VM.coerceToPathValue`).

6. Verify upstream alignment.
- Diff each copied spec/shared fixture against upstream and remove local drift.
```bash
diff -q spec/core/string/<name>_spec.rb ../ruby_spec/core/string/<name>_spec.rb
diff -q spec/shared/string/<shared>.rb ../ruby_spec/shared/string/<shared>.rb
```
- If divergence is unavoidable, keep it minimal and document the exact blocker.

7. Update `spec/TODO.md`.
- Mark the spec `[-]` if it remains partial.
- Mark the spec `[x]` when it is fully passing.
- Keep entries sorted/grouped exactly as the file already organizes them.

## Candidate Selection Heuristics

These are heuristics, not hard gates. If a spec in String, Integer, Array, or another core class is the logical next step, take it.
Circular dependencies are common in ruby/spec and truly prerequisite-light specs are rare; choose an order of attack that maximizes momentum and unblocks adjacent specs.

When asked “what next spec should we port?”, prefer this order:
1. Specs for methods already implemented in builtins (`start_with?`, `end_with?`, `ascii_only?`, `b`, etc.).
2. Specs that primarily reveal semantic mismatches (encoding boundaries, coercion, return values).
3. Specs that unlock shared examples used by multiple classes/modules.
4. Only then pick specs needing new broad subsystems.

## Editing Rules

- Do not rewrite upstream spec expectations to fit Cora behavior unless explicitly approved.
- Keep copied upstream files byte-for-byte identical whenever feasible.
- If a spec uses unsupported syntax/features and you cannot implement support immediately, preserve the upstream body and add the smallest possible `CORAFIXME` wrapper around failing examples.
- For compatibility shims in `spec/spec_helper.rb`, keep names and semantics close to mspec expectations.
- Avoid broad file-level disables when a narrow per-example `CORAFIXME` can isolate the gap.

## Completion Criteria

A ported spec is “done” when:
- Copied files exist locally and match upstream text.
- The spec passes via `zig build run -- spec/...`.
- Relevant focused tests pass.
- `zig build test` stays green.
- The corresponding `spec/TODO.md` entry is marked `[x]`.

## Commit Style

Match this repository's commit style for spec-porting work.

- Default to one commit per spec port.
- Keep runtime/compiler/parser work directly required for that spec in the same commit as the spec and `spec/TODO.md` update.
- Split into multiple commits only when there is clearly separate foundational or incidental work that should stand alone even without the target spec.
- Keep commit messages short, imperative, no body.
- Prefer non-interactive commits (`git add ... && git commit -m ...`).

Message rules:

1. Spec port with required behavior changes:
- `Make Hash#delete spec-compliant` (if fully compliant)
- `Make Array#[] more spec-compliant` (partial compliance improvement)

2. Spec added and passes without changing method behavior:
- `Add String#ascii_only? spec`
- `Add String#b spec`

3. Non-spec foundational work that truly should stand alone:
- Use concise imperative summaries, e.g.:
  - `Implement regexp numbered references`
  - `Add euc-jp encoding alias`
  - `Add Hash#delete` (not focused on spec compliance, but some basic version of the method was required by the spec under port)

## Useful Commands

```bash
# list local vs upstream missing string specs
diff <(ls -1 spec/core/string | sort) <(ls -1 ../ruby_spec/core/string | sort)

# run one spec file
zig build run -- spec/core/string/chars_spec.rb

# run filtered tests
zig build test -Dtest-filter="char|to_i"

# run full test suite
zig build test

# quick mismatch check for copied files
diff -q spec/core/string/start_with_spec.rb ../ruby_spec/core/string/start_with_spec.rb
```
