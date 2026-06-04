# Ch. 8.8 - Necessity, Or Not Getting What You Did Not Ask For (p154)

Source: [Data-Oriented Design online book, "Necessity"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00980000000000000000) (printed-book p154).

Summary: Carry only needed data into a loop so unused fields and optional work do not take time or memory.

## Main Lessons

- Do not put unused fields in the row used by the loop that runs many times.
  If a loop only reads two fields, make a small row for those two fields.

  ```zig
  const HotLayer = struct {
      optical_depth: f64,
      single_scatter_albedo: f64,
  };
  ```

  What to notice: this row has only the two fields the example loop needs. It
  does not carry unrelated layer data.

- Only allocate optional data when a later step will read it.
  Jacobian buffers should exist for Jacobian runs, not for every run.

  ```zig
  if (need_jacobians) {
      try storage.ensureJacobianBuffers(layer_count);
  }
  ```

  What to notice: the Jacobian buffers are created inside the `need_jacobians`
  branch. Runs without Jacobians skip them.

- If a feature is disabled, skip the data for that feature.
  An absorption-only run should not build scattering-only data.

  ```zig
  if (!config.has_scattering) {
      return solveAbsorptionOnly(input, workspace);
  }
  ```

  What to notice: the absorption-only path returns early. It does not build the
  data needed only by scattering.

  Zig syntax note: `!config.has_scattering` means "not scattering." The `!` is
  boolean negation here, not an error-return marker.

## Code Material

Fabian's section is prose. Adapted:

```zig
fn ensureJacobianStorage(storage: *ProductStorage, states: JacobianMask) !void {
    if (states.isEmpty()) {
        storage.releaseJacobians();
        return;
    }

    try storage.ensureJacobians(states.count());
}
```

What to notice: the function releases Jacobian storage when no states are
active, and only allocates it when the state mask says it will be used.

## Compiler Note

Chapter example tied to this note:

```zig
if (!config.has_scattering) {
    return solveAbsorptionOnly(input, workspace);
}
```

Wrong pattern:

```zig
for (layers) |layer| {
    if (config.has_scattering) try solveScattering(layer, workspace);
}
```

Better pattern:

```zig
if (!config.has_scattering) {
    return solveAbsorptionOnly(input, workspace);
}
for (scattering_layers) |layer| {
    try solveScattering(layer, workspace);
}
```

Why this contrast matters: the wrong version asks the same "is scattering on?"
question for every layer. The better version answers it once, then runs the
needed loop only when there is real work.

Wrong-pattern compiler artifact from
[`refreshScanAllFlags`](codegen/dod_codegen_examples.zig):

```asm
ldrb    w12, [x9], #1  ; load one per-row flag
cbz     w12, LBB16_5   ; branch around work when the flag says no
ldr     d1, [x10]      ; load data only after the branch passes
str     d1, [x11]      ; write output for the active row
```

What goes wrong: the loop carries optional-work checks row by row. If the whole
mode is off, that question should be answered before the loop starts.

Better-pattern compiler artifact from
[`refreshDirty`](codegen/dod_codegen_examples.zig):

```asm
ldp       q1, q2, [x10, #-32]  ; load dirty-row input values into vector registers
ldp       q3, q4, [x10], #64   ; load more dirty-row values and advance input pointer
fadd.2d   v1, v1, v1           ; double two f64 lanes for the refreshed value
stp       q1, q2, [x9, #-32]   ; store refreshed output values
```

What this proves: the better loop only receives rows that need work. It does
not ask each row whether optional work exists.

Related compiler artifact from the optional-storage shape:

```asm
cmp     x0, #0          ; check whether the requested work count is zero
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return the chosen size
```

What this proves: deciding "none requested" can be cheap. The bigger win is
skipping the data and loops that would have followed.

Benchmark evidence from the dirty-work example: processing only requested rows
was `4.18x` faster elapsed time than scanning all rows with flags.

## zdisamar Reading Notes

- Read optional buffer handling in
  [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig).
- Read LABOS optional local-source storage in
  [`src/forward_model/radiative_transfer/labos/orders.zig`](../../../src/forward_model/radiative_transfer/labos/orders.zig).
