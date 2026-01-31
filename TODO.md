# Cora Ruby Interpreter - TODO for ruby/spec Compatibility

## Overview

This document tracks language features needed to run ruby/spec tests instead of our custom Zig tests. Currently, ruby/spec files cannot even be parsed/compiled due to missing syntax and language features.

**Reference Spec Analyzed:** `../ruby_spec/language/block_spec.rb`

## Critical Path to ruby/spec Support

#### Splat/Rest Parameters ⭐ **HIGH PRIORITY**
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

#### Optional/Default Parameters ⭐ **HIGH PRIORITY**
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

#### Keyword Arguments ⭐ **MEDIUM PRIORITY**
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

#### Block-local Variables
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

#### Nested Parameter Destructuring
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

#### Anonymous Block Forwarding
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

#### eval ⭐ **MEDIUM PRIORITY**
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

#### defined? keyword
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

#### String Interpolation
**Status:** Unknown
**Prism Support:** ✅ `PM_INTERPOLATED_STRING_NODE`
**Blocker Level:** 🟡 High - Very common

**Syntax needed:**
```ruby
"Hello #{name}"
"Sum: #{1 + 2}"
```

#### Regular Expressions
**Status:** Not implemented
**Prism Support:** ✅ `PM_REGULAR_EXPRESSION_NODE`
**Blocker Level:** 🟠 Medium - Common in tests

**Syntax needed:**
```ruby
/pattern/
/pattern/i
=~ operator
```

#### Heredocs
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

#### Numbered Parameters
**Status:** Not implemented
**Prism Support:** ✅ `PM_NUMBERED_PARAMETERS_NODE`
**Blocker Level:** 🟢 Low - Modern convenience feature

**Syntax needed:**
```ruby
[1, 2, 3].map { _1 * 2 }
```

#### Reflection Methods
**Status:** Not implemented
**Blocker Level:** 🟠 Medium - Common in testing

**Methods needed:**
```ruby
respond_to?(:method_name)
method_missing
respond_to_missing?
```
