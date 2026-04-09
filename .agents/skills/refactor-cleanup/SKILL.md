---
name: refactor-cleanup
description: Refactor and clean up existing Cora code without changing behavior. Use when asked to reduce cruft, consolidate duplicate helpers, normalize naming, remove dead paths, or do a cleanup pass after feature work or ruby/spec porting.
---

# Refactor Cleanup

## Overview

Use this skill for behavior-preserving cleanup passes in Cora, especially after adding specs, builtins, compiler support, or VM features.

This skill complements `ruby-spec-porter`: porter work gets features/specs in place; this skill removes the follow-on cruft that tends to accumulate around them.

## Priorities

- Preserve behavior. Cleanup is successful only if semantics stay the same or become more internally consistent without user-visible regressions.
- Prefer consolidating onto existing canonical helpers over adding one more near-duplicate helper.
- Remove temporary scaffolding once the underlying mechanism exists.
- Normalize names toward repo conventions when touching adjacent code.
- Make shared logic easier to find and harder to accidentally fork again.
- Keep diffs scoped. Avoid opportunistic rewrites that mix cleanup with unrelated feature work.

## What To Look For

- Duplicate or near-duplicate helpers in builtins, VM, compiler, test support, or spec support.
- Inconsistent use of canonical helpers already called out in `AGENTS.md`.
- Ad hoc coercion, arity, warning, or probe logic that should reuse shared VM/builtin helpers.
- Temporary compatibility shims, one-off branches, or narrow special cases that can now collapse into a general path.
- Inconsistent builtin naming, especially `Bang`/`Q` suffix conventions.
- Repeated local variables, branches, or conversions that obscure the main control flow.
- Dead tests or Zig tests now superseded by imported ruby/spec coverage.
- Comments that describe obsolete behavior or implementation history instead of current intent.

## Canonicalization Checklist

Before keeping or adding a helper, check whether an existing shared helper already covers it.

- Arity validation: prefer `VM.requireArgCount`, `VM.requireArgCountRange`, and related helpers.
- Optional conversion/probe calls: prefer `VM.checkCallMethodByName`.
- Required dispatch: prefer `VM.callMethodByName`.
- `to_ary` behavior: prefer `VM.probeToAry` or `VM.coerceToArrayValue`, depending on strictness.
- String coercion: prefer `Value.coerceToStringValue`, `Value.coerceToStr`, or `VM.coerceToPath` as appropriate.
- Warning output: prefer shared helpers in `src/builtins/warning.zig`.

If none fit, add a new helper only when at least one of these is true:

- The logic is already duplicated.
- The abstraction removes a real correctness risk.
- The helper meaningfully clarifies a recurring Ruby semantic.

If you add a broadly reusable helper, document it in `AGENTS.md`.

## Workflow

1. Identify the cleanup target.
- Start from a concrete area: files touched by recent spec-porting work, a builtin under active change, a noisy helper cluster, or a test/support area with drift.
- Search for nearby duplication before editing.

2. Map the local patterns.
- Find all call sites and sibling implementations.
- Separate true semantic differences from accidental drift.
- Decide the canonical home for shared logic before patching.

3. Refactor toward one path.
- Inline dead wrappers.
- Merge duplicate helpers.
- Rename toward established conventions.
- Delete obsolete branches, comments, and compatibility glue that no longer earns its keep.
- Keep behavior-preserving reshaping ahead of any micro-optimizations.

4. Re-check surrounding tests.
- Update or remove Zig tests that are redundant with stronger ruby/spec coverage.
- Keep focused regression coverage for tricky semantics or bootstrap-only cases.

5. Verify.
- Run focused tests for the touched area first.
- Run broader tests if the cleanup affected shared helpers or central dispatch paths.

## Editing Rules

- Do not change user-visible behavior just because an implementation looks odd.
- Do not invent new helper layers when an existing helper can be generalized slightly.
- Do not keep both the old and new path unless the overlap is temporary and clearly justified.
- Avoid moving code across files unless it meaningfully improves discoverability or reuse.
- When consolidating helpers, prefer the location with the clearest ownership:
  - VM-wide Ruby semantics belong in `src/vm.zig`.
  - Cross-builtin helpers belong in shared builtin support files.
  - Type-specific behavior belongs with that builtin/class.
- Prefer deleting stale comments over rewriting them into longer stale comments.

## Completion Criteria

A cleanup pass is done when:

- The duplicated or inconsistent logic has one clear canonical path.
- Naming and helper usage match repo conventions in the touched area.
- Obsolete scaffolding is removed.
- Focused tests pass, and broader regression tests run when the cleanup touched shared machinery.
- Any new broadly reusable helper is documented in `AGENTS.md`.

## Useful Commands

```bash
# inspect duplicate-looking helpers or call patterns
rg -n "requireArgCount|checkCallMethodByName|callMethodByName|probeToAry|coerceToArrayValue|to_str|to_ary" src test

# find repeated builtin naming patterns
rg -n "builtin[A-Za-z0-9]+(Bang|Q)" src/builtins

# run focused tests
zig build test -Dtest-filter="String|Array|Kernel"

# run one spec file
zig build run -- spec/core/string/start_with_spec.rb

# run full suite
zig build test
```
