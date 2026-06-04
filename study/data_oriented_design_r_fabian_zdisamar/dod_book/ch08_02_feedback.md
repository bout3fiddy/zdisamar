# Ch. 8.2 - Feedback (p138)

Source: [Data-Oriented Design online book, "Feedback"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00920000000000000000) (printed-book p138).

Summary: Fabian's feedback lesson is that measurements must arrive soon enough
and must measure the right thing. Broad averages can hide the exact failure you
need to fix.

The experience behind the lesson is partly tool failure. Some third-party game
engines exposed only broad CPU, graphics, physics, or rendering numbers, and
their profilers could be incomplete or missing from release builds. Fabian also
uses latency stories from Amazon, Google, and trading systems to show why the
measured resource must match the real limit.

Take home: Put measurements around the specific part you care about, and record
enough context to explain the number. A timing without the amount of work often
tells only half the story.

## Main Lessons

- Time the part you are trying to improve.
  If radiance filling is the concern, put the timing around radiance filling,
  not around the whole program.

  ```zig
  const zone = trace.begin(.fill_radiance);
  defer zone.end();
  try fillRadiance(plan, storage);
  ```

  Notice that the trace starts before `fillRadiance` and ends when the
  function returns. The measured phase is exactly the radiance-fill phase.


- Record counts that help explain the timing.
  A run with more forward misses should usually cost more, so record that count.

  ```zig
  telemetry.count(.forward_misses, plan.miss_count);
  telemetry.count(.nominal_wavelengths, plan.rows.len);
  ```

  Notice that the timing can now be read together with the amount of work:
  number of misses and number of nominal wavelengths.

- Make slow runs easy to notice.
  If a phase goes over budget, record that as its own event.

  ```zig
  if (elapsed_ns > budget_ns) {
      telemetry.count(.product_budget_miss, 1);
  }
  ```

  Notice that the run records a separate event only when it misses the
  budget. Slow cases are easier to find later.

## Practical Example

Here is a pattern that records elapsed time without the size of the work.

```
bench integrate elapsed_ns=28061000
```

This shows that the timing has no scale. It says time passed, but not how many
items were processed, how many iterations ran, or whether the result still
matches the baseline.

A better approach records the workload and the correctness signal with the
timing.

```
bench integrate_linear_search items=512 iterations=30 elapsed_ns=28061000 ns_per_item=1826.888 checksum=3113100.000
bench integrate_prepared_indexes items=512 iterations=30 elapsed_ns=34917 ns_per_item=2.273 checksum=3113100.000
```

The first line says time elapsed, but not how much work produced that time. The
better lines include rows, iterations, and checksum, so the feedback can explain
the speed difference.

Useful feedback is not just time. It also records how much work was done. Here
the same 512 rows and same checksum make the `803.65x` speedup meaningful.

## zdisamar Reading Notes

- In [`src/input/o2a_reference/run.zig`](../../../src/input/o2a_reference/run.zig),
  note how preparation phases are separately traced.
- In forward-model code, prefer adding feedback surfaces before claiming a data
  layout is faster.
