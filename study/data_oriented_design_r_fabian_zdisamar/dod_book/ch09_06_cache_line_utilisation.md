# Ch. 9.6 - Cache Line Utilisation (p168)

Source: [Data-Oriented Design online book, "Cache line utilisation"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001060000000000000000) (printed-book p168).

Summary: Fabian reminds readers that memory is fetched in blocks, not single
fields. When the program asks for one value, nearby values often come along for
free.

The section ties back to his animation lookup example and to a codebase that
had only partly changed its data layout. Fabian uses measurements on an i5-4430
to show that putting the right nearby value into an already-loaded memory block
can matter more than using a fancier lookup structure.

Take home: Put nearby fields to good use. Keep values together when the same
question needs them, and move rarely used details away from hot repeated rows.

## Main Lessons

- When the CPU reads memory, it reads a small block, not one field.
  Fields stored next to each other may arrive together.

- Put fields together only when the same loop reads them together.
  This keeps useful data close without making every row too large.

  ```zig
  const KernelRef = struct {
      start: u32,
      count: u16,
  };

  fn sideSamples(ref: KernelRef, samples: []const SampleRef) []const SampleRef {
      // Turn the saved range into the sample references for this kernel.
      return samples[ref.start .. ref.start + ref.count];
  }
  ```

  Notice that `sideSamples` reads `start` and `count` together. Keeping those
  fields together helps the loop that repeatedly finds kernel samples.

  Passing `start` without `count` is not enough to read a sample range. Passing
  both separately is possible, but then a caller can mix `start` from one kernel
  with `count` from another. `KernelRef` gives the loop the complete range
  descriptor.

- Move debug names and rarely used data away from the row used by the loop that
  runs many times.
  That loop should not pull a source name into memory if it only needs a sample
  range.

  ```zig
  const KernelDebug = struct {
      source_name: []const u8,
  };

  fn describeKernel(debug: KernelDebug) []const u8 {
      // Debug text is read away from the repeated sample loop.
      return debug.source_name;
  }
  ```

  Notice that `describeKernel` uses the debug row outside the repeated sample
  loop. The repeated sample loop can use `KernelRef` without carrying
  `source_name`.

  Keeping debug text in `KernelRef` would make the hot lookup row carry data it
  does not read. `KernelDebug` keeps reporting data available without putting it
  in the repeated sample path.


## Code Material

The code material keeps the fields needed to find samples in the hot row:

```zig
const KernelRef = extern struct {
    // Fields read together by the sample loop stay in this row.
    side_start: u32,
    side_count: u16,
    inline_count: u8,
    inline_samples: [4]SampleRef,
};

fn sampleRefs(ref: KernelRef, side: []const SampleRef) []const SampleRef {
    if (ref.inline_count > 0) {
        // Small kernels keep their sample references inside the row.
        return ref.inline_samples[0..ref.inline_count];
    }
    // Larger kernels keep only a range into side storage.
    return side[ref.side_start .. ref.side_start + ref.side_count];
}

comptime {
    // Keep the row within the intended compact size.
    assert(@sizeOf(KernelRef) <= 64);
}
```

Notice that `sampleRefs` reads the fields that decide where the samples live.
The point is not "make every struct 64 bytes"; it is to keep related repeated
read fields together.

The alternative is to make callers branch on inline storage versus side storage
before reading samples. `sampleRefs` keeps that branch inside the row access
code, so callers use one access path.


## Practical Example

Here is a pattern that walks full rows to read the same field from each row.

```zig
for (layers) |layer| {
    total_tau += layer.optical_depth;
}
```

The compiler output below is generated machine code. It makes the row stride
from the code above visible.

```asm
ldur    d1, [x9, #-48]  ; load one f64 field from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load the same field from the next unrolled row
add     x9, x9, #96     ; advance the row pointer by four 24-byte rows
```

This shows that unused fields are not loaded, but full row stride still
matters. The loop advances by 96 bytes to consume four `f64` values.

A better approach puts the field the loop reads repeatedly in contiguous memory.

```zig
for (optical_depths) |tau| {
    total_tau += tau;
}
```

The first version walks whatever else is stored next to `optical_depth` in each
row. The better version puts the repeatedly read field in the memory order the
loop actually reads.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

The column layout keeps the repeated reads closer together in memory.

A benchmark for the optical-depth column showed it was `1.49x` faster
than reading the same field out of full rows.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for compact kernel references.
- Read [`src/forward_model/optical_properties/state_build/state_spectroscopy.zig`](../../../src/forward_model/optical_properties/state_build/state_spectroscopy.zig)
  for fixed inline spectroscopy cache rows.
