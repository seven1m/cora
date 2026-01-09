# Clara Interpreter - Agent Context Guide

Clara is a Ruby interpreter written in Zig using the Prism parser for AST generation. It evaluates by walking the AST tree directly.

## Core Architecture

**Key Files:**
- `src/prism.zig` - Prism C library wrapper with typed Node union
- `src/main.zig` - CLI entry point
- `src/value.zig` - Value types and factory methods
- `src/interpreter.zig` - AST evaluation logic with eval() method

**Value Types:** String, Integer, Nil, Symbol (interned), Module, Class, Instance

**Interpreter State:**
- `call_stack: ArrayList(CallFrame)` - Stack of execution frames with self and locals
- `constants: StringHashMap(Value)` - All classes, modules, constants
- `symbols: StringHashMap(void)` - Interned symbol names

## Key Concepts

**CallFrame Stack:** Each call/method/class definition pushes a frame with `self` (receiver) and `locals`. Top-level code has `self = Object` class. Class bodies push a frame with `self = class`. Method calls push a frame with `self = instance`. This fixes the nested call bug by isolating locals per frame.

**Symbol Interning:** Symbols stored in `symbols` HashMap with names as keys. Same symbol name always returns same object.

**Method Storage:** Methods stored as DefNode pointers in class/module `.methods` HashMap. Lookup walks inheritance chain up to Object.

**Prism Nodes:** Switch statements dispatch on node type variants (.string, .integer, .symbol, .call, etc.). Access properties via typed pointers.

## Adding Features

**New Value Type:**
1. Add variant to Value union in value.zig
2. Add factory method
3. Add eval() case for corresponding PM_*_NODE
4. Update evalPuts() for output
5. Test with StringWriter to capture output

**New Method:** Add check in evalCall(), implement logic, test with output verification

## Memory

- Always `defer interpreter.deinit()` after creation
- Modules and classes need method HashMap cleanup
- Instances not explicitly tracked (use arena/GC for production)

## Implemented Ruby Features

**Basics:** String/Integer/Nil literals, Symbols (interned), Constants, Local variables

**Methods:** `puts`, user-defined methods with arguments, method calls with receivers

**OOP:** Modules, Classes, Inheritance (defaults to Object), `ClassName.new` with `initialize`, Instance method calls, `self` keyword
