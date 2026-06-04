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
      inline_count: u8,
  };
  ```

  Notice that `start`, `count`, and `inline_count` describe how to read the
  kernel samples. Keeping them together helps the sample-reading loop.

- Move debug names and rarely used data away from the row used by the loop that
  runs many times.
  That loop should not pull a source name into memory if it only needs a sample
  range.

  ```zig
  const KernelDebug = struct {
      source_name: []const u8,
      build_note: []const u8,
  };
  ```

  Notice that `source_name` and `build_note` are useful for debugging, but
  not for the repeated sample loop. Keeping them elsewhere avoids loading them
  by accident.


## Code Material

Fabian references the lookup examples from Chapter 6 and gives cache-line size
reasoning. Adapted:

```zig
const KernelRef = extern struct {
    // Fields read together by the sample loop stay in this row.
    nominal_index: u32,
    side_start: u32,
    side_count: u16,
    inline_count: u8,
    flags: u8,
    inline_samples: [4]SampleRef,
};

comptime {
    // Keep the row within the intended compact size.
    assert(@sizeOf(KernelRef) <= 64);
}
```

Notice that the fields in `KernelRef` are the fields the sample-reading
loop needs together. The point is not "make every struct 64 bytes"; it is to
keep related repeated-read fields together.


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
