# Why zdisamar Is Faster Than DISAMAR

Scope: one O2 A forward spectrum. zdisamar is already at the required agreement level for the O2 A quantities we need. This folder explains why the current zdisamar run is faster than the DISAMAR executable run, and where the remaining wall is.

Checkpoint zdisamar timing:

```text
prepare_o2a                 0.509849 s
forward model               1.919895 s
reflectance max_abs         8.0019324e-14
output wavelengths                 701
```

DISAMAR executable timing from the retained log:

```text
full simulation            168.378 s
O2 table setup              24.131 s
O2-O2 table setup            1.755 s
high-resolution wavelengths  3,874
```

Those timers are not the same kind of measurement. zdisamar reports a prepare/forward split. DISAMAR reports a full executable simulation. The useful comparison is the mechanism: DISAMAR runs a broad configurable program, while zdisamar runs the O2 A forward spectrum through a narrower reusable calculation.

## Documents

- [Checkpoint timings](checkpoint-timings.md): exact script, commits, commands, and the measured 79-second, 35-second, 8-second, and 1.9-second rows.
- [01. Reuse LABOS storage](01-reuse-labos-storage.md): avoids repeated allocation in the frequently repeated Fourier and wavelength work.
- [02. Fuse layer-doubling matrix updates](02-fuse-layer-doubling-matrix-updates.md): reduces repeated matrix traffic in the most expensive LABOS block.
- [03. Use direct 12x10 and 12x12 matrix calculations](03-direct-12x10-12x12-matrix-calculations.md): uses the fixed O2 A 20-stream shape instead of a fully general matrix route.
- [04. Skip layers and terms that cannot contribute](04-skip-empty-layer-work.md): avoids scattering work for layers and terms that are mathematically zero or negligible.
- [05. Stop tiny Fourier tails](05-fourier-tail-and-basis-reuse.md): reuses Fourier basis values and stops once later Fourier terms are below the required scale.
- [06. Keep full-program setup out of the forward timer](06-keep-program-setup-out-of-forward-timer.md): separates fixed input and line/profile preparation from the two-second forward wall.
- [07. Carry layer activity into scattering orders](07-carry-layer-activity-into-orders.md): remembers which layers are zero so later scattering-order dot products can skip them.
- [08. Skip empty q-series work](08-skip-empty-qseries-work.md): avoids q-series matrix work when repeated reflection is below the configured threshold.
- [09. Write matrix results into separate outputs](09-write-matrix-results-into-separate-outputs.md): writes repeated matrix products directly into their final destination.
- [10. Combine the D update in doubling](10-combine-d-update-in-doubling.md): combines `T + Q*E + Q*T` for the common O2 A matrix shape.

Source links point at code commit `36598b67287c918b410ae25ca54319cbe63ade4b`, which is the source tree inspected for these excerpts. The code blocks below each link copy the relevant lines so the mechanism is readable without opening another file.

## Remaining Wall

The remaining wall is still scientific work:

```text
701 output wavelengths
-> 3,874 high-resolution radiance wavelengths
-> 120,390 Fourier terms
-> 5,417,550 LABOS layer visits
-> 1,075,939 doubled layers
-> 8,389,666 doubling steps
```

The current forward run is dominated by calculating radiance at the 3,874 high-resolution wavelengths. Inside those calculations, LABOS transport dominates. Inside LABOS, RT-layer construction and layer doubling dominate.
