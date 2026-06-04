# Ch. 10.4 - Reusable Functions (p186)

Source: [Data-Oriented Design online book, "Reusable functions"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001140000000000000000) (printed-book p186).

Summary: Small functions should accept simple arrays so they can be reused anywhere the same data shape exists.

## Main Lessons

- Small functions are easier to reuse when the input is simple.
  A function that sums a slice can be used anywhere you have a slice of numbers.

  ```zig
  fn sum(values: []const f64) f64 {
      var total: f64 = 0;
      for (values) |value| total += value;
      return total;
  }
  ```

  What to notice: `sum` only needs a read-only slice of numbers. That makes it
  easy to reuse.

- Do not pass a large object when the function only needs one array.
  Passing the slice makes the dependency obvious.

  ```zig
  fn maxValue(values: []const f64) f64 {
      return std.mem.max(f64, values);
  }
  ```

  What to notice: `maxValue` does not need to know whether the numbers came
  from layers, wavelengths, or residuals. It only needs the slice.

- Put inputs and outputs in the function signature.
  The caller can see that `input` is read and `output` is written.

  ```zig
  fn fillOutput(input: []const f64, output: []f64) void {
      for (input, output) |value, *dst| dst.* = value;
  }
  ```

  What to notice: `input` is read-only and `output` is writable. The signature
  explains the direction of data movement.

  Zig syntax note: `*dst` captures a pointer to each output slot. `dst.* = value`
  writes the input value into that output slot.

## Code Material

Fabian's section is prose. Adapted:

```zig
fn lowerBound(values: []const f64, needle: f64) usize {
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) low = mid + 1 else high = mid;
    }
    return low;
}

fn integrateWeighted(values: []const f64, weights: []const f64) f64 {
    var sum: f64 = 0;
    for (values, weights) |value, weight| sum += value * weight;
    return sum;
}
```

What to notice: both functions work on slices, not on a large model object.
That is why they can be reused wherever the data can be presented as slices.

## Compiler Note

Chapter example tied to this note:

```zig
fn lowerBound(values: []const f64, needle: f64) usize
```

Wrong pattern:

```zig
fn lowerBoundInModel(model: *const FullModel, needle: f64) usize
```

Better pattern:

```zig
fn lowerBound(values: []const f64, needle: f64) usize
```

Why this contrast matters: the wrong helper can only be used by callers that
have a `FullModel`. The better helper works for any caller that can provide a
sorted slice of numbers.

Wrong-pattern compiler artifact from
[`lowerBoundInModel`](codegen/dod_codegen_examples.zig):

```asm
ldr     x9, [x0, #8]          ; load model.len from the model object
ldr     x8, [x8]              ; load model.values from the model object
ldr     d1, [x8, x10, lsl #3] ; load values[mid]
fcmp    d1, d0                ; compare values[mid] with the needle
```

What goes wrong: the helper is tied to the larger model shape before it can do
the slice search.

Better-pattern compiler artifact from
[`lowerBound`](codegen/dod_codegen_examples.zig):

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

What this proves: the helper works on the slice it was given. It does not need a
large model object or payload table.

Benchmark evidence from reusable prepared data: prepared prefix starts were
`2039.62x` faster than re-summing counts for every query, with the same
checksum.

## zdisamar Reading Notes

- Read small data-changing functions in
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig)
  and [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- Prefer reusable functions whose input/output slices make cost and ownership
  obvious.
