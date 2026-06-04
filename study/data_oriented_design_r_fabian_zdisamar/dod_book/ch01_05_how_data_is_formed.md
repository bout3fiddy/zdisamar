# Ch. 1.5 - How Is Data Formed? (p18)

Source: [Data-Oriented Design online book, "How is data formed?"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00250000000000000000) (printed-book p18).

Summary: Fabian's lesson is that real project data keeps changing. New file
formats, tools, hardware, and features keep breaking old assumptions, so a
program needs a clear step that turns messy outside material into data it can
actually use.

He gets there from game-engine migration history. Old texture assumptions broke
when new texture formats appeared, graphics-program changes altered how
animation data was sent to the machine, open worlds changed rendering data, and
some hardware forced data to be laid out more carefully. The lasting lesson is
that the input world keeps moving.

Take home: Do setup once before repeated work starts. Turn files, settings, and
assets into clean data that later code can use without rereading or
reinterpreting them.

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
  ```

  Notice that this row contains the values a layer calculation needs close
  together. It leaves out file names and setup-only data.

## Code Material

Fabian discusses asset/toolchain conversion rather than a standalone listing in
this section. The applicable code shape is:

```zig
pub fn loadReferenceData(allocator: Allocator) !ReferenceAssets {
    // File-backed assets become reusable tables before the model runs.
    return .{
        .absorption_tables = try loadTables(allocator),
        .solar_spectrum = try loadSolar(allocator),
    };
}

pub fn prepareInput(scene: SceneInput, assets: ReferenceAssets) !PreparedInput {
    // Scene input and reference assets become RTM-ready data.
    return .{
        .optical = try buildOpticalState(scene, assets),
        .rtm_config = scene.rtm_config,
    };
}
```

Notice that loading creates `ReferenceAssets`, then `prepareInput` creates
`PreparedInput`. The later model run should use `PreparedInput` so it does not
repeat file-loading or asset-shaping work.


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

A related compiler output from a repeated transform shows the same boundary.

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

A benchmark for caller-owned reflectance output showed it was `1.50x`
faster than allocating output on every run, with the same checksum. This
supports the chapter lesson: do setup and shape-building before the repeated
run.

## zdisamar Reading Notes

- Start with [`src/input/reference_data/bundled/load.zig`](../../../src/input/reference_data/bundled/load.zig).
- Then follow preparation through [`src/root.zig`](../../../src/root.zig) and
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig).
- The loader/parser side forms data. The forward model should consume typed
  data, not files or control text.
