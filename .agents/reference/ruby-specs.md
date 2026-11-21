# Ruby Specs Workflow

The repo uses both Zig tests (`*_test.zig`) and Ruby specs (`*_spec.rb`).

- Zig tests in `test/` are used for bootstrapping language features and for edge cases that are awkward or inconvenient to express in Ruby spec files.
- Ruby spec files in `spec/` come from [ruby/spec](https://github.com/ruby/spec), the community-maintained Ruby behavior suite.
- When implementing a spec, look in `../ruby_spec` for the upstream source before going to the web.
- Prefer to keep copied specs matching upstream and add only the harness glue or local expectations needed to make them work here.
- Run `ruby tools/sync_spec_todo.rb` to sync `spec/TODO.md` with `../ruby_spec` (or pass another upstream directory). It groups paths by directory, adds upstream specs, removes obsolete tracker entries, marks absent local files `[ ]`, and downgrades changed files to `[-]`. Local spec files are preserved.
- The sync script does not run specs or promote entries to `[x]`; matching files retain `[x]` only if already recorded as passing. Mark specs `[x]` after verifying that they pass.
- Specs that put version guards before `require spec_helper` need MSpec loaded first. The aggregate runner handles this; standalone runs can use `zig-out/bin/cora -I ext/mspec/lib -r mspec -e 'load ARGV.shift' spec/path_spec.rb`.
