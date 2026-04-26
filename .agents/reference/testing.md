# Testing And Debugging

## Test Commands

```bash
# pass/fail status only, no details
zig build test

# filter to tests having the word "Proc" (case sensitive)
zig build test -Dtest-filter="Proc"

# filter by name and print every test description that matched
zig build test -Dtest-filter="Proc" -Dtest-verbose
```

Tests live under `test/` including `test/core/*.zig`, `test/language/*.zig`, and integration helpers/spec runner code. When adding a new test file, add it to `test/all_test.zig`.

## Running The CLI

```bash
zig build run -- [flags] [filename]

# or
zig-out/bin/cora [flags] [filename]
```

**CLI flags:**
- `-e` - run with a code string
- `--ast` - dump Prism AST to inspect node structure
- `--dump-bytecode` - show compiled bytecode, opcodes, constants, and chunks
