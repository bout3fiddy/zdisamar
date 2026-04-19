# Harmonize O2A With DISAMAR Reference Workpackages

## Overview

This folder captures the planning-only workpackages for harmonizing the Zig O2A
forward model and its hotspot probe surfaces with the bundled DISAMAR
reference.

The plan is organized around the completed `761.75 nm` hotspot function-diff
probe and the three current mismatch zones:

- harness normalization and comparable diff surfaces
- spectroscopy and strong-line semantics
- measurement kernel and slit/irradiance realization
- prepared sublayer state and optics-preparation semantics
- final residual closure and acceptance reruns

## Critical Path

`WP-01 -> WP-02 -> (WP-03 / WP-04) -> WP-05`

## Packages

- [WP-01 Normalize probe surfaces](./wp-01-normalize-probe-surfaces.md)
- [WP-02 Align spectroscopy semantics](./wp-02-align-spectroscopy-semantics.md)
- [WP-03 Align measurement kernel realization](./wp-03-align-measurement-kernel-realization.md)
- [WP-04 Align prepared sublayer state](./wp-04-align-prepared-sublayer-state.md)
- [WP-05 Close hotspot residuals](./wp-05-close-hotspot-residuals.md)

## Shared Architectural Rules

- Keep `src/kernels` free of file I/O, CLI wiring, and global mutable state.
- Keep the public flow literal around `Case -> Data -> Optics -> Spectrum -> Report`.
- No parsed control may be silently ignored; every new field must be consumed,
  rejected with a typed error, or explicitly documented as inert with test
  coverage.
- Preserve retained O2A semantics unless a compatibility break is intentional
  and called out in the package, implementation summary, and regression
  coverage.
- Treat DISAMAR as the reference family for parity and scientific comparison,
  not as an architecture template for new Zig code.
- Keep the hotspot probe outputs under `out/analysis/` and do not introduce
  tracked scientific fixtures for probe runs.

## Existing Runtime Anchors

- Hotspot probe front door:
  - `build.zig`
  - `scripts/testing_harness/o2a_function_diff.py`
  - `scripts/testing_harness/o2a_function_trace.zig`
  - `scripts/testing_harness/vendor_o2a_function_trace/o2aFunctionTraceModule.f90`
- Current spectroscopy path:
  - `src/model/reference/spectroscopy/line_list_eval.zig`
  - `src/model/reference/spectroscopy/physics_core.zig`
  - `src/model/reference/spectroscopy/strong_lines.zig`
  - `src/o2a/data/vendor_parity_runtime.zig`
  - `vendor/disamar-fortran/src/HITRANModule.f90`
- Current measurement path:
  - `src/o2a/providers/instrument/integration.zig`
  - `src/model/instrument/pipeline.zig`
  - `src/compat/observation/legacy_support.zig`
  - `src/kernels/transport/measurement/simulate.zig`
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `vendor/disamar-fortran/src/mathToolsModule.f90`
  - `vendor/disamar-fortran/src/readIrrRadFromFileModule.f90`
- Current optics-preparation path:
  - `src/kernels/optics/preparation/layer_accumulation.zig`
  - `src/kernels/optics/preparation/vertical_grid.zig`
  - `src/kernels/optics/preparation/state_optical_depth.zig`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`

