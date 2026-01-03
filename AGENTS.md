# Clara Interpreter - Agent Context Guide

## Project Overview

Clara is a Ruby interpreter written in Zig that uses the Prism parser (Ruby's official parser) for AST generation and performs direct AST walking evaluation.

**Key Command:**
```bash
./zig-out/bin/clara --ast -e ':hello'  # View AST for Ruby code
```

## Architecture

### Core Files

- `src/prism.zig` - Zig wrapper around Prism C library (Parser struct, typed Node union)
- `src/main.zig` - Entry point, handles CLI args (`-e` for code, `--ast` for AST output)
- `src/value.zig` - Value type definition (discriminated union with variants: string, integer, nil, symbol)
- `src/interpreter.zig` - Main interpreter with eval() method and helper functions
- `src/interpreter_test.zig` - Integration tests
- `src/value_test.zig` - Unit tests for Value type

### Value Type Structure

Value holds all Ruby values we support. Check out value.zig.

**Important:** Always call `defer interpreter.deinit()` after creating an interpreter to clean up memory.

## Adding New Ruby Features

### Pattern for Adding New Value Types

1. Add variant to `Value.data` union in `value.zig`
2. Add factory method in `Value` struct
3. Add case handling in `Interpreter.eval()` for the corresponding PM_*_NODE
4. Update `evalPuts()` switch statement to handle output
5. Add tests

### Pattern for Adding New Methods (like `puts`)

1. Check method name in `evalCall()`
2. Implement evaluation function (e.g., `evalPuts()`)
3. Handle all Value variants in switch statement
4. Add tests with StringWriter for output verification

### Handling Prism Nodes

The `prism.Node` is a tagged union with variants for each node type (`.string`, `.integer`, `.symbol`, `.call`, etc.). Use switch statements to dispatch:

```zig
switch (node) {
    .string => |string_node| { ... },
    .integer => |int_node| { ... },
    .symbol => |symbol_node| { ... },
    // etc.
}
```

Access node properties via the typed pointer (e.g., `string_node.unescaped`, `call_node.name`).

## Memory Management

### String Interning for Symbols

Symbols are stored in a `StringHashMap(void)` on the Interpreter. Keys are owned by the allocator:

```zig
// Check if exists
if (self.symbols.get(symbol_str)) |_| {
    return Value.symbol(symbol_str);
}

// Add new
const interned = self.allocator.dupe(u8, symbol_str) catch "";
self.symbols.put(interned, {}) catch {};
```

### Cleanup

The `deinit()` method must free all interned strings:

```zig
pub fn deinit(self: *Interpreter) void {
    var it = self.symbols.keyIterator();
    while (it.next()) |key_ptr| {
        self.allocator.free(key_ptr.*);
    }
    self.symbols.deinit();
}
```

## Testing Patterns

### Value Tests
Simple unit tests that create values and check properties.

### Interpreter Tests
Use `StringWriter` to capture output:

```zig
var string_writer = StringWriter.init(allocator);
defer string_writer.deinit();

var parser = try prism.Parser.init(allocator, ruby_code);
defer parser.deinit();

var interpreter = Interpreter.initWithWriter(allocator, &parser, createOutputWriter(&string_writer));
defer interpreter.deinit();

if (parser.root()) |root_node| {
    _ = interpreter.eval(root_node);
}
try std.testing.expectEqualSlices(u8, string_writer.getOutput(), "expected\n");
```

**Always defer parser, interpreter, and string_writer deinit.**

## Build Commands

```bash
zig build          # Build executable
zig build test     # Run all tests
```

## Ruby Language Features Already Implemented

- String literals: `"hello"`
- Integer literals: `42`, `-123`
- Symbols: `:hello` (with interning)
- Method calls: `puts` method
- Programs with multiple statements

## Useful Ruby to Prism Knowledge

- `puts :symbol` outputs the symbol name without `:` prefix
- Symbols are immutable and interned (same name = same object_id)
- Prism marks symbols with `PM_NODE_FLAG_STATIC_LITERAL` flag
- Symbol encoding flags track forced encoding (UTF-8, BINARY, US-ASCII)
