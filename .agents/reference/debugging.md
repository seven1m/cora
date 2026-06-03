# Debugging Reference

## General

- Prefer evidence first: traces, targeted bytecode dumps, debugger stops, cores.
- Narrow the failing Ruby file, chunk, and opcode before changing VM logic.
- When possible, prove where a bad value first appears, not only where it crashes.

## Memory Corruption

If you see:

- object header fields unexpectedly null or garbage
- a valid object later reappearing with `class = null`
- crashes far away from the true source
- behavior that still reproduces with `GC_DONT_GC=1`

then consider memory corruption early.

### High-value checks

- Wrong runtime object allocation for a class-specific builtin type.
  - Example shape: class should allocate `WeakMapObject`, `ArrayObject`, `HashObject`, etc, but VM allocates plain `Object`.
  - Symptom: builtin `initialize` or methods cast `receiver` to a larger struct and write past the allocation.
- Object type / `object_type` mismatch.
  - Check class creation (`newClassWithType`) and allocation dispatch (`newObjectForClass`).
- Re-entrant stack hazards.
  - Any opcode or builtin that keeps live pointers/slices into VM stack storage across Ruby calls is suspect.
- Wrong struct cast on `Value.toXObject()` path.
- Copy helpers that may write past object boundaries or copy the wrong layout.

### Checklist for typed object corruption

1. Identify corrupted object kind from header.
2. Find where that Ruby class is created.
3. Check its `object_type`.
4. Check `newObjectForClass` dispatch for that type.
5. Check builtins that cast `receiver` to a typed object and write fields in `initialize`, `[]`, `[]=`, etc.
6. If a specialized object type exists in `value.zig`, verify instances of that class cannot be allocated as plain `.instance`.

### Recent example

`ObjectSpace::WeakMap.new` was allocating plain `Object` instead of `WeakMapObject`.
`WeakMap#initialize` then wrote `keys` and `values` fields past the allocation, corrupting unrelated heap objects including `Gem::Version` instances.

This kind of bug can masquerade as:

- GC bug
- stale stack bug
- random ivar corruption
- wrong call return value

Check typed allocation mismatches early.
