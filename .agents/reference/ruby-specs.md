# Ruby Specs Workflow

The repo uses both Zig tests (`*_test.zig`) and Ruby specs (`*_spec.rb`).

- Zig tests in `test/` are used for bootstrapping language features and for edge cases that are awkward or inconvenient to express in Ruby spec files.
- Ruby spec files in `spec/` come from [ruby/spec](https://github.com/ruby/spec), the community-maintained Ruby behavior suite.
- When implementing a spec, look in `../ruby_spec` for the upstream source before going to the web.
- Prefer to keep copied specs matching upstream and add only the harness glue or local expectations needed to make them work here.
