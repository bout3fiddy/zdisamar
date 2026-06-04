# Ch. 8.7 - Lazy Evaluation For The Masses (p153)

Source: [Data-Oriented Design online book, "Lazy evaluation"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00970000000000000000) (printed-book p153).

Summary: Fabian warns that delaying work is not automatically faster. Sometimes
checking whether work is needed costs more than just doing the work.

The context is render-engine and compiler history. Fabian cites the shift from
marking scene data as "dirty" toward simply recomputing cheap matrices every
frame. He also points to Tony Albrecht's talks, where an old manual optimization
stopped helping as compilers and hardware improved.

Take home: Use laziness only when the saved work is larger than the check. For
expensive work, keep a clear list of the items that really need updating.

## Main Lessons

- Do not add checks that cost more than the work.
  If the update is cheap, doing it for every row may be faster and simpler than
  checking a flag for every row.

  ```zig
  for (layers, out) |layer, *dst| {
      dst.* = cheapUpdate(layer);
  }
  ```

  Notice that there is no dirty check here. The example is for cheap work
  where simply doing the work may be clearer and faster.

- If the work is expensive, keep a list of only the rows that need it.
  Then the loop visits the work that must be refreshed and skips everything
  else without checking every row.

  ```zig
  for (dirty_wavelengths) |wavelength_nm| {
      try refreshSpectralCache(cache, wavelength_nm);
  }
  ```

  Notice that the loop visits `dirty_wavelengths`, not every wavelength.
  The list itself says what needs refresh.

- Cached data is valid only for the input it was built from.
  When the key changes, rebuild the cache before using it.

  ```zig
  if (!cache.key.eql(new_key)) {
      try cache.rebuild(new_key, allocator);
  }
  ```

  Notice that the key is checked before reuse. A different key forces a
  rebuild.


## Code Material

The code material passes the refresh list to the refresh loop:

```zig
const DirtyPlan = struct {
    // This is already the refresh list, not every possible wavelength.
    wavelengths: []const f64,
};

fn refreshOnlyDirty(plan: DirtyPlan, cache: *SpectralCache) !void {
    for (plan.wavelengths) |wavelength_nm| {
        // Refresh only the entries listed in the plan.
        try cache.refresh(wavelength_nm);
    }
}
```

Notice that `plan.wavelengths` is the list of work to refresh. The function
does not scan every possible wavelength looking for dirty flags.

The refresh function could scan the whole cache and decide which entries are
dirty. Then every refresh pass also pays for dirty checks, and the loop hides
how much work was selected. `DirtyPlan` is built first, so the refresh loop only
refreshes the listed wavelengths.

## Practical Example

Here is a pattern that scans every wavelength to check whether its cached value
needs refresh.

```zig
for (all_wavelengths) |wavelength_nm| {
    if (cache.isDirty(wavelength_nm)) try refreshSpectralCache(cache, wavelength_nm);
}
```

The compiler output below is generated machine code. It makes the dirty-flag
load and branch from the code above visible.

```asm
ldrb    w12, [x9], #1  ; load one dirty flag
cbz     w12, LBB16_5   ; branch around refresh work when flag is zero
ldr     d1, [x10]      ; load wavelength only when dirty
str     d1, [x11]      ; store refreshed output
```

This shows that the scan-all version keeps a flag load and branch in the loop
for every possible row.

A better approach stores the wavelengths that need refresh as a list.

```zig
for (dirty_wavelengths) |wavelength_nm| {
    try refreshSpectralCache(cache, wavelength_nm);
}
```

The first loop scans every possible wavelength to find the few cache entries
needing refresh. The better loop stores that refresh list directly.

The generated output for the better approach is easier to read.

```llvm
%wide.load = load <2 x double>, ptr %scevgep24
%10 = fadd <2 x double> %6, splat (double 1.000000e+00)
store <2 x double> %10, ptr %scevgep19
```

A benchmark for the refresh list showed it was `4.18x` faster elapsed time than
scanning all flags, with the same checksum. The compiler optimized the loop it
was given; the source code made the loop shorter.

## zdisamar Reading Notes

- Read warm session storage in [`src/input/o2a_reference/root.zig`](../../../src/input/o2a_reference/root.zig).
- Read retained wavelength/profile caches in
  [`src/forward_model/instrument_grid/grid_calculation/simulate.zig`](../../../src/forward_model/instrument_grid/grid_calculation/simulate.zig).
