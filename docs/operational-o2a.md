# Operational O2 A-Band Path

## Why The Oxygen A-Band Matters

The oxygen A-band is a classic DISAMAR application domain because it is highly sensitive to photon path length. That makes it useful for cloud and aerosol-height retrieval, surface-reflection studies, and other problems where the vertical distribution of scattering and absorption matters.

The operational and research literature around this band is extensive:

- Sanders et al. (2015) describes an operational aerosol-layer-height context for Sentinel-5 Precursor.
- de Graaf et al. (2025) shows that directional surface reflection remains a scientifically important control on aerosol-layer-height performance.
- Tilstra et al. (2024) provides geometry-dependent surface-reflectivity climatologies that support oxygen-band cloud and trace-gas retrieval settings.

For the present codebase, the oxygen A-band is therefore not a narrow test case. It is the main operational science path used to organize mission ingestion, optical preparation, and measurement-space execution for the Sentinel-5P/TROPOMI line of work that feeds ESA and Copernicus processing chains.

## Scientific Interpretation

In this spectral region the forward model must balance several effects at once:

- strong molecular oxygen absorption,
- O2-O2 collision-induced absorption,
- surface reflectivity and its angular dependence,
- aerosol and cloud scattering,
- instrument spectral response and sampling.

Small changes in any of those terms can shift retrieved height or optical-depth behavior. That is why the operational path carries more typed replacement surfaces than a simple bundle-backed offline run.

## Current Execution Path

### 1. Operational ingestion

`src/adapters/ingest/spectral_ascii.zig` parses the measured and operational inputs needed for an oxygen A-band run:

- irradiance and radiance channels,
- geometry and auxiliary scene fields,
- line-shape metadata,
- wavelength-indexed slit-function rows,
- weighted reference-spectrum wavelength grids,
- external high-resolution solar spectra,
- O2 `ln(T)` / `ln(p)` lookup-table coefficients,
- O2-O2 `ln(T)` / `ln(p)` lookup-table coefficients.

These are stored as typed observation-model structures rather than pushed into global mutable tables.

### 2. Mission mapping

`src/adapters/missions/s5p/root.zig` maps those parsed inputs into a typed `Scene` and request configuration.

That mapping can replace or supplement:

- geometry,
- cloud and aerosol properties,
- surface parameters,
- instrument sampling controls,
- operational spectroscopy and reference-grid data.

The result is that the mission adapter defines the scene explicitly before the forward model starts.

### 3. Optical preparation

`src/kernels/optics/prepare.zig` prepares the oxygen-band optical state.

Two families of spectroscopy input are currently supported:

- bundle-backed references:
  - tracked O2 line lists,
  - strong-line sidecars,
  - relaxation matrices,
  - O2-O2 CIA tables;
- operational replacements:
  - typed O2 coefficient cubes,
  - typed O2-O2 coefficient cubes.

The operational coefficient cubes are evaluated on scaled `ln(T)` and `ln(p)` coordinates using Legendre terms, with temperature derivatives obtained from the same basis. That keeps the operational path explicit and analytically consistent.

### 4. Measurement-space evaluation

`src/kernels/transport/measurement_space.zig` then evaluates the prepared state using:

- measured channel grids,
- Gaussian FWHM sampling when requested,
- explicit high-resolution grids when present,
- fixed or wavelength-indexed instrument spectral response functions,
- external solar spectra when supplied by the mission path.

The output is an owned measurement-space product with radiance, irradiance, reflectance, and associated optical-depth summaries.

## Weighted Reference Grids

An operational oxygen-band run is not only a matter of loading coefficient cubes. It also depends on how reference spectra are aggregated across the fit window.

`OperationalReferenceGrid` carries:

- the wavelengths on which the operational reference is evaluated,
- the weights used to aggregate those samples.

`src/kernels/optics/prepare.zig` uses that grid when constructing operational O2 and O2-O2 band means. This is important because the effective spectroscopy seen by the retrieval depends on the mission-defined reference sampling, not only on a nominal channel grid.

## External Solar Spectra

The irradiance side of the problem is equally important. When operational metadata provides a high-resolution solar reference, `OperationalSolarSpectrum` carries it as typed request-owned state and `measurement_space.zig` interpolates it directly during execution.

This matters scientifically for at least two reasons:

- reflectance is derived from radiance and irradiance together,
- slit-function and wavelength-grid effects are only interpretable if the irradiance surface is represented consistently with the radiance sampling.

## Why The Inputs Are Explicit

The current architecture keeps operational O2 A-band inputs explicit because this band is operationally sensitive and scientifically layered. A run should make clear:

- which spectroscopy lane was used,
- which slit-function representation was selected,
- whether the solar spectrum came from a bundle or an operational file,
- which surface and atmospheric fields entered the scene.

That explicitness is what allows operational runs, unit tests, and validation harnesses to reason about the same science path without hidden mutation.

## Reading Order In Code

For the oxygen A-band path:

1. read `src/adapters/ingest/spectral_ascii.zig`,
2. read `src/adapters/missions/s5p/root.zig`,
3. read `src/model/Instrument.zig`,
4. read `src/kernels/optics/prepare.zig`,
5. read `src/kernels/transport/measurement_space.zig`,
6. inspect `tests/unit/optics_preparation_test.zig` and `tests/integration/mission_s5p_integration_test.zig`.
