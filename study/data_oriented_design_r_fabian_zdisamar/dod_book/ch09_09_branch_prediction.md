# Ch. 9.9 - Branch Prediction (p172)

Source: [Data-Oriented Design online book, "Branch prediction"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001090000000000000000) (printed-book p172).

Summary: Move unpredictable per-row decisions into preparation so hot loops avoid branches the CPU cannot guess well.

## Main Lessons

- A branch inside a big loop is harder when the answer changes randomly.
  If the CPU guesses wrong often, it wastes work.

  ```zig
  for (rows) |row| {
      if (row.needs_scattering) try solveScattering(row);
  }
  ```

  What to notice: every row asks the same question. If the answer changes
  unpredictably, the CPU may guess wrong often.

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

fn processByMode(rows: []const Row) void {
    const split = partitionByMode(rows);
    solveModeA(split.mode_a);
    solveModeB(split.mode_b);
}
```

What to notice: `partitionByMode` moves the decision before the repeated solve
work. Each solver receives rows for one mode.

## Compiler Note

Chapter example tied to this note:

```zig
for (rows) |row| {
    if (row.needs_scattering) try solveScattering(row);
}
```

Wrong pattern:

```zig
for (rows) |row| {
    if (row.needs_scattering) try solveScattering(row);
}
```

Better pattern:

```zig
const split = partitionRows(rows, scratch);
try solveAbsorptionRows(split.absorption);
try solveScatteringRows(split.scattering);
```

Why this contrast matters: the wrong version branches inside the repeated loop.
The better version moves the decision into a grouping step, then each solve loop
walks one kind of row.

Wrong-pattern compiler artifact from
[`sumSelected`](codegen/dod_codegen_examples.zig):

```asm
ldrb    w10, [x8], #1  ; load one runtime flag
cbz     w10, LBB22_5   ; branch when the flag is zero
ldr     w10, [x11]     ; load value only for selected rows
add     w0, w10, w0    ; add selected value
```

What goes wrong: the hot loop contains a branch whose direction depends on the
runtime flag pattern.

Better-pattern compiler artifact from
[`sumGroupedValues`](codegen/dod_codegen_examples.zig):

```asm
ldp     q4, q5, [x8, #-32]  ; load grouped values with no flag load
ldp     q6, q7, [x8], #64   ; load more grouped values and advance
add.4s  v0, v4, v0          ; add four i32 lanes
add.4s  v1, v5, v1          ; add four more i32 lanes
```

What this proves: after grouping, the repeated sum loop no longer asks the
per-row branch question.

Related compiler artifact from the flag-selection example:

```llvm
%6 = load i8, ptr %scevgep19
br i1 %.not, label %Block2, label %Then1
```

What this proves: the branch remains in the repeated loop. The compiler can
unroll, but it cannot know the future flag pattern.

Benchmark evidence: summing pre-grouped values was `33.56x` faster than
branching on every flag, with the same checksum. Grouping setup was excluded,
so measure setup too if grouping changes every call.

## zdisamar Reading Notes

- Read [`src/forward_model/radiative_transfer/labos/execute.zig`](../../../src/forward_model/radiative_transfer/labos/execute.zig)
  for physics/config branches.
- The current code has good "avoid unnecessary work" intent, but runtime
  branching remains one of the known divergence points.
