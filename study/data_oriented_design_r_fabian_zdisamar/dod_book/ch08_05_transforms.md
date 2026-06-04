# Ch. 8.5 - Transforms (p151)

Source: [Data-Oriented Design online book, "Transforms"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00950000000000000000) (printed-book p151).

Summary: Keep loading and setup outside the repeated data-changing step so the hot transform only changes prepared data.

## Main Lessons

- Keep loading separate from data-changing work.
  Loading reads files or reference tables. The next step should receive normal
  typed data and change it into the shape the model needs.
  The solver should not load files as part of its repeated math loop.

- Give the next step only the data it will read.
  This keeps the function small and makes the cost easier to see.

  ```zig
  const ctx = ForwardContext{
      .layers = prepared.layers,
      .carriers = cache.rows,
      .wavelength_nm = wavelength_nm,
  };
  ```

  What to notice: `ForwardContext` lists the data the next step needs: layers,
  carrier rows, and one wavelength.

  Zig syntax note: `const ctx = ForwardContext{ .layers = ..., ... };` creates
  a `ForwardContext` value and fills fields by name.

- Some totals can be built from smaller totals.
  If the math allows `left + right`, different chunks can be computed separately
  and combined later.

  ```zig
  const left = sumRadiance(samples[0..mid]);
  const right = sumRadiance(samples[mid..]);
  const total = left + right;
  ```

  What to notice: the final answer is made from two partial answers. That means
  the two halves can be computed separately if needed.

  Zig syntax note: `samples[0..mid]` is the first part of the slice.
  `samples[mid..]` is the rest of the slice starting at `mid`.

## Code Material

Fabian's section is prose with examples of data-changing steps. Adapted:

```zig
const PreparedContext = struct {
    layers: []const PreparedLayer,
    carriers: []const CarrierRow,
};

fn fillForwardInput(ctx: PreparedContext, wavelength_nm: f64, out: *ForwardInput) void {
    for (ctx.layers, out.layers) |layer, *dst| {
        dst.* = makeLayerInput(layer, ctx.carriers, wavelength_nm);
    }
}
```

What to notice: the function receives prepared layers and carrier rows, then
writes RTM layer input. It does not load reference files or parse scene data.

## Compiler Note

Chapter example tied to this note:

```zig
fn fillForwardInput(ctx: PreparedContext, wavelength_nm: f64, out: *ForwardInput) void {
    for (ctx.layers, out.layers) |layer, *dst| {
        dst.* = makeLayerInput(layer, ctx.carriers, wavelength_nm);
    }
}
```

Wrong pattern:

```zig
fn fillForwardInput(scene: SceneInput, assets: ReferenceAssets, wavelength_nm: f64, out: *ForwardInput) !void {
    const ctx = try prepareContext(scene, assets);
    for (ctx.layers, out.layers) |layer, *dst| {
        dst.* = makeLayerInput(layer, ctx.carriers, wavelength_nm);
    }
}
```

Better pattern:

```zig
fn fillForwardInput(ctx: PreparedContext, wavelength_nm: f64, out: *ForwardInput) void {
    for (ctx.layers, out.layers) |layer, *dst| {
        dst.* = makeLayerInput(layer, ctx.carriers, wavelength_nm);
    }
}
```

Why this contrast matters: the wrong version hides preparation inside the
transform. The better version gives the repeated transform prepared input and a
place to write.

Wrong-pattern compiler artifact from
[`prepareEveryProduct`](codegen/dod_codegen_examples.zig):

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare inside the repeated path
bl      _dod_codegen_examples.runPreparedForCodegen   ; run after rebuilding prepared data
subs    x19, x19, #1                                  ; count down repeated runs
b.ne    LBB2_2                                        ; loop back to prepare again
```

What goes wrong: the transform boundary includes setup, so the compiler keeps
the prepare call in the repeated loop.

Better-pattern compiler artifact from
[`fillLayerSource`](codegen/dod_codegen_examples.zig):

```llvm
tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> ...
```

What this proves: once loading and parsing are outside the transform, the
compiler sees numeric input and output arrays. It can generate vector arithmetic
for the repeated step.

Benchmark evidence: the related caller-owned output benchmark was `1.50x`
faster than allocating output every run, with the same checksum. That supports
making the transform step receive prepared data and storage instead of doing
setup inside the repeated work.

## zdisamar Reading Notes

- [`src/forward_model/instrument_grid/grid_calculation/forward_input.zig`](../../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig)
  is the repeated step that turns prepared optical state into RTM-ready input.
- [`src/root.zig`](../../../src/root.zig) shows the higher-level split between
  preparing data and running the model.
