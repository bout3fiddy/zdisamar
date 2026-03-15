# Reference Data and Runtime Bundles

## Why This Layer Exists

DISAMAR-class retrievals are driven by scientific data as much as by transport numerics. A realistic run depends on a stack of external references:

- atmospheric climatologies,
- molecular cross sections,
- line-by-line spectroscopy,
- collision-induced absorption tables,
- aerosol and cloud optical-property tables,
- air-mass-factor and support lookup tables,
- operational replacement surfaces when a mission supplies them.

The architecture in `zdisamar` treats those assets as named, typed scientific datasets. They are not implicit side effects of a directory layout.

## Main Principle

Reference data may be file-backed at the adapter and runtime boundary, but kernels and retrieval methods are allowed to see only typed in-memory forms.

That principle is what keeps the code readable and scientifically inspectable:

- parsers know about file formats,
- runtime preparation knows which datasets a scene requires,
- kernels know only about physical quantities and numerical shapes.

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

`src/model/ReferenceData.zig` is the main in-memory surface for reference data. It defines structures such as:

- `ClimatologyProfile`
- `CrossSectionTable`
- `SpectroscopyLineList`
- `SpectroscopyStrongLineSet`
- `SpectroscopyRelaxationMatrix`
- `CollisionInducedAbsorptionTable`
- `AirmassFactorLut`
- `MiePhaseTable`

These structures are not bookkeeping wrappers. They are the physical data surfaces used by optics preparation, measurement-space evaluation, validation, and result summaries.

## Runtime Preparation Path

The default execution path is:

1. `Engine.execute(...)` resolves the plan and request.
2. `src/runtime/reference/BundledOptics.zig` loads the reference datasets needed for that scene.
3. `src/kernels/optics/prepare.zig` turns them into a `PreparedOpticalState`.
4. `src/kernels/transport/measurement_space.zig` evaluates radiance, irradiance, reflectance, and derivative-related summaries from that prepared state.

The important architectural point is that dataset loading ends before the kernels begin. By the time transport runs, the code is operating on typed optical quantities rather than filenames, manifests, or ad hoc parser state.

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

For that reason the current implementation records:

- plugin and capability inventories,
- dataset hashes carried through the capability snapshot,
- plan identity and route selection,
- measurement-space and exporter provenance.

The result is that a stored artifact can be tied back to both a scientific configuration and a concrete set of reference data.

## Why The Boundary Matters

Moving file parsing out of kernels has scientific consequences:

- the same dataset can be used in unit tests and full runs without special hooks,
- optical preparation can be tested from typed inputs alone,
- operational overrides become explicit request-owned state,
- data provenance stays inspectable instead of being buried in execution order.

The current bundle and runtime layer is therefore not an implementation convenience. It is the mechanism that keeps the scientific inputs explicit.

## Reading Order In Code

To follow the reference-data path:

1. read `src/adapters/ingest/reference_assets.zig`,
2. read `src/model/ReferenceData.zig`,
3. read `src/runtime/reference/BundledOptics.zig`,
4. read `src/kernels/optics/prepare.zig`,
5. inspect `data/*/bundle_manifest.json` for representative datasets.
