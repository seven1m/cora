# Zig Tips

## `catch |err| switch (err) { ... }` Is Just `try`

A common anti-pattern: catching every error variant only to return/rethrow each one. This is exactly what `try` does:

```zig
// Instead of this:
_ = vm.callMethodByName(superclass_val, "inherited", inherited_args[0..], null) catch |err| switch (err) {
    error.Unwind => return err,
    else => return err,
};

// Write this:
_ = try vm.callMethodByName(superclass_val, "inherited", inherited_args[0..], null);
```

`try` propagates all error variants — whether `Unwind`, `Fatal`, or anything else.

## Tagged Union Payload Access

When switching on a tagged union like `ToAryResult`, the payload is the value directly:

```zig
const to_ary_result = try vm.probeToAry(result.value);
switch (to_ary_result) {
    .array => |ary| {
        // ary is already the Value, not a wrapper
        for (ary.toArrayObject().elements.items) |elem| { ... }
    },
    .missing, .nil_result => { ... },
}
```

## `ArrayList` Ownership

This repo uses unmanaged-style `std.ArrayList` fields initialized as `.empty`. The list does not remember an allocator, so every mutating call and `deinit()` must get the same allocator explicitly.

```zig
var out: std.ArrayList(u8) = .empty;
defer out.deinit(vm.allocator);

try out.append(vm.allocator, byte);
try out.appendSlice(vm.allocator, bytes);
```

If you need to return the contents, prefer `toOwnedSlice(allocator)` before the list is deinited.

## Match Allocator Families

Be strict about which allocator owns which memory:

- `vm.allocator` for infrastructure and temporary buffers
- `vm.gc_allocator` for GC-managed heap objects with internal pointers
- `vm.gc_allocator_atomic` for atomic byte storage like string backing buffers

Do not `free()` memory that came from a GC allocator. Do not store temp memory from `vm.allocator` into long-lived Ruby heap objects without duplicating it into the appropriate GC allocator first.

## Use `errdefer` During Partial Init

If a function allocates or duplicates owned memory and then can still fail, clean up the partial state with `errdefer`.

```zig
const owned_name = try allocator.dupe(u8, name);
errdefer allocator.free(owned_name);
```

Plain `defer` runs on success too, so it is wrong for values whose ownership is being transferred out of the function.

## Borrowed Slice Lifetimes Matter

Many strings in the compiler are borrowed, not copied.

- Parser strings are borrowed from the Prism AST.
- Constant-pool strings are usually borrowed too.
- `ArrayList.items` becomes invalid after resize or `deinit()`.

Do not return or stash a slice into a temporary buffer unless you intentionally duplicate it into owned storage first.

## Integer Casts Need Context

Modern Zig's `@intCast` relies on destination type inference. If the target type is not obvious from assignment or the call site, make it explicit with `@as(...)`.

```zig
const line: u32 = @intCast(raw_line);
const argc = @as(u8, @intCast(args.len));
```

If you skip the explicit type in ambiguous cases, the compiler error can point somewhere non-obvious.

## Prefer Small Explicit Conversions

Pointer and alignment casts are intentionally strict. When converting C pointers or interface back-pointers, use the minimal cast sequence needed and keep each step obvious.

```zig
const start_ptr: [*c]const c.OnigUChar = @ptrCast(text.ptr);
const w: *TestWriter = @alignCast(@fieldParentPtr("interface", io_w));
```

If a cast chain starts getting clever, split it into locals so alignment and constness stay readable.
