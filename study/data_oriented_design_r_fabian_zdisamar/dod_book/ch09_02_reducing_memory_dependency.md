# Ch. 9.2 - Reducing Memory Dependency (p164)

Source: [Data-Oriented Design online book, "Reducing memory dependency"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001020000000000000000) (printed-book p164).

Summary: Fabian's memory-dependency point is that pointer chains stall because
the address of the next load depends on the result of the previous load. The
hardware cannot hide that latency.

The concrete cases are linked lists, tree-shaped maps/sets, and pointer-based
entity-component composition. The lesson is not that every lookup is bad; it is
that a load whose address depends on another load creates a chain the CPU cannot
prefetch away.

Take home: Avoid pointer chains in hot loops because each dependent load can
make the CPU wait for the next address. `zdisamar` hot loops should prefer flat
arrays, indexes, and saved result positions over walking through object-like
state.

## Main Lessons

- Avoid "go here, then go there, then go somewhere else" in loops that run many
  times.
  A pointer chain makes the CPU wait for one memory load before it knows the
  address of the next load.

  ```zig
  const value = rows[index].optical_depth;
  ```

  What to notice: the code uses one array and one index. It does not follow a
  pointer to another object before finding `optical_depth`.

- Save positions into arrays when you can.
  Then the repeated loop can jump straight to the result it needs.

  ```zig
  const result_index = plan.sample_indices[i];
  sum += results[result_index].radiance;
  ```

  What to notice: `sample_indices` stores the result position. The next line
  uses that position to read `results` directly.

  Zig syntax note: `plan.sample_indices[i]` indexes one item from the slice.
  `results[result_index]` then indexes another slice using that saved position.

- If a loop reads the same field from many rows, consider storing that field
  together.
  This can be easier for the CPU than reading full rows with many unused fields.

  ```zig
  const OpticalDepths = struct {
      values: []const f64,
  };
  ```

  What to notice: this stores optical depths as one plain list. A loop that only
  needs optical depths can read this list without loading full layer rows.

## Code Material

Fabian's section is prose. Adapted:

```zig
fn integrate(plan: ForwardMissPlan, results: []const ForwardResult, out: []f64) void {
    for (plan.rows, out) |row, *dst| {
        var sum: f64 = 0;
        const indexes = plan.sample_indices[row.start .. row.start + row.count];
        for (indexes) |sample_index| {
            sum += results[sample_index].radiance;
        }
        dst.* = sum;
    }
}
```

What to notice: the inner loop follows saved indexes into one result array. It
does not walk a chain of objects or maps to find each radiance value.

## Compiler Note

Chapter example tied to this note:

```zig
const result_index = plan.sample_indices[i];
sum += results[result_index].radiance;
```

Wrong pattern:

```zig
const wavelength_nm = plan.sample_wavelengths[i];
const result_index = findResultIndex(results, wavelength_nm);
sum += results[result_index].radiance;
```

Better pattern:

```zig
const result_index = plan.sample_indices[i];
sum += results[result_index].radiance;
```

Why this contrast matters: the wrong version depends on a search before it can
read the result. The better version keeps one dependent load, but removes the
search chain from the repeated loop.

Wrong-pattern compiler artifact from
[`integrateLinearSearch`](codegen/dod_codegen_examples.zig):

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested wavelength
ldr     d2, [x2, x11, lsl #3]  ; load candidate result wavelength
fcmp    d2, d1                 ; compare before radiance can be read
b.eq    LBB11_7                ; branch when the search finds a match
```

What goes wrong: the result address depends on a repeated search, not just a
saved index.

Better-pattern compiler artifact from
[`integrateIndexed`](codegen/dod_codegen_examples.zig):

```llvm
%10 = load i32, ptr %scevgep
%13 = load double, ptr %12
```

What this proves: the loop follows a saved index and then reads the result. The
search is gone, but the result address still depends on the loaded index.

Benchmark evidence: prepared indexes were `803.65x` faster than linear search,
with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- The key study question is whether a loop that runs many times is doing direct
  indexed reads or repeated dependent lookups.
