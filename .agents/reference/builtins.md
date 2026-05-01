# Builtins And Conventions

## General Preferences

- Prefer importing files at the top of the file. Avoid inline `@import(...)` expressions in function bodies or expressions.
- Do not expose runtime implementation details to user Ruby code via fake or hidden instance variables or methods such as `@__store` or `__hidden_methods__`. Keep runtime-only state in VM/runtime structures.
- In `src/encoding/*.zig`, keep encoding capability predicates on the concrete encoding structs and have `src/encoding.zig` delegate via `inline else`. Avoid hard-coding per-tag switches in the `Encoding` union for flags like `isDummy` or `isUnicode`.
- If you add or discover a reusable builtin helper that is broadly useful, document it in this reference area.

## Dispatch, Arity, And Coercion Helpers

- Always use VM argument-count helpers such as `requireArgCount` and `requireArgCountRange` instead of hand-constructing wrong-arity exceptions.
- Prefer `VM.checkCallMethodByName(receiver, "method", include_private, args, block)` for optional conversion/probe calls where a missing method should behave like "not supported".
- Pass `include_private = true` to `checkCallMethodByName` only when Ruby semantics require private methods to count for the probe.
- Do not parse exception messages such as `"undefined method 'to_str'"` to detect missing methods.
- Use `VM.callMethodByName` when the call must always happen or its side effects must be preserved.
- Use `VM.respondsToMethodByName` for capability probes that should not force the method call.
- Use `VM.allocCStringZ` for temporary NUL-terminated C strings needed by libc APIs.
- Use `VM.copyObjectInstanceVariables` for dup/clone-style shallow ivar copying.

## Array And String Coercion Helpers

- `VM.probeToAry` centralizes low-level `to_ary` coercion. It distinguishes array, missing method, and nil result, and raises `TypeError` when `to_ary` returns a non-Array.
- `VM.coerceToArrayValue` is the strict array-like coercion helper for APIs like `Array#+` and `Array#replace`.
- `VM.probeToHash` centralizes optional `to_hash` probing. It distinguishes Hash, missing method, nil result, and non-Hash result so callers can preserve context-specific error messages.
- `Value.coerceToStringValue` in `src/value.zig` is the canonical implicit String coercion path for `to_str` semantics that should raise `TypeError` on failure.
- `Value.coerceToStr` should be used when you need `[]const u8` bytes after the same implicit coercion.
- `VM.probeToStringValue` is the preferred optional/cooperative `to_str` probe helper when missing `to_str` or nil should map to fallback behavior.
- Use `VM.checkCallMethodByName(..., "to_str", false, ...)` only when no shared `to_str` probe helper matches the semantics.
- If you only need capability probing, such as checking `to_str` support for `String#==` reverse dispatch, prefer `respond_to?` semantics rather than forcing coercion.
- Use `VM.coerceToPath` for path arguments (`to_path` and then String coercion).
- Use `VM.coerceToPathValue` when you must preserve the resulting String object's encoding/value.
- Avoid per-builtin ad hoc `to_str` helpers unless the semantics intentionally differ; if they do, document why near the helper.

## Encoding And Warning Helpers

- Use `VM.raiseEncodingCompatibilityError` for the common `Encoding::CompatibilityError` format of `"incompatible character encodings: ..."`.
- Prefer shared warning helpers in `src/builtins/warning.zig`, such as `writeWarning` and `warnBlockUnused`, over builtin-specific `$stderr` writers.

## Builtin Naming Conventions

- For Ruby `!` methods, use a `Bang` suffix in the Zig handler name, for example `builtinStringUpcaseBang`.
- For Ruby `?` methods, prefer descriptive names without punctuation, for example `builtinStringEmpty` or `builtinKernelRespondTo`.
- If a `?` method has a non-`?` sibling with the same stem, use a `Q` suffix to disambiguate, for example `builtinModuleInclude` and `builtinModuleIncludeQ`, or `builtinStringCasecmp` and `builtinStringCasecmpQ`.
