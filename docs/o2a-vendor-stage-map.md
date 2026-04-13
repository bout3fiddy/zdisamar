## O2A Vendor Stage Map

The retained O2 A path mirrors the vendor workflow in six stages:

1. case
2. data
3. optics
4. solver
5. spectrum
6. report

## Stage Mapping

- `case`
  - [src/o2a/case.zig](../src/o2a/case.zig)
  - [src/o2a/data/vendor_case.zig](../src/o2a/data/vendor_case.zig)
- `data`
  - [src/o2a/data/load.zig](../src/o2a/data/load.zig)
  - [src/o2a/data/assets.zig](../src/o2a/data/assets.zig)
  - [src/o2a/data/luts.zig](../src/o2a/data/luts.zig)
- `optics`
  - [src/o2a/optics.zig](../src/o2a/optics.zig)
  - [src/o2a/optics/layers.zig](../src/o2a/optics/layers.zig)
  - [src/o2a/optics/pseudo_spherical.zig](../src/o2a/optics/pseudo_spherical.zig)
- `solver`
  - [src/o2a/solver.zig](../src/o2a/solver.zig)
  - [src/o2a/solver/labos.zig](../src/o2a/solver/labos.zig)
  - [src/o2a/solver/reflectance.zig](../src/o2a/solver/reflectance.zig)
- `spectrum`
  - [src/o2a/spectrum.zig](../src/o2a/spectrum.zig)
  - [src/o2a/work.zig](../src/o2a/work.zig)
- `report`
  - [src/o2a/report.zig](../src/o2a/report.zig)
  - [src/o2a/report/json.zig](../src/o2a/report/json.zig)

## Validation Anchors

The retained validation story stays centered on:

- `validation/reference/o2a_with_cia_disamar_reference.csv`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build test-validation-o2a-vendor-profile`
- `zig build o2a-plot-bundle`
