# Cora Ruby Interpreter - TODO for ruby/spec Compatibility

## Keyword Arguments

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

## Nested Parameter Destructuring

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

## Anonymous Block Forwarding

**Syntax needed:**
```ruby
def foo(&); bar(&); end         # Forward block without name
```

**Implementation tasks:**
- [ ] Allow `&` without parameter name
- [ ] Forward anonymous block to other methods
- [ ] Track anonymous block in CallFrame

## eval

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

## defined? keyword

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

## String Interpolation

**Syntax needed:**
```ruby
"Hello #{name}"
"Sum: #{1 + 2}"
```

## Regular Expressions

**Syntax needed:**
```ruby
/pattern/
/pattern/i
=~ operator
```

## Heredocs

**Syntax needed:**
```ruby
<<EOF
  multi-line
  string
EOF
```

## Numbered Parameters

**Syntax needed:**
```ruby
[1, 2, 3].map { _1 * 2 }
```

## Reflection Methods

**Methods needed:**
```ruby
respond_to?(:method_name)
method_missing
respond_to_missing?
```
