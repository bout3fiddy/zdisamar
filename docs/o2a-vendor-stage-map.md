# O2A Vendor Stage Map

The retained O2A path is organized around:

1. `Case`
2. `Data`
3. `Optics`
4. `Spectrum`
5. `Report`

The implementation no longer mirrors the vendor file/module layout. DISAMAR is
kept as a reference family for parity checks, while the active runtime uses the
typed Zig scene, bundled data loader, optical-property preparation,
radiative-transfer evaluation on the instrument grid, and JSON report path.

DISAMAR stage map:

- `GENERAL`, `INSTRUMENT`, and `GEOMETRY` feed `Case`.
- `REFERENCE_DATA`, `PRESSURE_TEMPERATURE`, and absorbing-gas sections feed `Data`.
- `SURFACE`, `ATMOSPHERIC_INTERVALS`, `CLOUD`, `AEROSOL`, and `RADIATIVE_TRANSFER` feed `Optics`.
- `radianceIrradianceModule`, `LabosModule`, and `addingTools` correspond to `Spectrum`.
- `ADDITIONAL_OUTPUT` corresponds to `Report`.

Current anchors:

- public API: `src/root.zig` and `src/o2a.zig`
- bundled data and LUT workflows: `src/data/bundled/`
- optics preparation: `src/kernels/optics/preparation.zig`
- radiative transfer and instrument grid: `src/kernels/transport/`
- report output: `src/o2a/report/json.zig`
- parity runtime: `src/o2a/data/vendor_parity_*.zig`

Validation commands:

```bash
zig build test-validation-o2a
zig build test-validation-o2a-vendor
zig build test-validation-o2a-vendor-line-list
zig build test-validation-o2a-plot-bundle
zig build o2a-plot-bundle
```
