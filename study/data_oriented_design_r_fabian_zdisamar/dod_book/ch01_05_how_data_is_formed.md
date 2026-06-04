# Ch. 1.5 - How Is Data Formed? (p18)

Source: [Data-Oriented Design online book, "How is data formed?"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00250000000000000000) (printed-book p18).

Summary: Turn messy input files into clean prepared arrays so repeated model work does not parse or rebuild setup data.

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

  What to notice: this row contains the values a layer calculation needs close
  together. It leaves out file names and setup-only data.

## Code Material

Fabian discusses asset/toolchain conversion rather than a standalone listing in
this section. The applicable code shape is:

```zig
pub fn loadReferenceData(allocator: Allocator) !ReferenceAssets {
    return .{
        .absorption_tables = try loadTables(allocator),
        .solar_spectrum = try loadSolar(allocator),
    };
}

pub fn prepareInput(scene: SceneInput, assets: ReferenceAssets) !PreparedInput {
    return .{
        .optical = try buildOpticalState(scene, assets),
        .rtm_config = scene.rtm_config,
    };
}
```

What to notice: loading creates `ReferenceAssets`, then `prepareInput` creates
`PreparedInput`. The later model run should use `PreparedInput` so it does not
repeat file-loading or asset-shaping work.

Zig syntax note: `return .{ ... };` builds the return struct without repeating
the struct type name. The `.optical = ...` lines set fields by name.

## Compiler Note

Chapter example tied to this note:

```zig
pub fn prepareInput(scene: SceneInput, assets: ReferenceAssets) !PreparedInput {
    return .{
        .optical = try buildOpticalState(scene, assets),
        .rtm_config = scene.rtm_config,
    };
}
```

Wrong pattern:

```zig
for (products) |_| {
    const prepared = try prepareInput(scene, assets);
    try runPrepared(prepared, storage);
}
```

Better pattern:

```zig
const prepared = try prepareInput(scene, assets);
for (products) |_| {
    try runPrepared(prepared, storage);
}
```

Why this contrast matters: the wrong version repeats setup for every product.
The better version forms the data once, then keeps the repeated run focused on
model work.

Wrong-pattern compiler artifact from
[`prepareEveryProduct`](codegen/dod_codegen_examples.zig):

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare inside the product loop
bl      _dod_codegen_examples.runPreparedForCodegen   ; run after rebuilding prepared data
subs    x19, x19, #1                                  ; count down remaining products
b.ne    LBB2_2                                        ; repeat both calls
```

What goes wrong: preparation stays inside the repeated product loop. The
compiler output shows both the prepare call and the run call on the repeated
path.

Better-pattern compiler artifact from
[`runAlreadyPreparedProducts`](codegen/dod_codegen_examples.zig):

```asm
ldp     d0, d1, [x0]                                  ; load prepared values once
bl      _dod_codegen_examples.runPreparedForCodegen   ; compute from prepared data
fadd    d1, d0, d1                                    ; repeated loop only accumulates result
b.ne    LBB5_5                                        ; repeat the cheap loop body
```

What this proves: once the input is already prepared, the repeated loop no
longer includes the prepare call.

Related compiler artifact from the repeated transform example:

```llvm
define dso_local void @fillLayerSource(
  ptr nocapture nonnull readonly align 8 %0,
  ptr nocapture nonnull writeonly align 8 %1,
  ...
)
```

What this proves: after data has been formed, the repeated function can receive
read-only prepared input and a write-only output buffer. The loader/parser is
not part of that compiled symbol.

Benchmark evidence: caller-owned reflectance output was `1.50x` faster than
allocating output on every run, with the same checksum. This supports the
chapter lesson: do setup and shape-building before the repeated run.

## zdisamar Reading Notes

- Start with [`src/input/reference_data/bundled/load.zig`](../../../src/input/reference_data/bundled/load.zig).
- Then follow preparation through [`src/root.zig`](../../../src/root.zig) and
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig).
- The loader/parser side forms data. The forward model should consume typed
  data, not files or control text.
