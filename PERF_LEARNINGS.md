# Performance Learnings: `fib.rb` Experiment

## Scope and Goal

We ran a focused performance experiment on `examples/fib.rb`:

```ruby
def fib(n)
  if n == 0
    0
  elsif n == 1
    1
  else
    fib(n - 1) + fib(n - 2)
  end
end

puts fib(35)
```

Goal:
- Find a practical lower bound for runtime on this workload.
- Learn which optimization directions are likely high value for Cora proper.

---

## Baseline Measurements

Using `hyperfine --warmup 3`:

- `ruby examples/fib.rb`: **~987 ms**
- `zig-out/bin/cora examples/fib.rb`: **~3.48 s**
- `zig-out/bin/cora_lite examples/fib.rb`: **~726 ms**

`cora_lite` (final version) is ~**1.36x faster than Ruby** and ~**4.8x faster than Cora** on this narrow benchmark.

---

## Two `cora_lite` Approaches

### Approach A (early prototype, slower than Ruby)

Characteristics:
- Minimal VM with native ints and basic ops.
- AST subset compiler for this exact script shape.
- Interpreter used a more expensive representation and execution model (higher per-op/per-call overhead).

Observed outcome:
- Around **~1.05s** class execution on this machine (slightly slower than Ruby’s ~0.97s at that time).

Key takeaway:
- “Minimal” is not automatically “fast.” Data layout and loop shape dominate.

### Approach B (final prototype, faster than Ruby)

Changes vs Approach A:
- **Compact opcode stream**: opcode bytes + parallel immediate arrays.
- **Single global value stack**.
- **Tiny call frames**: `{chunk, ip, local_n, base_sp}`.
- Tight dispatch loop with less per-frame/per-op baggage.
- No extra benchmark loop in normal mode; just run-and-print.

Observed outcome:
- **~726 ms mean** in hyperfine (faster than Ruby on this workload).

Key takeaway:
- Tight data representation + tight loop architecture gave most of the speedup.

---

## What We Learned About Cora Proper

### 1) Micro-optimizations in generic call plumbing were low leverage

Attempts like:
- skipping optional/keyword/block setup paths when not used,
- minor callsite cache plumbing tweaks,
- small local-variable helper tweaks,
- frame helper refactors,

did not produce meaningful wins for `fib`.

Reason:
- They did not materially change the dominant cost structure in the hot loop.

### 2) Representation and execution model matter more than small branch edits

Big deltas came from:
- instruction encoding simplicity,
- fewer pointer-rich structures in hot path,
- low-overhead frame/value stack mechanics,
- dispatch friendliness for CPU caches/branching.

### 3) Benchmark phase separation is essential

Separating:
- parse/compile,
- execute-only,

made it clear where time is spent and avoided misleading conclusions from mixed phases.

---

## What We Learned About Zig (for this use case)

### 1) Tagged unions in tight loops can be expensive

A union-per-instruction model is ergonomic, but in hottest loops a compact opcode + immediate layout performed better.

### 2) Flat arrays and simple scalar state win

Global stack + tiny frame records outperformed heavier per-frame state and richer structures.

### 3) Keep hot-path helpers small and predictable

Inlining can help, but if underlying data/dispatch model is still heavy, inlining alone does not rescue performance.

### 4) Measure with stable harnesses

Use repeatable commands (`hyperfine`, warmups, enough runs) and avoid conflating one-time setup with steady-state execution.

---

## What We Learned About Building Tight/Fast Loops

1. Keep opcode decode cheap.
2. Minimize memory indirections in dispatch.
3. Use one value stack unless semantics require otherwise.
4. Make frames tiny and branch-light.
5. Avoid extra control layers in every call.
6. Keep hot instruction mix to primitive arithmetic/jumps where possible.

---

## Apply to Cora: Practical Suggestions

### Short-term (high confidence)

1. Add a dedicated micro-benchmark harness in-tree:
- `parse+compile` timing,
- `execute-only` timing on precompiled chunks,
- hyperfine recipes for standard scripts.

2. Introduce a “hot execution mode” experiment branch for VM internals:
- compact instruction stream for hot chunks,
- reduced frame structure for common method calls,
- single value stack discipline where semantically safe.

3. Add profile-guided counters in VM:
- opcode frequency,
- call-site monomorphism rate,
- frame push/pop counts,
- local access depth distribution.

### Medium-term (likely high payoff)

4. Specialize common call shape in Cora VM:
- no kwargs,
- no block arg conversion,
- simple positional arity,
- chunk target.

5. Explore superinstructions for recurrent patterns:
- `GET_LOCAL; PUSH_CONST; OPT_MINUS; CALL` style sequences for recursive integer workloads.

6. Revisit local/environment representation for hot methods:
- reduce depth-walk and environment pointer chasing in common depth-0 case.

### Guardrails

7. Preserve semantics first:
- visibility rules,
- method_missing behavior,
- dynamic method redefinition invalidation.

8. Require benchmark + correctness gates for each optimization PR:
- full tests,
- targeted semantic regressions,
- before/after hyperfine + perf snapshots.

---

## Bottom Line

For this benchmark, the main lesson is not “one clever callsite tweak”; it is:

**Cora likely needs structural VM hot-path simplification (instruction + frame + stack model) to get near Ruby-level performance on recursive integer-heavy workloads.**

`cora_lite` shows that with tighter loop architecture, the target is realistic.
