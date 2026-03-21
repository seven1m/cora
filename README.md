# Cora Ruby Interpreter

This is a Ruby interpreter written in Zig, mostly authored by AI with some oversight from Tim.
This is both an exploration of Zig and an LLM's ability to write code where the end result is well-defined.

The goal is to get a working Ruby interpreter that can pass some or all of [ruby/spec](https://github.com/ruby/spec).

Coverage reports can be generated with `zig build test -Dcoverage`. When run from the devbox shell, this uses `kcov` and writes an HTML report to `zig-out/kcov/index.html`.

Copyright (c) 2026 Tim Morgan. Licensed MIT.
