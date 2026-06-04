# Ch. 8.1 - When Should We Optimise? (p137)

Source: [Data-Oriented Design online book, "When should we optimise?"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00910000000000000000) (printed-book p137).

Summary: Measure the real slow part before changing code so optimization starts from evidence, not guesses.

## Main Lessons

- Measure before deciding that code is slow.
  A feeling is not enough. First record how long the code takes.

  ```zig
  const start = timer.read();
  try simulateProductWithWorkspace(input, storage);
  const elapsed_ns = timer.read() - start;
  ```

  What to notice: the code records the time around the actual product run. Now
  "slow" has a number attached to it.

- Write down the number you need to hit.
  This turns "too slow" into something testable.
  The target can live in a benchmark, telemetry check, or study note. It does
  not need a separate code example unless the surrounding code is measuring it.

- Keep the old result next to the new result.
  Without the old result, you cannot tell whether the change helped.

## Code Material

Fabian's section is prose. The actionable code shape is a budgeted measurement
surface:

```zig
const budget_ns = 2_000_000;

const start = timer.read();
try simulateProductWithWorkspace(input, storage);
const elapsed = timer.read() - start;

try telemetry.record(.product_run_ns, elapsed);
if (elapsed > budget_ns) try telemetry.record(.product_budget_miss, elapsed);
```

What to notice: the code records both the actual time and the budget miss. That
makes the optimization question measurable.

## Compiler Note

Chapter example tied to this note:

```zig
const start = timer.read();
try simulateProductWithWorkspace(input, storage);
const elapsed_ns = timer.read() - start;
```

Wrong evidence:

```text
caller-owned output is faster
```

Better evidence:

```text
bench fill_reflectance_caller_output items=131072 iterations=300 elapsed_ns=26615500 ns_per_item=0.677 checksum=127247609.700
bench fill_reflectance_allocate_output items=131072 iterations=300 elapsed_ns=39982000 ns_per_item=1.017 checksum=127247609.700
ratio caller_output_vs_allocate_output 1.50x
```

Why this contrast matters: the wrong line gives no boundary, no workload, no
iteration count, and no correctness signal. The better lines say exactly what
was timed and show that both versions produced the same checksum.

What this proves: the optimization claim is tied to a measured boundary,
iteration count, elapsed time, and checksum. Without those numbers, "faster" is
only a guess.

## zdisamar Reading Notes

- Read [`src/forward_model/instrumentation/trace.zig`](../../../src/forward_model/instrumentation/trace.zig)
  and [`src/forward_model/instrumentation/telemetry.zig`](../../../src/forward_model/instrumentation/telemetry.zig).
- Study any performance claim together with `benchmark/` evidence rather than
  only the code shape.
