# Builtins And Conventions

## General Preferences

- Prefer importing files at the top of the file. Avoid inline `@import(...)` expressions in function bodies or expressions.
- Do not expose runtime implementation details to user Ruby code via fake or hidden instance variables or methods such as `@__store` or `__hidden_methods__`. Keep runtime-only state in VM/runtime structures.
- In `src/encoding/*.zig`, keep encoding capability predicates on the concrete encoding structs and have `src/encoding.zig` delegate via `inline else`. Avoid hard-coding per-tag switches in the `Encoding` union for flags like `isDummy` or `isUnicode`.
- If you add or discover a reusable builtin helper that is broadly useful, document it in this reference area.

## Dispatch, Arity, And Coercion Helpers

- Always use VM argument-count helpers such as `requireArgCount` and `requireArgCountRange` instead of hand-constructing wrong-arity exceptions.
- Use `VM.evalStartLine` for the optional starting line in eval-family methods; it shares nil/default handling, integer coercion, and range errors.
- After `VM.yieldToBlock`, use `YieldResult.controlFlowValue()` when a builtin should propagate either block `break` or non-local `return` by returning the yielded control-flow value.
- Prefer `VM.checkCallMethodByName(receiver, "method", include_private, args, block)` for optional conversion/probe calls where a missing method should behave like "not supported".
  Ordinary misses with default response/missing handlers return without constructing
  NoMethodError or a backtrace. Handler identity is checked by builtin function,
  so aliases are recognized and custom/redefined/prepended hooks keep normal dispatch.
- Pass `include_private = true` to `checkCallMethodByName` only when Ruby semantics require private methods to count for the probe.
- Do not parse exception messages such as `"undefined method 'to_str'"` to detect missing methods.
- Use `VM.callMethodByName` when the call must always happen or its side effects must be preserved.
- Use `VM.respondsToMethodByName` for capability probes that should not force the method call.
- Use `VM.allocCStringZ` for temporary NUL-terminated C strings needed by libc APIs.
- Use `VM.callMethodWithIterationBreak` for native internal iteration that can
  stop early. Its callback requests termination with `VM.startThrow` and the
  private break tag; the helper consumes that termination after running Ruby
  ensure handlers and propagates unrelated exceptions and control flow. This
  path is shared by Enumerable predicates, prefix methods such as `take`, and
  C extension `rb_block_call`.
  External iteration through `Enumerator#next` remains fiber-backed.
  `Enumerator#to_a` inherits Enumerable's fresh internal traversal rather than
  consuming the external next/peek cursor. `Enumerator#map` and `collect` inherit
  the native Enumerable implementation;
  internal mapping calls `each` without consuming the external next/peek cursor.
- Internal collection callbacks for `flat_map`/`collect_concat`, `filter_map`, `each_with_object`, and
  `sort_by` dispatch directly to `each` in the caller's fiber. Promote captured
  user blocks before retaining them in GC-owned callback contexts.
- `Enumerable#each_entry` uses a native callback, forwards its arguments to
  `each`, preserves zero/single yields, and packs multiple yields with forced
  block-argument destructuring. Its callback returns nil to the source.
- `Enumerable#each_slice` retains its pending slice in a GC-owned callback
  context and detaches full slices after yielding them. Full-slice callbacks
  return the user block result to `each`; incomplete slices return nil. Flush
  the final partial slice only after `each` completes normally.
- Use `VM.yieldPairToBlock` for Hash/Struct pair iteration. It passes a packed
  `[key, value]` to one-argument/rest/lambda blocks, or two arguments to compatible
  native callbacks and ordinary multi-argument blocks.
- Use `VM.yieldPackedToBlock` for a packed multi-value entry that Ruby yields
  with forced block-argument destructuring (including strict lambdas). Use
  `VM.yieldToBlock` for ordinary raw argument lists; the distinction matters for
  `sort_by` versus `filter_map`, and for zero/multiple yielded values.
- Use `VM.copyObjectInstanceVariables` for dup/clone-style shallow ivar copying.
- Use `VM.probeRangeValues` for the range-like protocol (`begin`, `end`, and
  `exclude_end?`). Actual Ranges expose their native fields, ArithmeticSequence
  objects are excluded, and missing protocol methods return null.
- IO-compatible native output uses `io.printValues` and `io.putsValues`, which dispatch through the receiver's `write` method. The puts helper shares optional `to_ary` coercion, object string conversion, and a fiber-scoped recursion guard with IO and StringIO.
- Native Hash traversals that call Ruby can share `hash.hashIterationSnapshot`
  and `hash.hashIterationEntry`. Hold `iteration_depth` for the traversal so new
  keys are rejected, and resolve each snapshot entry again to observe deletions
  and updated values. `ENV.replace` uses this path during coercion.
- Use `VM.newEnvString` for environment names and values returned to Ruby. It
  uses the captured locale, honors default_internal, preserves raw bytes on
  failed conversion, and freezes the returned String.
- Use `VM.integerFromFloat` for native Float-to-Integer truncation, including
  Bignum results and FloatDomainError for nonfinite inputs. Use
  `VM.compareIntegerToFloat` for exact mixed numeric comparisons; it preserves
  integer bits beyond Float precision and returns null for NaN.
- Use `VM.roundingModeName` to validate the shared `half:` rounding modes.
  `integer.roundInteger` and `rational.roundRational` accept an already
  validated mode and precision for native callers such as `Float#round`.
- Regexp predicates use the capture-free `onigmo.searchAt` path. Share source coercion, encoding validation, and character-offset normalization through `prepareRegexpSearch` in `src/builtins/regexp.zig`; only paths needing match details or updating Ruby backreferences should construct capture arrays and MatchData.

Complex arithmetic shares `coerceAndCallComplexArithmetic` for the two-element
`coerce` protocol. Polar and rectangular constructors share `complexRealArgument`,
which accepts real Numerics and unwraps Complex arguments with a zero imaginary part.

Synchronization registrations and scheduler block/unblock callbacks are shared by
Mutex and Queue through `src/builtins/synchronization.zig`. Use identity-based
removal and clear unused GC-scanned list slots. `mutex.reacquireMutex` preserves
pending unwinds while waiting, ensuring sleep/wait callers own their lock before
an interrupt reaches Ruby.

Numeric#step and Range#step share interval-size arithmetic through
`builtins/arithmetic_sequence.zig`. It keeps non-Float counts exact and uses
Float endpoint error bounds for floating sequences. ArithmeticSequence producers
initialize native begin/end/step metadata on EnumeratorObject; accessors must not
infer a Range receiver. `module.removeOwnMethod` performs internal method removal
and callbacks after caller validation; Numeric's default singleton-added hook
uses it to roll back rejected methods even on frozen singleton classes.

## Array And String Coercion Helpers

- `VM.probeToAry` centralizes low-level `to_ary` coercion. It distinguishes array, missing method, and nil result, and raises `TypeError` when `to_ary` returns a non-Array.
- `VM.coerceToArrayValue` is the strict array-like coercion helper for APIs like `Array#+` and `Array#replace`.
- `VM.probeToHash` centralizes optional `to_hash` probing. It distinguishes Hash, missing method, nil result, and non-Hash result so callers can preserve context-specific error messages.
- `Value.coerceToStringValue` in `src/value.zig` is the canonical implicit String coercion path for `to_str` semantics that should raise `TypeError` on failure.
- `Value.coerceToStr` should be used when you need `[]const u8` bytes after the same implicit coercion.
- `VM.probeToStringValue` is the preferred optional/cooperative `to_str` probe helper when missing `to_str` or nil should map to fallback behavior.
- `VM.coerceViaToS` in `src/vm.zig` is the canonical path for explicit `to_s` coercion that raises `TypeError` ("to_s did not return String").
- `VM.objectAsString` implements `rb_obj_as_string`: keep Strings, otherwise call `to_s` and use the default object representation if it returns a non-String. Used by Array joining and quoted-printable packing.
- Use `VM.checkCallMethodByName(..., "to_str", false, ...)` only when no shared `to_str` probe helper matches the semantics.
- If you only need capability probing, such as checking `to_str` support for `String#==` reverse dispatch, prefer `respond_to?` semantics rather than forcing coercion.
- Use `VM.coerceToPath` for path arguments (`to_path` and then String coercion).
- Use `VM.coerceToPathValue` when you must preserve the resulting String object's encoding/value.
- For filesystem operations, use `VM.coerceToFilesystemPath` / `VM.coerceToFilesystemPathValue`; these also transcode macOS paths to UTF-8. Use `VM.filesystemPathValue` for an already coerced path, keeping the original value when storing `IO#path` or doing lexical path operations.
- Avoid per-builtin ad hoc `to_str` helpers unless the semantics intentionally differ; if they do, document why near the helper.

## Encoding And Warning Helpers

- `string.appendEncodedBytes` appends to a mutable StringObject with the same encoding negotiation as `String#<<`; callers handle frozen guards and coercion.

- Use `VM.raiseEncodingCompatibilityError` for the common `Encoding::CompatibilityError` format of `"incompatible character encodings: ..."`.
- Use `VM.writeStderr` for diagnostics that must honor Ruby `$stderr`, including custom writers.
- Prefer shared warning helpers in `src/builtins/warning.zig`, such as `writeWarning` and `warnBlockUnused`, over builtin-specific `$stderr` writers.

## Exception Raising Helpers

- Prefer `VM.raiseExceptionFmt(class, fmt, args)` over manual `createException` + `setPendingException` + `return error.Unwind`. This single helper handles allocation, creation, and pending-exception setup.
- Use `VM.raiseNameErrorFmt(name_sym, fmt, args)` to initialize the native NameError name field. Use `raiseNoMethodWithArguments` when the missing call supplies arguments, `raiseFrozenErrorFmt` for a frozen receiver, and `raiseSyntaxError` for source diagnostics with a path.
- Use `VM.raiseErrnoNumberFmt` for numeric errno values; `raiseErrnoFmt` and `raiseLastErrnoFmt` delegate to it and retain the native error number.
- Use `VM.raiseKeyErrorFmt(key, receiver, fmt, args)` for `KeyError` with key and receiver fields.
- Do not manually construct format strings with `std.fmt.allocPrint` just to pass them to `createException`; use the `*Fmt` helpers instead.

- Use `VM.prepareRaisedException` for exception delivery across execution contexts. It consumes raise keywords, invokes `exception`, validates cause chains, and resolves the cause in the caller; delivery captures any missing backtrace in the target context.

## Block Validation

- Use `VM.requireBlock(block)` to assert a block was provided. Returns the block or raises `ArgumentError("no block given")`.

## Frozen Object Guards

- Use `VM.guardNotFrozen(receiver)` to check if an object is frozen and raise `FrozenError("can't modify frozen ...")` if so. It includes the inspected receiver when available and guards recursive inspection. This replaces the repetitive `if (receiver.isFrozen()) { return vm.raiseExceptionFmt(...); }` pattern.

Use `VM.singletonClassForDefinition` when defining a singleton method. It checks singleton eligibility before frozen state, handles definitions on nil/true/false through their classes, and preserves the original frozen receiver.

## Method Change Hooks

- `VM.triggerMethodCallback` dispatches added/removed/undefined hooks normally for both classes/modules and singleton receivers. Both families have private default methods. An explicitly undefined callback must reach `method_missing` or raise `NoMethodError`; it is not an optional probe.

## Method Reflection

- Use `method_common.parametersForMethod` and `sourceLocationForMethod` with the method implementation. They do not require a fabricated `ResolvedMethod` or an owner-class fallback.
- A concrete lookup's visible owner must exist. Synthetic `respond_to_missing?` handles are created explicitly with no definition node; do not treat missing metadata on ordinary methods as that synthetic case.

## Builtin Naming Conventions

- For Ruby `!` methods, use a `Bang` suffix in the Zig handler name, for example `builtinStringUpcaseBang`.
- For Ruby `?` methods, prefer descriptive names without punctuation, for example `builtinStringEmpty` or `builtinKernelRespondTo`.
- If a `?` method has a non-`?` sibling with the same stem, use a `Q` suffix to disambiguate, for example `builtinModuleInclude` and `builtinModuleIncludeQ`, or `builtinStringCasecmp` and `builtinStringCasecmpQ`.
