# Ch. 8.7 - Lazy Evaluation For The Masses (p153)

Source: [Data-Oriented Design online book, "Lazy evaluation"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00970000000000000000) (printed-book p153).

Summary: Fabian warns that lazy evaluation is not automatically cheaper:
checking dirty flags can cost more than recomputing cheap values. For expensive
work, the better shape is to keep a dirty table where membership itself means
"update this."

The context is render-engine and compiler history. Fabian cites the shift from
dirty-bit scene hierarchy updates toward recomputing matrices every frame, and
Tony Albrecht's talks where an old manual devirtualization win stopped helping
as compilers and hardware moved on.

Take home: Delay work only when the saved work is larger than the check, because
lazy code can add its own cost. `zdisamar` caches should have explicit keys and
dirty lists, and add laziness only when avoided work exceeds validation cost.

## Main Lessons

- Do not add checks that cost more than the work.
  If the update is cheap, doing it for every row may be faster and simpler than
  checking a flag for every row.

  ```zig
  for (layers, out) |layer, *dst| {
      dst.* = cheapUpdate(layer);
  }
  ```

  What to notice: there is no dirty check here. The example is for cheap work
  where simply doing the work may be clearer and faster.

- If the work is expensive, keep a list of only the rows that need it.
  Then the loop visits the work that must be refreshed and skips everything
  else without checking every row.

  ```zig
  for (dirty_wavelengths) |wavelength_nm| {
      try refreshSpectralCache(cache, wavelength_nm);
  }
  ```

  What to notice: the loop visits `dirty_wavelengths`, not every wavelength.
  The list itself says what needs refresh.

- Cached data is valid only for the input it was built from.
  When the key changes, rebuild the cache before using it.

  ```zig
  if (!cache.key.eql(new_key)) {
      try cache.rebuild(new_key, allocator);
  }
  ```

  What to notice: the key is checked before reuse. A different key forces a
  rebuild.

  Zig syntax note: `!cache.key.eql(new_key)` uses `!` as boolean "not." This is
  different from `!T` in a return type, where `!` means "may return an error."

## Code Material

Fabian's section is prose. Adapted:

```zig
const DirtyPlan = struct {
    wavelengths: []const f64,
};

fn refreshOnlyDirty(plan: DirtyPlan, cache: *SpectralCache) !void {
    for (plan.wavelengths) |wavelength_nm| {
        try cache.refresh(wavelength_nm);
    }
}
```

What to notice: `plan.wavelengths` is the list of work to refresh. The function
does not scan every possible wavelength looking for dirty flags.

## Compiler Note

Chapter example tied to this note:

```zig
for (dirty_wavelengths) |wavelength_nm| {
    try refreshSpectralCache(cache, wavelength_nm);
}
```

Wrong pattern:

```zig
for (all_wavelengths) |wavelength_nm| {
    if (cache.isDirty(wavelength_nm)) try refreshSpectralCache(cache, wavelength_nm);
}
```

Better pattern:

```zig
for (dirty_wavelengths) |wavelength_nm| {
    try refreshSpectralCache(cache, wavelength_nm);
}
```

Why this contrast matters: the wrong version scans every possible row to find
the few rows needing work. The better version stores the work list directly.

Wrong-pattern compiler artifact from
[`refreshScanAllFlags`](codegen/dod_codegen_examples.zig):

```asm
ldrb    w12, [x9], #1  ; load one dirty flag
cbz     w12, LBB16_5   ; branch around refresh work when flag is zero
ldr     d1, [x10]      ; load wavelength only when dirty
str     d1, [x11]      ; store refreshed output
```

What goes wrong: the scan-all version keeps a flag load and branch in the loop
for every possible row.

Better-pattern compiler artifact from
[`refreshDirty`](codegen/dod_codegen_examples.zig):

```llvm
%wide.load = load <2 x double>, ptr %scevgep24
%10 = fadd <2 x double> %6, splat (double 1.000000e+00)
store <2 x double> %10, ptr %scevgep19
```

Benchmark evidence: using a dirty index list was `4.18x` faster elapsed time
than scanning all flags, with the same checksum. The compiler optimized the loop
it was given; the source code made the loop shorter.

## zdisamar Reading Notes

- Read warm session storage in [`src/input/o2a_reference/root.zig`](../../../src/input/o2a_reference/root.zig).
- Read retained wavelength/profile caches in
  [`src/forward_model/instrument_grid/grid_calculation/simulate.zig`](../../../src/forward_model/instrument_grid/grid_calculation/simulate.zig).
