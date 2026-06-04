# Ch. 8.2 - Feedback (p138)

Source: [Data-Oriented Design online book, "Feedback"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00920000000000000000) (printed-book p138).

Summary: Fabian says feedback must be immediate and about the right thing:
broad averages can hide spikes, and coarse profiling can measure the wrong
phase.

The experience behind the lesson is partly tool failure: third-party engines
often exposed only coarse CPU/GPU/physics/render budgets, and their built-in
profilers could be incomplete or unavailable in optimized publishing builds. He
also uses latency stories from Amazon, Google, and trading systems to show why
the measured resource must match the real business limit.

Take home: Put timing around the exact boundary you want to improve so the
measurement answers the right question. In `zdisamar`, trace zones and telemetry
should surround the stage under study and record counts or budget misses that
explain the timing.

## Main Lessons

- Time the part you are trying to improve.
  If radiance filling is the concern, put the timing around radiance filling,
  not around the whole program.

  ```zig
  const zone = trace.begin(.fill_radiance);
  defer zone.end();
  try fillRadiance(plan, storage);
  ```

  What to notice: the trace starts before `fillRadiance` and ends when the
  function returns. The measured phase is exactly the radiance-fill phase.

  Zig syntax note: `defer zone.end();` means "run `zone.end()` when this scope
  exits," even if the function returns early with an error.

- Record counts that help explain the timing.
  A run with more forward misses should usually cost more, so record that count.

  ```zig
  telemetry.count(.forward_misses, plan.miss_count);
  telemetry.count(.nominal_wavelengths, plan.rows.len);
  ```

  What to notice: the timing can now be read together with the amount of work:
  number of misses and number of nominal wavelengths.

- Make slow runs easy to notice.
  If a phase goes over budget, record that as its own event.

  ```zig
  if (elapsed_ns > budget_ns) {
      telemetry.count(.product_budget_miss, 1);
  }
  ```

  What to notice: the run records a separate event only when it misses the
  budget. Slow cases are easier to find later.

## Code Material

Fabian's section is prose. The corresponding code shape is narrow phase
instrumentation:

```zig
const zone = trace.begin(.fill_radiance);
defer zone.end();

try fillRadiance(product, plan, storage);
telemetry.count(.forward_misses, plan.miss_count);
```

What to notice: the timer covers one named phase, and the count records how much
work that phase did.

## Compiler Note

Chapter example tied to this note:

```zig
telemetry.count(.forward_misses, plan.miss_count);
telemetry.count(.nominal_wavelengths, plan.rows.len);
```

Wrong evidence:

```text
bench integrate elapsed_ns=28061000
```

Better evidence:

```text
bench integrate_linear_search items=512 iterations=30 elapsed_ns=28061000 ns_per_item=1826.888 checksum=3113100.000
bench integrate_prepared_indexes items=512 iterations=30 elapsed_ns=34917 ns_per_item=2.273 checksum=3113100.000
```

Why this contrast matters: the wrong line says time went somewhere, but not how
much work produced that time. The better lines include rows, iterations, and
checksum, so the feedback can explain the speed difference.

What this proves: the useful feedback is not just time. It also records how much
work was done. Here the same 512 rows and same checksum make the `803.65x`
speedup meaningful.

## zdisamar Reading Notes

- In [`src/input/o2a_reference/run.zig`](../../../src/input/o2a_reference/run.zig),
  note how preparation phases are separately traced.
- In forward-model code, prefer adding feedback surfaces before claiming a data
  layout is faster.
