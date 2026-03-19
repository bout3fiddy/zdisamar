# Current Work State And Findings

## Snapshot

- Date: 2026-03-17
- Repo: `zdisamar` workspace root
- Workpackage set in use: `round2_feature_parity_audit`
- Local-only note: the workpackage markdown is scratch planning material and should stay unversioned unless explicitly requested.

## Workpackage Status

- Completed in code: `WP-01`, `WP-02`, `WP-03`, `WP-04`, `WP-06`
- Still open: `WP-05`, `WP-07`
- Important caveat: the remaining O2 A-band forward mismatch is not mainly a `WP-05` or `WP-07` problem. It is a forward-parity problem that sits closer to unfinished scientific parity work than to retrieval-method or plugin-hygiene work.

## What Was Rebuilt

The previous comparison used a helper program and was not good enough as a config-matched proof. The generated artifacts were rebuilt from scratch around a closer YAML port of the vendored DISAMAR case:

- Vendor config source:
  - `Config_O2_with_CIA.in`
- New canonical YAML:
  - `vendor_config_o2a_forward.yaml`
- Derived helper files:
  - `vendor_config_o2a_profile.csv`
  - `vendor_config_o2a_solar_metadata.txt`
  - `vendor_config_o2a_mapping_summary.txt`
- Fresh outputs:
  - Vendor: `disamar.sim`
  - Zig: `vendor_config_o2a_forward_zdisamar.nc`

## What Matches Reasonably Well

The current YAML port carries the main scene-level setup faithfully enough to make the comparison worth doing:

- geometry: pseudo-spherical, `SZA=60`, `VZA=30`, `RAA=120`
- spectral window: `755.0` to `776.0 nm` with `0.03 nm` output spacing
- surface albedo: `0.20`
- aerosol optical properties: `tau=0.3`, `SSA=1.0`, `g=0.7`, `angstrom=0.0`
- slit width and shape: `0.38 nm`, flat-top style
- O2 and O2-O2 source assets
- solar spectrum source derived from the vendored irradiance file

## What Is Not 1:1

The current YAML and runtime still do not encode the decisive DISAMAR controls exactly:

1. Transport solver semantics are not matched.
   - DISAMAR is configured for scalar multiple scattering with `nstreams=20`, Fourier truncation controls, and `useAdding=0`, i.e. LABOS-style behavior.
   - The Zig run still routes through the current dispatcher/scalar transport path, which is not yet a demonstrated LABOS-equivalent implementation.

2. O2 spectroscopy controls are not matched.
   - The DISAMAR config carries explicit O2 A-band knobs for line mixing factor, isotope selection, line-strength threshold, and cutoff.
   - The Zig YAML uses the HITRAN file plus sidecar strong-line and line-mixing assets, but those config controls are not represented directly.

3. Strong-line sampling is not matched.
   - DISAMAR uses `20` points per FWHM plus adaptive strong-line refinement with min/max division-point controls.
   - The Zig YAML uses a fixed high-resolution step and half-span.

4. Aerosol vertical support is only approximated.
   - DISAMAR defines the aerosol in pressure interval 2, bounded by `520` and `500 hPa`.
   - The Zig YAML converts that to an altitude-centered HG layer using derived center/width values.

5. Some instrument/runtime knobs are still not carried 1:1.
   - The current canonical/runtime path does not expose every historical DISAMAR control for wavelength-node calibration behavior, separate radiance/irradiance slit handling, polarization correction, and some retrieval-adjacent control surfaces.

## Fresh Comparison Results

### Comparison Basis

- The vendor `disamar.sim` and Zig NetCDF outputs are on the same `701`-sample wavelength grid from `755.0` to `776.0 nm`.
- The clean direct comparison is TOA radiance after converting the vendor photon units into the NetCDF energy units.
- The normalized secondary comparison is TOA reflectance factor:
  - `rho = pi * L / (E * mu0)`
  - with `mu0 = cos(60 deg) = 0.5`

### Important Interpretation Trap

The NetCDF `reflectance` field is already `pi * L / (E * mu0)`, not plain `L / E`. Comparing vendor `L / E` directly to Zig `reflectance` is wrong by a factor of `pi / mu0`. This trap was explicitly checked during the fresh run.

### Metrics

Direct radiance comparison:

- `samples = 701`
- `RMSE = 3.136187057635 mW m^-2 nm^-1 sr^-1`
- `MAE = 2.696793701307 mW m^-2 nm^-1 sr^-1`
- `mean absolute percent difference = 22.34669612%`
- `correlation = 0.993706570246`

Solar irradiance comparison:

- `mean absolute percent difference = 0.06181110%`
- `correlation = 0.999997474123`

Reflectance comparison:

- trough wavelength matches exactly at `760.76 nm`
- vendor trough reflectance: `0.006168183160`
- Zig trough reflectance: `0.013246294973`

## Main Scientific Conclusion

The wavelength grid, solar source, and normalization bookkeeping are no longer the main problem.

The remaining mismatch is dominated by forward-model physics and numerics:

- transport parity
- O2 spectroscopy parity
- pressure-interval aerosol handling
- adaptive strong-line sampling

This means the current discrepancy is not mainly a YAML-plumbing issue and not mainly a retrieval-method issue. The YAML is incomplete, but the larger blocker is that the forward runtime is not yet a demonstrated method-faithful match for the vendored DISAMAR path.

## Runtime Note About "Failed To Perform Retrieval"

`Config_O2_with_CIA.in` already has `simulationOnly = 1`, so the case is configured as simulation-only. The confusing `Failed to perform retrieval` message is emitted by the wrapper executable, which always calls the retrieval entrypoint name even when the core exits intentionally after simulation completion. That banner is therefore misleading, although the long runtime still indicates the forward model is expensive.

## Most Relevant Artifacts

- YAML port:
  - `vendor_config_o2a_forward.yaml`
- Mapping summary:
  - `vendor_config_o2a_mapping_summary.txt`
- Vendor output:
  - `disamar.sim`
- Zig output:
  - `vendor_config_o2a_forward_zdisamar.nc`
- Direct radiance metrics:
  - `vendor_config_o2a_forward_radiance_metrics.txt`
- Irradiance metrics:
  - `vendor_config_o2a_forward_irradiance_metrics.txt`
- Reflectance metrics:
  - `vendor_config_o2a_forward_reflectance_metrics.txt`
- Overlay plots:
  - `vendor_config_o2a_forward_radiance_overlay.png`
  - `vendor_config_o2a_forward_reflectance_overlay.png`

## Recommended Next Research Direction

Do not treat `WP-05` and `WP-07` as the main path to closing the current O2 A-band mismatch.

A stronger next planning pass should create new or expanded workpackages for:

- forward transport parity against LABOS-style DISAMAR semantics
- exact O2 A-band spectroscopy control parity
- pressure-space aerosol interval modeling
- adaptive line-by-line sampling parity
- config parity expansion for canonical YAML
- tighter vendor-vs-Zig forward validation harnesses and acceptance criteria
