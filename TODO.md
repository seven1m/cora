# Cora Ruby Interpreter - TODO for ruby/spec Compatibility

## Overview

This document tracks language features needed to run ruby/spec tests instead of our custom Zig tests. Currently, ruby/spec files cannot even be parsed/compiled due to missing syntax and language features.

**Reference Spec Analyzed:** `../ruby_spec/language/block_spec.rb`

## Critical Path to ruby/spec Support

### Phase 1: Core Data Structures (Required for ANY spec file)

#### 1. Hash Literals ⭐ **CRITICAL**
**Status:** Not implemented
**Prism Support:** ✅ `PM_HASH_NODE`
**Blocker Level:** 🔴 Critical - Hashes are pervasive in Ruby code

**Syntax needed:**
```ruby
{x: 9}                    # Symbol key syntax
{"a" => 10}               # String key with hash rocket
{a: 1, "b" => 2}          # Mixed syntax
{}                        # Empty hash
```

**Implementation tasks:**
- [ ] Add `hash: *HashNode` to `Node` union in `src/prism.zig`
- [ ] Add `HashObject` to `Value.data` union in `src/value.zig`
- [ ] Implement `HashObject` structure with key-value storage (likely using HashMap)
- [ ] Add hash compilation in `src/compiler.zig`
- [ ] Add `PUSH_HASH` opcode to `src/bytecode.zig`
- [ ] Implement hash VM execution in `src/vm.zig`
- [ ] Add builtin hash methods: `[]`, `[]=`, `keys`, `values`, `each`, etc.

#### 2. Proc and Lambda ⭐ **CRITICAL**
**Status:** Not implemented (blocks exist, but not as first-class objects)
**Prism Support:** ✅ `PM_LAMBDA_NODE`
**Blocker Level:** 🔴 Critical - Testing frameworks rely on Proc objects

**Syntax needed:**
```ruby
-> { |x| x + 1 }          # Lambda literal (stabby lambda)
-> (x) { x + 1 }          # Lambda with parens
lambda { |x| x + 1 }      # Lambda method call
proc { |x| x + 1 }        # Proc literal
Proc.new { |x| x + 1 }    # Proc constructor
```

**Implementation tasks:**
- [ ] Add `lambda: *LambdaNode` to `Node` union in `src/prism.zig`
- [ ] Add `ProcObject` to `Value.data` union
- [ ] Design ProcObject structure (chunk reference, captured locals, binding)
- [ ] Compile lambda/proc literals to chunks with closure capture
- [ ] Add `PUSH_PROC` / `PUSH_LAMBDA` opcodes
- [ ] Implement `Proc#call` builtin method
- [ ] Handle proc vs lambda semantics (return behavior, arity checking)
- [ ] Implement `proc { }` and `Proc.new` global methods

#### 3. Module/Require System ⭐ **CRITICAL**
**Status:** Not implemented
**Prism Support:** ✅ (require is just a method call, but needs VM support)
**Blocker Level:** 🔴 Critical - Can't load spec framework or fixtures

**Syntax needed:**
```ruby
require 'foo'
require_relative '../spec_helper'
require_relative 'fixtures/block'
```

**Implementation tasks:**
- [ ] Design module load path system
- [ ] Implement `require` builtin method
- [ ] Implement `require_relative` builtin method
- [ ] Add loaded file tracking (prevent double-loads)
- [ ] Handle circular dependencies
- [ ] Integrate with existing file parser/compiler pipeline

### Phase 2: Advanced Block Parameters

#### 4. Splat/Rest Parameters ⭐ **HIGH PRIORITY**
**Status:** Not implemented
**Prism Support:** ✅ `PM_REST_PARAMETER_NODE`
**Blocker Level:** 🟡 High - Common in Ruby APIs

**Syntax needed:**
```ruby
def foo(*args); end        # Method rest args
{ |*a| }                   # Block rest args
{ |a, *b| }                # Mixed required + rest
{ |*a, b| }                # Rest + post args
{ |*| }                    # Anonymous rest (ignore all)
```

**Implementation tasks:**
- [ ] Add `rest_parameter: *RestParameterNode` to Node union
- [ ] Update parameter compilation to handle rest args
- [ ] Modify CallFrame locals to support variable arity
- [ ] Implement argument splatting in CALL/YIELD opcodes
- [ ] Handle array destructuring into rest args

#### 5. Optional/Default Parameters ⭐ **HIGH PRIORITY**
**Status:** Not implemented
**Prism Support:** ✅ `PM_OPTIONAL_PARAMETER_NODE`
**Blocker Level:** 🟡 High - Common pattern

**Syntax needed:**
```ruby
def foo(a=5, b=10); end    # Method optional params
{ |a=5, b=10| }            # Block optional params
{ |a, b=5, c| }            # Mixed (pre + optional + post)
```

**Implementation tasks:**
- [ ] Add `optional_parameter: *OptionalParameterNode` to Node union
- [ ] Compile default value expressions
- [ ] Add parameter count checking with defaults
- [ ] Handle argument assignment with defaults in VM
- [ ] Support complex pre/optional/post combinations

#### 6. Keyword Arguments ⭐ **MEDIUM PRIORITY**
**Status:** Not implemented
**Prism Support:** ✅ `PM_OPTIONAL_KEYWORD_PARAMETER_NODE`, `PM_REQUIRED_KEYWORD_PARAMETER_NODE`, `PM_KEYWORD_REST_PARAMETER_NODE`
**Blocker Level:** 🟠 Medium - Increasingly common in modern Ruby

**Syntax needed:**
```ruby
def foo(a:, b: 10); end          # Required + optional kwargs
def foo(**kwargs); end           # Keyword rest
{ |a, b:, c: 5, **rest| }       # All combined
def foo(**nil); end              # Disallow keywords
```

**Implementation tasks:**
- [ ] Add keyword parameter nodes to Node union
- [ ] Modify CALL opcode to handle keyword arguments
- [ ] Implement keyword argument extraction from hash
- [ ] Add keyword rest parameter collection
- [ ] Handle `**nil` (no keywords allowed)
- [ ] Implement keyword argument validation

#### 7. Block-local Variables
**Status:** Not implemented
**Prism Support:** ✅ (part of block parameters)
**Blocker Level:** 🟠 Medium - Used in careful scoping

**Syntax needed:**
```ruby
[1].each { |x; local| local = 5 }    # Semicolon syntax
{ |; a, b| }                         # No regular params
```

**Implementation tasks:**
- [ ] Parse block-local variable declarations
- [ ] Allocate separate local slots for block-local vars
- [ ] Prevent outer scope shadowing
- [ ] Ensure block-local vars don't leak to outer scope

#### 8. Nested Parameter Destructuring
**Status:** Not implemented
**Prism Support:** ✅ (Prism parses this)
**Blocker Level:** 🟢 Low - Less common, but spec uses it

**Syntax needed:**
```ruby
{ |(a, b)| }                    # Destructure single array arg
{ |(a, b), c| }                 # Multi-level destructuring
{ |a, (b, (c, d))| }           # Deep nesting
```

**Implementation tasks:**
- [ ] Parse nested parameter structures
- [ ] Generate bytecode for nested unpacking
- [ ] Call `#to_ary` for destructuring coercion
- [ ] Handle nil/missing values in destructuring

#### 9. Anonymous Block Forwarding
**Status:** Not implemented
**Prism Support:** ✅ `PM_BLOCK_PARAMETER_NODE`
**Blocker Level:** 🟢 Low - Modern Ruby feature

**Syntax needed:**
```ruby
def foo(&); bar(&); end         # Forward block without name
```

**Implementation tasks:**
- [ ] Allow `&` without parameter name
- [ ] Forward anonymous block to other methods
- [ ] Track anonymous block in CallFrame

### Phase 3: Metaprogramming & Introspection

#### 10. eval ⭐ **MEDIUM PRIORITY**
**Status:** Not implemented
**Blocker Level:** 🟠 Medium - Many specs test syntax errors with eval

**Syntax needed:**
```ruby
eval "1 + 1"
eval "proc { |x| x }"
```

**Implementation tasks:**
- [ ] Implement `eval` builtin method
- [ ] Parse and compile string at runtime
- [ ] Execute in current binding/scope
- [ ] Capture and propagate syntax errors
- [ ] Handle binding argument (optional)

**Note:** Can work around in individual specs by rewriting tests.

#### 11. defined? keyword
**Status:** Not implemented
**Prism Support:** ✅ `PM_DEFINED_NODE`
**Blocker Level:** 🟢 Low - Used for existence checks

**Syntax needed:**
```ruby
defined?(variable)
defined?(method_name)
defined?(ClassName)
```

**Implementation tasks:**
- [ ] Add `defined_node: *DefinedNode` to Node union
- [ ] Add `DEFINED` opcode
- [ ] Return string describing type or nil
- [ ] Check locals, methods, constants

### Phase 4: Additional Language Features

#### 12. String Interpolation
**Status:** Unknown
**Prism Support:** ✅ `PM_INTERPOLATED_STRING_NODE`
**Blocker Level:** 🟡 High - Very common

**Syntax needed:**
```ruby
"Hello #{name}"
"Sum: #{1 + 2}"
```

#### 13. Regular Expressions
**Status:** Not implemented
**Prism Support:** ✅ `PM_REGULAR_EXPRESSION_NODE`
**Blocker Level:** 🟠 Medium - Common in tests

**Syntax needed:**
```ruby
/pattern/
/pattern/i
=~ operator
```

#### 14. Heredocs
**Status:** Not implemented
**Prism Support:** ✅
**Blocker Level:** 🟢 Low - Can work around

**Syntax needed:**
```ruby
<<EOF
  multi-line
  string
EOF
```

#### 15. Numbered Parameters
**Status:** Not implemented
**Prism Support:** ✅ `PM_NUMBERED_PARAMETERS_NODE`
**Blocker Level:** 🟢 Low - Modern convenience feature

**Syntax needed:**
```ruby
[1, 2, 3].map { _1 * 2 }
```

#### 16. Reflection Methods
**Status:** Likely not implemented
**Blocker Level:** 🟠 Medium - Common in testing

**Methods needed:**
```ruby
respond_to?(:method_name)
method_missing
respond_to_missing?
```

## Recommended Implementation Order

### Milestone 1: Basic ruby/spec Support
1. Hash literals (required everywhere)
2. Proc/Lambda (testing framework dependency)
3. Splat parameters (common in specs)
4. Optional parameters (common pattern)
5. Module/require system (load spec files)

**Goal:** Load and run simple spec files with basic assertions.

### Milestone 2: Full Block Semantics
6. Keyword arguments
7. Block-local variables
8. Nested destructuring
9. Anonymous block forwarding

**Goal:** Pass ruby/spec language/block_spec.rb.

### Milestone 3: Metaprogramming
10. String interpolation
11. eval
12. defined?
13. Reflection methods (respond_to?, method_missing)

**Goal:** Support advanced testing patterns and error checking.

### Milestone 4: Nice-to-Have
14. Regular expressions
15. Heredocs
16. Numbered parameters

**Goal:** Full modern Ruby compatibility.

## Testing Strategy

1. **Keep existing Zig tests** - They're valuable for bootstrapping
2. **Add ruby/spec incrementally** - Start with simple specs
3. **Create bridge tests** - Small Ruby files that exercise new features
4. **Target one spec file at a time** - E.g., start with `block_spec.rb`

## Notes

- Prism parser already supports ALL these features
- Main work is in Cora's compiler and VM
- Some features (like Hash) require new runtime objects
- Others (like splat) are mainly compiler/VM changes
- Module system may need the most design work

## Progress Tracking

- [ ] Phase 1 complete (Core Data Structures)
- [ ] Phase 2 complete (Advanced Block Parameters)
- [ ] Phase 3 complete (Metaprogramming)
- [ ] Phase 4 complete (Additional Features)
- [ ] First ruby/spec file passing
- [ ] 10 ruby/spec files passing
- [ ] Full language/* specs passing
