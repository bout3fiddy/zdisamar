# Ch. 8.8 - Necessity, Or Not Getting What You Did Not Ask For (p154)

Source: [Data-Oriented Design online book, "Necessity"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00980000000000000000) (printed-book p154).

Summary: Fabian's "necessity" lesson is to avoid carrying data that a task did
not ask for. Large objects often make code load many fields when it only needed
one or two.

The source of the lesson is C++ object practice. Classes can gather multiple
roles, inheritance can add baggage, and a method call can force the machine to
load extra object data before it even knows which data the method will need.

Take home: Give a repeated step only the fields it will use. Optional data
should exist only when a later step will actually read it.

## Main Lessons

- Do not put unused fields in the row used by the loop that runs many times.
  If a loop only reads two fields, make a small row for those two fields.

  ```zig
  const HotLayer = struct {
      optical_depth: f64,
      single_scatter_albedo: f64,
  };

  fn buildHotLayers(layers: []const Layer, out: []HotLayer) void {
      for (layers, out) |layer, *hot| {
          // Keep only the fields the scattering loop will read.
          hot.* = .{
              .optical_depth = layer.optical_depth,
              .single_scatter_albedo = layer.single_scatter_albedo,
          };
      }
  }

  fn sumScattering(hot_layers: []const HotLayer) f64 {
      var total: f64 = 0;
      for (hot_layers) |layer| {
          total += layer.optical_depth * layer.single_scatter_albedo;
      }
      return total;
  }

  fn scatteringForLayers(layers: []const Layer, hot_layers: []HotLayer) f64 {
      buildHotLayers(layers, hot_layers);
      return sumScattering(hot_layers);
  }
  ```

  Notice that `buildHotLayers` does not return a new list. It fills the
  caller-provided `hot_layers` slice, and `scatteringForLayers` passes that
  filled slice into `sumScattering`.

  The simpler-looking alternative is to pass full `Layer` rows into
  `sumScattering`. That makes the loop carry fields it never reads. `HotLayer`
  is the loop's input shape, not a replacement for the full layer description.

- Only allocate optional data when a later step will read it.
  Jacobian buffers should exist for Jacobian runs, not for every run.

  ```zig
  if (need_jacobians) {
      try storage.ensureJacobianBuffers(layer_count);
  }
  ```

  Notice that the Jacobian buffers are created inside the `need_jacobians`
  branch. Runs without Jacobians skip them.

- If a feature is disabled, skip the data for that feature.
  An absorption-only run should not build scattering-only data.

  ```zig
  if (!config.has_scattering) {
      return solveAbsorptionOnly(input, workspace);
  }
  ```

  Notice that the absorption-only path returns early. It does not build the
  data needed only by scattering.


## Code Material

The code material allocates Jacobian storage only after the requested states are
known:

```zig
fn ensureJacobianStorage(storage: *ProductStorage, states: JacobianMask) !void {
    if (states.isEmpty()) {
        // No requested states means no Jacobian buffer is needed.
        storage.releaseJacobians();
        return;
    }

    // Allocate only enough storage for the requested states.
    try storage.ensureJacobians(states.count());
}

fn solveRequestedStates(
    storage: *ProductStorage,
    states: JacobianMask,
    input: ForwardInput,
) !ProductView {
    try ensureJacobianStorage(storage, states);
    return solveForward(input, storage);
}
```

Notice that the function releases Jacobian storage when no states are
active, and only allocates it when the state mask says it will be used.
`solveRequestedStates` then runs the forward solve with the same `storage`
after it has been cleared or sized for the requested states.

## Practical Example

Here is a pattern that checks `config.has_scattering` once per layer.

```zig
for (layers) |layer| {
    if (config.has_scattering) try solveScattering(layer, workspace);
}
```

The compiler output below is generated machine code. It makes the per-row flag
load and branch from the code above visible.

```asm
ldrb    w12, [x9], #1  ; load one per-row flag
cbz     w12, LBB16_5   ; branch around work when the flag says no
ldr     d1, [x10]      ; load data only after the branch passes
str     d1, [x11]      ; write output for the active row
```

The loop repeats the same scattering check for every layer. If
`config.has_scattering` is false, none of the layers can enter
`solveScattering`, so the check should happen before the loop.

A better approach checks `config.has_scattering` once, then runs the loop that
is actually needed.

```zig
if (!config.has_scattering) {
    return solveAbsorptionOnly(input, workspace);
}
for (scattering_layers) |layer| {
    try solveScattering(layer, workspace);
}
```

The first loop asks "is scattering on?" for every layer. The better version
answers that once, then runs the scattering loop only when scattering work can
happen.

The generated output for the better approach is easier to read.

```asm
ldp       q1, q2, [x10, #-32]  ; load dirty-row input values into vector registers
ldp       q3, q4, [x10], #64   ; load more dirty-row values and advance input pointer
fadd.2d   v1, v1, v1           ; double two f64 lanes for the refreshed value
stp       q1, q2, [x9, #-32]   ; store refreshed output values
```

The better loop only receives rows that need work. It does not ask each row
whether scattering work exists.

A related compiler output for optional storage shows the same zero-work check in
a smaller form.

```asm
cmp     x0, #0          ; check whether the requested work count is zero
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return the chosen size
```

Deciding "none requested" can be cheap. The bigger win is skipping the data and
loops that would have followed.

A benchmark for requested-row lists showed processing only requested rows was
`4.18x` faster elapsed time than scanning all rows with flags.

## zdisamar Reading Notes

- Read optional buffer handling in
  [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig).
- Read LABOS optional local-source storage in
  [`src/forward_model/radiative_transfer/labos/orders.zig`](../../../src/forward_model/radiative_transfer/labos/orders.zig).
