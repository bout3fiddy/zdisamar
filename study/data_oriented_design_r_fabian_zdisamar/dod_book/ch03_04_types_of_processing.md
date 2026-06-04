# Ch. 3.4 - Types Of Processing (p66)

Source: [Data-Oriented Design online book, "Types of processing"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00440000000000000000) (printed-book p66).

Summary: Fabian separates transforms by output cardinality: mutation writes one
row per input row, filtering writes zero or one, emission writes zero or many,
and generation writes without input rows. Naming that shape matters because it
drives the storage choice.

The classification comes out of existential processing, compute shaders, and
map-reduce style work: once a kernel is running the same instructions over a
homogeneous contiguous set, the remaining design question is how many output
rows each input can create.

Take home: Name the kind of data change so the loop shape matches the real
output being produced. In `zdisamar`, this decides whether a stage needs fixed
slices, append lists, or count/range tables.

## Main Lessons

- A transform is just a step that changes data.
  The simplest case is one input row producing one output row. In plain terms:
  every layer becomes one prepared layer.

  ```zig
  for (layers, out_layers) |layer, *out| out.* = prepareLayer(layer);
  ```

  What to notice: the loop walks two lists together. Each input layer writes
  exactly one output layer.

  Zig syntax note: `*out` means the loop gives you a pointer to the output slot.
  `out.* = ...` stores a value into that slot.

- Some steps keep only the rows that pass a test.
  The output can be smaller than the input because some samples are skipped.

  ```zig
  for (samples) |sample| {
      if (sample.in_band) try kept.append(sample);
  }
  ```

  What to notice: `kept` can end up shorter than `samples` because only
  in-band samples are appended.

  Zig syntax note: `try kept.append(sample)` calls `append`, and if append fails
  with an allocation error, the current function returns that error.

- Some steps expand one row into many rows.
  One instrument kernel can produce several high-resolution samples, so the
  output can be larger than the input.

  ```zig
  for (kernels) |kernel| {
      try appendKernelSamples(kernel, &samples);
  }
  ```

  What to notice: one `kernel` can append several items to `samples`, so the
  output list can grow faster than the input list.

## Code Material

Adapted data-changing step shapes:

```zig
fn writeOneOutputPerInput(in_rows: []const LayerInput, out_rows: []LayerOutput) void {
    for (in_rows, out_rows) |input, *output| output.* = solveLayer(input);
}

fn keepOnlyEnabledRows(rows: []const Candidate, kept: *ArrayList(Candidate)) !void {
    for (rows) |row| if (row.enabled) try kept.append(row);
}

fn appendManySamplesPerKernel(rows: []const KernelRef, samples: *ArrayList(Sample)) !void {
    for (rows) |row| try appendKernelSamples(row, samples);
}

fn fillOutputWithoutInputRows(out: []f64, value: f64) void {
    @memset(out, value);
}
```

What to notice: each function name says the input/output shape. One writes one
output per input, one may write fewer rows, one may write more rows, and one
writes output without reading input rows.

Zig syntax note: `*ArrayList(T)` means the function receives a pointer to a
growable list, so appending inside the function changes the caller's list.

## Compiler Note

Chapter examples tied to this note:

```zig
for (layers, out_layers) |layer, *out| out.* = prepareLayer(layer);

for (samples) |sample| {
    if (sample.in_band) try kept.append(sample);
}
```

Wrong pattern:

```zig
for (samples) |sample| {
    if (sample.in_band) sum += sample.value;
}
```

Better pattern:

```zig
const in_band_values = collectInBandValues(samples, scratch);
for (in_band_values) |value| {
    sum += value;
}
```

Why this contrast matters: the wrong version mixes filtering and summing inside
one repeated loop. The better version makes the filter step create a smaller
list, then the sum step walks only values that will be used.

Wrong-pattern compiler artifact from
[`sumSelected`](codegen/dod_codegen_examples.zig):

```asm
ldrb    w10, [x8], #1  ; load one keep/drop flag
cbz     w10, LBB22_5   ; branch if this row should be skipped
ldr     w10, [x11]     ; load the value only for a kept row
add     w0, w10, w0    ; add the kept value
```

What goes wrong: filtering and summing are mixed, so the repeated loop keeps a
branch for every row.

Better-pattern compiler artifact from
[`sumGroupedValues`](codegen/dod_codegen_examples.zig):

```asm
ldp     q4, q5, [x8, #-32]  ; load grouped values with no flag array
ldp     q6, q7, [x8], #64   ; load more grouped values and advance
add.4s  v0, v4, v0          ; add four i32 lanes
add.4s  v1, v5, v1          ; add four more i32 lanes
```

What this proves: once filtering has produced a grouped value list, the sum loop
does not need the per-row keep/drop branch.

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

Benchmark evidence: grouping values before summing was `33.56x` faster than
branching on every flag, with the same checksum. This proves that the type of
transform matters: mutation, filtering, and expansion create different machine
work. The benchmark excludes grouping setup, so include setup if the group must
be rebuilt every call.

## zdisamar Reading Notes

- LABOS path selection in [`src/forward_model/radiative_transfer/labos/execute.zig`](../../../src/forward_model/radiative_transfer/labos/execute.zig)
  is a good place to ask: does this step make the same number of rows, fewer
  rows, or more rows?
- Variable-length kernel expansion in [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  is an example where one input row can make several output rows.
