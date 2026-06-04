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

- The input file is allowed to be messy. The repeated-run data should not be.
  A file can contain names, paths, comments, defaults, and many choices. The
  repeated calculation should receive clean arrays and small structs.

- Do parsing and setup before the repeated run.
  If the same prepared input is used many times, the repeated part should not
  parse files or rebuild tables each time. The repeated function should receive
  prepared input and reusable storage, not raw files.

- Make the runtime struct match the loop that reads it.
  If the loop reads an amount, a rate, and a group index, those should be easy
  to read together.

  ```zig
  const PreparedItem = struct {
      amount: f64,
      rate: f64,
      group_index: usize,
  };

  fn prepareItems(
      inputs: []const RawItem,
      group_indices: []const usize,
      out: []PreparedItem,
  ) void {
      for (inputs, group_indices, out) |input, group_index, *dst| {
          // Copy only the values the repeated calculation will read.
          dst.* = .{
              .amount = input.amount,
              .rate = input.rate,
              .group_index = group_index,
          };
      }
  }

  fn totalContribution(
      items: []const PreparedItem,
      group_weight: []const f64,
  ) f64 {
      var total: f64 = 0;
      for (items) |item| {
          total += item.amount * item.rate * group_weight[item.group_index];
      }
      return total;
  }

  prepareItems(raw_items, group_indices, prepared_items);
  const total = totalContribution(prepared_items, group_weight);
  ```

  Notice that `prepareItems` is where the larger input rows become smaller
  runtime rows. `totalContribution` then loops over those rows without carrying
  file names or setup-only data.

  Without `PreparedItem`, the run would receive raw input fields plus a
  separate group index, or it would recompute that index inside the repeated
  path. Preparation chooses the index once and stores it beside the values that
  use it.

## Practical Example

Here is a pattern that rebuilds prepared input for every report.

```zig
for (reports) |_| {
    const prepared = try prepareInput(request, lookups);
    try runPrepared(prepared, storage);
}
```

The compiler output below is generated machine code. It makes the repeated calls
from the code above visible.

```asm
bl      _prepareInputForCodegen  ; prepare inside the report loop
bl      _runPreparedForCodegen   ; run after rebuilding prepared data
subs    x19, x19, #1             ; count down remaining reports
b.ne    LBB2_2                   ; repeat both calls
```

This shows that preparation stays inside the repeated report loop. The
compiler output shows both the prepare call and the run call on the repeated
path.

A better approach is to prepare once, then run each report from that prepared
data.

```zig
const prepared = try prepareInput(request, lookups);
for (reports) |_| {
    try runPrepared(prepared, storage);
}
```

The first loop repeats setup for every report. The better loop forms the data
once, then keeps each repeated run focused on calculation work.

The generated output for the better approach is easier to read.

```asm
ldp     d0, d1, [x0]             ; load prepared values once
bl      _runPreparedForCodegen   ; compute from prepared data
fadd    d1, d0, d1               ; repeated loop only accumulates result
b.ne    LBB5_5                   ; repeat the cheap loop body
```

Once the input is already prepared, the repeated loop no longer includes the
prepare call.

A related compiler output from a repeated transform shows the same split between
preparation and the loop.

```llvm
define dso_local void @fillScores(
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
