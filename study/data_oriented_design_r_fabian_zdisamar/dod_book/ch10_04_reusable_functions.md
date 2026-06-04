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
  A range counter can be used by validation, reporting, or alert code because
  it only asks for the values and the range.

  ```zig
  fn countInsideRange(values: []const f64, low: f64, high: f64) usize {
      var count: usize = 0;
      for (values) |value| {
          if (value >= low and value <= high) count += 1;
      }
      return count;
  }
  ```

  Notice that `countInsideRange` owns a small rule: count values inside this
  range. Any caller that can provide a numeric slice can use that rule.

- Do not pass a large object when the function only needs a few arrays.
  Passing the slices makes the dependency obvious.

  ```zig
  fn writeDeltas(previous: []const f64, current: []const f64, out: []f64) void {
      for (previous, current, out) |before, now, *dst| {
          dst.* = now - before;
      }
  }
  ```

  Notice that `writeDeltas` does not need a report object, a catalog object, or
  labels for the values. It needs two aligned input slices and one output slice.

- Put inputs and outputs in the function signature.
  The caller can see which values are read, which settings are copied, and
  which output buffer is written.

  ```zig
  fn writeNormalizedScores(
      scores: []const f64,
      mean: f64,
      inv_stddev: f64,
      out: []f64,
  ) void {
      for (scores, out) |score, *dst| {
          dst.* = (score - mean) * inv_stddev;
      }
  }

  const normalized = scratch.normalized[0..scores.len];
  writeNormalizedScores(scores, mean, inv_stddev, normalized);
  ```

  Notice that `scores` is read-only and `out` is writable. The call site shows
  where the output memory comes from, so the function does not allocate or hide
  the result.

## Practical Example

Here is a pattern that ties a small search helper to a large catalog object.

```zig
fn lowerBoundInCatalog(catalog: *const ValueCatalog, needle: f64) usize {
    var low: usize = 0;
    var high: usize = catalog.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (catalog.values[mid] < needle) low = mid + 1 else high = mid;
    }
    return low;
}
```

The compiler output below is generated machine code. It makes the catalog-object
loads from the code above visible.

```asm
ldr     x9, [x0, #8]          ; load catalog.len from the catalog object
ldr     x8, [x0]              ; load catalog.values from the catalog object
ldr     d1, [x8, x10, lsl #3] ; load values[mid]
fcmp    d1, d0                ; compare values[mid] with the needle
```

This shows that the helper is tied to the larger catalog shape before it can do
the slice search.

A better approach accepts only the sorted values it needs.

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
```

The first helper can only be used by callers that have a `ValueCatalog`. The
better helper works for any caller that can provide a sorted slice of numbers.

The generated output for the better approach is easier to read.

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

The helper works on the slice it was given. It does not need a large catalog
object.

## zdisamar Reading Notes

- Read small data-changing functions in
  [`src/forward_model/optical_properties/root.zig`](../../../src/forward_model/optical_properties/root.zig)
  and [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- Prefer reusable functions whose input/output slices make cost and ownership
  obvious.
