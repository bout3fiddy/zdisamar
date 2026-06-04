# Ch. 3 - Existential Processing (p57)

Source: [Data-Oriented Design online book, "Existential Processing"](https://www.dataorienteddesign.com/dodbook/node4.html) (printed-book p57).

Summary: Fabian's idea is to stop asking "should I process this?" for every
item. If something appears in the work list, that should already mean it is
valid and needs work.

This is one of the few places where Fabian is explicit about his own path. He
describes the chapter's way of handling different kinds of work at runtime as
the first data-oriented-friendly solution he discovered, and connects it to
component systems and graphics-style batch processing.

Take home: Use lists to represent requested work. An empty list means there is
nothing to do; a non-empty list tells the program exactly what to process.

## Main Lessons

- A row in a list can mean "this work is active."
  If `active_jacobians` contains a state, the code computes that Jacobian. If
  the list is empty, there is no Jacobian work to do.

  ```zig
  for (active_jacobians) |state| {
      try fillJacobian(state, storage);
  }
  ```

  What to notice: there is no `if (state.enabled)` inside the loop. Being in
  `active_jacobians` already means the work is enabled.

- Do not make every layer carry data for rare work.
  Add a row only when that rare work is actually requested.

  ```zig
  if (need_jacobians) {
      try active_jacobians.append(.surface_pressure);
  }
  ```

  What to notice: the row is added only when Jacobians are requested. Normal
  runs do not carry that extra work list.

- Be strict about what an empty list means.
  In this example, an empty Jacobian list means no Jacobian buffers are needed.

  ```zig
  if (active_jacobians.len == 0) {
      storage.releaseJacobianBuffers();
  }
  ```

  What to notice: the code treats "no rows" as "no Jacobian buffers." That keeps
  the meaning of the list clear.

## Code Material

Fabian's chapter uses health/regeneration examples. Adapted to Zig:

```zig
const ActiveDerivative = struct {
    layer_index: usize,
    state: JacobianState,
};

fn fillJacobians(active: []const ActiveDerivative, out: []JacobianRow) void {
    for (active, out) |derivative, *row| {
        row.* = computeDerivative(derivative.layer_index, derivative.state);
    }
}
```

What to notice: the row existing in `active` means "this derivative must be
computed". The loop does not need another enabled flag.

## Practical Example

Here is a pattern that stores every possible Jacobian state and checks an
enabled flag for each one.

```zig
for (jacobian_states) |state| {
    if (state.enabled) try fillJacobian(state, storage);
}
```

The compiler output below is generated machine code. It makes the enabled-flag
load and branch from the code above visible.

```asm
ldrb    w12, [x9], #1  ; load one enabled/dirty flag
cbz     w12, LBB16_5   ; branch around the work when the flag is zero
ldr     d1, [x10]      ; load the value only after the flag passes
str     d1, [x11]      ; write the refreshed output
```

Every row carries an `enabled` flag into the loop. The compiler has to keep the
flag load and branch.

A better approach stores only Jacobian states that need work.

```zig
for (active_jacobians) |state| {
    try fillJacobian(state, storage);
}
```

The first loop asks every possible state whether it should run. The better loop
receives the states to run, so row membership already means "do this work."

The generated output for the better approach is easier to read.

```asm
ldp       q1, q2, [x10, #-32]  ; load dirty-row input values into vector registers
ldp       q3, q4, [x10], #64   ; load more dirty-row values and advance input pointer
fadd.2d   v1, v1, v1           ; double two f64 lanes for the refreshed value
stp       q1, q2, [x9, #-32]   ; store refreshed output values
```

The better loop walks only rows that were already selected as work. There is no
per-row flag load and no branch around the work.

A related compiler output for optional storage shows that the presence check
can stay outside the row loop.

```llvm
define dso_local i64 @ensureJacobianStorage(i64 %0, i64 %1)
```

The matching machine code keeps the presence check outside any row loop.

```asm
cmp     x1, x0          ; compare capacity with requested state count
csel    x8, x1, x0, hi  ; keep capacity if it is larger, otherwise use count
cmp     x0, #0          ; check whether there are zero requested states
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return chosen size
```

A zero requested-state check can compile to a few compare/select instructions.
The expensive part is not the decision; the expensive part is carrying optional
buffers and loops when no Jacobian state needs work.

A benchmark for requested-state lists showed processing only requested rows was
`4.18x` faster elapsed time than scanning all rows with flags.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig)
  around active Jacobian storage.
- Read [`src/forward_model/jacobian/root.zig`](../../../src/forward_model/jacobian/root.zig)
  for the compact supported-state mask.
- The current code is partly existential: optional storage is gated, but some
  per-layer structs still carry fixed derivative lanes.
