# WP-03 Align measurement kernel realization

## Metadata

- Created: 2026-04-19
- Scope: align Zig measurement-kernel realization with DISAMAR so matching
  interval plans lead to matching sample wavelengths, weights, and slit
  convolution semantics
- Input sources:
  - `src/o2a/providers/instrument/integration.zig`
  - `src/model/instrument/pipeline.zig`
  - `src/compat/observation/legacy_support.zig`
  - `src/kernels/transport/measurement/simulate.zig`
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `vendor/disamar-fortran/src/mathToolsModule.f90`
  - `vendor/disamar-fortran/src/readIrrRadFromFileModule.f90`
  - `out/analysis/o2a/function_diff/20260419T142237Z/vendor/kernel_samples.csv`
  - `out/analysis/o2a/function_diff/20260419T142237Z/yaml/kernel_samples.csv`
- Dependencies:
  - `WP-01`
  - `WP-02`
- Reference baseline:
  - current hotspot `kernel_samples.csv` and `transport_samples.csv` mismatch

## Background

`adaptive_grid.csv` matches exactly, but `kernel_samples.csv` and
`transport_samples.csv` diverge immediately. The comparison shows that Zig is
still realizing the explicit HR-grid path while DISAMAR uses adaptive
Gauss-Legendre sampling plus different weight normalization and irradiance
handling.

## Overarching Goals

- Make Zig realize the same kernel that the probe is tracing.
- Align sample placement and weight semantics with DISAMAR.
- Align slit and irradiance handling closely enough that transport differences
  stop being dominated by measurement-shell mismatch.

## Non-goals

- Fixing the spectroscopy root cause; that belongs to `WP-02`.
- Rewriting transport closure formulas.
- Generalizing every instrument path in the repo before O2A parity is closed.

### WP-03 Align measurement kernel realization [Status: Todo]

Issue:
The current Zig path logs adaptive intervals but then executes an explicit
uniform HR lattice in `auto` mode, with different weight normalization, a
different slit-application phase, and a different irradiance source path.

Needs:
- one resolved kernel mode that actually matches the vendor parity intent
- sample wavelengths and weights that match the vendor probe semantics
- consistent HR-first convolution semantics for radiance and irradiance

How:
1. Rework parity-mode kernel resolution so the executed path matches the traced
   path.
2. Align sample-grid realization with vendor adaptive Gauss-Legendre semantics
   where the parity mode requests that behavior.
3. Align slit normalization and the timing of slit application in the transport
   measurement path.
4. Align irradiance realization with the vendor HR-first slit-convolution path
   as far as the retained assets allow.

Why this approach:
The probe already proves that interval choice is not the active mismatch.
Sample placement, weights, and post-spectroscopy measurement semantics are the
next causal layer after the spectroscopy stage.

Desired outcome:
`kernel_samples.csv` and `transport_samples.csv` move substantially closer for
the hotspot wavelength, and final radiance/reflectance stop being dominated by
kernel-shell differences.

Non-destructive tests:
- `zig build test-fast`
- `zig build test-validation-o2a`
- `zig build o2a-function-diff`
- `zig build o2a-plot-bundle`

Files by type:
- New targets:
  - none
- Existing targets to refactor:
  - `src/o2a/providers/instrument/integration.zig`
  - `src/model/instrument/pipeline.zig`
  - `src/compat/observation/legacy_support.zig`
  - `src/kernels/transport/measurement/simulate.zig`
  - `src/compat/transport/solar_irradiance.zig`
- Validation targets:
  - `tests/unit/measurement_test.zig`
  - `scripts/testing_harness/o2a_function_trace.zig`
  - `scripts/testing_harness/o2a_function_diff.py`

## Exact Patch Checklist

- [ ] Make parity-mode kernel execution use the same mode that the probe logs.
- [ ] Align kernel sample wavelength placement and quadrature weights with the
      vendor hotspot path.
- [ ] Align slit normalization and slit-application order with DISAMAR.
- [ ] Revisit irradiance realization so HR irradiance is convolved in parity
      mode instead of treated as already instrument-space.
- [ ] Add focused tests that fail if Zig silently falls back to the explicit
      HR lattice when parity mode expects adaptive realization.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] `kernel_samples.csv` and `transport_samples.csv` move materially closer
- [ ] Final hotspot radiance and reflectance improve without new regressions

## Implementation Status (2026-04-19)

Planning only. No code changes yet.

## Why This Works

The measurement mismatch is already localized: interval selection matches, but
sample realization does not. Aligning the executed kernel, weight semantics,
and HR convolution path attacks the first measurement-specific cause directly.

## Proof / Validation

- Planned: hotspot `kernel_samples.csv` sample counts and first sample
  wavelengths move toward the vendor trace
- Planned: hotspot `transport_summary.csv` radiance and reflectance improve
- Planned: retained fast O2A tests and plot-bundle generation still pass

## How To Test

1. Run `zig build test-fast`.
2. Run `zig build o2a-function-diff`.
3. Inspect `kernel_samples.csv`, `transport_samples.csv`, and
   `transport_summary.csv` in the new trace root.
4. Run `zig build o2a-plot-bundle` and compare the refreshed hotspot residual.

