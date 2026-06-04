# Ch. 8.1 - When Should We Optimise? (p137)

Source: [Data-Oriented Design online book, "When should we optimise?"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00910000000000000000) (printed-book p137).

Summary: Fabian says optimization should start with evidence, not a hunch. A
change is premature when there is no measured problem and no clear target for
improvement.

The practical setting is production risk. If a game falls to 5 frames per
second, runs out of memory, or drains a phone battery, performance is not an
optional polish task. Fabian's process answer is to measure early enough that
features are not built on untested assumptions.

Take home: Measure the real problem before changing code. Keep the old result,
the target, and the new result so you can tell whether the change helped.

## Main Lessons

- Measure before deciding that code is slow.
  A feeling is not enough. First record how long the code takes.

  ```zig
  const start = timer.read();
  try simulateProductWithWorkspace(input, storage);
  const elapsed_ns = timer.read() - start;
  ```

  Notice that the code records the time around the actual product run. Now
  "slow" has a number attached to it.

- Write down the number you need to hit.
  This turns "too slow" into something testable.
  The target can live in a benchmark, telemetry check, or study note. It does
  not need a separate code example unless the surrounding code is measuring it.

- Keep the old result next to the new result.
  Without the old result, you cannot tell whether the change helped.

## Code Material

The code material measures the product run and records the budget miss:

```zig
const budget_ns = 2_000_000;

const start = timer.read();
// Time the product run itself, not unrelated setup or reporting.
try simulateProductWithWorkspace(input, storage);
const elapsed = timer.read() - start;

// Record the measured cost and the budget miss separately.
try telemetry.record(.product_run_ns, elapsed);
if (elapsed > budget_ns) try telemetry.record(.product_budget_miss, elapsed);
```

Notice that the code records both the actual time and the budget miss. That
makes the optimization question measurable.

## Practical Example

Here is a pattern that states a performance conclusion without evidence.

```text
caller-owned output is faster
```

This is a conclusion without the evidence that would make it checkable. The
reader cannot see what was timed, how much work ran, whether the two versions
produced the same result, or how large the difference was.

A better approach writes the benchmark so the comparison can be checked.

```text
bench fill_reflectance_caller_output items=131072 iterations=300 elapsed_ns=26615500 ns_per_item=0.677 checksum=127247609.700
bench fill_reflectance_allocate_output items=131072 iterations=300 elapsed_ns=39982000 ns_per_item=1.017 checksum=127247609.700
ratio caller_output_vs_allocate_output 1.50x
```

The first line does not say what was timed, how much work ran, or whether the
output still matched. The better lines say exactly what was timed and show that
both versions produced the same checksum.

The optimization claim is tied to a timed code region, iteration count, elapsed
time, and checksum. Without those numbers, "faster" is only a guess.

## zdisamar Reading Notes

- Read [`src/forward_model/instrumentation/trace.zig`](../../../src/forward_model/instrumentation/trace.zig)
  and [`src/forward_model/instrumentation/telemetry.zig`](../../../src/forward_model/instrumentation/telemetry.zig).
- Study any performance claim together with `benchmark/` evidence rather than
  only the code shape.
