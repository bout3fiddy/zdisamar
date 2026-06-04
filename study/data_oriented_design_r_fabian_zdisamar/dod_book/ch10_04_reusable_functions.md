# Ch. 10.4 - Reusable Functions (p186)

Source: [Data-Oriented Design online book, "Reusable functions"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001140000000000000000) (printed-book p186).

Summary: Fabian argues that simple data shapes make functions accidentally
reusable. If different data can be presented in the same shape, the same
transform can often work on it.

The process lesson comes from languages and databases. Some languages make a
function's inputs and outputs clear from its type, and databases can optimize
many different queries because tables have regular shapes. Reusable functions
emerge from that regularity.

Take home: Write small functions around simple lists, counts, and tables. The
less a function knows about the larger program, the easier it is to reuse.

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

  Notice that `sum` only needs a read-only slice of numbers. That makes it
  easy to reuse.

- Do not pass a large object when the function only needs one array.
  Passing the slice makes the dependency obvious.

  ```zig
  fn maxValue(values: []const f64) f64 {
      return std.mem.max(f64, values);
  }
  ```

  Notice that `maxValue` does not need to know whether the numbers came
  from layers, wavelengths, or residuals. It only needs the slice.

- Put inputs and outputs in the function signature.
  The caller can see that `input` is read and `output` is written.

  ```zig
  fn fillOutput(input: []const f64, output: []f64) void {
      for (input, output) |value, *dst| dst.* = value;
  }
  ```

  Notice that `input` is read-only and `output` is writable. The signature
  explains the direction of data movement.


## Code Material

Fabian's section is prose. Adapted:

```zig
fn lowerBound(values: []const f64, needle: f64) usize {
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        // The search needs only the sorted values slice.
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) low = mid + 1 else high = mid;
    }
    return low;
}

fn integrateWeighted(values: []const f64, weights: []const f64) f64 {
    var sum: f64 = 0;
    // Matching slices keep the loop independent of caller-specific types.
    for (values, weights) |value, weight| sum += value * weight;
    return sum;
}
```

Notice that both functions work on slices, not on a large model object.
That is why they can be reused wherever the data can be presented as slices.

## Practical Example

Here is a pattern that ties a small search helper to a large model object.

```zig
fn lowerBoundInModel(model: *const FullModel, needle: f64) usize
```

The compiler output below is generated machine code. It makes the model-object
loads from the code above visible.

```asm
ldr     x9, [x0, #8]          ; load model.len from the model object
ldr     x8, [x8]              ; load model.values from the model object
ldr     d1, [x8, x10, lsl #3] ; load values[mid]
fcmp    d1, d0                ; compare values[mid] with the needle
```

This shows that the helper is tied to the larger model shape before it can do
the slice search.

A better approach accepts only the sorted values it needs.

```zig
fn lowerBound(values: []const f64, needle: f64) usize
```

The first helper can only be used by callers that have a `FullModel`. The
better helper works for any caller that can provide a sorted slice of numbers.

The generated output for the better approach is easier to read.

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

The helper works on the slice it was given. It does not need a large model
object.

A benchmark for prepared prefix starts showed they were `2039.62x` faster
than re-summing counts for every query, with the same checksum.

## zdisamar Reading Notes

- Read small data-changing functions in
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig)
  and [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- Prefer reusable functions whose input/output slices make cost and ownership
  obvious.
