# Ch. 9.2 - Reducing Memory Dependency (p164)

Source: [Data-Oriented Design online book, "Reducing memory dependency"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001020000000000000000) (printed-book p164).

Summary: Fabian's memory-dependency lesson is that a program can stall when
each memory read tells it where the next read is. The CPU cannot fetch the next
address early if it does not know it yet.

The concrete cases are linked lists, tree-shaped maps or sets, and systems that
connect objects through many pointers. The lesson is not that every lookup is
bad; it is that a long chain of "read this to find the next thing" gives the
machine little room to get ahead.

Take home: Avoid long chains of pointers in repeated work. Prefer simple lists
and saved positions when the program needs to visit many related values.

## Main Lessons

- Avoid "go here, then go there, then go somewhere else" in loops that run many
  times.
  A pointer chain makes the CPU wait for one memory load before it knows the
  address of the next load.

  ```zig
  const value = rows[index].optical_depth;
  ```

  Notice that the code uses one array and one index. It does not follow a
  pointer to another object before finding `optical_depth`.

- Save positions into arrays when you can.
  Then the repeated loop can jump straight to the result it needs.

  ```zig
  const result_index = plan.sample_indices[i];
  sum += results[result_index].radiance;
  ```

  Notice that `sample_indices` stores the result position. The next line
  uses that position to read `results` directly.


- If a loop reads the same field from many rows, consider storing that field
  together.
  This can be easier for the CPU than reading full rows with many unused fields.

  ```zig
  const OpticalDepths = struct {
      values: []const f64,
  };

  fn sumOpticalDepths(data: OpticalDepths) f64 {
      var total: f64 = 0;
      for (data.values) |tau| {
          // The loop walks one plain optical-depth list.
          total += tau;
      }
      return total;
  }
  ```

  Notice that `sumOpticalDepths` reads the plain list directly. The loop no
  longer has to step through full layer rows to find one field.

  A plain `[]const f64` is enough for the summing loop. The wrapper is for the
  place where prepared data is named. It says these numbers are optical depths;
  the small numeric helper can still work on the slice inside it.

## Code Material

The code material follows saved sample indexes into the result array:

```zig
fn integrate(plan: ForwardMissPlan, results: []const ForwardResult, out: []f64) void {
    for (plan.rows, out) |row, *dst| {
        var sum: f64 = 0;
        // The row points at prepared result indexes.
        const indexes = plan.sample_indices[row.start .. row.start + row.count];
        for (indexes) |sample_index| {
            // Read the index first, then read radiance from results.
            sum += results[sample_index].radiance;
        }
        dst.* = sum;
    }
}
```

Notice that the inner loop follows saved indexes into one result array. It
does not walk a chain of objects or maps to find each radiance value.

## Practical Example

Here is a pattern where a wavelength search must finish before radiance can be
read.

```zig
const wavelength_nm = plan.sample_wavelengths[i];
const result_index = findResultIndex(results, wavelength_nm);
sum += results[result_index].radiance;
```

The compiler output below is generated machine code. It makes the repeated
search and comparison from the code above visible.

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested wavelength
ldr     d2, [x2, x11, lsl #3]  ; load candidate result wavelength
fcmp    d2, d1                 ; compare before radiance can be read
b.eq    LBB11_7                ; branch when the search finds a match
```

This shows that the result address depends on a repeated search, not just a
saved index.

A better approach stores the result index before the repeated read.

```zig
const result_index = plan.sample_indices[i];
sum += results[result_index].radiance;
```

The first version depends on a search before it can read radiance. The better
version keeps one dependent load, but removes the search chain from the repeated
loop.

The generated output for the better approach is easier to read.

```llvm
%10 = load i32, ptr %scevgep
%13 = load double, ptr %12
```

The loop follows a saved index and then reads the result. The search is gone,
but the result address still depends on the loaded index.

A benchmark for prepared indexes showed they were `803.65x` faster than
linear search, with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- The key study question is whether a loop that runs many times is doing direct
  indexed reads or repeated dependent lookups.
