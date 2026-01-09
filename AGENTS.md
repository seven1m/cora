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
- `src/value.zig` - Value type definition (discriminated union with variants: string, integer, nil, symbol, module)
- `src/interpreter.zig` - Main interpreter with eval() method and helper functions
- `src/interpreter_test.zig` - Integration tests
- `src/value_test.zig` - Unit tests for Value type
- `src/prism_test.zig` - Tests for Prism parser wrapper
- `src/main_test.zig` - Tests for CLI argument handling
- `src/binary_test.zig` - Tests for the compiled binary

### Value Type Structure

Value holds all Ruby values we support with a `frozen` flag and discriminated union `data`:

```zig
pub const ModuleValue = struct {
    name: []const u8,
    methods: std.StringHashMap(*prism.DefNode),
};

pub const Value = struct {
    frozen: bool,
    data: union(enum) {
        string: []const u8,
        integer: i64,
        nil: void,
        symbol: []const u8,
        module: *ModuleValue,
    },
    // Factory methods: nil(), frozenString(), integer(), symbol(), module()
};
```

**Important:** Always call `defer interpreter.deinit()` after creating an interpreter to clean up memory.

### Interpreter Structure

The Interpreter holds:
- `allocator` - Memory allocator
- `parser` - Prism parser instance
- `output_writer` - Custom output writer for puts
- `symbols` - StringHashMap for symbol interning (keys owned by allocator, values are empty)
- `constants` - StringHashMap for storing constant values (classes, modules, etc.)

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

Symbols are stored in a `StringHashMap(void)` on the Interpreter. Symbol names come from the AST and are long-lived, so they're not duplicated:

```zig
pub fn intern(self: *Interpreter, name: []const u8) Value {
    if (self.symbols.getEntry(name)) |entry| {
        return Value.symbol(entry.key_ptr.*);
    }
    self.symbols.put(name, {}) catch unreachable;
    return Value.symbol(name);
}
```

### Module and Constant Management

Modules and methods are stored as constants and need proper cleanup:

```zig
pub fn deinit(self: *Interpreter) void {
    self.symbols.deinit();

    // Free allocated modules
    var const_it = self.constants.valueIterator();
    while (const_it.next()) |value_ptr| {
        if (value_ptr.data == .module) {
            value_ptr.data.module.methods.deinit();
            self.allocator.destroy(value_ptr.data.module);
        }
    }
    self.constants.deinit();
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
- Method calls: `puts` built-in method
- User-defined methods: `def method_name; ... end`
- Module definitions: `module ModuleName; ... end`
- Constants: `CONSTANT = value` and reading constants
- Programs with multiple statements

## Useful Ruby to Prism Knowledge

- `puts :symbol` outputs the symbol name without `:` prefix
- Symbols are immutable and interned (same name = same object_id)
- Prism marks symbols with `PM_NODE_FLAG_STATIC_LITERAL` flag
- Symbol encoding flags track forced encoding (UTF-8, BINARY, US-ASCII)
