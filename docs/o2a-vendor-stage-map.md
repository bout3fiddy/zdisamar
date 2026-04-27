# O2A Vendor Stage Map

The retained O2A path is organized around:

1. `Case`
2. `Prepared`
3. `Result`
4. `Report`

The implementation no longer mirrors the vendor file/module layout. DISAMAR is
kept as a reference family for parity checks, while the active runtime uses the
typed Zig scene, bundled data loader, optics preparation, measurement-space
transport, and JSON report path.

Current anchors:

- public API: `src/root.zig` and `src/o2a.zig`
- bundled data and LUT workflows: `src/data/bundled/`
- optics preparation: `src/kernels/optics/preparation.zig`
- transport and measurement: `src/kernels/transport/`
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
