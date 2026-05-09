# Forward Optimisation Notes

These notes keep the mechanism details behind the short optimisation history.
They intentionally avoid copied Fortran or Zig excerpts. Each note links to the
DISAMAR and zdisamar source snapshots, then uses small Python-shaped examples to
show the data-flow change.

Source snapshot convention:

```text
DISAMAR Fortran: d17c52884a875cb87b98e4c4ea7f722659e685ac
zdisamar:        36598b67287c918b410ae25ca54319cbe63ade4b
```

Notes:

- [01. Reuse wavelength work and layer geometry](01-high-resolution-wavelengths-and-layer-geometry.md)
- [02. Prepare line spectroscopy once](02-line-spectroscopy-once.md)
- [03. Reuse LABOS storage](03-labos-storage.md)
- [04. Fuse layer-doubling matrix updates](04-fused-layer-doubling-updates.md)
- [05. Use direct 12x10 and 12x12 matrix calculations](05-direct-matrix-calculations.md)
- [06. Skip layers and terms that cannot contribute](06-skip-empty-layer-work.md)
- [07. Stop tiny Fourier tails](07-fourier-tail-and-basis-reuse.md)
- [08. Keep program setup out of the forward timer](08-program-setup-boundary.md)
- [09. Carry layer activity into scattering orders](09-layer-activity-orders.md)
- [10. Skip empty q-series work](10-skip-empty-qseries.md)
- [11. Write matrix results into separate outputs](11-separate-matrix-outputs.md)
- [12. Combine the D update in doubling](12-combine-d-update.md)
