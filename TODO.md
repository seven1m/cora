# TODO

## Show-Stoppers (Runtime Correctness / Memory Safety)

These are high-risk issues that can silently corrupt runtime behavior. Treat each as a careful, test-driven change with focused regression coverage.

### `super` resolution must not depend on mutable chunk lexical scope

- Risk:
  - Reusing method chunks while mutating `chunk.lexical_scope` can make `super` resolve against the wrong scope.
  - This can raise `NoMethodError: super called outside of method` in unrelated later calls.
- Typical symptoms:
  - A method with `super` works, then fails after singleton-class/class-body operations.
  - Failures appear order-dependent.
- Regression example:
  ```ruby
  class S < String
    def initialize(x)
      super
    end
  end

  obj = S.new("x")
  class << obj
    C = 1
  end

  # this must never fail:
  S.new("y")
  ```
- Careful implementation notes:
  - Verify both dispatch paths:
    - bytecode `CALL`
    - runtime `callMethodByName`
- Done when:
  - Repros remain stable regardless of execution order.
  - `language/super` tests pass together with singleton-class specs.
