# Ch. 8.3 - A Strategy For Optimisation (p142)

Source: [Data-Oriented Design online book, "A strategy"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00930000000000000000) (printed-book p142).

Summary: Fabian presents optimization as a repeatable process: define the
problem, measure it, analyze it, try one change, and check the result.

He borrows the process shape from outside game programming, especially
Toyota-style lean improvement: find the waste, measure it, understand it,
change it, and confirm the result. The history matters because the method is
about making improvement repeatable, not about clever local tuning.

Take home: Do not start with the fix. Start with the problem, make the baseline
repeatable, change one thing, and write down what happened.

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

## Practical Example

This section uses benchmark notes instead of Zig code because the chapter
lesson is about process evidence.

Here is a pattern that records an optimization story without enough evidence.

```text
Problem: make the branch code faster
Fix: group the data
Result: faster
```

This shows that the note records an outcome, but not the starting point, the
workload, the measured result, or the correctness check. It is hard to repeat
or falsify.

A better approach keeps the baseline implementation, changed implementation,
result, ratio, and checksum together.

```text
bench sum_selected_branchy items=262144 iterations=1000 elapsed_ns=146827667 ns_per_item=0.560 checksum=8387918000
bench sum_grouped_values items=131072 iterations=1000 elapsed_ns=4374958 ns_per_item=0.033 checksum=8387918000
ratio grouped_values_vs_branchy 33.56x
```

The first note records an opinion after the fact. The better note records the
baseline implementation, the changed implementation, workload, elapsed time,
ratio, and checksum.

The result is tied to a problem, baseline implementation, changed
implementation, and matching checksum. That is the chapter lesson. Compiler
output becomes useful after the measured problem is known.

## zdisamar Reading Notes

- [`src/forward_model/work_partition.zig`](../../../src/forward_model/work_partition.zig)
  is worth reading with this section because it records why scheduling policy
  changes with workload shape.
- The study habit is to keep the problem statement, measured baseline,
  prediction, implementation, and confirmation together.
