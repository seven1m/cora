# String Encode Plan

## Priority Order

1. Implement `xml:` behavior in `String#encode` / `String#encode!`
- Support `xml: :text` escaping (`&`, `<`, `>`).
- Support `xml: :attr` escaping (`&`, `<`, `>`, `"`) and wrapping output in double quotes.
- For undefined destination conversions under `xml`, emit uppercase hex character references (`&#x...;`).
- Raise `ArgumentError` for unsupported `xml` values.

2. Support `fallback: method(:name)` behavior
- Treat `Method` fallback as callable like proc/lambda.
- Preserve return-value coercion semantics (`to_str` required, no `to_s` fallback).
- Preserve `too big fallback string` behavior for invalid fallback return values.

3. Fix core transcoding semantics
- Correct default-internal transcoding behavior.
- Correct encoding resolution and conversion mapping for `to` / `from` combinations.
- Match converter-not-found vs undefined-conversion error behavior.

4. Fix invalid-byte replacement compaction
- Under `invalid: :replace`, collapse trailing/adjacent invalid-byte runs to a single replacement where required by spec.

## Execution Notes
- Keep shared spec files upstream-identical except explicit `CORAFIXME` wrappers around failing example bodies.
- Remove `CORAFIXME` wrappers only when the underlying behavior is implemented and verified.
