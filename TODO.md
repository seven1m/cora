# TODO: Support `../natalie/test/support/spec.rb`

Prioritized by prerequisites (items earlier unblock later ones).

## 1) Compiler/parser blockers (must compile first)

- [x] Add `FloatNode` support end-to-end.
  - Evidence: `../natalie/test/support/spec.rb:23`, `../natalie/test/support/spec.rb:24`
  - Verified failure: `UnhandledNode: FloatNode` when running `cora ../natalie/test/support/spec.rb`.
- [x] Add operator-write AST support for locals (`+=`, `-=`, etc.), at least `LocalVariableOperatorWriteNode`.
  - Evidence: `../natalie/test/support/spec.rb:208` (`zone += ...`)
  - Verified failure after float stripping: `UnhandledNode: LocalVariableOperatorWriteNode`.
- [x] Add splat arguments in calls/super (`foo(*args)`, `super(*args, &block)`).
  - Evidence: `../natalie/test/support/spec.rb:797`, `../natalie/test/support/spec.rb:1077`
  - Verified failure with snippet: `def f(*a); g(*a); end` -> unsupported `.splat` node.
- [x] Add `XStringNode` / `InterpolatedXStringNode` (backtick command literals).
  - Evidence: `../natalie/test/support/spec.rb:259`, `../natalie/test/support/spec.rb:264`, `../natalie/test/support/spec.rb:480`
  - Verified failure: `UnhandledNode: XStringNode`.
- [x] Extend rescue exception-type compilation to allow dynamic expressions (e.g. ivar/class expression), not only simple constant forms.
  - Evidence: `../natalie/test/support/spec.rb:920`, `../natalie/test/support/spec.rb:946` (`rescue @klass => e`)
  - Verified failure with snippet: `unsupported exception type node`.
- [x] Add class variable support (`@@x`) end-to-end (parser/compiler/VM/runtime semantics).
  - surfaced while copying ruby/spec Array fixtures (`spec/core/array/fixtures/classes.rb` uses `@@count`)
- [ ] Add `Integer#times`.
  - surfaced while copying ruby/spec Array fixtures (`spec/core/array/fixtures/classes.rb` uses `5.times`)

## 2) Core boot/runtime globals required by this file

- [x] Implement `Kernel#__dir__` (or equivalent pseudo-variable behavior).
  - Evidence: `../natalie/test/support/spec.rb:27`
  - Verified failure: `undefined method '__dir__' for Object`.
- [x] Provide `ARGV` constant/behavior.
  - Evidence: `../natalie/test/support/spec.rb:29`
  - Verified failure: `uninitialized constant ARGV`.
- [x] Provide `ENV` object and `ENV[]` read/write behavior.
  - Evidence: `../natalie/test/support/spec.rb:120`, `../natalie/test/support/spec.rb:206`, `../natalie/test/support/spec.rb:210`
  - Verified failure: `uninitialized constant ENV`.
- [x] Provide Ruby platform/version constants used by guards:
  - `RUBY_ENGINE` (`../natalie/test/support/spec.rb:251`, `../natalie/test/support/spec.rb:1767`)
  - `RUBY_VERSION` (`../natalie/test/support/spec.rb:298`)
  - `RUBY_PLATFORM` (`../natalie/test/support/spec.rb:339`)
- [x] Provide `STDOUT` constant (and likely `STDERR` for parity).
  - Evidence: `../natalie/test/support/spec.rb:1515`
  - Verified failure: `uninitialized constant STDOUT`.

## 3) Meta-programming/method dispatch foundations

- [x] Add `method_missing` fallback dispatch when a method lookup fails.
  - Evidence: matcher DSL defines `method_missing` and relies on unknown matcher methods (`../natalie/test/support/spec.rb:509`).
  - Verified failure with snippet: class-defined `method_missing` is not invoked.
- [x] Add `Module#undef_method`.
  - Evidence: `../natalie/test/support/spec.rb:533`
  - Verified failure with snippet: `undefined method 'undef_method' for Class`.
- [x] Add `Object#define_singleton_method` and method removal support (`Module#remove_method` on singleton classes).
  - Evidence: `../natalie/test/support/spec.rb:1077`, `../natalie/test/support/spec.rb:1091`, `../natalie/test/support/spec.rb:1538`
  - Verified failure: `undefined method 'define_singleton_method' for Object`.

## 4) Reflection APIs needed by spec matchers

- [x] Add `Module/Class#constants`.
  - Evidence: `../natalie/test/support/spec.rb:1281`
  - Verified failure: `undefined method 'constants' for Class`.
- [x] Add `Module/Class#instance_methods`, `#private_instance_methods`, `#protected_instance_methods`, `#public_instance_methods`.
  - Evidence: `../natalie/test/support/spec.rb:1337`, `../natalie/test/support/spec.rb:1356`, `../natalie/test/support/spec.rb:1375`, `../natalie/test/support/spec.rb:1396`
  - Verified failure example: `private_instance_methods` missing.
- [x] Add `Object#methods` and `#private_methods`.
  - Evidence: `../natalie/test/support/spec.rb:1299`, `../natalie/test/support/spec.rb:1318`
- [x] Add `Module/Class#ancestors`.
  - Evidence: `../natalie/test/support/spec.rb:588`

## 5) Core builtin methods used by this support file

- [x] Add `Object#tap`.
  - Evidence: `../natalie/test/support/spec.rb:1534`, `../natalie/test/support/spec.rb:1587`, `../natalie/test/support/spec.rb:1614`
  - Verified failure: `undefined method 'tap' for Object`.
- [ ] Add missing `Array` methods used here: `reverse_each`, `prepend`, `find`, `empty?`, `none?`, `concat`.
  - Evidence: `../natalie/test/support/spec.rb:86`, `../natalie/test/support/spec.rb:1070`, `../natalie/test/support/spec.rb:1078`, `../natalie/test/support/spec.rb:1127`
  - Verified failure example: `reverse_each` missing.
- [ ] Add missing `Hash` methods used here: `key?`, `clear`, `dup`.
  - Evidence: `../natalie/test/support/spec.rb:966`, `../natalie/test/support/spec.rb:1095`, `../natalie/test/support/spec.rb:1099`
  - Verified failures for all three.
- [ ] Add missing `String` methods used here: `delete_prefix`, `delete_suffix!`, `gsub`, `scan`.
  - Evidence: `../natalie/test/support/spec.rb:277`, `../natalie/test/support/spec.rb:292`, `../natalie/test/support/spec.rb:1046`, `../natalie/test/support/spec.rb:720`
  - Verified failures for `delete_prefix`, `gsub`, `scan`.
- [ ] Add `Integer#to_int`.
  - Evidence: `../natalie/test/support/spec.rb:1614`
- [ ] Add regex match operators as used by this file (`String#=~`, `String#!~`, and/or matching Ruby-compatible operator behavior).
  - Evidence: `../natalie/test/support/spec.rb:498`, `../natalie/test/support/spec.rb:506`, `../natalie/test/support/spec.rb:339`
  - Verified failure: `undefined method '=~' for String`.

## 6) Host/OS integration used by helper behaviors

- [x] Provide minimal `File` support used directly by this file.
  - Evidence: `../natalie/test/support/spec.rb:27`, `../natalie/test/support/spec.rb:265`, `../natalie/test/support/spec.rb:268`, `../natalie/test/support/spec.rb:291`
- [ ] Provide minimal `Tempfile` support used directly by this file.
  - Evidence: `../natalie/test/support/spec.rb:265`, `../natalie/test/support/spec.rb:268`
  - Verified failure: `uninitialized constant Tempfile`.
- [ ] Provide `Signal.list` used for exit-status decoding.
  - Evidence: `../natalie/test/support/spec.rb:277`
  - Verified failure: `uninitialized constant Signal`.
- [ ] Provide minimal `Process.uid` / `Process.euid`.
  - Evidence: `../natalie/test/support/spec.rb:372`, `../natalie/test/support/spec.rb:376`, `../natalie/test/support/spec.rb:380`
  - Verified failure: `uninitialized constant Process`.
- [ ] Provide minimal `Thread` API used by matcher (`Thread.new`, `status`, `kill`, `join`, `value`, `.pass`).
  - Evidence: `../natalie/test/support/spec.rb:615`, `../natalie/test/support/spec.rb:629`
  - Verified failure: `uninitialized constant Thread`.
- [x] Backtick execution should update `$?` with process status semantics expected by this file.
  - Evidence: backticks + `$?.exitstatus` check in `../natalie/test/support/spec.rb:259`, `../natalie/test/support/spec.rb:280`

## 7) Cleanup

- [ ] Audit all exception raising code and make one or more helpers to look up class and format message
- [ ] Audit all argument count checking code and use existing helpers -- make a new helper if needed
