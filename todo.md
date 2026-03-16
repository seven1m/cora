## Lifecycle method dispatch gap

- `initialize` and `initialize_copy` do not currently behave like MRI when the real method has been removed and behavior is supplied through `respond_to_missing?` / `method_missing`.
- During the dispatch audit, removing `findMethod` prechecks from object construction and dup/copy paths exposed a deeper runtime issue instead of a simple guard bug.

### What was observed

- `Object.new` and `Class#new` currently rely on explicit method presence checks before calling `initialize`.
- `String#dup` and similar copy paths rely on explicit method presence checks before calling `initialize_copy`.
- If those guards are removed, Cora still does not match MRI because the default private lifecycle methods are not properly exposed to normal Ruby dispatch.
- In the failing cases, `send(:initialize)` / `send(:initialize_copy, ...)` can raise `NameError` in Cora where MRI dispatches successfully.
- After `undef_method :initialize` or `undef_method :initialize_copy`, MRI can still reach `method_missing` when `respond_to_missing?` advertises the method, but Cora currently does not.

### MRI-aligned behavior to implement later

- Add correct default private `Kernel#initialize`.
- Add correct default private `Kernel#initialize_copy`.
- Revisit constructor and dup/clone/copy call sites after those defaults exist, and remove any remaining `findMethod` gates that incorrectly bypass dynamic dispatch.
- Verify behavior against `../ruby` for:
- `Object.new`
- `Class#new`
- `send(:initialize)`
- `send(:initialize_copy, obj)`
- `dup` / `clone`
- dynamic `respond_to_missing?` / `method_missing` overrides for both lifecycle methods

### Why this matters

- The earlier mock/stub mismatch in `spec_helper.rb` caused us to audit `findMethod`-based prechecks across the runtime.
- Some of those sites were genuine bugs and have already been fixed in committed work.
- The lifecycle-method sites are different: they reveal missing runtime semantics, not just a bad probe-vs-dispatch choice.
