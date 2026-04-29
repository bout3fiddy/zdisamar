# Reference Data and Runtime Bundles

## Why This Layer Exists

DISAMAR-class retrievals are driven by scientific data as much as by radiative-transfer calculations. A realistic run depends on a stack of external references:

- atmospheric climatologies,
- molecular cross sections,
- line-by-line spectroscopy,
- collision-induced absorption tables,
- aerosol and cloud optical-property tables,
- air-mass-factor and support lookup tables,
- operational replacement surfaces when a mission supplies them.

The architecture in `zdisamar` treats those assets as named, typed scientific datasets. They are not implicit side effects of a directory layout.

## Main Principle

Reference data may be file-backed at the adapter boundary, but calculation routines are allowed to see only typed in-memory forms.

That principle is what keeps the code readable and scientifically inspectable:

- parsers know about file formats,
- preparation knows which datasets a scene requires,
- routines know only about physical quantities and numerical shapes.

## Bundled Scientific Assets

The tracked bundle manifests under `data/` describe the current reference-data surface. Representative classes include:

- climatology profiles for pressure, temperature, and density structure,
- continuum and cross-section tables,
- HITRAN-style line lists and strong-line sidecars,
- relaxation matrices,
- O2-O2 collision-induced absorption tables,
- aerosol and cloud phase tables,
- support lookup tables used by operational and validation paths.

Each dataset is intended to be:

- explicitly named,
- versioned and hashable for provenance,
- loadable into a typed structure,
- reusable by both normal execution and validation harnesses.

## Typed Scientific Structures

`src/input/ReferenceData.zig` is the main in-memory surface for reference data. It defines structures such as:

- `ClimatologyProfile`
- `CrossSectionTable`
- `SpectroscopyLineList`
- `SpectroscopyStrongLineSet`
- `SpectroscopyRelaxationMatrix`
- `CollisionInducedAbsorptionTable`
- `AirmassFactorLut`
- `MiePhaseTable`

These structures are not bookkeeping wrappers. They are the physical data surfaces used by optical-property preparation, instrument-grid evaluation, validation, and result summaries.

## Runtime Preparation Path

The default O2 A execution path is:

1. `Input` records the spectral grid, geometry, surface, atmosphere, and instrument controls.
2. `ReferenceData` loads the reference datasets needed for that input.
3. `OpticalProperties` prepares wavelength-dependent optical properties.
4. `Output` contains radiance, irradiance, and reflectance on the instrument grid.
5. `DiagnosticReport` records diagnostics and provenance.

The important architectural point is that dataset loading ends before the numerical routines begin. By the time radiative transfer runs, the code is operating on typed optical quantities rather than filenames, manifests, or ad hoc parser state.

## Operational Replacement Surfaces

Operational products often need more than the default bundle set. In the present oxygen A-band path, scene-specific metadata can provide:

- explicit measured-channel sampling,
- wavelength-indexed slit-function tables,
- weighted reference-spectrum wavelength grids,
- external high-resolution solar spectra,
- O2 and O2-O2 `ln(T)` / `ln(p)` coefficient cubes.

Those replacements do not invalidate the bundle model. They override a bounded set of scientific surfaces while the rest of the prepared state still comes from tracked reference data. This makes it possible to represent operational runs without turning the entire codebase into a mission-specific file reader.

## Provenance And Dataset Identity

Reference data matters only if a result can state which dataset family it used.

For that reason the current implementation records dataset identity, hashes,
case settings, radiative-transfer method, and report provenance.

The result is that a stored artifact can be tied back to both a scientific configuration and a concrete set of reference data.

## Why The Boundary Matters

Moving file parsing out of numerical routines has scientific consequences:

- the same dataset can be used in unit tests and full runs without special hooks,
- optical preparation can be tested from typed inputs alone,
- operational overrides become explicit request-owned state,
- data provenance stays inspectable instead of being buried in execution order.

The current bundle and runtime layer is therefore not an implementation convenience. It is the mechanism that keeps the scientific inputs explicit.

## Reading Order In Code

To follow the reference-data path:

1. read `src/input/reference_data/ingest/reference_assets.zig`,
2. read `src/input/ReferenceData.zig`,
3. read `src/input/reference_data/bundled/load.zig`,
4. read `src/forward_model/optical_properties/root.zig`,
5. inspect `data/reference_data/*/bundle_manifest.json` for representative datasets.
