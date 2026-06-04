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

Start by naming the problem in observable terms. If the branch-heavy loop is
suspect, the problem is not "we should group the data." The problem is that a
measured loop is spending time on branch-heavy work, and the current cost is
known.

Make the baseline repeatable before changing code. If two unchanged runs give
very different numbers, the measurement is not stable enough to judge a change.

Change one thing, then write down what happened. The note should let a later
reader see the starting point, the change, the result, and whether the output
still matched.

## Code Material

Fabian's section is procedural rather than code-heavy. The useful material is
not a Zig snippet; it is the record left behind after an optimization attempt.
That record should say what was slow, how the original version behaved, what
change was tried, how the changed version behaved, and whether both versions
still produced the same result.

## Practical Example

This chapter does not need a code block for the practical example. The useful
material is the difference between a vague optimization note and a note that
can be checked later.

An under-specified note might say that the branch code was slow, the data was
grouped, and the result was faster. That records an opinion after the fact, but
it leaves out the starting measurement, the amount of work, the exact changed
version, and the correctness check. A reader cannot repeat it or falsify it.

The stronger record keeps the comparison together. The baseline was
`sum_selected_branchy`, with `262144` items, `1000` iterations, `146827667`
elapsed nanoseconds, `0.560` nanoseconds per item, and checksum `8387918000`.
The changed version was `sum_grouped_values`, with `131072` items, `1000`
iterations, `4374958` elapsed nanoseconds, `0.033` nanoseconds per item, and
the same checksum. The measured ratio was `33.56x`.

Now the result is tied to a problem, a baseline implementation, a changed
implementation, a measured workload, and matching output. That is the chapter
lesson. Compiler output becomes useful after the measured problem is known.

## zdisamar Reading Notes

- [`src/forward_model/work_partition.zig`](../../../src/forward_model/work_partition.zig)
  is worth reading with this section because it records why scheduling policy
  changes with workload shape.
- The study habit is to keep the problem statement, measured baseline,
  prediction, implementation, and confirmation together.
