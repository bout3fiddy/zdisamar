# Validation and Scientific Scope

## What Validation Means In This Repository

The purpose of validation in `zdisamar` is to show that the current implementation carries the intended scientific surfaces of the DISAMAR model family and that those surfaces behave coherently across unit tests, integration tests, and bounded reference-implementation comparisons.

An earlier Fortran implementation remains useful as a reference implementation for focused comparisons, but validation in this repository is broader than source-to-source matching. The current compatibility stance is a bounded hybrid-contract envelope, not blanket numeric equivalence to every historical DISAMAR run. Validation here therefore has to cover:

- scientific input preparation,
- radiative-transfer and instrument-grid behavior,
- operational replacement surfaces,
- retrieval-facing derivatives and contracts,
- provenance and artifact integrity.

## Layers Of Validation

### Unit tests

Unit tests check scientific mechanics in isolation, for example:

- spectroscopy evaluation,
- line-shape and partition handling,
- O2-O2 CIA interpolation,
- Mie and phase-table interpolation,
- operational reference-grid and solar-spectrum validation,
- operational O2 and O2-O2 lookup-table evaluation,
- optics preparation with operational overrides.

### Integration tests

Integration tests check that case assembly, bundled scientific data, optical-property preparation, radiative-transfer evaluation, and result ownership agree on one typed execution flow.

### Validation harnesses

Validation harnesses make bounded comparison explicit. They record which scientific surfaces are under comparison and which imported datasets support those comparisons. This is where the repository states, in a falsifiable way, what is actually covered by the current tested and validated contract envelope.

### Performance smoke tests

Performance tests do not prove correctness, and they are not benchmark claims by themselves, but they protect the architecture against regressions that would make scientific validation harder, for example accidental allocation blowups or dispatch-path changes that invalidate existing assumptions.

## Current Tested And Validated Contract Envelope

The current implementation is tested and validated for a bounded but operationally important contract envelope centered on oxygen A-band work and the surrounding scientific infrastructure. That envelope includes:

- bundle-backed climatology and spectroscopy ingestion,
- typed HITRAN-style line lists and strong-line sidecars,
- relaxation matrices and O2-O2 CIA subsets,
- aerosol and cloud phase-table preparation,
- runtime preparation of optical state from tracked bundles,
- instrument-grid materialization into owned arrays,
- Sentinel-5P/TROPOMI-style operational replacement surfaces for:
  - geometry and auxiliary fields,
  - explicit slit functions,
  - weighted reference-spectrum grids,
  - external solar spectra,
  - O2 and O2-O2 coefficient cubes.

This is the scientific scope that the current docs and tests can defend.

## Claims The Documentation Should Make Carefully

Safe claims:

- the present repository carries the main oxygen A-band operational surfaces explicitly in typed state,
- instrument-grid outputs and provenance are validated on the normal execution path,
- the current implementation preserves the DISAMAR family structure and typed forward-model stages needed for later method-faithful work.

Claims that should remain qualified:

- complete equivalence to every historical DISAMAR dataset,
- mission equivalence beyond the currently exercised Sentinel-5P path,
- equality of every numerical intermediate with any earlier implementation,
- method-faithful implementation of every currently named radiative-transfer or retrieval family,
- blanket scientific coverage outside the documented and tested data surfaces.

## Literature Context

The literature is part of the validation story because the software must be judged against the science it claims to support.

- de Haan et al. (2022) defines DISAMAR as a coupled radiative-transfer and retrieval system across multiple spectral domains.
- Sanders et al. (2015) anchors the operational oxygen A-band aerosol-layer-height setting.
- Keppens et al. (2024) documents sustained operational ozone profiling with TROPOMI.
- Tilstra et al. (2024) and de Graaf et al. (2025) document the surface-reflectance and oxygen-band context in which operational retrieval behavior should be interpreted.

Those papers are the reason the docs in this repository focus on scientific scope, operational surfaces, and retrieval behavior instead of only on code translation.

## Main Validation Artifacts

Representative files include:

- `tests/unit/input/reference_data/ingest/reference_assets_test.zig`
- `tests/unit/forward_model/optical_properties/state_build/root_test.zig`
- `tests/unit/forward_model/instrument_grid/grid_calculation/root_test.zig`
- `tests/validation/o2a_forward_shape_test.zig`
- `tests/validation/o2a_vendor_reflectance_assessment_test.zig`
- `validation/o2a_with_cia_disamar_reference.csv`
- `validation/comparison_metrics.json`

## Reading Order

If the goal is to understand the current tested and validated contract envelope quickly:

1. read [DISAMAR Overview](./disamar-overview.md),
2. read [O2A Forward](./o2a-forward.md),
3. inspect `validation/README.md`,
4. read `tests/validation/o2a_forward_shape_test.zig`,
5. inspect the unit and integration tests for the surface you care about.
