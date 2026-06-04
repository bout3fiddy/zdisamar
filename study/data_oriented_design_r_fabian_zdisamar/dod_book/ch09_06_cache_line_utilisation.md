# Ch. 9.6 - Cache Line Utilisation (p168)

Source: [Data-Oriented Design online book, "Cache line utilisation"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001060000000000000000) (printed-book p168).

Summary: Fabian reminds readers that memory is fetched in blocks, not single
fields. When a row must be loaded anyway, the unused bytes in that cache line
can answer common questions without another lookup.

The section ties back to his animation lookup example and to a codebase that
had only partly changed its data layout. Fabian uses measurements on an i5-4430
to show that putting the right nearby value into an already-loaded memory block
can matter more than using a fancier lookup structure.

Take home: Use nearby bytes only for information the hot path actually asks for.
Do not treat cache-line awareness as permission to pack unrelated fields into a
row.

## Main Lessons

- When the CPU reads memory, it reads a small block, not one field.
  Fields stored next to each other may arrive together.

- Use nearby bytes for answers the hot path actually asks for.
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

  Notice that `sideSamples` reads `start` and `count` together to answer the
  same question: where are this kernel's samples? Keeping those fields together
  helps the loop that repeatedly asks that question.

  Passing `start` without `count` is not enough to read a sample range. Passing
  both separately is possible, but then a caller can mix `start` from one kernel
  with `count` from another. `KernelRef` gives the loop the complete range
  descriptor.

- Do not fill the nearby bytes with unrelated data.
  Cache-line space is useful only when the hot path reads the nearby value.
  Debug text belongs somewhere else if the sample loop never asks for it.

  ```zig
  fn describeKernel(
      kernel_index: usize,
      kernel_source_names: []const []const u8,
  ) []const u8 {
      // Debug text is read away from the repeated sample loop.
      return kernel_source_names[kernel_index];
  }
  ```

  Notice that `describeKernel` reads the source-name table outside the repeated
  sample loop. The repeated sample loop can use `KernelRef` without carrying
  `source_name`.

  Keeping debug text in `KernelRef` would make the hot lookup row carry data it
  does not read. A separate `kernel_source_names` table keeps reporting data
  available without putting it in the repeated sample path.

## Practical Example

Here is a pattern that loads a side table just to answer whether a kernel has
sample work.

```zig
if (sideSampleCount(sample_counts, kernel.id) != 0) {
    try appendSideSamples(kernel, side_samples, out);
}
```

That shape can be reasonable if the question is rare. It is wasteful if the hot
loop asks it for every kernel, because the code loads another structure before
it knows whether sample work exists.

A better approach keeps the common answer in the row the loop already loaded.

```zig
if (kernel.side_count != 0) {
    try appendSideSamples(kernel, side_samples, out);
}
```

Now the presence check and the side-storage range live in the same compact row.
Fabian's own cache-line example showed the same kind of effect: on his i5-4430
measurement, a simple map check took `11.31ms`, a cached presence check took
`3.71ms`, and a fully cached query took `0.30ms`. The lesson is not "cache
everything"; it is that bytes already fetched should answer questions the hot
path asks often.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for compact kernel references.
- Read [`src/forward_model/optical_properties/state_build/state_spectroscopy.zig`](../../../src/forward_model/optical_properties/state_build/state_spectroscopy.zig)
  for fixed inline spectroscopy cache rows.
