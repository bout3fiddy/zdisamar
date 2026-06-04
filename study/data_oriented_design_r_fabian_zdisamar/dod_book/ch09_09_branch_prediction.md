# Ch. 9.9 - Branch Prediction (p172)

Source: [Data-Oriented Design online book, "Branch prediction"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001090000000000000000) (printed-book p172).

Summary: Fabian's branch-prediction lesson is that changing answers are hard
for the CPU to guess. If many items take the same path together, the CPU can
usually do better.

His path to the rule is a small "sum if this item qualifies" example. Random
answers hurt, sorted data can help, but the simplest version may compile into
code without a real branch anyway. The process lesson is to include compiler
behavior in the story, not just CPU folklore.

Take home: If a branch inside a repeated loop is unpredictable, consider
grouping the data first. Only do that when the grouping cost is worth it.

## Main Lessons

- A branch inside a big loop is harder when the answer changes randomly.
  If the CPU guesses wrong often, it wastes work.

  ```zig
  for (rows) |row| {
      if (row.needs_scattering) try solveScattering(row);
  }
  ```

  What to notice: every row checks `row.needs_scattering`. If that value
  changes unpredictably, the CPU may guess wrong often.

  Zig syntax note: `if (row.needs_scattering) try solveScattering(row);` is a
  one-line `if`. The `try` still means an error from `solveScattering` returns
  from the current function.

- When possible, run one group for one case and another group for the other
  case.
  This can remove the branch from the inner loop.

  ```zig
  const split = partitionRows(rows, scratch);
  try solveAbsorptionRows(split.absorption);
  try solveScatteringRows(split.scattering);
  ```

  What to notice: each function receives rows that need the same path. The
  scattering decision is made before the repeated solve loop.

  Zig syntax note: `split.absorption` reads the `absorption` field from
  `split`.

- Sorting or grouping has its own cost.
  Only do it when the measured run shows that the grouping pays for itself.
  The comparison should include the cost of making the groups, not only the
  cost after the groups already exist.

## Code Material

Fabian gives a simple sum-if-data example and compares random versus sorted
branch behavior. Adapted:

```zig
fn sumSelected(flags: []const bool, values: []const i32) i32 {
    var sum: i32 = 0;
    for (flags, values) |flag, value| {
        if (flag) sum += value;
    }
    return sum;
}

fn processByScatteringNeed(rows: []const Row) void {
    const split = partitionByScatteringNeed(rows);
    solveAbsorptionRows(split.absorption);
    solveScatteringRows(split.scattering);
}
```

What to notice: `partitionByScatteringNeed` moves the decision before the
repeated solve work. Each solver receives rows for one branch of the physics.

## Practical Example

Here is a pattern that branches on each row in the repeated loop.

```zig
for (rows) |row| {
    if (row.needs_scattering) try solveScattering(row);
}
```

The compiler output below is generated machine code. It makes the per-row
`needs_scattering` flag load and branch from the code above visible.

```asm
ldrb    w10, [x8], #1  ; load one runtime flag
cbz     w10, LBB22_5   ; branch when the flag is zero
ldr     w10, [x11]     ; load value only for selected rows
add     w0, w10, w0    ; add selected value
```

The loop contains a branch whose direction depends on the runtime values of
`row.needs_scattering`.

A better approach groups rows first, then runs each group.

```zig
const split = partitionRows(rows, scratch);
try solveAbsorptionRows(split.absorption);
try solveScatteringRows(split.scattering);
```

The first version branches inside the repeated loop. The better version moves
the decision into a grouping step, then each solve loop walks one kind of row.

The generated output for the better approach is easier to read.

```asm
ldp     q4, q5, [x8, #-32]  ; load grouped values with no flag load
ldp     q6, q7, [x8], #64   ; load more grouped values and advance
add.4s  v0, v4, v0          ; add four i32 lanes
add.4s  v1, v5, v1          ; add four more i32 lanes
```

After grouping, the repeated sum loop no longer checks `row.needs_scattering`
for every row.

A related flag-selection output shows the branch directly.

```llvm
%6 = load i8, ptr %scevgep19
br i1 %.not, label %Block2, label %Then1
```

The branch remains in the repeated loop. The compiler can unroll, but it cannot
know the future `row.needs_scattering` values.

A benchmark for pre-grouped values showed summing them was `33.56x` faster
than branching on every flag, with the same checksum. Grouping setup was
excluded, so measure setup too if grouping changes every call.

## zdisamar Reading Notes

- Read [`src/forward_model/radiative_transfer/labos/execute.zig`](../../../src/forward_model/radiative_transfer/labos/execute.zig)
  for physics/config branches.
- The current code has good "avoid unnecessary work" intent, but runtime
  branching remains one of the known divergence points.
