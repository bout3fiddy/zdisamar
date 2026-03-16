# Documentation

This directory explains DISAMAR as an atmospheric radiative-transfer and retrieval model family and documents the current implementation in `zdisamar`. Earlier operational implementations were developed in Fortran at KNMI, but the material here is written about the present codebase: its scientific scope, execution model, operational interfaces, extension boundaries, and bounded validation surfaces. Where the current code still uses surrogate transport or retrieval lanes, the docs should say so directly instead of implying completed method-faithful parity.

## Recommended Reading Order

1. [DISAMAR Overview](./disamar-overview.md)
2. [Architecture and Execution Model](./zig-architecture.md)
3. [Plugin System End-To-End Flow](./plugin-system-end-to-end.md)
4. [Operational O2 A-Band Path](./operational-o2a.md)
5. [Reference Data and Runtime Bundles](./reference-data-and-bundles.md)
6. [Retrieval and Measurement-Space Outputs](./retrieval-and-measurement-space.md)
7. [Exporters and Result Artifacts](./exporters-and-artifacts.md)
8. [Plugins and Extension Boundaries](./plugins-and-extension-boundaries.md)
9. [Validation and Scientific Scope](./validation-and-parity.md)

## Scope

- The top-level documents in `docs/` describe the current implementation and its scientific role.
- `docs/workpackages/` records execution history and closure notes for implementation packages.
- `docs/specs/` is local scratch space and should not be read as the main architectural narrative.

## Canonical Implementation References

- [Source tree router](../src/AGENTS.md)
- [Engine lifecycle](../src/core/Engine.zig)
- [Reference-data runtime bridge](../src/runtime/reference/BundledOptics.zig)
- [Plugin registry and freeze snapshot](../src/plugins/registry/CapabilityRegistry.zig)

## Selected Scientific References

- de Haan, J. F., Wang, P., Sneep, M., Veefkind, J. P., and Stammes, P.: [Introduction of the DISAMAR radiative transfer model: determining instrument specifications and analysing methods for atmospheric retrieval (version 4.1.5)](https://gmd.copernicus.org/articles/15/7031/2022/gmd-15-7031-2022.html), *Geosci. Model Dev.*, 15, 7031-7064, 2022.
- Sanders, A. F. J., de Haan, J. F., Sneep, M., Apituley, A., Stammes, P., et al.: [Evaluation of the operational Aerosol Layer Height retrieval algorithm for Sentinel-5 Precursor: application to O2 A-band observations from GOME-2A](https://amt.copernicus.org/articles/8/4947/2015/), *Atmos. Meas. Tech.*, 8, 4947-4977, 2015.
- Keppens, A., Di Pede, S., Hubert, D., Lambert, J.-C., Veefkind, P., Sneep, M., de Haan, J., et al.: [5 years of Sentinel-5P TROPOMI operational ozone profiling and geophysical validation using ozonesonde and lidar ground-based networks](https://amt.copernicus.org/articles/17/3969/2024/), *Atmos. Meas. Tech.*, 17, 3969-3993, 2024.
- Tilstra, L. G., de Graaf, M., Wang, P., et al.: [A geometry-dependent surface Lambert-equivalent reflectivity climatology from TROPOMI](https://amt.copernicus.org/articles/17/2235/2024/), *Atmos. Meas. Tech.*, 17, 2235-2264, 2024.
- de Graaf, M., Tilstra, L. G., Sneep, M., Litvinov, P., and Stammes, P.: [Improving directional surface reflection treatment in TROPOMI/S5P aerosol layer height retrieval](https://amt.copernicus.org/articles/18/2553/2025/), *Atmos. Meas. Tech.*, 18, 2553-2577, 2025.
- van Peet, J. C. A., Hubert, D., Lambert, J.-C., Keppens, A., et al.: [Harmonisation of sixteen tropospheric ozone satellite data records](https://amt.copernicus.org/articles/18/6893/2025/), *Atmos. Meas. Tech.*, 18, 6893-6916, 2025.
