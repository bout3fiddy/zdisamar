# O2A Vendor Stage Map

The retained O2A path is organized around:

1. `Input`
2. `ReferenceData`
3. `OpticalProperties`
4. `Output`
5. `DiagnosticReport`

The implementation no longer mirrors the vendor file/module layout. DISAMAR is
kept as a reference family for parity checks, while the active runtime uses the
typed Zig scene, bundled data loader, optical-property preparation,
radiative-transfer evaluation on the instrument grid, and JSON report path.

DISAMAR stage map:

- `GENERAL`, `INSTRUMENT`, and `GEOMETRY` feed `Input`.
- `REFERENCE_DATA`, `PRESSURE_TEMPERATURE`, and absorbing-gas sections feed `ReferenceData`.
- `SURFACE`, `ATMOSPHERIC_INTERVALS`, `CLOUD`, `AEROSOL`, and `RADIATIVE_TRANSFER` feed `OpticalProperties`.
- `radianceIrradianceModule`, `LabosModule`, and `addingTools` correspond to `Output`.
- `ADDITIONAL_OUTPUT` corresponds to `DiagnosticReport`.

Current anchors:

- public API: `src/root.zig`
- bundled data and LUT workflows: `src/input/reference_data/bundled/`
- reference-data ingestion: `src/input/reference_data/ingest/`
- optics preparation: `src/forward_model/optical_properties/`
- radiative transfer and instrument grid: `src/forward_model/radiative_transfer/` and `src/forward_model/instrument_grid/`
- report output: `src/output/json.zig`
- parity runtime: `src/validation/disamar_reference/`

Validation commands:

```bash
zig build test-validation-o2a
zig build test-validation-o2a-vendor
zig build test-validation-o2a-vendor-line-list
zig build test-validation-o2a-plot-bundle
zig build o2a-plot-bundle
```
