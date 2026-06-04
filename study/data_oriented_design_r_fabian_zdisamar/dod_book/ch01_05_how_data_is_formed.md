# Ch. 1.5 - How Is Data Formed? (p18)

Source: [Data-Oriented Design online book, "How is data formed?"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00250000000000000000) (printed-book p18).

Summary: Fabian's lesson is that real project data does not stay in one neat
shape. Tools, file formats, hardware, and game features keep changing what the
data needs to represent, so a runtime layout copied from yesterday's asset
model will keep fighting the next change.

He gets there from game-engine migration history. Old texture assumptions broke
when new texture formats appeared, graphics-program changes altered how
animation data was sent to the machine, open worlds changed rendering data, and
some hardware forced data to be laid out more carefully. The lasting lesson is
that the input world keeps moving.

Take home: Do not let the outside asset or control-file shape become the runtime
shape by default. Add a preparation step that reshapes messy input around the
computations that will use it.

## Main Lessons

- The input file is allowed to be messy. The solver data should not be.
  A file can contain names, paths, comments, defaults, and many choices. The
  solver should receive clean arrays and small structs.
  In `zdisamar`, that usually means file/control input is turned into prepared
  optical data before the solver sees it.

- Do parsing and setup before the repeated run.
  If the same prepared input is used many times, the repeated part should not
  parse files or rebuild tables each time. The repeated function should receive
  prepared input and reusable storage, not raw files.

- Make the runtime struct match the loop that reads it.
  If the loop reads optical depth, single-scatter albedo, and a phase index,
  those should be easy to read together.

  ```zig
  const PreparedLayer = struct {
      optical_depth: f64,
      single_scatter_albedo: f64,
      phase_index: usize,
  };

  fn prepareLayer(input: SceneLayer, phase_index: usize) PreparedLayer {
      // Copy only the values the layer solve will read.
      return .{
          .optical_depth = input.optical_depth,
          .single_scatter_albedo = input.single_scatter_albedo,
          .phase_index = phase_index,
      };
  }

  fn layerContribution(layer: PreparedLayer, phase_weight: []const f64) f64 {
      // The later solve reads the prepared row directly.
      return layer.optical_depth *
          layer.single_scatter_albedo *
          phase_weight[layer.phase_index];
  }
  ```

  Notice that `prepareLayer` is where the larger scene layer is turned into the
  smaller row. `layerContribution` then reads that row without carrying file
  names or setup-only data.

  Without `PreparedLayer`, the solve would receive raw scene fields plus a
  separate phase index, or it would recompute that index inside the repeated
  path. Preparation chooses the index once and stores it beside the optical
  values that use it.

## Practical Example

Here is a pattern that rebuilds prepared input for every product.

```zig
for (products) |_| {
    const prepared = try prepareInput(scene, assets);
    try runPrepared(prepared, storage);
}
```

The compiler output below is generated machine code. It makes the repeated calls
from the code above visible.

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare inside the product loop
bl      _dod_codegen_examples.runPreparedForCodegen   ; run after rebuilding prepared data
subs    x19, x19, #1                                  ; count down remaining products
b.ne    LBB2_2                                        ; repeat both calls
```

This shows that preparation stays inside the repeated product loop. The
compiler output shows both the prepare call and the run call on the repeated
path.

A better approach is to prepare once, then run each product from that prepared
data.

```zig
const prepared = try prepareInput(scene, assets);
for (products) |_| {
    try runPrepared(prepared, storage);
}
```

The first loop repeats setup for every product. The better loop forms the data
once, then keeps each repeated run focused on model work.

The generated output for the better approach is easier to read.

```asm
ldp     d0, d1, [x0]                                  ; load prepared values once
bl      _dod_codegen_examples.runPreparedForCodegen   ; compute from prepared data
fadd    d1, d0, d1                                    ; repeated loop only accumulates result
b.ne    LBB5_5                                        ; repeat the cheap loop body
```

Once the input is already prepared, the repeated loop no longer includes the
prepare call.

A related compiler output from a repeated transform shows the same split between
preparation and the loop.

```llvm
define dso_local void @fillLayerSource(
  ptr nocapture nonnull readonly align 8 %0,
  ptr nocapture nonnull writeonly align 8 %1,
  ...
)
```

After data has been formed, the repeated function can receive read-only
prepared input and a write-only output buffer. The loader/parser is not part of
that compiled symbol.

## zdisamar Reading Notes

- Start with [`src/input/reference_data/bundled/load.zig`](../../../src/input/reference_data/bundled/load.zig).
- Then follow preparation through [`src/root.zig`](../../../src/root.zig) and
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig).
- The loader/parser side forms data. The forward model should consume typed
  data, not files or control text.
