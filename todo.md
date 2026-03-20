## Lifecycle method dispatch gap

- Follow-up lifecycle work remains, but the core runtime gap is smaller now.
- Default private lifecycle methods now exist for normal Ruby dispatch:
- `BasicObject#initialize`
- `Kernel#initialize_copy`
- `Kernel#initialize_dup`
- `Kernel#initialize_clone`
- `String#initialize_copy`
- `Object.new`, `Class#new`, and `String#dup` now dispatch through the normal call path, so `undef_method` plus `respond_to_missing?` / `method_missing` works for those entry points.

### What was fixed

- `send(:initialize)` now dispatches successfully through the default private method instead of raising `NameError`.
- `send(:initialize_copy, ...)` now dispatches successfully for default object behavior and for `String`.
- After `undef_method :initialize`, constructor dispatch can now reach `method_missing` when `respond_to_missing?` advertises the method.
- After `undef_method :initialize_copy`, `String#dup` can now reach `method_missing` when `respond_to_missing?` advertises the method.

### Remaining follow-up

- Revisit other dup/clone/copy call sites beyond `String#dup` and remove any remaining `findMethod` gates that still bypass dynamic dispatch.
- Port and run the missing lifecycle specs that cover the newly-added defaults:
- `../ruby_spec/core/kernel/initialize_copy_spec.rb`
- `../ruby_spec/core/kernel/initialize_dup_spec.rb`
- `../ruby_spec/core/kernel/initialize_clone_spec.rb`
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
- The remaining lifecycle-method sites are still worth auditing because they can silently bypass Ruby dispatch even after the default methods exist.
