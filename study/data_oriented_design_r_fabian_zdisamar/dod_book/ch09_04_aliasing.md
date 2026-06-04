# Ch. 9.4 - Aliasing (p166)

Source: [Data-Oriented Design online book, "Aliasing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001040000000000000000) (printed-book p166).

Summary: Fabian explains aliasing as uncertainty: two references might point to
the same memory. When that is possible, the compiler has to be more cautious
after a write.

Fabian makes this concrete with C and C++ examples. Copying between overlapping
memory ranges has to proceed carefully because output can affect later input,
and passing a loop limit by reference can force reloads because another pointer
might change it.

Take home: Make it obvious which data is only read and which data is written.
Avoid letting input and output secretly refer to the same storage.

## Main Lessons

- Mark input slices as read-only when the function should not change them, but
  do not treat that as a full aliasing guarantee.
  `[]const` says the function will not write through `input`. The caller still
  needs to keep `input` and `output` from overlapping when the loop depends on
  that.

  ```zig
  fn scale(input: []const f64, factor: f64, output: []f64) void {
      for (input, output) |value, *dst| dst.* = value * factor;
  }

  const scaled = scratch.scaled[0..input.len];
  scale(input, factor, scaled);
  ```

  Notice that `input` is `[]const f64`, so this function promises not to write
  through that slice. The separate `output` argument is the writable result, and
  the caller is responsible for keeping it separate from `input`. The call site
  makes that rule visible by taking output space from `scratch.scaled`.

- Do not let input and output secretly point to the same memory.
  If they overlap, a write to the output can change a value the function has not
  read yet.
  Keep the read buffer and write buffer separate, and say that rule near the
  function that writes output.

- Pass small settings directly.
  A copied setting cannot be changed through another pointer while the function
  is running.
  This is useful for small configuration values. Do not use it as an excuse to
  copy large arrays.

## Practical Example

Here is a pattern whose signature leaves input/output ownership unclear.

```zig
fn fillRatio(numerator: []f64, denominator: []f64, output: []f64) void {
    for (numerator, denominator, output) |top, bottom, *dst| {
        dst.* = if (bottom != 0.0) top / bottom else 0.0;
    }
}
```

The compiler output below is generated machine code. It makes the runtime
overlap checks from the code above visible.

```asm
sub     x9, x2, x0  ; compute distance between output and first input
cmp     x9, #64     ; check whether the slices might overlap
b.lo    LBB8_3      ; use scalar fallback if overlap is too close
sub     x9, x2, x1  ; repeat the overlap check for the second input
cmp     x9, #64     ; check whether output is too close to that input
b.lo    LBB8_3      ; use scalar fallback if this pair might overlap
```

When aliasing is possible, the compiler adds runtime overlap checks before it
can use the fast vector loop.

A better approach marks inputs read-only and states the separate-output rule.

```zig
fn fillRatio(
    numerator: []const f64,
    denominator: []const f64,
    output: []f64,
) void {
    // The caller passes an output slice that does not overlap either input.
    for (numerator, denominator, output) |top, bottom, *dst| {
        dst.* = if (bottom != 0.0) top / bottom else 0.0;
    }
}

const ratios = output[0..numerator.len];
fillRatio(numerator, denominator, ratios);
writeRatioReport(ratios);
```

The first signature does not tell the reader which slice is input and which
slice is output. The better signature marks the inputs read-only, and the
comment states the rule Fabian's aliasing section cares about: the output slice
is separate. The call site then passes the filled `ratios` slice to the next
step.

The generated output for the better approach is easier to read.

```asm
ldp     q0, q1, [x10, #-32]  ; load numerator vectors directly
ldp     q4, q5, [x11, #-32]  ; load denominator vectors directly
fdiv.2d v0, v0, v4           ; divide vector lanes
fdiv.2d v1, v1, v5           ; divide the next vector lanes
stp     q0, q1, [x9, #-32]   ; store output vectors
```

The no-alias version can enter the vector loop without the same overlap-check
setup.

A related vector-path output shows why overlap matters.

```llvm
vector.memcheck:
br i1 %conflict.rdx, label %Then.preheader13, label %vector.ph
```

`vector.memcheck` is the compiler's overlap check before the fast vector loop.
Clear read/write ownership makes that fast path easier to justify.

## zdisamar Reading Notes

- Read borrowed view and owned output boundaries in
  [`src/forward_model/instrument_grid/grid_calculation/types.zig`](../../../src/forward_model/instrument_grid/grid_calculation/types.zig).
- Read immutable profile/table borrowing in
  [`src/forward_model/optical_properties/state_build/context.zig`](../../../src/forward_model/optical_properties/state_build/context.zig).
