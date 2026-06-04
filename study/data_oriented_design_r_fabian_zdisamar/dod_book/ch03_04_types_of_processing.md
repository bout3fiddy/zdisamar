# Ch. 3.4 - Types Of Processing (p66)

Source: [Data-Oriented Design online book, "Types of processing"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00440000000000000000) (printed-book p66).

Summary: Fabian groups work by how many results it can create. Some steps turn
each input into one output, some keep or drop inputs, some create many outputs,
and some create data without an input list at all.

The classification comes from stream-style processing, where the program runs
the same kind of work over a regular group of items. Once the repeated work is
clear, the next design question is simple: how many results can one input
produce?

Take home: Before choosing a data structure, ask what the step produces. Does
each input make one result, no result, or many results? The answer should shape
the storage.

## Main Lessons

- A transform is just a step that changes data.
  The simplest case is one input row producing one output row. In plain terms:
  every layer becomes one prepared layer.

  ```zig
  for (layers, out_layers) |layer, *out| out.* = prepareLayer(layer);
  ```

  Notice that the loop walks two lists together. Each input layer writes
  exactly one output layer.


- Some steps keep only the rows that pass a test.
  The output can be smaller than the input because some samples are skipped.

  ```zig
  for (samples) |sample| {
      if (sample.in_band) try kept.append(sample);
  }
  ```

  Notice that `kept` can end up shorter than `samples` because only
  in-band samples are appended.


- Some steps expand one row into many rows.
  One instrument kernel can produce several high-resolution samples, so the
  output can be larger than the input.

  ```zig
  for (kernels) |kernel| {
      try appendKernelSamples(kernel, &samples);
  }
  ```

  Notice that one `kernel` can append several items to `samples`, so the
  output list can grow faster than the input list.

## Code Material

Adapted data-changing step shapes:

```zig
fn writeOneOutputPerInput(in_rows: []const LayerInput, out_rows: []LayerOutput) void {
    // Every input row has a matching output row.
    for (in_rows, out_rows) |input, *output| output.* = solveLayer(input);
}

fn keepOnlyEnabledRows(rows: []const Candidate, kept: *ArrayList(Candidate)) !void {
    // Only enabled rows are appended to the output list.
    for (rows) |row| if (row.enabled) try kept.append(row);
}

fn appendManySamplesPerKernel(rows: []const KernelRef, samples: *ArrayList(Sample)) !void {
    // One kernel can append several samples.
    for (rows) |row| try appendKernelSamples(row, samples);
}

fn fillOutputWithoutInputRows(out: []f64, value: f64) void {
    // Output is produced without reading an input row list.
    @memset(out, value);
}
```

Notice that each function name says the input/output shape. One writes one
output per input, one may write fewer rows, one may write more rows, and one
writes output without reading input rows.


## Practical Example

Here is a pattern that filters samples and sums them in the same loop.

```zig
for (samples) |sample| {
    if (sample.in_band) sum += sample.value;
}
```

The compiler output below is generated machine code. It makes the keep/drop
flag load and branch from the code above visible.

```asm
ldrb    w10, [x8], #1  ; load one keep/drop flag
cbz     w10, LBB22_5   ; branch if this row should be skipped
ldr     w10, [x11]     ; load the value only for a kept row
add     w0, w10, w0    ; add the kept value
```

This shows that filtering and summing are mixed, so the repeated loop keeps a
branch for every row.

A better approach separates selection from summing.

```zig
const in_band_values = collectInBandValues(samples, scratch);
for (in_band_values) |value| {
    sum += value;
}
```

The first loop mixes filtering and summing. The better version makes the filter
step create a smaller list, then the sum step walks only values that will be
used.

The generated output for the better approach is easier to read.

```asm
ldp     q4, q5, [x8, #-32]  ; load grouped values with no flag array
ldp     q6, q7, [x8], #64   ; load more grouped values and advance
add.4s  v0, v4, v0          ; add four i32 lanes
add.4s  v1, v5, v1          ; add four more i32 lanes
```

Once filtering has produced a grouped value list, the sum loop does not need the
per-row keep/drop branch.

The one-output-per-input shape compiles to vector work in the transform example:

```llvm
tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> ...
```

The filter shape keeps a branch in the branch example:

```llvm
%6 = load i8, ptr %scevgep19
br i1 %.not, label %Block2, label %Then1
```

A benchmark for grouped values showed summing after grouping was `33.56x`
faster than branching on every flag, with the same checksum. Mutation,
filtering, and expansion create different machine work. The benchmark excludes
grouping setup, so include setup if the group must be rebuilt every call.

## zdisamar Reading Notes

- LABOS path selection in [`src/forward_model/radiative_transfer/labos/execute.zig`](../../../src/forward_model/radiative_transfer/labos/execute.zig)
  is a good place to ask: does this step make the same number of rows, fewer
  rows, or more rows?
- Variable-length kernel expansion in [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  is an example where one input row can make several output rows.
