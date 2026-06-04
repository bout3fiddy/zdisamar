# Ch. 8.3 - A Strategy For Optimisation (p142)

Source: [Data-Oriented Design online book, "A strategy"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00930000000000000000) (printed-book p142).

Summary: Fabian's optimization strategy is procedural discipline: define the
problem in objective terms, measure reproducibly, analyze the evidence, try an
experiment, then confirm and report what happened. The point is to stop guesses
from becoming "optimizations."

Fabian borrows the process shape from outside game programming, especially
Toyota-style lean optimization: define the waste, measure it, analyze it, change
it, and confirm the result. The history matters because the method is about
making improvement repeatable, not about clever local tuning.

Take home: State the problem, measure a baseline, change one thing, and measure
again so each result teaches something. `zdisamar` study notes should keep the
baseline, change, result, and interpretation together.

## Main Lessons

- State the problem before naming the fix.
  This prevents the study from starting with a guess.

- Check that the baseline is repeatable.
  If two unchanged runs give very different numbers, the measurement is not
  stable enough to judge a code change.

- Write down the change and the result.
  This keeps the lesson useful after the details leave your head.

## Code Material

Fabian's section is procedural rather than code-heavy. No Zig example is needed
for the main idea. The useful artifact is a short note or benchmark report with:

- the problem stated without a guessed fix;
- the baseline measurement;
- the predicted result;
- the implemented change;
- the confirmed result.

## Compiler Note

This section has no code example on purpose. Benchmark evidence is the
shape of a benchmark report:

Wrong evidence:

```text
Problem: make the branch code faster
Fix: group the data
Result: faster
```

Better evidence:

```text
bench sum_selected_branchy items=262144 iterations=1000 elapsed_ns=146827667 ns_per_item=0.560 checksum=8387918000
bench sum_grouped_values items=131072 iterations=1000 elapsed_ns=4374958 ns_per_item=0.033 checksum=8387918000
ratio grouped_values_vs_branchy 33.56x
```

Why this contrast matters: the wrong note records an opinion after the fact.
The better note records the baseline, changed shape, workload, elapsed time,
ratio, and checksum.

What this proves: the result is tied to a problem, baseline, changed shape, and
matching checksum. That is the chapter lesson. Compiler output becomes useful
after the measured problem is known.

## zdisamar Reading Notes

- [`src/forward_model/work_partition.zig`](../../../src/forward_model/work_partition.zig)
  is worth reading with this section because it records why scheduling policy
  changes with workload shape.
- The study habit is to keep the problem statement, measured baseline,
  prediction, implementation, and confirmation together.
